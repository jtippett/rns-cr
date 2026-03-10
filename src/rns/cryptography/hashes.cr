require "openssl"

module RNS
  module Cryptography
    TRUNCATED_HASHLENGTH = 128 # bits

    def self.sha256(data : Bytes) : Bytes
      digest = OpenSSL::Digest.new("SHA256")
      digest.update(data)
      digest.final
    end

    def self.sha512(data : Bytes) : Bytes
      digest = OpenSSL::Digest.new("SHA512")
      digest.update(data)
      digest.final
    end

    def self.full_hash(data : Bytes) : Bytes
      sha256(data)
    end

    def self.truncated_hash(data : Bytes) : Bytes
      full_hash(data)[0, TRUNCATED_HASHLENGTH // 8]
    end
  end
end
