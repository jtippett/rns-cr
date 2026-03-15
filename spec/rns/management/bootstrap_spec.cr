require "../../spec_helper"

# Convenience alias matching the one used in the production code
private alias MPHash = Hash(MessagePack::Type, MessagePack::Type)

# Helper to build a token msgpack payload for testing
private def build_token_payload(
  dest_hash : Bytes = Bytes.new(16, 0xAA_u8),
  type : String = "TCPClientInterface",
  target_host : String = "reticule.example.com",
  target_port : Int = 4242,
  network_name : MessagePack::Type = nil,
  passphrase : MessagePack::Type = nil,
  token_secret : Bytes = Bytes.new(32, 0xBB_u8),
  token_expires : Float64 = (Time.utc + 1.hour).to_unix_f
) : Bytes
  h = MPHash.new
  h["reticule_dest_hash"] = dest_hash
  bootstrap_iface = MPHash.new
  bootstrap_iface["type"] = type
  bootstrap_iface["target_host"] = target_host
  bootstrap_iface["target_port"] = target_port.to_i64
  bootstrap_iface["network_name"] = network_name
  bootstrap_iface["passphrase"] = passphrase
  h["bootstrap_interface"] = bootstrap_iface.as(MessagePack::Type)
  h["token_secret"] = token_secret
  h["token_expires"] = token_expires
  h.to_msgpack
end

describe RNS::Management::Bootstrap do
  describe "Base32" do
    it "round-trips arbitrary bytes" do
      original = Bytes[0x00, 0x01, 0x02, 0xFF, 0xFE, 0xAB, 0xCD]
      encoded = RNS::Management::Base32.encode(original)
      decoded = RNS::Management::Base32.decode(encoded)
      decoded.should eq(original)
    end

    it "encodes known test vectors" do
      # RFC 4648 test vectors (without padding)
      RNS::Management::Base32.encode("".to_slice).should eq("")
      RNS::Management::Base32.encode("f".to_slice).should eq("MY")
      RNS::Management::Base32.encode("fo".to_slice).should eq("MZXQ")
      RNS::Management::Base32.encode("foo".to_slice).should eq("MZXW6")
      RNS::Management::Base32.encode("foob".to_slice).should eq("MZXW6YQ")
      RNS::Management::Base32.encode("fooba".to_slice).should eq("MZXW6YTB")
      RNS::Management::Base32.encode("foobar".to_slice).should eq("MZXW6YTBOI")
    end

    it "decodes case-insensitively" do
      original = "Hello".to_slice
      encoded = RNS::Management::Base32.encode(original)
      RNS::Management::Base32.decode(encoded.downcase).should eq(original)
      RNS::Management::Base32.decode(encoded.upcase).should eq(original)
    end
  end

  describe "ProvisioningToken" do
    it "parses from MessagePack bytes" do
      raw = build_token_payload
      token = RNS::Management::ProvisioningToken.from_bytes(raw)

      token.reticule_dest_hash.should eq(Bytes.new(16, 0xAA_u8))
      token.bootstrap_type.should eq("TCPClientInterface")
      token.target_host.should eq("reticule.example.com")
      token.target_port.should eq(4242_u16)
      token.token_secret.should eq(Bytes.new(32, 0xBB_u8))
      token.expired?.should be_false
    end

    it "detects expired tokens" do
      raw = build_token_payload(
        token_expires: (Time.utc - 1.hour).to_unix_f
      )
      token = RNS::Management::ProvisioningToken.from_bytes(raw)
      token.expired?.should be_true
    end

    it "parses optional network_name and passphrase" do
      raw = build_token_payload(
        network_name: "my-network",
        passphrase: "secret-pass"
      )
      token = RNS::Management::ProvisioningToken.from_bytes(raw)
      token.network_name.should eq("my-network")
      token.passphrase.should eq("secret-pass")
    end

    it "handles nil network_name and passphrase" do
      raw = build_token_payload
      token = RNS::Management::ProvisioningToken.from_bytes(raw)
      token.network_name.should be_nil
      token.passphrase.should be_nil
    end
  end

  describe ".parse_token_input" do
    it "parses raw base32 token" do
      raw = build_token_payload(
        dest_hash: Bytes.new(16, 0xCC_u8),
        target_host: "10.0.0.1",
        target_port: 5555,
        token_secret: Bytes.new(32, 0xDD_u8)
      )

      encoded = RNS::Management::Base32.encode(raw)
      token = RNS::Management::Bootstrap.parse_token_input(encoded)
      token.target_host.should eq("10.0.0.1")
      token.target_port.should eq(5555_u16)
    end

    it "parses reti:// URL format" do
      raw = build_token_payload(
        dest_hash: Bytes.new(16, 0xCC_u8),
        target_host: "reticule.example.com",
        target_port: 4242,
        token_secret: Bytes.new(32, 0xEE_u8)
      )

      encoded = RNS::Management::Base32.encode(raw)
      url = "reti://reticule.example.com/join/#{encoded}"
      token = RNS::Management::Bootstrap.parse_token_input(url)
      token.target_host.should eq("reticule.example.com")
    end

    it "parses from file path" do
      raw = build_token_payload(
        dest_hash: Bytes.new(16, 0xCC_u8),
        target_host: "filehost",
        target_port: 9999,
        token_secret: Bytes.new(32, 0xFF_u8)
      )

      tmpfile = File.tempfile("token", ".reti") do |f|
        f.write(raw)
      end
      begin
        token = RNS::Management::Bootstrap.parse_token_input(tmpfile.path)
        token.target_host.should eq("filehost")
      ensure
        tmpfile.delete
      end
    end
  end
end
