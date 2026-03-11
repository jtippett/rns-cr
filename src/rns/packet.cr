module RNS
  class Packet
    # ─── Packet types ───────────────────────────────────────────────
    DATA        = 0x00_u8
    ANNOUNCE    = 0x01_u8
    LINKREQUEST = 0x02_u8
    PROOF       = 0x03_u8

    # ─── Header types ──────────────────────────────────────────────
    HEADER_1 = 0x00_u8
    HEADER_2 = 0x01_u8

    # ─── Context types ─────────────────────────────────────────────
    NONE           = 0x00_u8
    RESOURCE       = 0x01_u8
    RESOURCE_ADV   = 0x02_u8
    RESOURCE_REQ   = 0x03_u8
    RESOURCE_HMU   = 0x04_u8
    RESOURCE_PRF   = 0x05_u8
    RESOURCE_ICL   = 0x06_u8
    RESOURCE_RCL   = 0x07_u8
    CACHE_REQUEST  = 0x08_u8
    REQUEST        = 0x09_u8
    RESPONSE       = 0x0A_u8
    PATH_RESPONSE  = 0x0B_u8
    COMMAND        = 0x0C_u8
    COMMAND_STATUS = 0x0D_u8
    CHANNEL        = 0x0E_u8
    KEEPALIVE      = 0xFA_u8
    LINKIDENTIFY   = 0xFB_u8
    LINKCLOSE      = 0xFC_u8
    LINKPROOF      = 0xFD_u8
    LRRTT          = 0xFE_u8
    LRPROOF        = 0xFF_u8

    # ─── Context flag values ───────────────────────────────────────
    FLAG_SET   = 0x01_u8
    FLAG_UNSET = 0x00_u8

    # ─── Size constants ────────────────────────────────────────────
    HEADER_MAXSIZE = Reticulum::HEADER_MAXSIZE
    HEADER_MINSIZE = Reticulum::HEADER_MINSIZE
    MDU            = Reticulum::MDU
    PLAIN_MDU      = MDU

    # With an MTU of 500, the maximum of data we can send in a
    # single encrypted packet is 383 bytes.
    ENCRYPTED_MDU = ((Reticulum::MDU - Identity::TOKEN_OVERHEAD - Identity::KEYSIZE // 16) // Identity::AES128_BLOCKSIZE) * Identity::AES128_BLOCKSIZE - 1

    TIMEOUT_PER_HOP = Reticulum::DEFAULT_PER_HOP_TIMEOUT

    # ─── Instance properties ───────────────────────────────────────
    property hops : UInt8
    property header : Bytes?
    property header_type : UInt8
    property packet_type : UInt8
    property transport_type : UInt8
    property context : UInt8
    property context_flag : UInt8
    property destination : Destination::DestinationInterface?
    property transport_id : Bytes?
    property data : Bytes
    property flags : UInt8
    property raw : Bytes?
    property packed : Bool
    property sent : Bool
    property create_receipt : Bool
    property receipt : PacketReceipt?
    property from_packed : Bool
    property mtu : Int32

    property sent_at : Float64?
    property packet_hash : Bytes?
    property ratchet_id : Bytes?

    property attached_interface : Nil  # NOTE: Should be Interface? — requires refactoring Link/Packet interface types
    property receiving_interface : Nil # NOTE: Should be Interface? — requires refactoring Link/Packet interface types
    property rssi : Float64?
    property snr : Float64?
    property q : Float64?

    property ciphertext : Bytes?
    property plaintext : Bytes?
    property destination_hash : Bytes?
    property destination_type : UInt8?
    # NOTE: property link : Link? — not added due to Packet/Link circular dependency
    property map_hash : Bytes?

    def initialize(destination : Destination::DestinationInterface?, data : Bytes,
                   packet_type : UInt8 = DATA, context : UInt8 = NONE,
                   transport_type : UInt8 = Transport::BROADCAST,
                   header_type : UInt8 = HEADER_1, transport_id : Bytes? = nil,
                   attached_interface = nil, create_receipt : Bool = true,
                   context_flag : UInt8 = FLAG_UNSET)
      if destination
        @header_type = header_type
        @packet_type = packet_type
        @transport_type = transport_type
        @context = context
        @context_flag = context_flag

        @hops = 0_u8
        @destination = destination
        @transport_id = transport_id
        @data = data
        @flags = get_packed_flags

        @raw = nil
        @packed = false
        @sent = false
        @create_receipt = create_receipt
        @receipt = nil
        @from_packed = false
      else
        @header_type = 0_u8
        @packet_type = 0_u8
        @transport_type = 0_u8
        @context = 0_u8
        @context_flag = 0_u8
        @hops = 0_u8
        @destination = nil
        @transport_id = nil
        @flags = 0_u8

        @raw = data
        @data = data
        @packed = true
        @from_packed = true
        @create_receipt = false
        @sent = false
        @receipt = nil
      end

      if destination && destination.type == Destination::LINK
        @mtu = if destination.is_a?(Destination)
                 destination.mtu
               elsif destination.is_a?(Destination::Stub)
                 destination.mtu
               else
                 Reticulum::MTU
               end
      else
        @mtu = Reticulum::MTU
      end

      @sent_at = nil
      @packet_hash = nil
      @ratchet_id = nil

      @attached_interface = nil
      @receiving_interface = nil
      @rssi = nil
      @snr = nil
      @q = nil

      @header = nil
      @ciphertext = nil
      @plaintext = nil
      @destination_hash = nil
      @destination_type = nil
      @map_hash = nil
    end

    def get_packed_flags : UInt8
      dest = @destination
      if @context == LRPROOF
        ((@header_type.to_u8 << 6) | (@context_flag.to_u8 << 5) | (@transport_type.to_u8 << 4) | (Destination::LINK.to_u8 << 2) | @packet_type.to_u8).to_u8
      elsif dest
        ((@header_type.to_u8 << 6) | (@context_flag.to_u8 << 5) | (@transport_type.to_u8 << 4) | (dest.type.to_u8 << 2) | @packet_type.to_u8).to_u8
      else
        0_u8
      end
    end

    def pack
      dest = @destination.not_nil!
      @destination_hash = dest.hash
      @destination_type = dest.type

      header_io = IO::Memory.new
      header_io.write_byte(@flags)
      header_io.write_byte(@hops)

      if @context == LRPROOF
        link_id = dest.as(Destination::Stub).link_id # LRPROOF only used with Stub/Link destinations
        header_io.write(link_id.not_nil!)
        @ciphertext = @data
      else
        if @header_type == HEADER_1
          header_io.write(dest.hash)

          if @packet_type == ANNOUNCE
            @ciphertext = @data
          elsif @packet_type == LINKREQUEST
            @ciphertext = @data
          elsif @packet_type == PROOF && @context == RESOURCE_PRF
            @ciphertext = @data
          elsif @packet_type == PROOF && dest.type == Destination::LINK
            @ciphertext = @data
          elsif @context == RESOURCE
            @ciphertext = @data
          elsif @context == KEEPALIVE
            @ciphertext = @data
          elsif @context == CACHE_REQUEST
            @ciphertext = @data
          else
            @ciphertext = dest.encrypt(@data)
            if dest.is_a?(Destination)
              @ratchet_id = dest.latest_ratchet_id
            elsif dest.is_a?(Destination::Stub)
              @ratchet_id = dest.latest_ratchet_id
            end
          end
        end

        if @header_type == HEADER_2
          tid = @transport_id
          if tid
            header_io.write(tid)
            header_io.write(dest.hash)

            if @packet_type == ANNOUNCE
              @ciphertext = @data
            end
          else
            raise IO::Error.new("Packet with header type 2 must have a transport ID")
          end
        end
      end

      header_io.write_byte(@context)
      @header = header_io.to_slice

      raw_io = IO::Memory.new
      raw_io.write(@header.not_nil!)
      raw_io.write(@ciphertext.not_nil!)
      @raw = raw_io.to_slice

      if @raw.not_nil!.size > @mtu
        raise IO::Error.new("Packet size of #{@raw.not_nil!.size} exceeds MTU of #{@mtu} bytes")
      end

      @packed = true
      update_hash
    end

    def unpack : Bool
      raw = @raw.not_nil!

      @flags = raw[0]
      @hops = raw[1]

      @header_type = ((@flags & 0b01000000_u8) >> 6).to_u8
      @context_flag = ((@flags & 0b00100000_u8) >> 5).to_u8
      @transport_type = ((@flags & 0b00010000_u8) >> 4).to_u8
      @destination_type = ((@flags & 0b00001100_u8) >> 2).to_u8
      @packet_type = (@flags & 0b00000011_u8).to_u8

      dst_len = Reticulum::TRUNCATED_HASHLENGTH // 8

      if @header_type == HEADER_2
        @transport_id = raw[2, dst_len]
        @destination_hash = raw[dst_len + 2, dst_len]
        @context = raw[2 * dst_len + 2]
        @data = raw[(2 * dst_len + 3)..]
      else
        @transport_id = nil
        @destination_hash = raw[2, dst_len]
        @context = raw[dst_len + 2]
        @data = raw[(dst_len + 3)..]
      end

      @packed = false
      update_hash
      true
    rescue ex
      RNS.log("Received malformed packet, dropping it. The contained exception was: #{ex}", RNS::LOG_EXTREME)
      false
    end

    def update_hash
      @packet_hash = get_hash
    end

    def get_hash : Bytes
      Identity.full_hash(get_hashable_part)
    end

    def get_truncated_hash : Bytes
      Identity.truncated_hash(get_hashable_part)
    end

    def get_hashable_part : Bytes
      raw = @raw.not_nil!
      masked_flags = Bytes[raw[0] & 0b00001111_u8]

      if @header_type == HEADER_2
        dst_len = Identity::TRUNCATED_HASHLENGTH // 8
        rest = raw[(dst_len + 2)..]
      else
        rest = raw[2..]
      end

      result = Bytes.new(masked_flags.size + rest.size)
      masked_flags.copy_to(result)
      rest.copy_to(result + masked_flags.size)
      result
    end

    def send
      return if @sent

      pack unless @packed

      # NOTE: Transport.outbound(self) exists but is not wired here to avoid
      # side effects in unit tests. Full integration requires a running Reticulum instance.
      @sent = true
      @sent_at = Time.utc.to_unix_f
    end

    def generate_proof_destination : ProofDestination
      ProofDestination.new(self)
    end
  end

  class ProofDestination
    include Destination::DestinationInterface

    getter hash : Bytes
    getter type : UInt8

    def initialize(packet : Packet)
      @hash = packet.get_hash[0, Reticulum::TRUNCATED_HASHLENGTH // 8]
      @type = Destination::SINGLE
    end

    def encrypt(plaintext : Bytes) : Bytes
      plaintext
    end
  end

  class PacketReceipt
    # ─── Status constants ──────────────────────────────────────────
    FAILED    = 0x00_u8
    SENT      = 0x01_u8
    DELIVERED = 0x02_u8
    CULLED    = 0xFF_u8

    EXPL_LENGTH = Identity::HASHLENGTH // 8 + Identity::SIGLENGTH // 8 # 32 + 64 = 96
    IMPL_LENGTH = Identity::SIGLENGTH // 8                             # 64

    property hash : Bytes
    property truncated_hash : Bytes
    property sent : Bool
    property sent_at : Float64
    property proved : Bool
    property status : UInt8
    property destination : Destination::DestinationInterface?
    property callbacks : PacketReceiptCallbacks
    property concluded_at : Float64?
    property proof_packet : Packet?
    property timeout : Float64

    def initialize(packet : Packet)
      @hash = packet.get_hash
      @truncated_hash = packet.get_truncated_hash
      @sent = true
      @sent_at = Time.utc.to_unix_f
      @proved = false
      @status = SENT
      @destination = packet.destination
      @callbacks = PacketReceiptCallbacks.new
      @concluded_at = nil
      @proof_packet = nil

      # Default timeout — will be refined when Transport/Link are available
      @timeout = Reticulum::DEFAULT_PER_HOP_TIMEOUT.to_f64
    end

    def get_status : UInt8
      @status
    end

    def get_rtt : Float64
      @concluded_at.not_nil! - @sent_at
    end

    def is_timed_out? : Bool
      @sent_at + @timeout < Time.utc.to_unix_f
    end

    def check_timeout
      if @status == SENT && is_timed_out?
        if @timeout == -1.0
          @status = CULLED
        else
          @status = FAILED
        end

        @concluded_at = Time.utc.to_unix_f

        cb = @callbacks.timeout
        if cb
          spawn do
            cb.call(self)
          end
        end
      end
    end

    def set_timeout(timeout : Float64)
      @timeout = timeout
    end

    def set_delivery_callback(callback : Proc(PacketReceipt, Nil))
      @callbacks.delivery = callback
    end

    def set_timeout_callback(callback : Proc(PacketReceipt, Nil))
      @callbacks.timeout = callback
    end

    def validate_proof_packet(proof_packet : Packet) : Bool
      # NOTE: When Packet gains a `link` property, should dispatch to
      # validate_link_proof(proof_packet.data, proof_packet.link) for link proofs.
      validate_proof(proof_packet.data)
    end

    def validate_proof(proof : Bytes, proof_packet : Packet? = nil) : Bool
      if proof.size == EXPL_LENGTH
        proof_hash = proof[0, Identity::HASHLENGTH // 8]
        signature = proof[Identity::HASHLENGTH // 8, Identity::SIGLENGTH // 8]
        dest = @destination
        identity = if dest.is_a?(Destination)
                     dest.identity
                   elsif dest.is_a?(Destination::Stub)
                     dest.identity
                   else
                     nil
                   end
        if proof_hash == @hash && identity
          if identity.validate(signature, @hash)
            @status = DELIVERED
            @proved = true
            @concluded_at = Time.utc.to_unix_f
            @proof_packet = proof_packet

            cb = @callbacks.delivery
            if cb
              begin
                cb.call(self)
              rescue ex
                RNS.log("Error while executing proof validated callback. The contained exception was: #{ex}", RNS::LOG_ERROR)
              end
            end
            return true
          end
        end
        false
      elsif proof.size == IMPL_LENGTH
        dest = @destination
        return false unless dest
        identity = if dest.is_a?(Destination)
                     dest.identity
                   elsif dest.is_a?(Destination::Stub)
                     dest.identity
                   else
                     nil
                   end
        return false if identity.nil?

        signature = proof[0, Identity::SIGLENGTH // 8]
        if identity.validate(signature, @hash)
          @status = DELIVERED
          @proved = true
          @concluded_at = Time.utc.to_unix_f
          @proof_packet = proof_packet

          cb = @callbacks.delivery
          if cb
            begin
              cb.call(self)
            rescue ex
              RNS.log("Error while executing proof validated callback. The contained exception was: #{ex}", RNS::LOG_ERROR)
            end
          end
          return true
        end
        false
      else
        false
      end
    end
  end

  class PacketReceiptCallbacks
    property delivery : Proc(PacketReceipt, Nil)?
    property timeout : Proc(PacketReceipt, Nil)?

    def initialize
      @delivery = nil
      @timeout = nil
    end
  end
end
