require "../../spec_helper"

describe RNS::Cryptography::Token do
  describe "TOKEN_OVERHEAD" do
    it "is 48 bytes" do
      RNS::Cryptography::Token::TOKEN_OVERHEAD.should eq(48)
    end
  end

  describe ".generate_key" do
    it "generates a 64-byte key for AES-256-CBC (default)" do
      key = RNS::Cryptography::Token.generate_key
      key.size.should eq(64)
    end

    it "generates a 32-byte key for AES-128-CBC" do
      key = RNS::Cryptography::Token.generate_key(:aes_128_cbc)
      key.size.should eq(32)
    end

    it "generates a 64-byte key for AES-256-CBC explicitly" do
      key = RNS::Cryptography::Token.generate_key(:aes_256_cbc)
      key.size.should eq(64)
    end

    it "generates unique keys each time" do
      key1 = RNS::Cryptography::Token.generate_key
      key2 = RNS::Cryptography::Token.generate_key
      key1.should_not eq(key2)
    end

    it "raises on invalid mode" do
      expect_raises(ArgumentError) do
        RNS::Cryptography::Token.generate_key(:invalid)
      end
    end
  end

  describe "#initialize" do
    it "accepts a 64-byte key for AES-256-CBC" do
      key = RNS::Cryptography::Token.generate_key(:aes_256_cbc)
      token = RNS::Cryptography::Token.new(key)
      token.should_not be_nil
    end

    it "accepts a 32-byte key for AES-128-CBC" do
      key = RNS::Cryptography::Token.generate_key(:aes_128_cbc)
      token = RNS::Cryptography::Token.new(key)
      token.should_not be_nil
    end

    it "raises on invalid key size" do
      expect_raises(ArgumentError, /128 or 256 bits/) do
        RNS::Cryptography::Token.new(Bytes.new(48))
      end
    end

    it "raises on empty key" do
      expect_raises(ArgumentError) do
        RNS::Cryptography::Token.new(Bytes.new(0))
      end
    end

    it "splits 64-byte key into 32-byte signing and 32-byte encryption keys" do
      key = Bytes.new(64, &.to_u8)
      token = RNS::Cryptography::Token.new(key)
      # Verify by encrypting/decrypting — correct key split means it works
      plaintext = "test data".to_slice
      encrypted = token.encrypt(plaintext)
      decrypted = token.decrypt(encrypted)
      decrypted.should eq(plaintext)
    end

    it "splits 32-byte key into 16-byte signing and 16-byte encryption keys" do
      key = Bytes.new(32, &.to_u8)
      token = RNS::Cryptography::Token.new(key)
      plaintext = "test data".to_slice
      encrypted = token.encrypt(plaintext)
      decrypted = token.decrypt(encrypted)
      decrypted.should eq(plaintext)
    end
  end

  describe "#encrypt" do
    it "returns bytes larger than plaintext by TOKEN_OVERHEAD" do
      key = RNS::Cryptography::Token.generate_key
      token = RNS::Cryptography::Token.new(key)
      plaintext = "hello world".to_slice
      encrypted = token.encrypt(plaintext)
      # Overhead = 16 (IV) + 32 (HMAC) = 48, plus PKCS7 padding rounds up plaintext
      encrypted.size.should be > plaintext.size
      # Minimum size: TOKEN_OVERHEAD + one block (16 bytes for PKCS7 padding)
      encrypted.size.should be >= RNS::Cryptography::Token::TOKEN_OVERHEAD + 16
    end

    it "produces different ciphertext each time due to random IV" do
      key = RNS::Cryptography::Token.generate_key
      token = RNS::Cryptography::Token.new(key)
      plaintext = "deterministic test".to_slice
      enc1 = token.encrypt(plaintext)
      enc2 = token.encrypt(plaintext)
      enc1.should_not eq(enc2)
    end

    it "handles empty data" do
      key = RNS::Cryptography::Token.generate_key
      token = RNS::Cryptography::Token.new(key)
      plaintext = Bytes.empty
      encrypted = token.encrypt(plaintext)
      # Empty plaintext + PKCS7 pad = 16 bytes, plus 16 IV + 32 HMAC = 64 bytes
      encrypted.size.should eq(64)
    end

    it "handles large data" do
      key = RNS::Cryptography::Token.generate_key
      token = RNS::Cryptography::Token.new(key)
      plaintext = Random::Secure.random_bytes(10000)
      encrypted = token.encrypt(plaintext)
      encrypted.size.should be > plaintext.size
    end
  end

  describe "#decrypt" do
    it "recovers the original plaintext" do
      key = RNS::Cryptography::Token.generate_key
      token = RNS::Cryptography::Token.new(key)
      plaintext = "hello, reticulum!".to_slice
      encrypted = token.encrypt(plaintext)
      decrypted = token.decrypt(encrypted)
      decrypted.should eq(plaintext)
    end

    it "roundtrips with AES-128-CBC mode" do
      key = RNS::Cryptography::Token.generate_key(:aes_128_cbc)
      token = RNS::Cryptography::Token.new(key)
      plaintext = "128-bit mode test".to_slice
      encrypted = token.encrypt(plaintext)
      decrypted = token.decrypt(encrypted)
      decrypted.should eq(plaintext)
    end

    it "roundtrips with AES-256-CBC mode" do
      key = RNS::Cryptography::Token.generate_key(:aes_256_cbc)
      token = RNS::Cryptography::Token.new(key)
      plaintext = "256-bit mode test".to_slice
      encrypted = token.encrypt(plaintext)
      decrypted = token.decrypt(encrypted)
      decrypted.should eq(plaintext)
    end

    it "raises on tampered ciphertext" do
      key = RNS::Cryptography::Token.generate_key
      token = RNS::Cryptography::Token.new(key)
      encrypted = token.encrypt("secret".to_slice)
      # Tamper with ciphertext (between IV and HMAC)
      tampered = encrypted.dup
      tampered[20] = tampered[20] ^ 0xFF_u8
      expect_raises(ArgumentError, /HMAC/) do
        token.decrypt(tampered)
      end
    end

    it "raises on tampered HMAC" do
      key = RNS::Cryptography::Token.generate_key
      token = RNS::Cryptography::Token.new(key)
      encrypted = token.encrypt("secret".to_slice)
      tampered = encrypted.dup
      tampered[tampered.size - 1] = tampered[tampered.size - 1] ^ 0xFF_u8
      expect_raises(ArgumentError, /HMAC/) do
        token.decrypt(tampered)
      end
    end

    it "raises with wrong key" do
      key1 = RNS::Cryptography::Token.generate_key
      key2 = RNS::Cryptography::Token.generate_key
      token1 = RNS::Cryptography::Token.new(key1)
      token2 = RNS::Cryptography::Token.new(key2)
      encrypted = token1.encrypt("secret".to_slice)
      expect_raises(ArgumentError) do
        token2.decrypt(encrypted)
      end
    end

    it "raises on too-short token" do
      key = RNS::Cryptography::Token.generate_key
      token = RNS::Cryptography::Token.new(key)
      expect_raises(ArgumentError) do
        token.decrypt(Bytes.new(32))
      end
    end
  end

  describe "#verify_hmac" do
    it "returns true for valid token" do
      key = RNS::Cryptography::Token.generate_key
      token = RNS::Cryptography::Token.new(key)
      encrypted = token.encrypt("test".to_slice)
      token.verify_hmac(encrypted).should be_true
    end

    it "returns false for tampered token" do
      key = RNS::Cryptography::Token.generate_key
      token = RNS::Cryptography::Token.new(key)
      encrypted = token.encrypt("test".to_slice)
      tampered = encrypted.dup
      tampered[0] = tampered[0] ^ 0xFF_u8
      token.verify_hmac(tampered).should be_false
    end

    it "raises on token of 32 bytes or less" do
      key = RNS::Cryptography::Token.generate_key
      token = RNS::Cryptography::Token.new(key)
      expect_raises(ArgumentError) do
        token.verify_hmac(Bytes.new(32))
      end
    end
  end

  describe "overhead constant verification" do
    it "encrypted output is exactly plaintext_padded + TOKEN_OVERHEAD bytes" do
      key = RNS::Cryptography::Token.generate_key
      token = RNS::Cryptography::Token.new(key)

      # For block-aligned plaintext (16 bytes), PKCS7 adds a full block (16 bytes)
      # So padded = 32 bytes, encrypted = 32 + 48 = 80
      plaintext = Bytes.new(16, 0_u8)
      encrypted = token.encrypt(plaintext)
      encrypted.size.should eq(32 + RNS::Cryptography::Token::TOKEN_OVERHEAD)

      # For 1-byte plaintext, PKCS7 pads to 16 bytes
      # encrypted = 16 + 48 = 64
      plaintext = Bytes.new(1, 0_u8)
      encrypted = token.encrypt(plaintext)
      encrypted.size.should eq(16 + RNS::Cryptography::Token::TOKEN_OVERHEAD)

      # For 15-byte plaintext, PKCS7 pads to 16 bytes
      # encrypted = 16 + 48 = 64
      plaintext = Bytes.new(15, 0_u8)
      encrypted = token.encrypt(plaintext)
      encrypted.size.should eq(16 + RNS::Cryptography::Token::TOKEN_OVERHEAD)

      # For 17-byte plaintext, PKCS7 pads to 32 bytes
      # encrypted = 32 + 48 = 80
      plaintext = Bytes.new(17, 0_u8)
      encrypted = token.encrypt(plaintext)
      encrypted.size.should eq(32 + RNS::Cryptography::Token::TOKEN_OVERHEAD)
    end
  end

  describe "random roundtrip tests" do
    it "roundtrips 100 random plaintexts with AES-256-CBC" do
      key = RNS::Cryptography::Token.generate_key(:aes_256_cbc)
      token = RNS::Cryptography::Token.new(key)
      100.times do
        size = Random.rand(0..1000)
        plaintext = Random::Secure.random_bytes(size)
        encrypted = token.encrypt(plaintext)
        decrypted = token.decrypt(encrypted)
        decrypted.should eq(plaintext)
      end
    end

    it "roundtrips 100 random plaintexts with AES-128-CBC" do
      key = RNS::Cryptography::Token.generate_key(:aes_128_cbc)
      token = RNS::Cryptography::Token.new(key)
      100.times do
        size = Random.rand(0..1000)
        plaintext = Random::Secure.random_bytes(size)
        encrypted = token.encrypt(plaintext)
        decrypted = token.decrypt(encrypted)
        decrypted.should eq(plaintext)
      end
    end
  end
end
