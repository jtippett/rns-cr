require "../../spec_helper"

describe RNS::Cryptography::HMAC do
  # RFC 2104 / RFC 4231 test vectors for HMAC-SHA256

  describe ".digest" do
    it "computes HMAC-SHA256 with simple key and message" do
      # RFC 4231 Test Case 2
      key = "Jefe".to_slice
      data = "what do ya want for nothing?".to_slice
      expected = "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"

      result = RNS::Cryptography::HMAC.digest(key, data)
      result.hexstring.should eq(expected)
    end

    it "computes HMAC-SHA256 with RFC 4231 Test Case 1" do
      # Key = 20 bytes of 0x0b
      key = Bytes.new(20, 0x0b_u8)
      data = "Hi There".to_slice
      expected = "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"

      result = RNS::Cryptography::HMAC.digest(key, data)
      result.hexstring.should eq(expected)
    end

    it "computes HMAC-SHA256 with RFC 4231 Test Case 3" do
      # Key = 20 bytes of 0xaa
      key = Bytes.new(20, 0xaa_u8)
      # Data = 50 bytes of 0xdd
      data = Bytes.new(50, 0xdd_u8)
      expected = "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe"

      result = RNS::Cryptography::HMAC.digest(key, data)
      result.hexstring.should eq(expected)
    end

    it "computes HMAC-SHA256 with RFC 4231 Test Case 4" do
      key = Bytes.new(25) { |i| (i + 1).to_u8 }
      data = Bytes.new(50, 0xcd_u8)
      expected = "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b"

      result = RNS::Cryptography::HMAC.digest(key, data)
      result.hexstring.should eq(expected)
    end

    it "computes HMAC-SHA256 with key longer than block size (RFC 4231 Test Case 6)" do
      # Key = 131 bytes of 0xaa (longer than 64-byte block size)
      key = Bytes.new(131, 0xaa_u8)
      data = "Test Using Larger Than Block-Size Key - Hash Key First".to_slice
      expected = "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"

      result = RNS::Cryptography::HMAC.digest(key, data)
      result.hexstring.should eq(expected)
    end

    it "computes HMAC-SHA256 with long key and long data (RFC 4231 Test Case 7)" do
      key = Bytes.new(131, 0xaa_u8)
      data = "This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.".to_slice
      expected = "9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2"

      result = RNS::Cryptography::HMAC.digest(key, data)
      result.hexstring.should eq(expected)
    end

    it "returns 32 bytes for SHA256" do
      key = Random::Secure.random_bytes(32)
      data = Random::Secure.random_bytes(64)
      result = RNS::Cryptography::HMAC.digest(key, data)
      result.size.should eq(32)
    end

    it "produces different output for different keys" do
      data = "same message".to_slice
      key1 = Random::Secure.random_bytes(32)
      key2 = Random::Secure.random_bytes(32)
      result1 = RNS::Cryptography::HMAC.digest(key1, data)
      result2 = RNS::Cryptography::HMAC.digest(key2, data)
      result1.should_not eq(result2)
    end

    it "produces different output for different messages" do
      key = Random::Secure.random_bytes(32)
      result1 = RNS::Cryptography::HMAC.digest(key, "message1".to_slice)
      result2 = RNS::Cryptography::HMAC.digest(key, "message2".to_slice)
      result1.should_not eq(result2)
    end

    it "is deterministic" do
      key = Random::Secure.random_bytes(32)
      data = Random::Secure.random_bytes(64)
      result1 = RNS::Cryptography::HMAC.digest(key, data)
      result2 = RNS::Cryptography::HMAC.digest(key, data)
      result1.should eq(result2)
    end
  end

  describe ".new" do
    it "creates an HMAC object and produces correct digest" do
      key = "Jefe".to_slice
      data = "what do ya want for nothing?".to_slice
      expected = "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"

      hmac = RNS::Cryptography::HMAC.new(key, data)
      hmac.digest.hexstring.should eq(expected)
    end

    it "creates an HMAC object without initial message" do
      key = "Jefe".to_slice
      hmac = RNS::Cryptography::HMAC.new(key)
      hmac.update("what do ya want for nothing?".to_slice)
      expected = "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
      hmac.digest.hexstring.should eq(expected)
    end

    it "supports incremental updates" do
      key = Bytes.new(20, 0x0b_u8)

      # All at once
      hmac1 = RNS::Cryptography::HMAC.new(key, "Hi There".to_slice)

      # Incrementally
      hmac2 = RNS::Cryptography::HMAC.new(key)
      hmac2.update("Hi ".to_slice)
      hmac2.update("There".to_slice)

      hmac1.digest.should eq(hmac2.digest)
    end

    it "supports hexdigest" do
      key = "Jefe".to_slice
      data = "what do ya want for nothing?".to_slice
      hmac = RNS::Cryptography::HMAC.new(key, data)
      hmac.hexdigest.should eq("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
    end

    it "does not alter state after calling digest" do
      key = Random::Secure.random_bytes(32)
      data = Random::Secure.random_bytes(64)
      hmac = RNS::Cryptography::HMAC.new(key, data)
      digest1 = hmac.digest
      digest2 = hmac.digest
      digest1.should eq(digest2)
    end
  end

  describe "random roundtrip" do
    it "matches OpenSSL HMAC for 100 random inputs" do
      100.times do
        key = Random::Secure.random_bytes(rand(1..128))
        data = Random::Secure.random_bytes(rand(0..512))

        our_result = RNS::Cryptography::HMAC.digest(key, data)
        openssl_result = OpenSSL::HMAC.digest(OpenSSL::Algorithm::SHA256, key, data)

        our_result.should eq(openssl_result)
      end
    end
  end
end
