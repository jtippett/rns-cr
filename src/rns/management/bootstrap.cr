require "msgpack"

module RNS
  module Management
    # Minimal Base32 encoder/decoder (RFC 4648, no padding)
    module Base32
      ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

      def self.encode(data : Bytes) : String
        return "" if data.empty?
        result = String::Builder.new
        buffer = 0_u64
        bits_left = 0
        data.each do |byte|
          buffer = (buffer << 8) | byte
          bits_left += 8
          while bits_left >= 5
            bits_left -= 5
            result << ALPHABET[(buffer >> bits_left) & 0x1f]
          end
        end
        if bits_left > 0
          result << ALPHABET[(buffer << (5 - bits_left)) & 0x1f]
        end
        result.to_s
      end

      def self.decode(str : String) : Bytes
        clean = str.upcase.gsub(/[^A-Z2-7]/, "")
        return Bytes.empty if clean.empty?
        buffer = 0_u64
        bits_left = 0
        output = IO::Memory.new
        clean.each_char do |c|
          val = ALPHABET.index(c)
          next unless val
          buffer = (buffer << 5) | val
          bits_left += 5
          if bits_left >= 8
            bits_left -= 8
            output.write_byte(((buffer >> bits_left) & 0xff).to_u8)
          end
        end
        output.to_slice.dup
      end
    end

    class ProvisioningToken
      getter reticule_dest_hash : Bytes
      getter bootstrap_type : String
      getter target_host : String
      getter target_port : UInt16
      getter network_name : String?
      getter passphrase : String?
      getter token_secret : Bytes
      getter token_expires : Float64

      def initialize(@reticule_dest_hash, @bootstrap_type, @target_host,
                     @target_port, @network_name, @passphrase,
                     @token_secret, @token_expires)
      end

      def expired? : Bool
        Time.utc.to_unix_f > @token_expires
      end

      def self.from_bytes(raw : Bytes) : ProvisioningToken
        pull = MessagePack::IOUnpacker.new(IO::Memory.new(raw))
        h = pull.read.as(Hash)
        bi = h["bootstrap_interface"].as(Hash)

        raw_nn = bi["network_name"]?
        raw_pp = bi["passphrase"]?

        ProvisioningToken.new(
          reticule_dest_hash: h["reticule_dest_hash"].as(Bytes),
          bootstrap_type: bi["type"].as(String),
          target_host: bi["target_host"].as(String),
          target_port: bi["target_port"].as(Int).to_u16,
          network_name: raw_nn.is_a?(String) ? raw_nn : nil,
          passphrase: raw_pp.is_a?(String) ? raw_pp : nil,
          token_secret: h["token_secret"].as(Bytes),
          token_expires: h["token_expires"].as(Float64),
        )
      end
    end

    module Bootstrap
      # Parse a token from CLI input: base32 string, reti:// URL, or file path.
      def self.parse_token_input(input : String) : ProvisioningToken
        if input.starts_with?("reti://")
          # reti://host/join/<base32_token>
          token_part = input.split("/").last
          raw = Base32.decode(token_part)
          ProvisioningToken.from_bytes(raw)
        elsif File.exists?(input)
          raw = File.read(input).to_slice
          ProvisioningToken.from_bytes(raw)
        else
          # Assume raw base32
          raw = Base32.decode(input)
          ProvisioningToken.from_bytes(raw)
        end
      end
    end
  end
end
