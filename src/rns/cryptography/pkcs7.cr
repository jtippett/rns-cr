module RNS
  module Cryptography
    module PKCS7
      BLOCKSIZE = 16

      def self.pad(data : Bytes, bs : Int32 = BLOCKSIZE) : Bytes
        l = data.size
        n = bs - l % bs
        padded = Bytes.new(l + n)
        padded.copy_from(data)
        padded[l, n].fill(n.to_u8)
        padded
      end

      def self.unpad(data : Bytes, bs : Int32 = BLOCKSIZE) : Bytes
        raise ArgumentError.new("Cannot unpad empty data") if data.empty?
        n = data[data.size - 1]
        if n > bs || n == 0
          raise ArgumentError.new("Cannot unpad, invalid padding length of #{n} bytes")
        end
        data[0, data.size - n]
      end
    end
  end
end
