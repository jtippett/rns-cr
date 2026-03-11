require "../../spec_helper"

describe RNS::Cryptography::AES256CBC do
  describe ".encrypt and .decrypt" do
    it "roundtrips a single block" do
      key = Random::Secure.random_bytes(32)
      iv = Random::Secure.random_bytes(16)
      plaintext = RNS::Cryptography::PKCS7.pad(Bytes[1, 2, 3, 4, 5])

      ciphertext = RNS::Cryptography::AES256CBC.encrypt(plaintext, key, iv)
      decrypted = RNS::Cryptography::AES256CBC.decrypt(ciphertext, key, iv)
      decrypted.should eq(plaintext)
    end

    it "roundtrips multiple blocks" do
      key = Random::Secure.random_bytes(32)
      iv = Random::Secure.random_bytes(16)
      data = Random::Secure.random_bytes(100)
      plaintext = RNS::Cryptography::PKCS7.pad(data)

      ciphertext = RNS::Cryptography::AES256CBC.encrypt(plaintext, key, iv)
      decrypted = RNS::Cryptography::AES256CBC.decrypt(ciphertext, key, iv)
      RNS::Cryptography::PKCS7.unpad(decrypted).should eq(data)
    end

    it "produces different ciphertext with different keys" do
      key1 = Random::Secure.random_bytes(32)
      key2 = Random::Secure.random_bytes(32)
      iv = Random::Secure.random_bytes(16)
      plaintext = RNS::Cryptography::PKCS7.pad("Hello, World!".to_slice)

      ct1 = RNS::Cryptography::AES256CBC.encrypt(plaintext, key1, iv)
      ct2 = RNS::Cryptography::AES256CBC.encrypt(plaintext, key2, iv)
      ct1.should_not eq(ct2)
    end

    it "produces different ciphertext with different IVs" do
      key = Random::Secure.random_bytes(32)
      iv1 = Random::Secure.random_bytes(16)
      iv2 = Random::Secure.random_bytes(16)
      plaintext = RNS::Cryptography::PKCS7.pad("Hello, World!".to_slice)

      ct1 = RNS::Cryptography::AES256CBC.encrypt(plaintext, key, iv1)
      ct2 = RNS::Cryptography::AES256CBC.encrypt(plaintext, key, iv2)
      ct1.should_not eq(ct2)
    end

    it "ciphertext size equals padded plaintext size" do
      key = Random::Secure.random_bytes(32)
      iv = Random::Secure.random_bytes(16)
      plaintext = RNS::Cryptography::PKCS7.pad(Random::Secure.random_bytes(42))

      ciphertext = RNS::Cryptography::AES256CBC.encrypt(plaintext, key, iv)
      ciphertext.size.should eq(plaintext.size)
    end

    it "raises on invalid key length (too short)" do
      key = Random::Secure.random_bytes(16)
      iv = Random::Secure.random_bytes(16)
      plaintext = RNS::Cryptography::PKCS7.pad(Bytes[1])

      expect_raises(ArgumentError, "Invalid key length 128 for AES-256-CBC") do
        RNS::Cryptography::AES256CBC.encrypt(plaintext, key, iv)
      end
    end

    it "raises on invalid key length for decrypt (too short)" do
      key = Random::Secure.random_bytes(16)
      iv = Random::Secure.random_bytes(16)
      ciphertext = Random::Secure.random_bytes(16)

      expect_raises(ArgumentError, "Invalid key length 128 for AES-256-CBC") do
        RNS::Cryptography::AES256CBC.decrypt(ciphertext, key, iv)
      end
    end

    it "matches NIST AES-256-CBC test vector" do
      # NIST SP 800-38A F.2.5 CBC-AES256.Encrypt
      key = Bytes[
        0x60, 0x3d, 0xeb, 0x10, 0x15, 0xca, 0x71, 0xbe,
        0x2b, 0x73, 0xae, 0xf0, 0x85, 0x7d, 0x77, 0x81,
        0x1f, 0x35, 0x2c, 0x07, 0x3b, 0x61, 0x08, 0xd7,
        0x2d, 0x98, 0x10, 0xa3, 0x09, 0x14, 0xdf, 0xf4,
      ]
      iv = Bytes[
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
      ]
      # Block 1 plaintext
      plaintext = Bytes[
        0x6b, 0xc1, 0xbe, 0xe2, 0x2e, 0x40, 0x9f, 0x96,
        0xe9, 0x3d, 0x7e, 0x11, 0x73, 0x93, 0x17, 0x2a,
      ]
      # Expected ciphertext for block 1
      expected = Bytes[
        0xf5, 0x8c, 0x4c, 0x04, 0xd6, 0xe5, 0xf1, 0xba,
        0x77, 0x9e, 0xab, 0xfb, 0x5f, 0x7b, 0xfb, 0xd6,
      ]

      ciphertext = RNS::Cryptography::AES256CBC.encrypt(plaintext, key, iv)
      ciphertext.should eq(expected)

      decrypted = RNS::Cryptography::AES256CBC.decrypt(ciphertext, key, iv)
      decrypted.should eq(plaintext)
    end

    it "matches NIST AES-256-CBC multi-block test vector" do
      # NIST SP 800-38A F.2.5 CBC-AES256.Encrypt (all 4 blocks)
      key = Bytes[
        0x60, 0x3d, 0xeb, 0x10, 0x15, 0xca, 0x71, 0xbe,
        0x2b, 0x73, 0xae, 0xf0, 0x85, 0x7d, 0x77, 0x81,
        0x1f, 0x35, 0x2c, 0x07, 0x3b, 0x61, 0x08, 0xd7,
        0x2d, 0x98, 0x10, 0xa3, 0x09, 0x14, 0xdf, 0xf4,
      ]
      iv = Bytes[
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
      ]
      plaintext = Bytes[
        0x6b, 0xc1, 0xbe, 0xe2, 0x2e, 0x40, 0x9f, 0x96,
        0xe9, 0x3d, 0x7e, 0x11, 0x73, 0x93, 0x17, 0x2a,
        0xae, 0x2d, 0x8a, 0x57, 0x1e, 0x03, 0xac, 0x9c,
        0x9e, 0xb7, 0x6f, 0xac, 0x45, 0xaf, 0x8e, 0x51,
        0x30, 0xc8, 0x1c, 0x46, 0xa3, 0x5c, 0xe4, 0x11,
        0xe5, 0xfb, 0xc1, 0x19, 0x1a, 0x0a, 0x52, 0xef,
        0xf6, 0x9f, 0x24, 0x45, 0xdf, 0x4f, 0x9b, 0x17,
        0xad, 0x2b, 0x41, 0x7b, 0xe6, 0x6c, 0x37, 0x10,
      ]
      expected = Bytes[
        0xf5, 0x8c, 0x4c, 0x04, 0xd6, 0xe5, 0xf1, 0xba,
        0x77, 0x9e, 0xab, 0xfb, 0x5f, 0x7b, 0xfb, 0xd6,
        0x9c, 0xfc, 0x4e, 0x96, 0x7e, 0xdb, 0x80, 0x8d,
        0x67, 0x9f, 0x77, 0x7b, 0xc6, 0x70, 0x2c, 0x7d,
        0x39, 0xf2, 0x33, 0x69, 0xa9, 0xd9, 0xba, 0xcf,
        0xa5, 0x30, 0xe2, 0x63, 0x04, 0x23, 0x14, 0x61,
        0xb2, 0xeb, 0x05, 0xe2, 0xc3, 0x9b, 0xe9, 0xfc,
        0xda, 0x6c, 0x19, 0x07, 0x8c, 0x6a, 0x9d, 0x1b,
      ]

      ciphertext = RNS::Cryptography::AES256CBC.encrypt(plaintext, key, iv)
      ciphertext.should eq(expected)

      decrypted = RNS::Cryptography::AES256CBC.decrypt(ciphertext, key, iv)
      decrypted.should eq(plaintext)
    end

    it "roundtrips 1000 random iterations with PKCS7" do
      1000.times do
        key = Random::Secure.random_bytes(32)
        iv = Random::Secure.random_bytes(16)
        len = Random.new.rand(0..256)
        data = Random::Secure.random_bytes(len)
        padded = RNS::Cryptography::PKCS7.pad(data)
        ciphertext = RNS::Cryptography::AES256CBC.encrypt(padded, key, iv)
        decrypted = RNS::Cryptography::AES256CBC.decrypt(ciphertext, key, iv)
        unpadded = RNS::Cryptography::PKCS7.unpad(decrypted)
        unpadded.should eq(data)
      end
    end
  end
