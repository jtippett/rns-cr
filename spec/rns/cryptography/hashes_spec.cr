require "../../spec_helper"

describe RNS::Cryptography do
  describe ".sha256" do
    it "hashes empty input" do
      result = RNS::Cryptography.sha256(Bytes.empty)
      result.should eq("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855".hexbytes)
    end

    it "hashes less than block length (abc)" do
      result = RNS::Cryptography.sha256("abc".to_slice)
      result.should eq("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad".hexbytes)
    end

    it "hashes exactly one block length (64 bytes of 'a')" do
      data = Bytes.new(64, 'a'.ord.to_u8)
      result = RNS::Cryptography.sha256(data)
      result.should eq("ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb".hexbytes)
    end

    it "hashes several blocks (1,000,000 bytes of 'a')" do
      data = Bytes.new(1_000_000, 'a'.ord.to_u8)
      result = RNS::Cryptography.sha256(data)
      result.should eq("cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0".hexbytes)
    end

    it "returns 32 bytes" do
      result = RNS::Cryptography.sha256("test".to_slice)
      result.size.should eq(32)
    end

    it "produces consistent results" do
      data = "deterministic".to_slice
      a = RNS::Cryptography.sha256(data)
      b = RNS::Cryptography.sha256(data)
      a.should eq(b)
    end

    it "produces different hashes for different inputs" do
      a = RNS::Cryptography.sha256("hello".to_slice)
      b = RNS::Cryptography.sha256("world".to_slice)
      a.should_not eq(b)
    end

    it "matches OpenSSL directly for 1000 random inputs" do
      1000.times do
        len = Random.rand(0..16384)
        data = Random::Secure.random_bytes(len)
        expected = OpenSSL::Digest.new("SHA256").update(data).final
        result = RNS::Cryptography.sha256(data)
        result.should eq(expected)
      end
    end
  end

  describe ".sha512" do
    it "hashes empty input" do
      result = RNS::Cryptography.sha512(Bytes.empty)
      expected = ("cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce" \
                  "47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e").hexbytes
      result.should eq(expected)
    end

    it "hashes less than block length (abc)" do
      result = RNS::Cryptography.sha512("abc".to_slice)
      expected = ("ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a" \
                  "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f").hexbytes
      result.should eq(expected)
    end

    it "hashes exactly one block length (128 bytes of 'a')" do
      data = Bytes.new(128, 'a'.ord.to_u8)
      result = RNS::Cryptography.sha512(data)
      expected = ("b73d1929aa615934e61a871596b3f3b33359f42b8175602e89f7e06e5f658a24" \
                  "3667807ed300314b95cacdd579f3e33abdfbe351909519a846d465c59582f321").hexbytes
      result.should eq(expected)
    end

    it "hashes several blocks (1,000,000 bytes of 'a')" do
      data = Bytes.new(1_000_000, 'a'.ord.to_u8)
      result = RNS::Cryptography.sha512(data)
      expected = ("e718483d0ce769644e2e42c7bc15b4638e1f98b13b2044285632a803afa973eb" \
                  "de0ff244877ea60a4cb0432ce577c31beb009c5c2c49aa2e4eadb217ad8cc09b").hexbytes
      result.should eq(expected)
    end

    it "returns 64 bytes" do
      result = RNS::Cryptography.sha512("test".to_slice)
      result.size.should eq(64)
    end

    it "produces consistent results" do
      data = "deterministic".to_slice
      a = RNS::Cryptography.sha512(data)
      b = RNS::Cryptography.sha512(data)
      a.should eq(b)
    end

    it "produces different hashes for different inputs" do
      a = RNS::Cryptography.sha512("hello".to_slice)
      b = RNS::Cryptography.sha512("world".to_slice)
      a.should_not eq(b)
    end

    it "matches OpenSSL directly for 1000 random inputs" do
      1000.times do
        len = Random.rand(0..16384)
        data = Random::Secure.random_bytes(len)
        expected = OpenSSL::Digest.new("SHA512").update(data).final
        result = RNS::Cryptography.sha512(data)
        result.should eq(expected)
      end
    end
  end

  describe ".truncated_hash" do
    it "returns first 16 bytes (128 bits) of SHA-256 hash" do
      data = "test".to_slice
      full = RNS::Cryptography.sha256(data)
      truncated = RNS::Cryptography.truncated_hash(data)
      truncated.size.should eq(16)
      truncated.should eq(full[0, 16])
    end

    it "returns consistent results" do
      data = "deterministic".to_slice
      a = RNS::Cryptography.truncated_hash(data)
      b = RNS::Cryptography.truncated_hash(data)
      a.should eq(b)
    end

    it "produces different hashes for different inputs" do
      a = RNS::Cryptography.truncated_hash("hello".to_slice)
      b = RNS::Cryptography.truncated_hash("world".to_slice)
      a.should_not eq(b)
    end

    it "matches manual truncation for 1000 random inputs" do
      1000.times do
        len = Random.rand(0..1024)
        data = Random::Secure.random_bytes(len)
        full = RNS::Cryptography.sha256(data)
        truncated = RNS::Cryptography.truncated_hash(data)
        truncated.should eq(full[0, 16])
      end
    end
  end

  describe ".full_hash" do
    it "is an alias for sha256" do
      data = "test data".to_slice
      RNS::Cryptography.full_hash(data).should eq(RNS::Cryptography.sha256(data))
    end
  end
end
