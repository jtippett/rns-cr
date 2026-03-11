require "./hashes"
require "./hmac"
require "./hkdf"
require "./pkcs7"
require "./aes"
require "./x25519"
require "./ed25519"
require "./token"

module RNS
  # Cryptographic primitives used throughout RNS: hashing (SHA-256/512),
  # HMAC, HKDF key derivation, AES-256-CBC encryption, X25519 ECDH key
  # exchange, Ed25519 signatures, and Fernet-like authenticated encryption.
  module Cryptography
    # The crypto backend in use. `:internal` means Crystal OpenSSL bindings.
    PROVIDER = :internal
  end
end
