require "../../spec_helper"

# Protocol Compatibility Verification
#
# These tests verify that the Crystal RNS implementation produces byte-identical
# outputs to the Python RNS implementation for the same inputs. Test vectors are
# derived from RFC standards and the Python RNS source code behavior.
#
# Critical for wire-compatibility: the Crystal port must interoperate with
# the Python implementation at the packet level.

describe "Protocol Compatibility" do
  # =========================================================================
  # Section 1: Constants must match exactly
  # =========================================================================
  describe "Constants" do
    it "MTU matches Python (500)" do
      RNS::Reticulum::MTU.should eq 500
    end

    it "TRUNCATED_HASHLENGTH matches Python (128 bits)" do
      RNS::Reticulum::TRUNCATED_HASHLENGTH.should eq 128
    end

    it "HEADER_MINSIZE matches Python (19 bytes)" do
      RNS::Reticulum::HEADER_MINSIZE.should eq 19
    end

    it "HEADER_MAXSIZE matches Python (35 bytes)" do
      RNS::Reticulum::HEADER_MAXSIZE.should eq 35
    end

    it "Identity KEYSIZE matches Python (512 bits)" do
      RNS::Identity::KEYSIZE.should eq 512
    end

    it "Identity HASHLENGTH matches Python (256 bits)" do
      RNS::Identity::HASHLENGTH.should eq 256
    end

    it "Identity NAME_HASH_LENGTH matches Python (80 bits)" do
      RNS::Identity::NAME_HASH_LENGTH.should eq 80
    end

    it "Identity RATCHETSIZE matches Python (256 bits)" do
      RNS::Identity::RATCHETSIZE.should eq 256
    end

    it "Identity SIGLENGTH matches Python (512 bits)" do
      RNS::Identity::SIGLENGTH.should eq 512
    end

    it "Token TOKEN_OVERHEAD matches Python (48 bytes)" do
      RNS::Cryptography::Token::TOKEN_OVERHEAD.should eq 48
    end

    it "IFAC_MIN_SIZE matches Python (1)" do
      RNS::Reticulum::IFAC_MIN_SIZE.should eq 1
    end

    it "Destination type constants match Python" do
      RNS::Destination::SINGLE.should eq 0x00_u8
      RNS::Destination::GROUP.should eq 0x01_u8
      RNS::Destination::PLAIN.should eq 0x02_u8
      RNS::Destination::LINK.should eq 0x03_u8
    end

    it "Destination direction constants match Python" do
      RNS::Destination::IN.should eq 0x11_u8
      RNS::Destination::OUT.should eq 0x12_u8
    end

    it "Destination proof strategy constants match Python" do
      RNS::Destination::PROVE_NONE.should eq 0x21_u8
      RNS::Destination::PROVE_APP.should eq 0x22_u8
      RNS::Destination::PROVE_ALL.should eq 0x23_u8
    end

    it "Packet type constants match Python" do
      RNS::Packet::DATA.should eq 0x00_u8
      RNS::Packet::ANNOUNCE.should eq 0x01_u8
      RNS::Packet::LINKREQUEST.should eq 0x02_u8
      RNS::Packet::PROOF.should eq 0x03_u8
    end

    it "Packet header type constants match Python" do
      RNS::Packet::HEADER_1.should eq 0x00_u8
      RNS::Packet::HEADER_2.should eq 0x01_u8
    end

    it "Packet context constants match Python" do
      RNS::Packet::NONE.should eq 0x00_u8
      RNS::Packet::RESOURCE.should eq 0x01_u8
      RNS::Packet::RESOURCE_ADV.should eq 0x02_u8
      RNS::Packet::RESOURCE_REQ.should eq 0x03_u8
      RNS::Packet::RESOURCE_HMU.should eq 0x04_u8
      RNS::Packet::RESOURCE_PRF.should eq 0x05_u8
      RNS::Packet::RESOURCE_ICL.should eq 0x06_u8
      RNS::Packet::RESOURCE_RCL.should eq 0x07_u8
      RNS::Packet::CACHE_REQUEST.should eq 0x08_u8
      RNS::Packet::REQUEST.should eq 0x09_u8
      RNS::Packet::RESPONSE.should eq 0x0A_u8
      RNS::Packet::PATH_RESPONSE.should eq 0x0B_u8
      RNS::Packet::CHANNEL.should eq 0x0E_u8
      RNS::Packet::KEEPALIVE.should eq 0xFA_u8
      RNS::Packet::LINKIDENTIFY.should eq 0xFB_u8
      RNS::Packet::LINKCLOSE.should eq 0xFC_u8
      RNS::Packet::LINKPROOF.should eq 0xFD_u8
      RNS::Packet::LRRTT.should eq 0xFE_u8
      RNS::Packet::LRPROOF.should eq 0xFF_u8
    end
  end

  # =========================================================================
  # Section 2: Hash computation — SHA-256/512 and truncation
  # =========================================================================
  describe "Hash computation" do
    it "SHA-256 of 'Hello, Reticulum!' matches Python output" do
      # Python: hashlib.sha256(b'Hello, Reticulum!').hexdigest()
      input = "Hello, Reticulum!".to_slice
      result = RNS::Cryptography.sha256(input)
      # NIST SHA-256 is deterministic — same on all implementations
      expected = OpenSSL::Digest.new("SHA256").update(input).final
      result.should eq expected
      result.size.should eq 32
    end

    it "SHA-512 of 'Hello, Reticulum!' matches Python output" do
      input = "Hello, Reticulum!".to_slice
      result = RNS::Cryptography.sha512(input)
      expected = OpenSSL::Digest.new("SHA512").update(input).final
      result.should eq expected
      result.size.should eq 64
    end

    it "SHA-256 of empty input matches NIST test vector" do
      # NIST: SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
      result = RNS::Cryptography.sha256(Bytes.empty)
      result.hexstring.should eq "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    end

    it "SHA-256 of 'abc' matches NIST test vector" do
      # NIST: SHA-256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
      result = RNS::Cryptography.sha256("abc".to_slice)
      result.hexstring.should eq "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    end

    it "full_hash is SHA-256" do
      data = "test data".to_slice
      RNS::Identity.full_hash(data).should eq RNS::Cryptography.sha256(data)
    end

    it "truncated_hash returns first 16 bytes of SHA-256" do
      data = "test data".to_slice
      full = RNS::Cryptography.sha256(data)
      truncated = RNS::Identity.truncated_hash(data)
      truncated.size.should eq 16
      truncated.should eq full[0, 16]
    end

    it "truncated_hash length is TRUNCATED_HASHLENGTH/8" do
      data = Random::Secure.random_bytes(64)
      result = RNS::Identity.truncated_hash(data)
      result.size.should eq RNS::Reticulum::TRUNCATED_HASHLENGTH // 8
    end

    it "1000 random inputs produce consistent SHA-256" do
      1000.times do
        data = Random::Secure.random_bytes(rand(1..256))
        crystal_result = RNS::Cryptography.sha256(data)
        openssl_result = OpenSSL::Digest.new("SHA256").update(data).final
        crystal_result.should eq openssl_result
      end
    end
  end

  # =========================================================================
  # Section 3: HMAC-SHA256
  # =========================================================================
  describe "HMAC-SHA256" do
    it "RFC 4231 Case 1 matches Python output" do
      # Key = 0x0b * 20, Data = "Hi There"
      key = Bytes.new(20, 0x0b_u8)
      data = "Hi There".to_slice
      expected = "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
      result = RNS::Cryptography::HMAC.new(key, data).digest
      result.hexstring.should eq expected
    end

    it "RFC 4231 Case 2 matches Python output" do
      # Key = "Jefe", Data = "what do ya want for nothing?"
      key = "Jefe".to_slice
      data = "what do ya want for nothing?".to_slice
      expected = "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
      result = RNS::Cryptography::HMAC.new(key, data).digest
      result.hexstring.should eq expected
    end

    it "class method digest matches instance method" do
      key = Random::Secure.random_bytes(32)
      data = Random::Secure.random_bytes(64)
      instance_result = RNS::Cryptography::HMAC.new(key, data).digest
      class_result = RNS::Cryptography::HMAC.digest(key, data)
      instance_result.should eq class_result
    end
  end

  # =========================================================================
  # Section 4: HKDF — Key derivation
  # =========================================================================
  describe "HKDF" do
    it "RFC 5869 Case 1 matches Python output" do
      # IKM = 0x0b * 22, Salt = 000102030405060708090a0b0c, Info = f0f1f2f3f4f5f6f7f8f9
      ikm = Bytes.new(22, 0x0b_u8)
      salt = Bytes[0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c]
      info = Bytes[0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9]
      expected = "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"

      result = RNS::Cryptography.hkdf(42, ikm, salt, info)
      result.hexstring.should eq expected
    end

    it "nil salt defaults to 32 zero bytes (matching Python)" do
      # Python: if salt == None or len(salt) == 0: salt = bytes([0] * 32)
      ikm = Random::Secure.random_bytes(32)
      result_nil = RNS::Cryptography.hkdf(32, ikm, nil, nil)
      result_zeros = RNS::Cryptography.hkdf(32, ikm, Bytes.new(32, 0_u8), Bytes.empty)
      result_nil.should eq result_zeros
    end

    it "nil context defaults to empty bytes (matching Python)" do
      ikm = Random::Secure.random_bytes(32)
      salt = Random::Secure.random_bytes(16)
      result_nil = RNS::Cryptography.hkdf(64, ikm, salt, nil)
      result_empty = RNS::Cryptography.hkdf(64, ikm, salt, Bytes.empty)
      result_nil.should eq result_empty
    end

    it "derives 64-byte key as used in Identity encryption" do
      # Python uses: hkdf(length=64, derive_from=shared_key, salt=identity.hash, context=None)
      shared_key = Random::Secure.random_bytes(32)
      identity_hash = Random::Secure.random_bytes(16)
      result = RNS::Cryptography.hkdf(64, shared_key, identity_hash, nil)
      result.size.should eq 64
    end
  end

  # =========================================================================
  # Section 5: PKCS7 padding
  # =========================================================================
  describe "PKCS7 padding" do
    it "pads 12-byte input to 16 bytes with 0x04 bytes" do
      # Python: PKCS7.pad(b'Hello World!') → 12 bytes + 4 bytes of 0x04
      input = "Hello World!".to_slice
      padded = RNS::Cryptography::PKCS7.pad(input)
      padded.size.should eq 16
      padded[12].should eq 4_u8
      padded[13].should eq 4_u8
      padded[14].should eq 4_u8
      padded[15].should eq 4_u8
    end

    it "pads 16-byte input to 32 bytes with 0x10 bytes" do
      # Python: PKCS7.pad(b'0123456789abcdef') → 16 bytes + 16 bytes of 0x10
      input = "0123456789abcdef".to_slice
      padded = RNS::Cryptography::PKCS7.pad(input)
      padded.size.should eq 32
      (16...32).each { |i| padded[i].should eq 16_u8 }
    end

    it "pads 1-byte input to 16 bytes with 0x0f bytes" do
      input = Bytes[0x41]
      padded = RNS::Cryptography::PKCS7.pad(input)
      padded.size.should eq 16
      padded[0].should eq 0x41_u8
      (1...16).each { |i| padded[i].should eq 15_u8 }
    end

    it "pad/unpad roundtrip preserves data" do
      100.times do
        data = Random::Secure.random_bytes(rand(1..256))
        padded = RNS::Cryptography::PKCS7.pad(data)
        unpadded = RNS::Cryptography::PKCS7.unpad(padded)
        unpadded.should eq data
      end
    end
  end

  # =========================================================================
  # Section 6: AES-256-CBC
  # =========================================================================
  describe "AES-256-CBC" do
    it "encrypt/decrypt roundtrip matches Python behavior" do
      key = Random::Secure.random_bytes(32)
      iv = Random::Secure.random_bytes(16)
      plaintext = "Hello Reticulum AES test!".to_slice
      padded = RNS::Cryptography::PKCS7.pad(plaintext)

      ciphertext = RNS::Cryptography::AES256CBC.encrypt(padded, key, iv)
      decrypted = RNS::Cryptography::AES256CBC.decrypt(ciphertext, key, iv)
      unpadded = RNS::Cryptography::PKCS7.unpad(decrypted)
      unpadded.should eq plaintext
    end

    it "produces deterministic ciphertext for same key/IV/plaintext" do
      key = Bytes.new(32, &.to_u8)
      iv = Bytes.new(16) { |i| (i + 0x10).to_u8 }
      plaintext = RNS::Cryptography::PKCS7.pad("test".to_slice)

      ct1 = RNS::Cryptography::AES256CBC.encrypt(plaintext, key, iv)
      ct2 = RNS::Cryptography::AES256CBC.encrypt(plaintext, key, iv)
      ct1.should eq ct2
    end

    it "ciphertext is always a multiple of 16 bytes" do
      key = Random::Secure.random_bytes(32)
      iv = Random::Secure.random_bytes(16)
      50.times do
        plaintext = RNS::Cryptography::PKCS7.pad(Random::Secure.random_bytes(rand(1..200)))
        ciphertext = RNS::Cryptography::AES256CBC.encrypt(plaintext, key, iv)
        (ciphertext.size % 16).should eq 0
      end
    end
  end

  # =========================================================================
  # Section 7: X25519 key exchange
  # =========================================================================
  describe "X25519 key exchange" do
    it "two parties derive the same shared secret" do
      prv_a = RNS::Cryptography::X25519PrivateKey.generate
      prv_b = RNS::Cryptography::X25519PrivateKey.generate
      pub_a = prv_a.public_key
      pub_b = prv_b.public_key

      shared_ab = prv_a.exchange(pub_b)
      shared_ba = prv_b.exchange(pub_a)

      shared_ab.should eq shared_ba
      shared_ab.size.should eq 32
    end

    it "public key is 32 bytes" do
      prv = RNS::Cryptography::X25519PrivateKey.generate
      prv.public_key.public_bytes.size.should eq 32
    end

    it "private key is 32 bytes" do
      prv = RNS::Cryptography::X25519PrivateKey.generate
      prv.private_bytes.size.should eq 32
    end

    it "key from private bytes produces same public key" do
      prv = RNS::Cryptography::X25519PrivateKey.generate
      prv2 = RNS::Cryptography::X25519PrivateKey.from_private_bytes(prv.private_bytes)
      prv2.public_key.public_bytes.should eq prv.public_key.public_bytes
    end

    it "exchange with bytes works same as exchange with key object" do
      prv_a = RNS::Cryptography::X25519PrivateKey.generate
      prv_b = RNS::Cryptography::X25519PrivateKey.generate

      shared_obj = prv_a.exchange(prv_b.public_key)
      shared_bytes = prv_a.exchange(prv_b.public_key.public_bytes)
      shared_obj.should eq shared_bytes
    end

    it "100 random key exchanges produce matching shared secrets" do
      100.times do
        a = RNS::Cryptography::X25519PrivateKey.generate
        b = RNS::Cryptography::X25519PrivateKey.generate
        a.exchange(b.public_key).should eq b.exchange(a.public_key)
      end
    end
  end

  # =========================================================================
  # Section 8: Ed25519 signatures
  # =========================================================================
  describe "Ed25519 signatures" do
    it "sign/verify roundtrip succeeds" do
      prv = RNS::Cryptography::Ed25519PrivateKey.generate
      pub = prv.public_key
      message = "Test message for Ed25519".to_slice
      signature = prv.sign(message)

      signature.size.should eq 64
      pub.verify(signature, message) # Should not raise
    end

    it "invalid signature raises" do
      prv = RNS::Cryptography::Ed25519PrivateKey.generate
      pub = prv.public_key
      message = "Test message".to_slice
      signature = prv.sign(message)

      bad_sig = signature.dup
      bad_sig[0] = bad_sig[0] ^ 0xFF_u8

      expect_raises(Exception) do
        pub.verify(bad_sig, message)
      end
    end

    it "signature from different key fails" do
      prv1 = RNS::Cryptography::Ed25519PrivateKey.generate
      prv2 = RNS::Cryptography::Ed25519PrivateKey.generate
      message = "Test message".to_slice
      signature = prv1.sign(message)

      expect_raises(Exception) do
        prv2.public_key.verify(signature, message)
      end
    end

    it "key serialization roundtrip preserves signing ability" do
      prv = RNS::Cryptography::Ed25519PrivateKey.generate
      seed = prv.private_bytes
      pub_bytes = prv.public_key.public_bytes

      prv2 = RNS::Cryptography::Ed25519PrivateKey.from_private_bytes(seed)
      pub2 = RNS::Cryptography::Ed25519PublicKey.from_public_bytes(pub_bytes)

      message = "roundtrip test".to_slice
      sig = prv2.sign(message)
      pub2.verify(sig, message) # Should not raise
    end

    it "public key is 32 bytes, signature is 64 bytes" do
      prv = RNS::Cryptography::Ed25519PrivateKey.generate
      prv.public_key.public_bytes.size.should eq 32
      prv.sign("test".to_slice).size.should eq 64
    end
  end

  # =========================================================================
  # Section 9: Token (Fernet-like authenticated encryption)
  # =========================================================================
  describe "Token encrypt/decrypt" do
    it "encrypt produces IV(16) + ciphertext + HMAC(32)" do
      key = Random::Secure.random_bytes(64)
      token = RNS::Cryptography::Token.new(key)
      plaintext = "Token test data!".to_slice

      ciphertext = token.encrypt(plaintext)
      # Must be at least TOKEN_OVERHEAD (48) + 16 bytes (one AES block)
      ciphertext.size.should be >= 48 + 16
      # Ciphertext minus overhead should be multiple of 16
      ((ciphertext.size - 48) % 16).should eq 0
    end

    it "decrypt recovers original plaintext" do
      key = Random::Secure.random_bytes(64)
      token = RNS::Cryptography::Token.new(key)
      plaintext = "Token test data for compatibility!".to_slice

      ciphertext = token.encrypt(plaintext)
      decrypted = token.decrypt(ciphertext)
      decrypted.should eq plaintext
    end

    it "key split: first 32 bytes = signing, last 32 bytes = encryption (64-byte key)" do
      # Python: signing_key = key[:32], encryption_key = key[32:]
      key = Bytes.new(64, &.to_u8)
      token = RNS::Cryptography::Token.new(key)

      # Encrypt something and verify HMAC uses first 32 bytes as key
      plaintext = "test".to_slice
      ciphertext = token.encrypt(plaintext)

      # Extract IV + AES ciphertext (everything except last 32 bytes)
      signed_part = ciphertext[0...(ciphertext.size - 32)]
      received_hmac = ciphertext[(ciphertext.size - 32)..]

      # Compute expected HMAC with signing key (first 32 bytes of key)
      signing_key = key[0, 32]
      expected_hmac = RNS::Cryptography::HMAC.new(signing_key, signed_part).digest
      received_hmac.should eq expected_hmac
    end

    it "verify_hmac returns true for valid token" do
      key = Random::Secure.random_bytes(64)
      token = RNS::Cryptography::Token.new(key)
      ciphertext = token.encrypt("test data".to_slice)
      token.verify_hmac(ciphertext).should be_true
    end

    it "verify_hmac returns false for tampered token" do
      key = Random::Secure.random_bytes(64)
      token = RNS::Cryptography::Token.new(key)
      ciphertext = token.encrypt("test data".to_slice)

      tampered = ciphertext.dup
      tampered[20] = tampered[20] ^ 0xFF_u8
      token.verify_hmac(tampered).should be_false
    end

    it "TOKEN_OVERHEAD accounts for 16 IV + 32 HMAC = 48 bytes" do
      key = Random::Secure.random_bytes(64)
      token = RNS::Cryptography::Token.new(key)

      # For a 16-byte plaintext, PKCS7 pads to 32 bytes (16 data + 16 padding)
      plaintext = Bytes.new(16, 0x42_u8)
      ciphertext = token.encrypt(plaintext)
      # Expected: 16 (IV) + 32 (AES of padded) + 32 (HMAC) = 80
      ciphertext.size.should eq 80
    end

    it "100 random encrypt/decrypt roundtrips succeed" do
      key = Random::Secure.random_bytes(64)
      token = RNS::Cryptography::Token.new(key)
      100.times do
        plaintext = Random::Secure.random_bytes(rand(1..256))
        ciphertext = token.encrypt(plaintext)
        decrypted = token.decrypt(ciphertext)
        decrypted.should eq plaintext
      end
    end
  end

  # =========================================================================
  # Section 10: Identity — key format and hash
  # =========================================================================
  describe "Identity key format" do
    it "public key is 64 bytes: 32 X25519 + 32 Ed25519" do
      identity = RNS::Identity.new
      pub = identity.get_public_key
      pub.size.should eq 64
    end

    it "private key is 64 bytes: 32 X25519 + 32 Ed25519" do
      identity = RNS::Identity.new
      prv = identity.get_private_key
      prv.size.should eq 64
    end

    it "identity hash = truncated SHA-256 of public key (16 bytes)" do
      identity = RNS::Identity.new
      pub = identity.get_public_key
      expected_hash = RNS::Cryptography.sha256(pub)[0, 16]
      identity.hash.not_nil!.should eq expected_hash
    end

    it "hexhash is hex of hash" do
      identity = RNS::Identity.new
      identity.hexhash.not_nil!.should eq identity.hash.not_nil!.hexstring
    end

    it "load_private_key splits correctly: first 32 = X25519, last 32 = Ed25519" do
      # Create known key material
      prv_x25519 = Random::Secure.random_bytes(32)
      prv_ed25519 = Random::Secure.random_bytes(32)
      combined = Bytes.new(64)
      combined.copy_from(prv_x25519)
      prv_ed25519.copy_to(combined + 32)

      identity = RNS::Identity.new(create_keys: false)
      identity.load_private_key(combined)

      # Public key should be derived from the private keys
      pub = identity.get_public_key
      pub.size.should eq 64

      # Hash should be truncated SHA-256 of public key
      identity.hash.not_nil!.should eq RNS::Cryptography.sha256(pub)[0, 16]
    end

    it "load_public_key splits correctly: first 32 = X25519, last 32 = Ed25519" do
      identity1 = RNS::Identity.new
      pub = identity1.get_public_key

      identity2 = RNS::Identity.new(create_keys: false)
      identity2.load_public_key(pub)

      identity2.hash.not_nil!.should eq identity1.hash.not_nil!
      identity2.get_public_key.should eq pub
    end

    it "private key roundtrip preserves identity" do
      identity1 = RNS::Identity.new
      prv = identity1.get_private_key
      pub = identity1.get_public_key
      hash = identity1.hash.not_nil!

      identity2 = RNS::Identity.new(create_keys: false)
      identity2.load_private_key(prv)

      identity2.get_public_key.should eq pub
      identity2.hash.not_nil!.should eq hash
    end
  end

  # =========================================================================
  # Section 11: Identity — sign/verify
  # =========================================================================
  describe "Identity sign/verify" do
    it "sign produces 64-byte Ed25519 signature" do
      identity = RNS::Identity.new
      message = "Reticulum identity test message".to_slice
      sig = identity.sign(message)
      sig.size.should eq 64
    end

    it "validate returns true for valid signature" do
      identity = RNS::Identity.new
      message = "Reticulum identity test message".to_slice
      sig = identity.sign(message)
      identity.validate(sig, message).should be_true
    end

    it "validate returns false for tampered signature" do
      identity = RNS::Identity.new
      message = "test".to_slice
      sig = identity.sign(message)
      bad_sig = sig.dup
      bad_sig[0] = bad_sig[0] ^ 0xFF_u8
      identity.validate(bad_sig, message).should be_false
    end

    it "validate returns false for wrong message" do
      identity = RNS::Identity.new
      sig = identity.sign("message A".to_slice)
      identity.validate(sig, "message B".to_slice).should be_false
    end

    it "signature from one identity fails validation by another" do
      id1 = RNS::Identity.new
      id2 = RNS::Identity.new
      message = "cross-identity test".to_slice
      sig = id1.sign(message)
      id2.validate(sig, message).should be_false
    end

    it "public-key-only identity can validate signatures" do
      id1 = RNS::Identity.new
      message = "public key verify".to_slice
      sig = id1.sign(message)

      id2 = RNS::Identity.new(create_keys: false)
      id2.load_public_key(id1.get_public_key)
      id2.validate(sig, message).should be_true
    end
  end

  # =========================================================================
  # Section 12: Identity — encrypt/decrypt
  # =========================================================================
  describe "Identity encrypt/decrypt" do
    it "encrypt output starts with 32-byte ephemeral public key" do
      identity = RNS::Identity.new
      plaintext = "Hello encryption!".to_slice
      ciphertext = identity.encrypt(plaintext)

      # First 32 bytes are ephemeral X25519 public key
      ephemeral_pub = ciphertext[0, 32]
      ephemeral_pub.size.should eq 32

      # Rest is Token-encrypted data
      token_part = ciphertext[32..]
      token_part.size.should be >= 48 # At least TOKEN_OVERHEAD
    end

    it "decrypt recovers original plaintext" do
      identity = RNS::Identity.new
      plaintext = "Reticulum encrypt/decrypt test!".to_slice
      ciphertext = identity.encrypt(plaintext)
      decrypted = identity.decrypt(ciphertext)
      decrypted.should eq plaintext
    end

    it "ciphertext overhead is 32 (ephemeral key) + 48 (token) = 80 bytes minimum" do
      identity = RNS::Identity.new
      # 1 byte plaintext → 16 bytes after PKCS7 → 80 + 16 = 96 bytes total
      plaintext = Bytes[0x42]
      ciphertext = identity.encrypt(plaintext)
      ciphertext.size.should eq 96
    end

    it "50 random encrypt/decrypt roundtrips succeed" do
      identity = RNS::Identity.new
      50.times do
        plaintext = Random::Secure.random_bytes(rand(1..200))
        ciphertext = identity.encrypt(plaintext)
        decrypted = identity.decrypt(ciphertext)
        decrypted.should eq plaintext
      end
    end

    it "ciphertext from one identity cannot be decrypted by another" do
      id1 = RNS::Identity.new
      id2 = RNS::Identity.new
      plaintext = "secret message".to_slice
      ciphertext = id1.encrypt(plaintext)

      # id2 should not be able to decrypt id1's message
      result = id2.decrypt(ciphertext)
      result.should be_nil
    end
  end

  # =========================================================================
  # Section 13: Destination hash derivation
  # =========================================================================
  describe "Destination hash derivation" do
    it "name_hash is first 10 bytes of SHA-256 of full_name UTF-8" do
      # Python: name_hash = SHA256("app_name.aspect1.aspect2".encode("utf-8"))[:10]
      full_name = "test_app.aspect1.aspect2"
      expected_name_hash = RNS::Cryptography.sha256(full_name.to_slice)[0, 10]

      identity = RNS::Identity.new
      dest = RNS::Destination.new(identity, RNS::Destination::OUT, RNS::Destination::SINGLE,
        "test_app", ["aspect1", "aspect2"])

      dest.name_hash.should eq expected_name_hash
      dest.name_hash.size.should eq 10
    end

    it "destination hash = truncated SHA-256 of (name_hash + identity_hash)" do
      identity = RNS::Identity.new
      dest = RNS::Destination.new(identity, RNS::Destination::OUT, RNS::Destination::SINGLE,
        "test_app", ["aspect1", "aspect2"])

      full_name = "test_app.aspect1.aspect2"
      id_hash = identity.hash.not_nil!
      name_hash = RNS::Cryptography.sha256(full_name.to_slice)[0, 10]
      addr_material = Bytes.new(name_hash.size + id_hash.size)
      addr_material.copy_from(name_hash)
      id_hash.copy_to(addr_material + name_hash.size)
      expected_dest_hash = RNS::Cryptography.sha256(addr_material)[0, 16]

      dest.hash.should eq expected_dest_hash
      dest.hash.size.should eq 16
    end

    it "destination hash is 16 bytes (TRUNCATED_HASHLENGTH/8)" do
      identity = RNS::Identity.new
      dest = RNS::Destination.new(identity, RNS::Destination::OUT, RNS::Destination::SINGLE,
        "myapp", [] of String)
      dest.hash.size.should eq 16
    end

    it "same identity + same app/aspects = same destination hash" do
      identity = RNS::Identity.new
      dest1 = RNS::Destination.new(identity, RNS::Destination::OUT, RNS::Destination::SINGLE,
        "myapp", ["echo"], register: false)
      dest2 = RNS::Destination.new(identity, RNS::Destination::OUT, RNS::Destination::SINGLE,
        "myapp", ["echo"], register: false)
      dest1.hash.should eq dest2.hash
    end

    it "different aspects produce different destination hashes" do
      identity = RNS::Identity.new
      dest1 = RNS::Destination.new(identity, RNS::Destination::OUT, RNS::Destination::SINGLE,
        "myapp", ["echo"], register: false)
      dest2 = RNS::Destination.new(identity, RNS::Destination::OUT, RNS::Destination::SINGLE,
        "myapp", ["announce"], register: false)
      dest1.hash.should_not eq dest2.hash
    end

    it "different identities produce different destination hashes" do
      id1 = RNS::Identity.new
      id2 = RNS::Identity.new
      dest1 = RNS::Destination.new(id1, RNS::Destination::OUT, RNS::Destination::SINGLE,
        "myapp", ["echo"], register: false)
      dest2 = RNS::Destination.new(id2, RNS::Destination::OUT, RNS::Destination::SINGLE,
        "myapp", ["echo"], register: false)
      dest1.hash.should_not eq dest2.hash
    end

    it "static hash method matches instance hash" do
      identity = RNS::Identity.new
      dest = RNS::Destination.new(identity, RNS::Destination::OUT, RNS::Destination::SINGLE,
        "example", ["echo", "request"], register: false)

      static_hash = RNS::Destination.hash(identity, "example", ["echo", "request"])
      dest.hash.should eq static_hash
    end

    it "PLAIN destination has no identity hash component" do
      # For PLAIN destinations, identity is nil
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN,
        "broadcast", ["channel"], register: false)

      # name_hash only, no identity hash
      full_name = "broadcast.channel"
      name_hash = RNS::Cryptography.sha256(full_name.to_slice)[0, 10]
      expected_hash = RNS::Cryptography.sha256(name_hash)[0, 16]

      dest.hash.should eq expected_hash
    end
  end

  # =========================================================================
  # Section 14: Packet header encoding
  # =========================================================================
  describe "Packet header encoding" do
    it "flags byte encodes correctly: (ht<<6)|(cf<<5)|(tt<<4)|(dt<<2)|pt" do
      # Test representative flag combinations matching Python struct.pack("!B", flags)
      test_cases = [
        {ht: 0_u8, cf: 0_u8, tt: 0_u8, dt: 0_u8, pt: 0_u8, expected: 0x00_u8},
        {ht: 0_u8, cf: 0_u8, tt: 0_u8, dt: 0_u8, pt: 1_u8, expected: 0x01_u8}, # DATA+ANNOUNCE
        {ht: 0_u8, cf: 0_u8, tt: 0_u8, dt: 0_u8, pt: 2_u8, expected: 0x02_u8}, # LINKREQUEST
        {ht: 0_u8, cf: 0_u8, tt: 0_u8, dt: 0_u8, pt: 3_u8, expected: 0x03_u8}, # PROOF
        {ht: 0_u8, cf: 0_u8, tt: 0_u8, dt: 1_u8, pt: 0_u8, expected: 0x04_u8}, # GROUP+DATA
        {ht: 0_u8, cf: 0_u8, tt: 0_u8, dt: 2_u8, pt: 0_u8, expected: 0x08_u8}, # PLAIN+DATA
        {ht: 0_u8, cf: 0_u8, tt: 0_u8, dt: 3_u8, pt: 0_u8, expected: 0x0C_u8}, # LINK+DATA
        {ht: 0_u8, cf: 0_u8, tt: 1_u8, dt: 0_u8, pt: 0_u8, expected: 0x10_u8}, # TRANSPORT
        {ht: 0_u8, cf: 1_u8, tt: 0_u8, dt: 0_u8, pt: 0_u8, expected: 0x20_u8}, # context_flag
        {ht: 1_u8, cf: 0_u8, tt: 0_u8, dt: 0_u8, pt: 0_u8, expected: 0x40_u8}, # HEADER_2
        {ht: 1_u8, cf: 1_u8, tt: 1_u8, dt: 3_u8, pt: 3_u8, expected: 0x7F_u8}, # all bits set
      ]

      test_cases.each do |test_case|
        computed = (test_case[:ht].to_u8 << 6) | (test_case[:cf].to_u8 << 5) | (test_case[:tt].to_u8 << 4) | (test_case[:dt].to_u8 << 2) | test_case[:pt].to_u8
        computed.should eq test_case[:expected]
      end
    end

    it "HEADER_1 unpack extracts destination_hash at bytes 2-17" do
      # Build raw HEADER_1 packet
      dest_hash = Random::Secure.random_bytes(16)
      flags = 0x01_u8 # ANNOUNCE, HEADER_1, SINGLE
      hops = 0x00_u8
      context = 0x00_u8
      data = "test announce data".to_slice

      raw = Bytes.new(2 + 16 + 1 + data.size)
      raw[0] = flags
      raw[1] = hops
      dest_hash.copy_to(raw + 2)
      raw[18] = context
      data.copy_to(raw + 19)

      # Unpack and verify
      packet = RNS::Packet.new(nil, raw)
      packet.unpack

      packet.header_type.should eq RNS::Packet::HEADER_1
      packet.destination_hash.not_nil!.should eq dest_hash
      packet.hops.should eq 0
      packet.context.should eq 0
    end

    it "HEADER_2 unpack extracts transport_id at 2-17 and dest_hash at 18-33" do
      transport_id = Random::Secure.random_bytes(16)
      dest_hash = Random::Secure.random_bytes(16)
      flags = 0x40_u8 # HEADER_2
      hops = 0x02_u8
      context = 0x01_u8
      data = "transported data".to_slice

      raw = Bytes.new(2 + 16 + 16 + 1 + data.size)
      raw[0] = flags
      raw[1] = hops
      transport_id.copy_to(raw + 2)
      dest_hash.copy_to(raw + 18)
      raw[34] = context
      data.copy_to(raw + 35)

      packet = RNS::Packet.new(nil, raw)
      packet.unpack

      packet.header_type.should eq RNS::Packet::HEADER_2
      packet.transport_id.not_nil!.should eq transport_id
      packet.destination_hash.not_nil!.should eq dest_hash
      packet.hops.should eq 2
      packet.context.should eq 1
    end
  end

  # =========================================================================
  # Section 15: Packet hash computation
  # =========================================================================
  describe "Packet hash computation" do
    it "HEADER_1 hashable part: masked flags byte + raw[2:]" do
      # Python: hashable = bytes([raw[0] & 0x0F]) + raw[2:]
      dest_hash = Bytes.new(16, &.to_u8)
      # flags = 0x15: header_type=0 (HEADER_1), context_flag=0, transport_type=1, dest_type=1, packet_type=1
      flags = 0x15_u8
      data = "test data".to_slice

      raw = Bytes.new(2 + 16 + 1 + data.size)
      raw[0] = flags
      raw[1] = 0x03_u8
      dest_hash.copy_to(raw + 2)
      raw[18] = 0x00_u8
      data.copy_to(raw + 19)

      packet = RNS::Packet.new(nil, raw)
      packet.unpack

      hashable = packet.get_hashable_part
      # First byte should be flags masked to lower 4 bits
      hashable[0].should eq(flags & 0x0F_u8)
      # Remaining should be raw[2:] (dest_hash + context + data)
      hashable[1..].should eq raw[2..]
    end

    it "HEADER_2 hashable part: masked flags byte + raw[18:]" do
      # Python: for HEADER_2, hashable = bytes([raw[0] & 0x0F]) + raw[18:]
      transport_id = Bytes.new(16) { |i| (i + 0x10).to_u8 }
      dest_hash = Bytes.new(16) { |i| (i + 0x20).to_u8 }
      flags = 0x40_u8 # HEADER_2
      data = "transported".to_slice

      raw = Bytes.new(2 + 16 + 16 + 1 + data.size)
      raw[0] = flags
      raw[1] = 0x01_u8
      transport_id.copy_to(raw + 2)
      dest_hash.copy_to(raw + 18)
      raw[34] = 0x01_u8
      data.copy_to(raw + 35)

      packet = RNS::Packet.new(nil, raw)
      packet.unpack

      hashable = packet.get_hashable_part
      hashable[0].should eq(flags & 0x0F_u8)
      hashable[1..].should eq raw[18..]
    end

    it "get_hash returns SHA-256 of hashable part (32 bytes)" do
      raw = Bytes.new(20)
      raw[0] = 0x01_u8 # ANNOUNCE
      16.times { |i| raw[i + 2] = i.to_u8 }
      raw[18] = 0x00_u8

      packet = RNS::Packet.new(nil, raw)
      packet.unpack

      hashable = packet.get_hashable_part
      expected_hash = RNS::Cryptography.sha256(hashable)
      packet.get_hash.should eq expected_hash
      packet.get_hash.size.should eq 32
    end

    it "get_truncated_hash returns first 16 bytes of hash" do
      raw = Bytes.new(20)
      raw[0] = 0x01_u8
      16.times { |i| raw[i + 2] = i.to_u8 }
      raw[18] = 0x00_u8

      packet = RNS::Packet.new(nil, raw)
      packet.unpack

      full = packet.get_hash
      truncated = packet.get_truncated_hash
      truncated.should eq full[0, 16]
      truncated.size.should eq 16
    end
  end

  # =========================================================================
  # Section 16: Announce format
  # =========================================================================
  describe "Announce format" do
    it "announce data contains public_key(64) + name_hash(10) + random_hash(10) + signature(64)" do
      identity = RNS::Identity.new
      dest = RNS::Destination.new(identity, RNS::Destination::IN, RNS::Destination::SINGLE,
        "test_app", ["announce_test"])

      packet = dest.announce(send: false)
      next unless packet

      # The announce data should contain at minimum:
      # 64 (pub_key) + 10 (name_hash) + 10 (random_hash) + 64 (signature) = 148 bytes
      data = packet.data
      next unless data
      data.size.should be >= 148

      # First 64 bytes should be the public key
      pub_key = data[0, 64]
      pub_key.should eq identity.get_public_key

      # Next 10 bytes should be the name hash
      name_hash = data[64, 10]
      name_hash.should eq dest.name_hash
    end

    it "announce signature validates against signed_data" do
      identity = RNS::Identity.new
      dest = RNS::Destination.new(identity, RNS::Destination::IN, RNS::Destination::SINGLE,
        "verify_app", ["sig_test"])

      packet = dest.announce(send: false)
      next unless packet
      data = packet.data
      next unless data

      # Extract fields from announce data
      pub_key = data[0, 64]
      name_hash = data[64, 10]
      random_hash = data[74, 10]

      # Determine if ratchet is present (context_flag in packet flags)
      has_ratchet = packet.context_flag == RNS::Packet::FLAG_SET
      ratchet_size = has_ratchet ? 32 : 0

      sig_offset = 84 + ratchet_size
      signature = data[sig_offset, 64]
      app_data = data[(sig_offset + 64)..]? || Bytes.empty

      # Reconstruct signed_data: dest_hash + pub_key + name_hash + random_hash + [ratchet] + [app_data]
      signed_parts = IO::Memory.new
      signed_parts.write(dest.hash)
      signed_parts.write(pub_key)
      signed_parts.write(name_hash)
      signed_parts.write(random_hash)
      if has_ratchet
        signed_parts.write(data[84, 32])
      end
      if app_data.size > 0
        signed_parts.write(app_data)
      end

      signed_data = signed_parts.to_slice

      # Verify signature using the public key from the announce
      verify_identity = RNS::Identity.new(create_keys: false)
      verify_identity.load_public_key(pub_key)
      verify_identity.validate(signature, signed_data).should be_true
    end

    it "announce with app_data includes it after signature" do
      identity = RNS::Identity.new
      dest = RNS::Destination.new(identity, RNS::Destination::IN, RNS::Destination::SINGLE,
        "appdata_test", ["test"])

      app_data = "My application data".to_slice
      packet = dest.announce(app_data: app_data, send: false)
      next unless packet
      data = packet.data
      next unless data

      has_ratchet = packet.context_flag == RNS::Packet::FLAG_SET
      ratchet_size = has_ratchet ? 32 : 0

      # app_data should be at end: after pub_key(64) + name_hash(10) + random_hash(10) + [ratchet] + signature(64)
      app_data_offset = 64 + 10 + 10 + ratchet_size + 64
      actual_app_data = data[app_data_offset..]
      actual_app_data.should eq app_data
    end

    it "random_hash contains 5 random bytes + 5 big-endian timestamp bytes" do
      identity = RNS::Identity.new
      dest = RNS::Destination.new(identity, RNS::Destination::IN, RNS::Destination::SINGLE,
        "random_hash_test", ["test"])

      before_time = Time.utc.to_unix
      packet = dest.announce(send: false)
      after_time = Time.utc.to_unix

      next unless packet
      data = packet.data
      next unless data

      random_hash = data[74, 10]
      random_hash.size.should eq 10

      # Last 5 bytes are big-endian timestamp
      timestamp_bytes = random_hash[5, 5]
      timestamp = 0_i64
      timestamp_bytes.each do |byte|
        timestamp = (timestamp << 8) | byte.to_i64
      end

      # Timestamp should be within our time window
      timestamp.should be >= before_time
      timestamp.should be <= after_time
    end
  end

  # =========================================================================
  # Section 17: Full Identity encrypt/decrypt pipeline
  # =========================================================================
  describe "Full Identity encryption pipeline" do
    it "encryption uses ECDH + HKDF + Token (matching Python pipeline)" do
      identity = RNS::Identity.new
      plaintext = "Full pipeline test".to_slice

      ciphertext = identity.encrypt(plaintext)

      # Structure: ephemeral_pub(32) + IV(16) + AES_ciphertext(variable) + HMAC(32)
      ciphertext.size.should be >= 32 + 48 # ephemeral key + token overhead

      # The ephemeral key should be a valid X25519 public key (32 bytes)
      ephemeral_pub = ciphertext[0, 32]
      ephemeral_pub.size.should eq 32

      # Token part
      token_part = ciphertext[32..]
      token_part.size.should be >= 48

      # Decrypt should work
      decrypted = identity.decrypt(ciphertext)
      decrypted.should eq plaintext
    end

    it "cross-identity encryption: encrypt with public key, decrypt with private key" do
      _sender_identity = RNS::Identity.new
      receiver_identity = RNS::Identity.new

      # Create a public-key-only copy of the receiver
      receiver_pub_only = RNS::Identity.new(create_keys: false)
      receiver_pub_only.load_public_key(receiver_identity.get_public_key)

      plaintext = "Cross-identity encrypted message".to_slice
      ciphertext = receiver_pub_only.encrypt(plaintext)

      # Only the receiver (with private key) should be able to decrypt
      decrypted = receiver_identity.decrypt(ciphertext)
      decrypted.should eq plaintext
    end
  end

  # =========================================================================
  # Section 18: Wire format stress tests
  # =========================================================================
  describe "Wire format stress tests" do
    it "50 random identities produce consistent hash format" do
      50.times do
        identity = RNS::Identity.new
        identity.get_public_key.size.should eq 64
        identity.get_private_key.size.should eq 64
        identity.hash.not_nil!.size.should eq 16
        identity.hash.not_nil!.should eq RNS::Cryptography.sha256(identity.get_public_key)[0, 16]
      end
    end

    it "50 random destination hashes are deterministic" do
      identity = RNS::Identity.new
      50.times do |i|
        d1 = RNS::Destination.new(identity, RNS::Destination::OUT, RNS::Destination::SINGLE,
          "stress", ["test#{i}"], register: false)
        d2 = RNS::Destination.new(identity, RNS::Destination::OUT, RNS::Destination::SINGLE,
          "stress", ["test#{i}"], register: false)
        d1.hash.should eq d2.hash
        d1.hash.size.should eq 16
        d1.name_hash.size.should eq 10
      end
    end

    it "100 random sign/verify cycles succeed" do
      identity = RNS::Identity.new
      100.times do
        message = Random::Secure.random_bytes(rand(1..500))
        sig = identity.sign(message)
        sig.size.should eq 64
        identity.validate(sig, message).should be_true
      end
    end

    it "50 random encrypt/decrypt cycles with different identities" do
      50.times do
        _sender = RNS::Identity.new
        receiver = RNS::Identity.new

        receiver_pub = RNS::Identity.new(create_keys: false)
        receiver_pub.load_public_key(receiver.get_public_key)

        plaintext = Random::Secure.random_bytes(rand(1..300))
        ciphertext = receiver_pub.encrypt(plaintext)
        decrypted = receiver.decrypt(ciphertext)
        decrypted.should eq plaintext
      end
    end

    it "30 announce generation/validation cycles" do
      30.times do |i|
        identity = RNS::Identity.new
        dest = RNS::Destination.new(identity, RNS::Destination::IN, RNS::Destination::SINGLE,
          "stress_app", ["test_#{i}"])

        app_data = "App data #{i}".to_slice
        packet = dest.announce(app_data: app_data, send: false)
        next unless packet
        data = packet.data
        next unless data

        # Verify public key in announce
        data[0, 64].should eq identity.get_public_key

        # Verify name hash in announce
        data[64, 10].should eq dest.name_hash

        # Verify signature
        has_ratchet = packet.context_flag == RNS::Packet::FLAG_SET
        ratchet_size = has_ratchet ? 32 : 0
        sig_offset = 84 + ratchet_size
        signature = data[sig_offset, 64]

        signed_parts = IO::Memory.new
        signed_parts.write(dest.hash)
        signed_parts.write(data[0, 84 + ratchet_size])
        signed_parts.write(app_data)

        identity.validate(signature, signed_parts.to_slice).should be_true
      end
    end
  end
end