end

describe RNS::Cryptography::AES128CBC do
  describe ".encrypt and .decrypt" do
    it "roundtrips a single block" do
      key = Random::Secure.random_bytes(16)
      iv = Random::Secure.random_bytes(16)
      plaintext = RNS::Cryptography::PKCS7.pad(Bytes[1, 2, 3, 4, 5])

      ciphertext = RNS::Cryptography::AES128CBC.encrypt(plaintext, key, iv)
      decrypted = RNS::Cryptography::AES128CBC.decrypt(ciphertext, key, iv)
      decrypted.should eq(plaintext)
    end

    it "raises on invalid key length" do
      key = Random::Secure.random_bytes(32)
      iv = Random::Secure.random_bytes(16)
      plaintext = RNS::Cryptography::PKCS7.pad(Bytes[1])

      expect_raises(ArgumentError, "Invalid key length 256 for AES-128-CBC") do
        RNS::Cryptography::AES128CBC.encrypt(plaintext, key, iv)
      end
    end

    it "raises on invalid key length for decrypt" do
      key = Random::Secure.random_bytes(32)
      iv = Random::Secure.random_bytes(16)
      ciphertext = Random::Secure.random_bytes(16)

      expect_raises(ArgumentError, "Invalid key length 256 for AES-128-CBC") do
        RNS::Cryptography::AES128CBC.decrypt(ciphertext, key, iv)
      end
    end

    it "matches NIST AES-128-CBC test vector" do
      # NIST SP 800-38A F.2.1 CBC-AES128.Encrypt
      key = Bytes[
        0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6,
        0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c,
      ]
      iv = Bytes[
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
      ]
      plaintext = Bytes[
        0x6b, 0xc1, 0xbe, 0xe2, 0x2e, 0x40, 0x9f, 0x96,
        0xe9, 0x3d, 0x7e, 0x11, 0x73, 0x93, 0x17, 0x2a,
      ]
      expected = Bytes[
        0x76, 0x49, 0xab, 0xac, 0x81, 0x19, 0xb2, 0x46,
        0xce, 0xe9, 0x8e, 0x9b, 0x12, 0xe9, 0x19, 0x7d,
      ]

      ciphertext = RNS::Cryptography::AES128CBC.encrypt(plaintext, key, iv)
      ciphertext.should eq(expected)

      decrypted = RNS::Cryptography::AES128CBC.decrypt(ciphertext, key, iv)
      decrypted.should eq(plaintext)
    end

    it "roundtrips 1000 random iterations with PKCS7" do
      1000.times do
        key = Random::Secure.random_bytes(16)
        iv = Random::Secure.random_bytes(16)
        len = Random.new.rand(0..256)
        data = Random::Secure.random_bytes(len)
        padded = RNS::Cryptography::PKCS7.pad(data)
        ciphertext = RNS::Cryptography::AES128CBC.encrypt(padded, key, iv)
        decrypted = RNS::Cryptography::AES128CBC.decrypt(ciphertext, key, iv)
        unpadded = RNS::Cryptography::PKCS7.unpad(decrypted)
        unpadded.should eq(data)
      end
    end
  end
end
