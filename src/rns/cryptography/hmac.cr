require "openssl/hmac"

module RNS
  module Cryptography
    class HMAC
      @key : Bytes
      @data : IO::Memory

      def initialize(key : Bytes, msg : Bytes? = nil)
        @key = key
        @data = IO::Memory.new
        if msg
          @data.write(msg)
        end
      end

      def update(msg : Bytes) : self
        @data.write(msg)
        self
      end

      def digest : Bytes
        OpenSSL::HMAC.digest(OpenSSL::Algorithm::SHA256, @key, @data.to_slice)
      end

      def hexdigest : String
        digest.hexstring
      end

      def self.digest(key : Bytes, data : Bytes) : Bytes
        OpenSSL::HMAC.digest(OpenSSL::Algorithm::SHA256, key, data)
      end
    end
  end
end
