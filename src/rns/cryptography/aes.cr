require "openssl"

module RNS
  module Cryptography
    module AES_128_CBC
      def self.encrypt(plaintext : Bytes, key : Bytes, iv : Bytes) : Bytes
        if key.size != 16
          raise ArgumentError.new("Invalid key length #{key.size * 8} for AES-128-CBC")
        end
        cipher = OpenSSL::Cipher.new("aes-128-cbc")
        cipher.encrypt
        cipher.padding = false
        cipher.key = key
        cipher.iv = iv
        output = IO::Memory.new
        output.write(cipher.update(plaintext))
        output.write(cipher.final)
        output.to_slice.dup
      end

      def self.decrypt(ciphertext : Bytes, key : Bytes, iv : Bytes) : Bytes
        if key.size != 16
          raise ArgumentError.new("Invalid key length #{key.size * 8} for AES-128-CBC")
        end
        cipher = OpenSSL::Cipher.new("aes-128-cbc")
        cipher.decrypt
        cipher.padding = false
        cipher.key = key
        cipher.iv = iv
        output = IO::Memory.new
        output.write(cipher.update(ciphertext))
        output.write(cipher.final)
        output.to_slice.dup
      end
    end

    module AES_256_CBC
      def self.encrypt(plaintext : Bytes, key : Bytes, iv : Bytes) : Bytes
        if key.size != 32
          raise ArgumentError.new("Invalid key length #{key.size * 8} for AES-256-CBC")
        end
        cipher = OpenSSL::Cipher.new("aes-256-cbc")
        cipher.encrypt
        cipher.padding = false
        cipher.key = key
        cipher.iv = iv
        output = IO::Memory.new
        output.write(cipher.update(plaintext))
        output.write(cipher.final)
        output.to_slice.dup
      end

      def self.decrypt(ciphertext : Bytes, key : Bytes, iv : Bytes) : Bytes
        if key.size != 32
          raise ArgumentError.new("Invalid key length #{key.size * 8} for AES-256-CBC")
        end
        cipher = OpenSSL::Cipher.new("aes-256-cbc")
        cipher.decrypt
        cipher.padding = false
        cipher.key = key
        cipher.iv = iv
        output = IO::Memory.new
        output.write(cipher.update(ciphertext))
        output.write(cipher.final)
        output.to_slice.dup
      end
    end
  end
end
