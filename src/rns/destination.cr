module RNS
  module Destination
    SINGLE = 0x00_u8
    GROUP  = 0x01_u8
    PLAIN  = 0x02_u8
    LINK   = 0x03_u8

    IN  = 0x11_u8
    OUT = 0x12_u8

    PROVE_NONE = 0x00_u8
    PROVE_APP  = 0x01_u8
    PROVE_ALL  = 0x02_u8

    # Destination-like interface for use by Packet
    module DestinationInterface
      abstract def hash : Bytes
      abstract def type : UInt8
      abstract def encrypt(plaintext : Bytes) : Bytes
    end

    # Lightweight stub used for testing and for Packet construction
    # before the full Destination class is implemented.
    class Stub
      include DestinationInterface

      getter hash : Bytes
      getter type : UInt8
      getter identity : RNS::Identity?
      getter link_id : Bytes?
      property latest_ratchet_id : Bytes?
      property mtu : Int32

      def initialize(*, @hash : Bytes, @type : UInt8, @identity : RNS::Identity? = nil,
                     @link_id : Bytes? = nil, @mtu : Int32 = RNS::Reticulum::MTU)
      end

      def encrypt(plaintext : Bytes) : Bytes
        id = @identity
        if id
          id.encrypt(plaintext)
        else
          plaintext
        end
      end
    end
  end
end
