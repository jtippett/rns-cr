module RNS
  # Minimal link protocol for Transport interaction.
  # The full Link class (Task 5.2/5.3) will implement this module.
  # For now, Transport uses this abstraction for link management.
  module LinkLike
    # Link states (matching Python RNS.Link constants)
    PENDING   = 0x00_u8
    HANDSHAKE = 0x01_u8
    ACTIVE    = 0x02_u8
    STALE     = 0x03_u8
    CLOSED    = 0x04_u8

    # Stale time (matching Python RNS.Link.STALE_TIME)
    STALE_TIME = 720.0 # 12 minutes

    # Establishment timeout per hop (matching Python RNS.Link.ESTABLISHMENT_TIMEOUT_PER_HOP)
    ESTABLISHMENT_TIMEOUT_PER_HOP = 6.0

    # ECPUBSIZE (matching Python RNS.Link.ECPUBSIZE = 32+32 = 64 bytes)
    ECPUBSIZE = 32 + 32 # 64 bytes: 32 X25519 + 32 Ed25519

    abstract def link_id : Bytes
    abstract def initiator? : Bool
    abstract def status : UInt8
    abstract def status=(value : UInt8)
    abstract def destination_hash : Bytes
    abstract def expected_hops : Int32
    abstract def attached_interface : Bytes?
  end

  # Stub implementation of LinkLike for testing before Link module is built.
  class LinkStub
    include LinkLike

    getter link_id : Bytes
    getter? initiator : Bool
    @status : UInt8
    getter expected_hops : Int32
    getter attached_interface : Bytes?
    getter destination_hash : Bytes

    def status : UInt8
      @status
    end

    def status=(value : UInt8)
      @status = value
    end

    def initialize(@link_id : Bytes,
                   @initiator : Bool = true,
                   @status : UInt8 = PENDING,
                   @destination_hash : Bytes = Bytes.new(16),
                   @expected_hops : Int32 = 0,
                   @attached_interface : Bytes? = nil)
    end
  end
end
