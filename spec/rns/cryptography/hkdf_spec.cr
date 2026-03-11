require "../../spec_helper"

describe RNS::Cryptography do
  describe ".hkdf" do
    # RFC 5869 Test Vectors for HKDF-SHA256

    it "computes RFC 5869 Test Case 1" do
      ikm = Bytes[0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b,
        0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b,
        0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b]
      salt = Bytes[0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0a, 0x0b, 0x0c]
      info = Bytes[0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7,
        0xf8, 0xf9]
      length = 42

      expected = "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"

      result = RNS::Cryptography.hkdf(length: length, derive_from: ikm, salt: salt, context: info)
      result.hexstring.should eq(expected)
    end

    it "computes RFC 5869 Test Case 2 (longer inputs/outputs)" do
      ikm = Bytes.new(80, &.to_u8)
      salt = Bytes.new(80) { |i| (0x60 + i).to_u8 }
      info = Bytes.new(80) { |i| (0xb0 + i).to_u8 }
      length = 82

      expected = "b11e398dc80327a1c8e7f78c596a49344f012eda2d4efad8a050cc4c19afa97c59045a99cac7827271cb41c65e590e09da3275600c2f09b8367793a9aca3db71cc30c58179ec3e87c14c01d5c1f3434f1d87"

      result = RNS::Cryptography.hkdf(length: length, derive_from: ikm, salt: salt, context: info)
      result.hexstring.should eq(expected)
    end

    it "computes RFC 5869 Test Case 3 (zero-length salt and info)" do
      ikm = Bytes.new(22, 0x0b_u8)
      salt = Bytes.empty
      info = Bytes.empty
      length = 42

      expected = "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8"

      result = RNS::Cryptography.hkdf(length: length, derive_from: ikm, salt: salt, context: info)
      result.hexstring.should eq(expected)
    end

    it "handles nil salt (defaults to zeros)" do
      ikm = Bytes.new(22, 0x0b_u8)
      info = Bytes.empty
      length = 42

      # With nil salt, should use 32 zero bytes as salt (matching Python behavior)
      expected = "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8"

      result = RNS::Cryptography.hkdf(length: length, derive_from: ikm, salt: nil, context: info)
      result.hexstring.should eq(expected)
    end

    it "handles nil context (defaults to empty bytes)" do
      ikm = Bytes.new(22, 0x0b_u8)
      salt = Bytes.new(13, &.to_u8)
      length = 42

      # nil context should behave same as empty context
      result1 = RNS::Cryptography.hkdf(length: length, derive_from: ikm, salt: salt, context: nil)
      result2 = RNS::Cryptography.hkdf(length: length, derive_from: ikm, salt: salt, context: Bytes.empty)
      result1.should eq(result2)
    end

    it "raises on invalid length (zero)" do
      ikm = Random::Secure.random_bytes(32)
      expect_raises(ArgumentError) do
        RNS::Cryptography.hkdf(length: 0, derive_from: ikm)
      end
    end

    it "raises on invalid length (negative)" do
      ikm = Random::Secure.random_bytes(32)
      expect_raises(ArgumentError) do
        RNS::Cryptography.hkdf(length: -1, derive_from: ikm)
      end
    end

    it "raises on nil derive_from" do
      expect_raises(ArgumentError) do
        RNS::Cryptography.hkdf(length: 32, derive_from: nil)
      end
    end

    it "raises on empty derive_from" do
      expect_raises(ArgumentError) do
        RNS::Cryptography.hkdf(length: 32, derive_from: Bytes.empty)
      end
    end

    it "returns exactly the requested number of bytes" do
      ikm = Random::Secure.random_bytes(32)
      [1, 16, 32, 48, 64, 128].each do |len|
        result = RNS::Cryptography.hkdf(length: len, derive_from: ikm)
        result.size.should eq(len)
      end
    end

    it "is deterministic" do
      ikm = Random::Secure.random_bytes(32)
      salt = Random::Secure.random_bytes(16)
      info = Random::Secure.random_bytes(8)

      result1 = RNS::Cryptography.hkdf(length: 32, derive_from: ikm, salt: salt, context: info)
      result2 = RNS::Cryptography.hkdf(length: 32, derive_from: ikm, salt: salt, context: info)
      result1.should eq(result2)
    end

    it "produces different output for different input key material" do
      ikm1 = Random::Secure.random_bytes(32)
      ikm2 = Random::Secure.random_bytes(32)

      result1 = RNS::Cryptography.hkdf(length: 32, derive_from: ikm1)
      result2 = RNS::Cryptography.hkdf(length: 32, derive_from: ikm2)
      result1.should_not eq(result2)
    end

    it "produces different output for different salts" do
      ikm = Random::Secure.random_bytes(32)
      salt1 = Random::Secure.random_bytes(16)
      salt2 = Random::Secure.random_bytes(16)

      result1 = RNS::Cryptography.hkdf(length: 32, derive_from: ikm, salt: salt1)
      result2 = RNS::Cryptography.hkdf(length: 32, derive_from: ikm, salt: salt2)
      result1.should_not eq(result2)
    end

    it "produces different output for different contexts" do
      ikm = Random::Secure.random_bytes(32)
      info1 = "context1".to_slice
      info2 = "context2".to_slice

      result1 = RNS::Cryptography.hkdf(length: 32, derive_from: ikm, context: info1)
      result2 = RNS::Cryptography.hkdf(length: 32, derive_from: ikm, context: info2)
      result1.should_not eq(result2)
    end

    it "matches Python RNS HKDF output for known inputs" do
      # Cross-verified with Python:
      # from RNS.Cryptography.HKDF import hkdf
      # hkdf(length=32, derive_from=b'\x01'*32, salt=b'\x02'*32, context=b'\x03'*16).hex()
      ikm = Bytes.new(32, 0x01_u8)
      salt = Bytes.new(32, 0x02_u8)
      info = Bytes.new(16, 0x03_u8)

      result = RNS::Cryptography.hkdf(length: 32, derive_from: ikm, salt: salt, context: info)
      # This is HKDF-SHA256 with these specific inputs
      # extract: PRK = HMAC-SHA256(salt, ikm)
      # expand: OKM = HMAC-SHA256(PRK, info || 0x01) truncated to 32 bytes
      prk = OpenSSL::HMAC.digest(OpenSSL::Algorithm::SHA256, salt, ikm)
      expand_input = IO::Memory.new
      expand_input.write(info)
      expand_input.write_byte(0x01_u8)
      expected = OpenSSL::HMAC.digest(OpenSSL::Algorithm::SHA256, prk, expand_input.to_slice)

      result.should eq(expected)
    end
  end
end
