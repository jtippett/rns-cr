require "../../spec_helper"

describe RNS::Cryptography::PKCS7 do
  describe ".pad" do
    it "pads data shorter than block size" do
      data = Bytes[1, 2, 3]
      padded = RNS::Cryptography::PKCS7.pad(data)
      padded.size.should eq(16)
      # Last 13 bytes should all be 13
      padded[3, 13].each(&.should(eq(13)))
      padded[0, 3].should eq(data)
    end

    it "pads data exactly at block size with a full block of padding" do
      data = Bytes.new(16, 0xAA_u8)
      padded = RNS::Cryptography::PKCS7.pad(data)
      padded.size.should eq(32)
      padded[0, 16].should eq(data)
      padded[16, 16].each(&.should(eq(16)))
    end

    it "pads data one byte short of block size" do
      data = Bytes.new(15, 0xBB_u8)
      padded = RNS::Cryptography::PKCS7.pad(data)
      padded.size.should eq(16)
      padded[15].should eq(1)
    end

    it "pads data longer than one block" do
      data = Bytes.new(20, 0xCC_u8)
      padded = RNS::Cryptography::PKCS7.pad(data)
      padded.size.should eq(32)
      # 32 - 20 = 12 bytes of padding
      padded[20, 12].each(&.should(eq(12)))
    end

    it "pads empty data with full block of padding" do
      data = Bytes.new(0)
      padded = RNS::Cryptography::PKCS7.pad(data)
      padded.size.should eq(16)
      padded.each(&.should(eq(16)))
    end

    it "supports custom block size" do
      data = Bytes[1, 2, 3]
      padded = RNS::Cryptography::PKCS7.pad(data, 8)
      padded.size.should eq(8)
      padded[3, 5].each(&.should(eq(5)))
    end

    it "pads data at custom block size boundary" do
      data = Bytes.new(8, 0xDD_u8)
      padded = RNS::Cryptography::PKCS7.pad(data, 8)
      padded.size.should eq(16)
      padded[8, 8].each(&.should(eq(8)))
    end
  end

  describe ".unpad" do
    it "unpads data with valid padding" do
      # 3 bytes data + 13 bytes padding
      padded = Bytes.new(16)
      padded[0] = 1_u8
      padded[1] = 2_u8
      padded[2] = 3_u8
      (3...16).each { |i| padded[i] = 13_u8 }
      unpadded = RNS::Cryptography::PKCS7.unpad(padded)
      unpadded.should eq(Bytes[1, 2, 3])
    end

    it "unpads a full block of padding" do
      padded = Bytes.new(32)
      (0...16).each { |i| padded[i] = 0xAA_u8 }
      (16...32).each { |i| padded[i] = 16_u8 }
      unpadded = RNS::Cryptography::PKCS7.unpad(padded)
      unpadded.size.should eq(16)
      unpadded.each(&.should(eq(170)))
    end

    it "unpads single byte of padding" do
      padded = Bytes.new(16)
      (0...15).each { |i| padded[i] = 0xBB_u8 }
      padded[15] = 1_u8
      unpadded = RNS::Cryptography::PKCS7.unpad(padded)
      unpadded.size.should eq(15)
    end

    it "raises on invalid padding length exceeding block size" do
      padded = Bytes.new(16)
      padded[15] = 17_u8 # Invalid: > BLOCKSIZE
      expect_raises(ArgumentError, "invalid padding length") do
        RNS::Cryptography::PKCS7.unpad(padded)
      end
    end

    it "raises on zero padding byte" do
      padded = Bytes.new(16)
      padded[15] = 0_u8
      expect_raises(ArgumentError, "invalid padding length") do
        RNS::Cryptography::PKCS7.unpad(padded)
      end
    end

    it "raises on empty data" do
      expect_raises(ArgumentError, "Cannot unpad empty data") do
        RNS::Cryptography::PKCS7.unpad(Bytes.new(0))
      end
    end

    it "supports custom block size" do
      padded = Bytes[1, 2, 3, 5, 5, 5, 5, 5]
      unpadded = RNS::Cryptography::PKCS7.unpad(padded, 8)
      unpadded.should eq(Bytes[1, 2, 3])
    end

    it "raises on invalid padding for custom block size" do
      padded = Bytes[1, 2, 3, 4, 5, 6, 7, 9] # 9 > block size 8
      expect_raises(ArgumentError, "invalid padding length") do
        RNS::Cryptography::PKCS7.unpad(padded, 8)
      end
    end
  end

  describe "pad/unpad roundtrip" do
    it "roundtrips for various data lengths" do
      (0..64).each do |len|
        data = Random::Secure.random_bytes(len)
        padded = RNS::Cryptography::PKCS7.pad(data)
        unpadded = RNS::Cryptography::PKCS7.unpad(padded)
        unpadded.should eq(data)
      end
    end

    it "roundtrips with custom block sizes" do
      [8, 16, 32].each do |bs|
        (0..48).each do |len|
          data = Random::Secure.random_bytes(len)
          padded = RNS::Cryptography::PKCS7.pad(data, bs)
          (padded.size % bs).should eq(0)
          unpadded = RNS::Cryptography::PKCS7.unpad(padded, bs)
          unpadded.should eq(data)
        end
      end
    end

    it "roundtrips 1000 random iterations" do
      1000.times do
        len = Random.new.rand(0..256)
        data = Random::Secure.random_bytes(len)
        padded = RNS::Cryptography::PKCS7.pad(data)
        unpadded = RNS::Cryptography::PKCS7.unpad(padded)
        unpadded.should eq(data)
      end
    end
  end

  it "has BLOCKSIZE constant of 16" do
    RNS::Cryptography::PKCS7::BLOCKSIZE.should eq(16)
  end
end
