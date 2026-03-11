require "./hmac"
require "./pkcs7"
require "./aes"

module RNS
  module Cryptography
    class Token
      TOKEN_OVERHEAD = 48 # 16 bytes IV + 32 bytes HMAC-SHA256

      enum Mode
        AES_128_CBC
        AES_256_CBC
      end

      @signing_key : Bytes
      @encryption_key : Bytes
      @mode : Mode

      def self.generate_key(mode : Symbol = :aes_256_cbc) : Bytes
        case mode
        when :aes_256_cbc
          Random::Secure.random_bytes(64)
        when :aes_128_cbc
          Random::Secure.random_bytes(32)
        else
          raise ArgumentError.new("Invalid token mode: #{mode}")
        end
      end

      def initialize(key : Bytes)
        case key.size
        when 32
          @mode = Mode::AES_128_CBC
          @signing_key = key[0, 16].dup
          @encryption_key = key[16, 16].dup
        when 64
          @mode = Mode::AES_256_CBC
          @signing_key = key[0, 32].dup
          @encryption_key = key[32, 32].dup
        else
          raise ArgumentError.new("Token key must be 128 or 256 bits, not #{key.size * 8}")
        end
      end

      def verify_hmac(token : Bytes) : Bool
        if token.size <= 32
          raise ArgumentError.new("Cannot verify HMAC on token of only #{token.size} bytes")
        end

        received_hmac = token[token.size - 32, 32]
        expected_hmac = HMAC.new(@signing_key, token[0, token.size - 32]).digest

        received_hmac == expected_hmac
      end

      def encrypt(data : Bytes) : Bytes
        iv = Random::Secure.random_bytes(16)
        padded = PKCS7.pad(data)

        ciphertext = case @mode
                     when Mode::AES_128_CBC
                       AES128CBC.encrypt(padded, @encryption_key, iv)
                     when Mode::AES_256_CBC
                       AES256CBC.encrypt(padded, @encryption_key, iv)
                     else
                       raise ArgumentError.new("Invalid mode")
                     end

        signed_parts = Bytes.new(iv.size + ciphertext.size)
        signed_parts.copy_from(iv)
        ciphertext.copy_to(signed_parts + iv.size)

        hmac = HMAC.new(@signing_key, signed_parts).digest

        result = Bytes.new(signed_parts.size + hmac.size)
        signed_parts.copy_to(result)
        hmac.copy_to(result + signed_parts.size)
        result
      end

      def decrypt(token : Bytes) : Bytes
        if !verify_hmac(token)
          raise ArgumentError.new("Token HMAC was invalid")
        end

        iv = token[0, 16]
        ciphertext = token[16, token.size - 48]

        plaintext = case @mode
                    when Mode::AES_128_CBC
                      AES128CBC.decrypt(ciphertext, @encryption_key, iv)
                    when Mode::AES_256_CBC
                      AES256CBC.decrypt(ciphertext, @encryption_key, iv)
                    else
                      raise ArgumentError.new("Invalid mode")
                    end

        PKCS7.unpad(plaintext)
      rescue ex : ArgumentError
        raise ex
      rescue ex
        raise ArgumentError.new("Could not decrypt token: #{ex.message}")
      end
    end
  end
end
