require "openssl/hmac"

module RNS
  module Cryptography
    HASH_LEN = 32 # SHA-256 output length

    def self.hkdf(length : Int32, derive_from : Bytes?, salt : Bytes? = nil, context : Bytes? = nil) : Bytes
      if length < 1
        raise ArgumentError.new("Invalid output key length")
      end

      if derive_from.nil? || derive_from.empty?
        raise ArgumentError.new("Cannot derive key from empty input material")
      end

      if salt.nil? || salt.empty?
        salt = Bytes.new(HASH_LEN, 0_u8)
      end

      context = Bytes.empty if context.nil?

      # Extract phase
      pseudorandom_key = OpenSSL::HMAC.digest(OpenSSL::Algorithm::SHA256, salt, derive_from)

      # Expand phase
      block = Bytes.empty
      derived = IO::Memory.new

      num_blocks = (length + HASH_LEN - 1) // HASH_LEN
      num_blocks.times do |i|
        input = IO::Memory.new
        input.write(block)
        input.write(context)
        input.write_byte(((i + 1) % (0xFF + 1)).to_u8)

        block = OpenSSL::HMAC.digest(OpenSSL::Algorithm::SHA256, pseudorandom_key, input.to_slice)
        derived.write(block)
      end

      derived.to_slice[0, length].dup
    end
  end
end
