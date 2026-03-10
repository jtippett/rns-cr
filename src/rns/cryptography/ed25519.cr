require "openssl"

# Extend Crystal's existing LibCrypto with Ed25519-specific EVP functions
lib LibCrypto
  NID_ED25519 = 1087

  type EVP_PKEY = Void*

  fun evp_pkey_new_raw_private_key = EVP_PKEY_new_raw_private_key(
    type : Int32, e : Void*, key : UInt8*, keylen : LibC::SizeT
  ) : EVP_PKEY

  fun evp_pkey_new_raw_public_key = EVP_PKEY_new_raw_public_key(
    type : Int32, e : Void*, key : UInt8*, keylen : LibC::SizeT
  ) : EVP_PKEY

  fun evp_pkey_get_raw_public_key = EVP_PKEY_get_raw_public_key(
    pkey : EVP_PKEY, pub : UInt8*, len : LibC::SizeT*
  ) : Int32

  fun evp_pkey_free = EVP_PKEY_free(pkey : EVP_PKEY) : Void

  fun evp_digest_sign_init = EVP_DigestSignInit(
    ctx : EVP_MD_CTX, pctx : Void*, type : Void*, e : Void*, pkey : EVP_PKEY
  ) : Int32

  fun evp_digest_sign = EVP_DigestSign(
    ctx : EVP_MD_CTX, sigret : UInt8*, siglen : LibC::SizeT*, tbs : UInt8*, tbslen : LibC::SizeT
  ) : Int32

  fun evp_digest_verify_init = EVP_DigestVerifyInit(
    ctx : EVP_MD_CTX, pctx : Void*, type : Void*, e : Void*, pkey : EVP_PKEY
  ) : Int32

  fun evp_digest_verify = EVP_DigestVerify(
    ctx : EVP_MD_CTX, sigret : UInt8*, siglen : LibC::SizeT, tbs : UInt8*, tbslen : LibC::SizeT
  ) : Int32
end

module RNS
  module Cryptography
    class Ed25519PublicKey
      @public_bytes : Bytes

      def initialize(@public_bytes : Bytes)
      end

      def self.from_public_bytes(data : Bytes) : Ed25519PublicKey
        raise ArgumentError.new("Ed25519 public key must be 32 bytes, got #{data.size}") unless data.size == 32
        Ed25519PublicKey.new(data.dup)
      end

      def public_bytes : Bytes
        @public_bytes.dup
      end

      def verify(signature : Bytes, message : Bytes) : Nil
        pkey = LibCrypto.evp_pkey_new_raw_public_key(
          LibCrypto::NID_ED25519, Pointer(Void).null,
          @public_bytes.to_unsafe, @public_bytes.size
        )
        raise "Failed to create Ed25519 public key" if pkey.null?

        begin
          ctx = LibCrypto.evp_md_ctx_new
          raise "Failed to create EVP_MD_CTX" if ctx.null?

          begin
            ret = LibCrypto.evp_digest_verify_init(
              ctx, Pointer(Void).null, Pointer(Void).null, Pointer(Void).null, pkey
            )
            raise "EVP_DigestVerifyInit failed" unless ret == 1

            result = LibCrypto.evp_digest_verify(
              ctx, signature.to_unsafe, signature.size, message.to_unsafe, message.size
            )
            raise Exception.new("Ed25519 signature verification failed") unless result == 1
          ensure
            LibCrypto.evp_md_ctx_free(ctx)
          end
        ensure
          LibCrypto.evp_pkey_free(pkey)
        end
      end
    end

    class Ed25519PrivateKey
      @seed : Bytes

      def initialize(@seed : Bytes)
      end

      def self.generate : Ed25519PrivateKey
        from_private_bytes(Random::Secure.random_bytes(32))
      end

      def self.from_private_bytes(data : Bytes) : Ed25519PrivateKey
        raise ArgumentError.new("Ed25519 private key seed must be 32 bytes, got #{data.size}") unless data.size == 32
        Ed25519PrivateKey.new(data.dup)
      end

      def private_bytes : Bytes
        @seed.dup
      end

      def public_key : Ed25519PublicKey
        pkey = LibCrypto.evp_pkey_new_raw_private_key(
          LibCrypto::NID_ED25519, Pointer(Void).null,
          @seed.to_unsafe, @seed.size
        )
        raise "Failed to create Ed25519 private key" if pkey.null?

        begin
          len = LibC::SizeT.new(32)
          pub_buf = Bytes.new(32)
          ret = LibCrypto.evp_pkey_get_raw_public_key(pkey, pub_buf.to_unsafe, pointerof(len))
          raise "Failed to extract Ed25519 public key" unless ret == 1
          Ed25519PublicKey.from_public_bytes(pub_buf)
        ensure
          LibCrypto.evp_pkey_free(pkey)
        end
      end

      def sign(message : Bytes) : Bytes
        pkey = LibCrypto.evp_pkey_new_raw_private_key(
          LibCrypto::NID_ED25519, Pointer(Void).null,
          @seed.to_unsafe, @seed.size
        )
        raise "Failed to create Ed25519 private key" if pkey.null?

        begin
          ctx = LibCrypto.evp_md_ctx_new
          raise "Failed to create EVP_MD_CTX" if ctx.null?

          begin
            ret = LibCrypto.evp_digest_sign_init(
              ctx, Pointer(Void).null, Pointer(Void).null, Pointer(Void).null, pkey
            )
            raise "EVP_DigestSignInit failed" unless ret == 1

            # First call to get signature length
            sig_len = LibC::SizeT.new(0)
            ret = LibCrypto.evp_digest_sign(
              ctx, Pointer(UInt8).null, pointerof(sig_len), message.to_unsafe, message.size
            )
            raise "EVP_DigestSign (get length) failed" unless ret == 1

            # Second call to actually sign
            sig = Bytes.new(sig_len)
            ret = LibCrypto.evp_digest_sign(
              ctx, sig.to_unsafe, pointerof(sig_len), message.to_unsafe, message.size
            )
            raise "EVP_DigestSign failed" unless ret == 1

            sig[0, sig_len]
          ensure
            LibCrypto.evp_md_ctx_free(ctx)
          end
        ensure
          LibCrypto.evp_pkey_free(pkey)
        end
      end
    end
  end
end
