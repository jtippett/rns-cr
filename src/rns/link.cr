module RNS
  # Container for link event callback procs (established, closed, packet, resource, identify).
  class LinkCallbacks
    property link_established : Proc(Link, Nil)?
    property link_closed : Proc(Link, Nil)?
    property packet : Proc(Bytes, Packet, Nil)?
    property resource : Proc(Resource, Bool)?          # Resource -> accept?
    property resource_started : Proc(Resource, Nil)?   # Resource -> void
    property resource_concluded : Proc(Resource, Nil)? # Resource -> void
    property remote_identified : Proc(Link, Identity, Nil)?

    def initialize
      @link_established = nil
      @link_closed = nil
      @packet = nil
      @resource = nil
      @resource_started = nil
      @resource_concluded = nil
      @remote_identified = nil
    end
  end

  # Encrypted bidirectional communication channel between two Reticulum destinations,
  # established via ECDH key exchange over X25519 with Ed25519 signing.
  class Link
    include LinkLike
    include Destination::DestinationInterface

    # Curve type and key sizes for ECDH key exchange and signing.
    # ─── Curve and key size constants ────────────────────────────────
    CURVE     = Identity::CURVE
    ECPUBSIZE = 32 + 32 # 64 bytes: 32 X25519 + 32 Ed25519 public key bytes
    KEYSIZE   = 32      # Derived key size in bytes

    # Maximum Data Unit: largest plaintext payload that fits in an encrypted link packet.
    # ─── MDU ─────────────────────────────────────────────────────────
    MDU = ((Reticulum::MTU - Reticulum::IFAC_MIN_SIZE - Reticulum::HEADER_MINSIZE - Identity::TOKEN_OVERHEAD) // Identity::AES128_BLOCKSIZE) * Identity::AES128_BLOCKSIZE - 1

    # Timeout, keepalive, and watchdog timing parameters for link lifecycle management.
    # ─── Timing constants ────────────────────────────────────────────
    ESTABLISHMENT_TIMEOUT_PER_HOP = Reticulum::DEFAULT_PER_HOP_TIMEOUT.to_f64
    LINK_MTU_SIZE                 =     3
    TRAFFIC_TIMEOUT_MIN_MS        =     5
    TRAFFIC_TIMEOUT_FACTOR        =     6
    KEEPALIVE_MAX_RTT             =  1.75
    KEEPALIVE_TIMEOUT_FACTOR      =     4
    STALE_GRACE                   =   5.0
    KEEPALIVE_MAX                 = 360.0
    KEEPALIVE_MIN                 =   5.0
    KEEPALIVE                     = KEEPALIVE_MAX
    STALE_FACTOR                  = 2
    STALE_TIME                    = STALE_FACTOR * KEEPALIVE
    WATCHDOG_MAX_SLEEP            = 5.0

    # Link lifecycle states: PENDING -> HANDSHAKE -> ACTIVE -> STALE -> CLOSED.
    # ─── Link states ─────────────────────────────────────────────────
    PENDING   = 0x00_u8
    HANDSHAKE = 0x01_u8
    ACTIVE    = 0x02_u8
    STALE     = 0x03_u8
    CLOSED    = 0x04_u8

    # Reason codes recorded when a link is torn down.
    # ─── Teardown reasons ────────────────────────────────────────────
    TIMEOUT            = 0x01_u8
    INITIATOR_CLOSED   = 0x02_u8
    DESTINATION_CLOSED = 0x03_u8

    # Policies controlling whether incoming resource transfers are accepted.
    # ─── Resource strategies ─────────────────────────────────────────
    ACCEPT_NONE         = 0x00_u8
    ACCEPT_APP          = 0x01_u8
    ACCEPT_ALL          = 0x02_u8
    RESOURCE_STRATEGIES = [ACCEPT_NONE, ACCEPT_APP, ACCEPT_ALL]

    # Symmetric encryption modes negotiated during link establishment.
    # ─── Encryption modes ────────────────────────────────────────────
    MODE_AES128_CBC    = 0x00_u8
    MODE_AES256_CBC    = 0x01_u8
    MODE_AES256_GCM    = 0x02_u8
    MODE_OTP_RESERVED  = 0x03_u8
    MODE_PQ_RESERVED_1 = 0x04_u8
    MODE_PQ_RESERVED_2 = 0x05_u8
    MODE_PQ_RESERVED_3 = 0x06_u8
    MODE_PQ_RESERVED_4 = 0x07_u8
    ENABLED_MODES      = [MODE_AES256_CBC]
    MODE_DEFAULT       = MODE_AES256_CBC
    MODE_DESCRIPTIONS  = {
      MODE_AES128_CBC    => "AES_128_CBC",
      MODE_AES256_CBC    => "AES_256_CBC",
      MODE_AES256_GCM    => "MODE_AES256_GCM",
      MODE_OTP_RESERVED  => "MODE_OTP_RESERVED",
      MODE_PQ_RESERVED_1 => "MODE_PQ_RESERVED_1",
      MODE_PQ_RESERVED_2 => "MODE_PQ_RESERVED_2",
      MODE_PQ_RESERVED_3 => "MODE_PQ_RESERVED_3",
      MODE_PQ_RESERVED_4 => "MODE_PQ_RESERVED_4",
    }

    # Bitmasks for encoding MTU and encryption mode into signalling bytes.
    # ─── Byte masks for MTU signalling ───────────────────────────────
    MTU_BYTEMASK  = 0x1FFFFF_u32
    MODE_BYTEMASK =      0xE0_u8

    # ─── Instance properties ─────────────────────────────────────────
    getter? initiator : Bool
    getter destination : Destination?
    getter expected_hops : Int32

    property mode : UInt8
    property rtt : Float64?
    property mtu : Int32
    property mdu : Int32
    property callbacks : LinkCallbacks
    property resource_strategy : UInt8
    property last_inbound : Float64
    property last_outbound : Float64
    property last_keepalive : Float64
    property last_proof : Float64
    property last_data : Float64
    property tx : Int64
    property rx : Int64
    property txbytes : Int64
    property rxbytes : Int64
    property rssi : Float64?
    property snr : Float64?
    property q : Float64?
    property traffic_timeout_factor : Int32
    property keepalive_timeout_factor : Int32
    property keepalive : Float64
    property stale_time : Float64
    property activated_at : Float64?
    property request_time : Float64?
    property establishment_cost : Int32
    property establishment_rate : Float64?
    property expected_rate : Float64?
    property teardown_reason : UInt8?
    property pending_requests : Array(RequestReceipt)
    property outgoing_resources : Array(Bytes) # NOTE: Resource hashes; should be Array(Resource) for proof routing
    property incoming_resources : Array(Bytes) # NOTE: Resource hashes; should be Array(Resource) for part receiving
    property last_resource_window : Int32?
    property last_resource_eifr : Float64?
    property attached_interface : Bytes? # NOTE: Should be Interface? but Packet.receiving_interface is still Nil stub

    @status : UInt8
    @owner : Destination?
    @prv : Cryptography::X25519PrivateKey?
    @sig_prv : Cryptography::Ed25519PrivateKey?
    @pub : Cryptography::X25519PublicKey?
    @pub_bytes : Bytes?
    @sig_pub : Cryptography::Ed25519PublicKey?
    @sig_pub_bytes : Bytes?
    @peer_pub : Cryptography::X25519PublicKey?
    @peer_pub_bytes : Bytes?
    @peer_sig_pub : Cryptography::Ed25519PublicKey?
    @peer_sig_pub_bytes : Bytes?
    @shared_key : Bytes?
    @derived_key : Bytes?
    @token : Cryptography::Token?
    @remote_identity : Identity?
    @track_phy_stats : Bool
    # NOTE: @channel : Channel(Packet)? — deferred due to Crystal codegen bug
    # with non-generic class storing generic instantiation as instance variable.
    # Channel class exists but cannot be stored here without triggering the bug.
    @channel_enabled : Bool = false
    @watchdog_lock : Bool
    @link_id : Bytes
    @hash : Bytes
    @type : UInt8
    @establishment_timeout : Float64

    # ─── DestinationInterface ────────────────────────────────────────

    def hash : Bytes
      @hash
    end

    def type : UInt8
      @type
    end

    def encrypt(plaintext : Bytes) : Bytes
      encrypt_data(plaintext)
    end

    # ─── LinkLike ────────────────────────────────────────────────────

    def link_id : Bytes
      @link_id
    end

    def status : UInt8
      @status
    end

    def status=(value : UInt8)
      @status = value
    end

    def destination_hash : Bytes
      dest = @destination
      dest ? dest.hash : Bytes.new(16)
    end

    # ─── Static helpers ──────────────────────────────────────────────

    def self.signalling_bytes(mtu : UInt32, mode : UInt8) : Bytes
      raise TypeError.new("Requested link mode #{MODE_DESCRIPTIONS[mode]?} not enabled") unless ENABLED_MODES.includes?(mode)
      signalling_value = (mtu & MTU_BYTEMASK) + ((((mode.to_u32 << 5) & MODE_BYTEMASK.to_u32) << 16))
      # Pack as big-endian 4 bytes, take last 3
      io = IO::Memory.new(4)
      io.write_bytes(signalling_value, IO::ByteFormat::BigEndian)
      io.to_slice[1, 3].dup
    end

    def self.mtu_from_lr_packet(packet : Packet) : Int32?
      if packet.data.size == ECPUBSIZE + LINK_MTU_SIZE
        d = packet.data
        ((d[ECPUBSIZE].to_i32 << 16) + (d[ECPUBSIZE + 1].to_i32 << 8) + d[ECPUBSIZE + 2].to_i32) & MTU_BYTEMASK.to_i32
      else
        nil
      end
    end

    def self.mtu_from_lp_packet(packet : Packet) : Int32?
      sig_len = Identity::SIGLENGTH // 8
      ecpub_half = ECPUBSIZE // 2
      if packet.data.size == sig_len + ecpub_half + LINK_MTU_SIZE
        offset = sig_len + ecpub_half
        d = packet.data
        ((d[offset].to_i32 << 16) + (d[offset + 1].to_i32 << 8) + d[offset + 2].to_i32) & MTU_BYTEMASK.to_i32
      else
        nil
      end
    end

    def self.mode_from_lr_packet(packet : Packet) : UInt8
      if packet.data.size > ECPUBSIZE
        (packet.data[ECPUBSIZE] & MODE_BYTEMASK) >> 5
      else
        MODE_DEFAULT
      end
    end

    def self.mode_from_lp_packet(packet : Packet) : UInt8
      sig_len = Identity::SIGLENGTH // 8
      ecpub_half = ECPUBSIZE // 2
      if packet.data.size > sig_len + ecpub_half
        packet.data[sig_len + ecpub_half] >> 5
      else
        MODE_DEFAULT
      end
    end

    def self.link_id_from_lr_packet(packet : Packet) : Bytes
      hashable_part = packet.get_hashable_part
      if packet.data.size > ECPUBSIZE
        diff = packet.data.size - ECPUBSIZE
        hashable_part = hashable_part[0, hashable_part.size - diff]
      end
      Identity.truncated_hash(hashable_part)
    end

    # Validates an incoming link request packet, creates the responder-side link, and sends a proof.
    def self.validate_request(owner : Destination, data : Bytes, packet : Packet) : Link?
      if data.size == ECPUBSIZE || data.size == ECPUBSIZE + LINK_MTU_SIZE
        begin
          peer_pub_bytes = data[0, ECPUBSIZE // 2]
          peer_sig_pub_bytes = data[ECPUBSIZE // 2, ECPUBSIZE // 2]

          link = Link.new(
            owner: owner,
            peer_pub_bytes: peer_pub_bytes,
            peer_sig_pub_bytes: peer_sig_pub_bytes
          )
          link.set_link_id(packet)

          if data.size == ECPUBSIZE + LINK_MTU_SIZE
            link.mtu = Link.mtu_from_lr_packet(packet) || Reticulum::MTU
          end

          link.mode = Link.mode_from_lr_packet(packet)
          link.update_mdu
          link.set_destination(packet.destination.as?(Destination))
          link.establishment_timeout = ESTABLISHMENT_TIMEOUT_PER_HOP * Math.max(1, packet.hops).to_f64 + KEEPALIVE
          link.establishment_cost += packet.raw.not_nil!.size

          link.do_handshake
          link.attached_interface = nil # NOTE: Should be packet.receiving_interface when Packet uses Interface type
          link.prove
          link.request_time = Time.utc.to_unix_f
          Transport.register_link(link)
          link.last_inbound = Time.utc.to_unix_f
          link.start_watchdog

          link
        rescue ex
          RNS.log("Validating link request failed: #{ex}", RNS::LOG_VERBOSE)
          nil
        end
      else
        RNS.log("Invalid link request payload size of #{data.size} bytes, dropping request", RNS::LOG_DEBUG)
        nil
      end
    end

    # ─── Constructor ─────────────────────────────────────────────────

    # Creates a new link. When *destination* is provided, acts as initiator and sends a link request.
    # When *owner* and peer key bytes are provided instead, acts as responder during `validate_request`.
    def initialize(destination : Destination? = nil,
                   established_callback : Proc(Link, Nil)? = nil,
                   closed_callback : Proc(Link, Nil)? = nil,
                   owner : Destination? = nil,
                   peer_pub_bytes : Bytes? = nil,
                   peer_sig_pub_bytes : Bytes? = nil,
                   mode : UInt8 = MODE_DEFAULT)
      if destination && destination.type != Destination::SINGLE
        raise TypeError.new("Links can only be established to the \"single\" destination type")
      end

      @mode = mode
      @rtt = nil
      @mtu = Reticulum::MTU
      @mdu = 0
      @establishment_cost = 0
      @establishment_rate = nil
      @expected_rate = nil
      @callbacks = LinkCallbacks.new
      @resource_strategy = ACCEPT_NONE
      @outgoing_resources = [] of Bytes
      @incoming_resources = [] of Bytes
      @last_resource_window = nil
      @last_resource_eifr = nil
      @pending_requests = [] of RequestReceipt
      @last_inbound = 0.0
      @last_outbound = 0.0
      @last_keepalive = 0.0
      @last_proof = 0.0
      @last_data = 0.0
      @tx = 0_i64
      @rx = 0_i64
      @txbytes = 0_i64
      @rxbytes = 0_i64
      @rssi = nil
      @snr = nil
      @q = nil
      @traffic_timeout_factor = TRAFFIC_TIMEOUT_FACTOR
      @keepalive_timeout_factor = KEEPALIVE_TIMEOUT_FACTOR
      @keepalive = KEEPALIVE
      @stale_time = STALE_TIME
      @watchdog_lock = false
      @status = PENDING
      @activated_at = nil
      @type = Destination::LINK
      @owner = owner
      @destination = destination
      @expected_hops = 0
      @attached_interface = nil
      @remote_identity = nil
      @track_phy_stats = false
      @channel_enabled = false
      @token = nil
      @shared_key = nil
      @derived_key = nil
      @hash = Bytes.new(0)
      @link_id = Bytes.new(0)
      @request_time = nil
      @teardown_reason = nil
      @establishment_timeout = 0.0

      if destination.nil?
        # Responder path
        @initiator = false
        @prv = Cryptography::X25519PrivateKey.generate
        owner_identity = owner.not_nil!.identity.not_nil!
        @sig_prv = owner_identity.sig_prv
      else
        # Initiator path
        @initiator = true
        @expected_hops = Transport.hops_to(destination.hash)
        @establishment_timeout = ESTABLISHMENT_TIMEOUT_PER_HOP * Math.max(1, @expected_hops).to_f64
        @prv = Cryptography::X25519PrivateKey.generate
        @sig_prv = Cryptography::Ed25519PrivateKey.generate
      end

      @pub = @prv.not_nil!.public_key
      @pub_bytes = @pub.not_nil!.public_bytes

      @sig_pub = @sig_prv.not_nil!.public_key
      @sig_pub_bytes = @sig_pub.not_nil!.public_bytes

      if peer_pub_bytes
        load_peer(peer_pub_bytes, peer_sig_pub_bytes.not_nil!)
      else
        @peer_pub = nil
        @peer_pub_bytes = nil
        @peer_sig_pub = nil
        @peer_sig_pub_bytes = nil
      end

      set_link_established_callback(established_callback) if established_callback
      set_link_closed_callback(closed_callback) if closed_callback

      if @initiator
        dest = destination.not_nil!
        signalling_bytes = Link.signalling_bytes(@mtu.to_u32, @mode)
        pub_b = @pub_bytes.not_nil!
        sig_b = @sig_pub_bytes.not_nil!
        request_data = Bytes.new(pub_b.size + sig_b.size + signalling_bytes.size)
        pub_b.copy_to(request_data)
        sig_b.copy_to(request_data + pub_b.size)
        signalling_bytes.copy_to(request_data + pub_b.size + sig_b.size)

        packet = Packet.new(dest, request_data, packet_type: Packet::LINKREQUEST)
        packet.pack
        @establishment_cost += packet.raw.not_nil!.size
        set_link_id(packet)
        Transport.register_link(self)
        @request_time = Time.utc.to_unix_f
        start_watchdog
        packet.send
        had_outbound
      end
    end

    # ─── Peer loading ────────────────────────────────────────────────

    # Loads the remote peer's X25519 and Ed25519 public keys from raw bytes.
    def load_peer(peer_pub_bytes : Bytes, peer_sig_pub_bytes : Bytes)
      @peer_pub_bytes = peer_pub_bytes
      @peer_pub = Cryptography::X25519PublicKey.from_public_bytes(peer_pub_bytes)
      @peer_sig_pub_bytes = peer_sig_pub_bytes
      @peer_sig_pub = Cryptography::Ed25519PublicKey.from_public_bytes(peer_sig_pub_bytes)
    end

    # ─── Link ID ─────────────────────────────────────────────────────

    def set_link_id(packet : Packet)
      @link_id = Link.link_id_from_lr_packet(packet)
      @hash = @link_id
    end

    def set_destination(dest : Destination?)
      @destination = dest
    end

    def establishment_timeout=(value : Float64)
      @establishment_timeout = value
    end

    # Test helper to set link_id directly (normally set via set_link_id from packet)
    def set_link_id_bytes(id : Bytes)
      @link_id = id
      @hash = id
    end

    # Test accessors for internal state verification
    def derived_key : Bytes?
      @derived_key
    end

    def pub_bytes : Bytes?
      @pub_bytes
    end

    def prv_key : Cryptography::X25519PrivateKey?
      @prv
    end

    def pub_key : Cryptography::X25519PublicKey?
      @pub
    end

    def shared_key : Bytes?
      @shared_key
    end

    def set_initiator(value : Bool)
      @initiator = value
    end

    # ─── Handshake (ECDH key derivation) ─────────────────────────────

    # Performs ECDH key exchange and derives symmetric encryption keys via HKDF.
    def do_handshake
      if @status == PENDING && @prv
        @status = HANDSHAKE
        @shared_key = @prv.not_nil!.exchange(@peer_pub.not_nil!)

        derived_key_length = case @mode
                             when MODE_AES128_CBC then 32
                             when MODE_AES256_CBC then 64
                             else                      raise TypeError.new("Invalid link mode #{@mode} on #{self}")
                             end

        @derived_key = Cryptography.hkdf(
          length: derived_key_length,
          derive_from: @shared_key.not_nil!,
          salt: get_salt,
          context: get_context
        )
      else
        RNS.log("Handshake attempt on #{self} with invalid state #{@status}", RNS::LOG_ERROR)
      end
    end

    # ─── Prove (responder sends proof to initiator) ──────────────────

    # Constructs and sends a signed link proof packet from the responder to the initiator.
    def prove
      signalling_bytes = Link.signalling_bytes(@mtu.to_u32, @mode)
      pub_b = @pub_bytes.not_nil!
      sig_pub_b = @sig_pub_bytes.not_nil!

      signed_data = Bytes.new(@link_id.size + pub_b.size + sig_pub_b.size + signalling_bytes.size)
      pos = 0
      @link_id.copy_to(signed_data + pos); pos += @link_id.size
      pub_b.copy_to(signed_data + pos); pos += pub_b.size
      sig_pub_b.copy_to(signed_data + pos); pos += sig_pub_b.size
      signalling_bytes.copy_to(signed_data + pos)

      signature = @owner.not_nil!.identity.not_nil!.sign(signed_data)

      proof_data = Bytes.new(signature.size + pub_b.size + signalling_bytes.size)
      pos = 0
      signature.copy_to(proof_data + pos); pos += signature.size
      pub_b.copy_to(proof_data + pos); pos += pub_b.size
      signalling_bytes.copy_to(proof_data + pos)

      # Create a stub destination for the LRPROOF packet
      proof_dest = Destination::Stub.new(hash: @link_id, type: Destination::LINK, link_id: @link_id)
      proof_packet = Packet.new(proof_dest, proof_data, packet_type: Packet::PROOF, context: Packet::LRPROOF)
      proof_packet.send
      @establishment_cost += proof_packet.raw.not_nil!.size
      had_outbound
    end

    # ─── Validate proof (initiator receives and verifies) ────────────

    # Validates a link proof received by the initiator, completing the handshake and activating the link.
    def validate_proof(packet : Packet)
      if @status == PENDING
        sig_len = Identity::SIGLENGTH // 8 # 64 bytes
        ecpub_half = ECPUBSIZE // 2        # 32 bytes

        signalling_bytes = Bytes.empty
        confirmed_mtu : Int32? = nil
        mode = Link.mode_from_lp_packet(packet)
        raise TypeError.new("Invalid link mode #{mode} in link request proof") if mode != @mode

        if packet.data.size == sig_len + ecpub_half + LINK_MTU_SIZE
          confirmed_mtu = Link.mtu_from_lp_packet(packet)
          signalling_bytes = Link.signalling_bytes(confirmed_mtu.not_nil!.to_u32, mode) if confirmed_mtu
          packet.data = packet.data[0, sig_len + ecpub_half]
        end

        if @initiator && packet.data.size == sig_len + ecpub_half
          peer_pub_bytes = packet.data[sig_len, ecpub_half]
          dest_identity = @destination.not_nil!.identity.not_nil!
          peer_sig_pub_bytes = dest_identity.get_public_key[ecpub_half, ecpub_half]

          load_peer(peer_pub_bytes, peer_sig_pub_bytes)
          do_handshake

          @establishment_cost += packet.raw.not_nil!.size

          signed_data = Bytes.new(@link_id.size + @peer_pub_bytes.not_nil!.size + @peer_sig_pub_bytes.not_nil!.size + signalling_bytes.size)
          pos = 0
          @link_id.copy_to(signed_data + pos); pos += @link_id.size
          @peer_pub_bytes.not_nil!.copy_to(signed_data + pos); pos += @peer_pub_bytes.not_nil!.size
          @peer_sig_pub_bytes.not_nil!.copy_to(signed_data + pos); pos += @peer_sig_pub_bytes.not_nil!.size
          signalling_bytes.copy_to(signed_data + pos)

          signature = packet.data[0, sig_len]

          if dest_identity.validate(signature, signed_data)
            raise IO::Error.new("Invalid link state for proof validation: #{@status}") if @status != HANDSHAKE

            @rtt = Time.utc.to_unix_f - @request_time.not_nil!
            @attached_interface = nil # NOTE: Should be packet.receiving_interface when Packet uses Interface type
            @remote_identity = dest_identity
            @mtu = confirmed_mtu || Reticulum::MTU
            update_mdu
            @status = ACTIVE
            @activated_at = Time.utc.to_unix_f
            @last_proof = @activated_at.not_nil!
            Transport.activate_link(self)

            rtt_val = @rtt.not_nil!
            if rtt_val > 0 && @establishment_cost > 0
              @establishment_rate = @establishment_cost.to_f64 / rtt_val
            end

            update_keepalive

            rtt_data = IO::Memory.new
            rtt_val.to_msgpack(rtt_data)
            rtt_packet = Packet.new(self, rtt_data.to_slice, context: Packet::LRRTT)
            rtt_packet.send
            had_outbound

            cb = @callbacks.link_established
            if cb
              spawn do
                cb.call(self)
              end
            end
          else
            RNS.log("Invalid link proof signature received by #{self}. Ignoring.", RNS::LOG_DEBUG)
          end
        end
      end
    rescue ex
      @status = CLOSED
      RNS.log("An error occurred while validating link request proof on #{self}.", RNS::LOG_ERROR)
      RNS.log("The contained exception was: #{ex}", RNS::LOG_ERROR)
    end

    # ─── RTT packet handling (responder) ─────────────────────────────

    # Handles an RTT measurement packet on the responder side, activating the link.
    def rtt_packet(packet : Packet)
      measured_rtt = Time.utc.to_unix_f - @request_time.not_nil!
      plaintext = decrypt_data(packet.data)
      if plaintext
        rtt = Float64.from_msgpack(IO::Memory.new(plaintext))
        @rtt = Math.max(measured_rtt, rtt)
        @status = ACTIVE
        @activated_at = Time.utc.to_unix_f

        rtt_val = @rtt.not_nil!
        if rtt_val > 0 && @establishment_cost > 0
          @establishment_rate = @establishment_cost.to_f64 / rtt_val
        end

        update_keepalive

        owner_dest = @owner
        if owner_dest
          cb = owner_dest.callbacks.link_established
          if cb
            begin
              cb.call(self)
            rescue ex
              RNS.log("Error occurred in external link establishment callback: #{ex}", RNS::LOG_ERROR)
            end
          end
        end
      end
    rescue ex
      RNS.log("Error occurred while processing RTT packet, tearing down link: #{ex}", RNS::LOG_ERROR)
      teardown
    end

    # ─── Encryption and decryption ───────────────────────────────────

    # Encrypts plaintext using the link's derived symmetric key via the Token cipher.
    def encrypt_data(plaintext : Bytes) : Bytes
      token = @token
      if token.nil?
        begin
          @token = Cryptography::Token.new(@derived_key.not_nil!)
          token = @token.not_nil!
        rescue ex
          RNS.log("Could not instantiate token while performing encryption on link #{self}: #{ex}", RNS::LOG_ERROR)
          raise ex
        end
      end
      token.encrypt(plaintext)
    rescue ex
      RNS.log("Encryption on link #{self} failed: #{ex}", RNS::LOG_ERROR)
      raise ex
    end

    # Decrypts ciphertext using the link's derived symmetric key. Returns nil on failure.
    def decrypt_data(ciphertext : Bytes) : Bytes?
      token = @token
      if token.nil?
        @token = Cryptography::Token.new(@derived_key.not_nil!)
        token = @token.not_nil!
      end
      token.decrypt(ciphertext)
    rescue ex
      RNS.log("Decryption failed on link #{self}: #{ex}", RNS::LOG_ERROR)
      nil
    end

    # ─── Signing and validation ──────────────────────────────────────

    # Signs a message using this link's Ed25519 private key.
    def sign(message : Bytes) : Bytes
      @sig_prv.not_nil!.sign(message)
    end

    # Validates a signature against a message using the peer's Ed25519 public key.
    def validate(signature : Bytes, message : Bytes) : Bool
      @peer_sig_pub.not_nil!.verify(signature, message)
      true
    rescue
      false
    end

    # ─── Identify (initiator reveals identity to responder) ──────────

    # Reveals the initiator's identity to the responder by sending a signed identity proof.
    def identify(identity : Identity)
      if @initiator && @status == ACTIVE
        pub_key = identity.get_public_key
        signed_data = Bytes.new(@link_id.size + pub_key.size)
        @link_id.copy_to(signed_data)
        pub_key.copy_to(signed_data + @link_id.size)
        signature = identity.sign(signed_data)

        proof_data = Bytes.new(pub_key.size + signature.size)
        pub_key.copy_to(proof_data)
        signature.copy_to(proof_data + pub_key.size)

        proof_packet = Packet.new(self, proof_data, packet_type: Packet::DATA, context: Packet::LINKIDENTIFY)
        proof_packet.send
        had_outbound
      end
    end

    # ─── Request ─────────────────────────────────────────────────────

    RESPONSE_MAX_GRACE_TIME = 10.0 # Placeholder until Resource module provides this

    # Sends a request to the remote destination on *path* and returns a `RequestReceipt` to track the response.
    def request(path : String,
                data : Bytes? = nil,
                response_callback : Proc(RequestReceipt, Nil)? = nil,
                failed_callback : Proc(RequestReceipt, Nil)? = nil,
                progress_callback : Proc(RequestReceipt, Nil)? = nil,
                timeout : Float64? = nil) : RequestReceipt?
      request_path_hash = Identity.truncated_hash(path.to_slice)

      packed_request = IO::Memory.new
      packer = MessagePack::Packer.new(packed_request)
      packer.write_array_start(3)
      Time.utc.to_unix_f.to_msgpack(packed_request)
      request_path_hash.to_msgpack(packed_request)
      if data
        data.to_msgpack(packed_request)
      else
        nil.to_msgpack(packed_request)
      end
      packed_bytes = packed_request.to_slice

      actual_timeout = timeout
      if actual_timeout.nil?
        rtt_val = @rtt
        return nil if rtt_val.nil?
        actual_timeout = rtt_val * @traffic_timeout_factor + RESPONSE_MAX_GRACE_TIME * 1.125
      end

      if packed_bytes.size <= @mdu
        request_packet = Packet.new(self, packed_bytes, packet_type: Packet::DATA, context: Packet::REQUEST)
        request_packet.send

        receipt = request_packet.receipt
        if receipt
          receipt.set_timeout(actual_timeout)
          return RequestReceipt.new(
            link: self,
            packet_receipt: receipt,
            response_callback: response_callback,
            failed_callback: failed_callback,
            progress_callback: progress_callback,
            timeout: actual_timeout,
            request_size: packed_bytes.size
          )
        end
        nil
      else
        # Large requests would go via Resource — not yet implemented
        RNS.log("Request too large for packet MDU and Resource not yet implemented", RNS::LOG_ERROR)
        nil
      end
    end

    # ─── MDU update ──────────────────────────────────────────────────

    def update_mdu
      @mdu = ((@mtu - Reticulum::IFAC_MIN_SIZE - Reticulum::HEADER_MINSIZE - Identity::TOKEN_OVERHEAD) // Identity::AES128_BLOCKSIZE) * Identity::AES128_BLOCKSIZE - 1
    end

    # ─── Salt and context for HKDF ───────────────────────────────────

    def get_salt : Bytes
      @link_id
    end

    def get_context : Bytes?
      nil
    end

    # ─── Timing helpers ──────────────────────────────────────────────

    def had_outbound(is_keepalive : Bool = false)
      @last_outbound = Time.utc.to_unix_f
      if is_keepalive
        @last_keepalive = @last_outbound
      else
        @last_data = @last_outbound
      end
    end

    def no_inbound_for : Float64
      aa = @activated_at || 0.0
      last = Math.max(@last_inbound, aa)
      Time.utc.to_unix_f - last
    end

    def no_outbound_for : Float64
      Time.utc.to_unix_f - @last_outbound
    end

    def no_data_for : Float64
      Time.utc.to_unix_f - @last_data
    end

    def inactive_for : Float64
      Math.min(no_inbound_for, no_outbound_for)
    end

    def get_age : Float64?
      aa = @activated_at
      aa ? Time.utc.to_unix_f - aa : nil
    end

    # ─── Keepalive management ────────────────────────────────────────

    def update_keepalive
      rtt_val = @rtt
      if rtt_val
        @keepalive = Math.max(Math.min(rtt_val * (KEEPALIVE_MAX / KEEPALIVE_MAX_RTT), KEEPALIVE_MAX), KEEPALIVE_MIN)
        @stale_time = @keepalive * STALE_FACTOR
      end
    end

    def send_keepalive
      keepalive_packet = Packet.new(self, Bytes[0xFF], context: Packet::KEEPALIVE)
      keepalive_packet.send
      had_outbound(is_keepalive: true)
    end

    # ─── Prove packet (for data packet proofs) ───────────────────────

    def prove_packet(packet : Packet)
      ph = packet.packet_hash
      return unless ph
      signature = sign(ph)
      proof_data = Bytes.new(ph.size + signature.size)
      ph.copy_to(proof_data)
      signature.copy_to(proof_data + ph.size)
      proof = Packet.new(self, proof_data, packet_type: Packet::PROOF)
      proof.send
      had_outbound
    end

    # ─── Send convenience ────────────────────────────────────────────

    # Sends data over the link as an encrypted packet. Returns nil if the link is closed.
    def send(data : Bytes, packet_type : UInt8 = Packet::DATA, context : UInt8 = Packet::NONE) : Packet?
      return nil if @status == CLOSED
      packet = Packet.new(self, data, packet_type: packet_type, context: context)
      packet.send
      had_outbound
      @tx += 1
      @txbytes += data.size
      packet
    end

    # ─── Resource management ──────────────────────────────────────────

    def register_outgoing_resource(resource_hash : Bytes)
      @outgoing_resources << resource_hash
    end

    def register_incoming_resource(resource_hash : Bytes)
      @incoming_resources << resource_hash
    end

    def has_incoming_resource?(resource_hash : Bytes) : Bool
      @incoming_resources.any? { |hash| hash == resource_hash }
    end

    def cancel_outgoing_resource(resource_hash : Bytes)
      if @outgoing_resources.includes?(resource_hash)
        @outgoing_resources.delete(resource_hash)
      else
        RNS.log("Attempt to cancel a non-existing outgoing resource", RNS::LOG_ERROR)
      end
    end

    def cancel_incoming_resource(resource_hash : Bytes)
      if @incoming_resources.includes?(resource_hash)
        @incoming_resources.delete(resource_hash)
      else
        RNS.log("Attempt to cancel a non-existing incoming resource", RNS::LOG_ERROR)
      end
    end

    def ready_for_new_resource? : Bool
      @outgoing_resources.empty?
    end

    def get_last_resource_window : Int32?
      @last_resource_window
    end

    def get_last_resource_eifr : Float64?
      @last_resource_eifr
    end

    def resource_concluded(resource_hash : Bytes, resource_size : Int64, started_transferring : Float64,
                           window : Int32? = nil, eifr : Float64? = nil, incoming : Bool = true)
      concluded_at = Time.utc.to_unix_f
      if incoming && @incoming_resources.includes?(resource_hash)
        @last_resource_window = window
        @last_resource_eifr = eifr
        @incoming_resources.delete(resource_hash)
        elapsed = Math.max(concluded_at - started_transferring, 0.0001)
        @expected_rate = (resource_size * 8).to_f64 / elapsed
      end
      if @outgoing_resources.includes?(resource_hash)
        @outgoing_resources.delete(resource_hash)
        elapsed = Math.max(concluded_at - started_transferring, 0.0001)
        @expected_rate = (resource_size * 8).to_f64 / elapsed
      end
    end

    # ─── Teardown ────────────────────────────────────────────────────

    # Tears down the link, sending a close packet to the peer and purging keys.
    def teardown
      if @status != PENDING && @status != CLOSED
        teardown_pkt = Packet.new(self, @link_id, context: Packet::LINKCLOSE)
        teardown_pkt.send
        had_outbound
      end
      @status = CLOSED
      @teardown_reason = @initiator ? INITIATOR_CLOSED : DESTINATION_CLOSED
      link_closed
    end

    def teardown_packet(packet : Packet)
      plaintext = decrypt_data(packet.data)
      if plaintext && plaintext == @link_id
        @status = CLOSED
        @teardown_reason = @initiator ? DESTINATION_CLOSED : INITIATOR_CLOSED
        link_closed
      end
    rescue ex
      RNS.log("Error processing teardown packet: #{ex.message}", RNS::LOG_DEBUG)
    end

    # Cleans up after link closure: purges keys, removes from destination, and fires the closed callback.
    def link_closed
      # Clear resource lists (cancel handled by Resource module when implemented)
      @incoming_resources.clear
      @outgoing_resources.clear

      # Purge keys
      @prv = nil
      @pub = nil
      @pub_bytes = nil
      @shared_key = nil
      @derived_key = nil

      dest = @destination
      if dest && dest.direction == Destination::IN
        dest.links.delete(self) if dest.is_a?(Destination)
      end

      cb = @callbacks.link_closed
      if cb
        begin
          cb.call(self)
        rescue ex
          RNS.log("Error while executing link closed callback from #{self}: #{ex}", RNS::LOG_ERROR)
        end
      end
    end

    # ─── Watchdog ────────────────────────────────────────────────────

    def start_watchdog
      spawn do
        watchdog_job
      end
    end

    private def watchdog_job
      while @status != CLOSED
        while @watchdog_lock
          rtt_wait = @rtt || 0.025
          sleep Math.max(rtt_wait, 0.025).seconds
        end

        break if @status == CLOSED

        sleep_time = 0.0

        if @status == PENDING
          rt = @request_time || Time.utc.to_unix_f
          next_check = rt + @establishment_timeout
          sleep_time = next_check - Time.utc.to_unix_f
          if Time.utc.to_unix_f >= rt + @establishment_timeout
            @status = CLOSED
            @teardown_reason = TIMEOUT
            link_closed
            break
          end
        elsif @status == HANDSHAKE
          rt = @request_time || Time.utc.to_unix_f
          next_check = rt + @establishment_timeout
          sleep_time = next_check - Time.utc.to_unix_f
          if Time.utc.to_unix_f >= rt + @establishment_timeout
            @status = CLOSED
            @teardown_reason = TIMEOUT
            link_closed
            break
          end
        elsif @status == ACTIVE
          aa = @activated_at || 0.0
          last_in = Math.max(Math.max(@last_inbound, @last_proof), aa)
          now = Time.utc.to_unix_f

          if now >= last_in + @keepalive
            if @initiator && now >= @last_keepalive + @keepalive
              send_keepalive
            end

            if now >= last_in + @stale_time
              rtt_val = @rtt || 0.0
              sleep_time = rtt_val * @keepalive_timeout_factor + STALE_GRACE
              @status = STALE
            else
              sleep_time = @keepalive
            end
          else
            sleep_time = (last_in + @keepalive) - now
          end
        elsif @status == STALE
          teardown_pkt = Packet.new(self, @link_id, context: Packet::LINKCLOSE)
          teardown_pkt.send
          had_outbound
          @status = CLOSED
          @teardown_reason = TIMEOUT
          link_closed
          break
        end

        if sleep_time <= 0.0
          sleep_time = 0.001
        end

        sleep_time = Math.min(sleep_time, WATCHDOG_MAX_SLEEP)
        sleep sleep_time.seconds

        unless @track_phy_stats
          @rssi = nil
          @snr = nil
          @q = nil
        end
      end
    end

    # ─── Receive ─────────────────────────────────────────────────────

    # Processes an incoming packet on this link, dispatching by context (data, identify, request, keepalive, etc.).
    def receive(packet : Packet)
      @watchdog_lock = true

      if @status != CLOSED && !(@initiator && packet.context == Packet::KEEPALIVE && packet.data == Bytes[0xFF])
        # NOTE: Should verify packet.receiving_interface == @attached_interface when Packet uses Interface type

        @last_inbound = Time.utc.to_unix_f
        @last_data = @last_inbound if packet.context != Packet::KEEPALIVE
        @rx += 1
        @rxbytes += packet.data.size

        @status = ACTIVE if @status == STALE

        if packet.packet_type == Packet::DATA
          case packet.context
          when Packet::NONE
            plaintext = decrypt_data(packet.data)
            if plaintext
              pt = plaintext # Bind non-nil for closure
              cb = @callbacks.packet
              if cb
                spawn { cb.call(pt, packet) }
              end

              dest = @destination
              if dest
                if dest.proof_strategy == Destination::PROVE_ALL
                  prove_packet(packet)
                elsif dest.proof_strategy == Destination::PROVE_APP
                  pr_cb = dest.callbacks.proof_requested
                  if pr_cb
                    begin
                      prove_packet(packet) if pr_cb.call(packet)
                    rescue ex
                      RNS.log("Error while executing proof request callback: #{ex}", RNS::LOG_ERROR)
                    end
                  end
                end
              end
            end
          when Packet::LINKIDENTIFY
            plaintext = decrypt_data(packet.data)
            if plaintext && !@initiator
              key_size = Identity::KEYSIZE // 8
              sig_size = Identity::SIGLENGTH // 8
              if plaintext.size == key_size + sig_size
                public_key = plaintext[0, key_size]
                signed_data = Bytes.new(@link_id.size + public_key.size)
                @link_id.copy_to(signed_data)
                public_key.copy_to(signed_data + @link_id.size)
                signature = plaintext[key_size, sig_size]

                identity = Identity.new(create_keys: false)
                identity.load_public_key(public_key)

                if identity.validate(signature, signed_data)
                  @remote_identity = identity
                  ri_cb = @callbacks.remote_identified
                  if ri_cb
                    begin
                      ri_cb.call(self, identity)
                    rescue ex
                      RNS.log("Error while executing remote identified callback: #{ex}", RNS::LOG_ERROR)
                    end
                  end
                end
              end
            end
          when Packet::REQUEST
            begin
              plaintext = decrypt_data(packet.data)
              if plaintext
                request_id = packet.get_truncated_hash
                unpacked = Array(MessagePack::Any).from_msgpack(IO::Memory.new(plaintext))
                spawn { handle_request(request_id, unpacked) }
              end
            rescue ex
              RNS.log("Error occurred while handling request: #{ex}", RNS::LOG_ERROR)
            end
          when Packet::RESPONSE
            begin
              plaintext = decrypt_data(packet.data)
              if plaintext
                unpacked = Array(MessagePack::Any).from_msgpack(IO::Memory.new(plaintext))
                if unpacked.size >= 2
                  request_id = unpacked[0].raw.as(Bytes)
                  response_data = unpacked[1]
                  spawn { handle_response(request_id, response_data) }
                end
              end
            rescue ex
              RNS.log("Error occurred while handling response: #{ex}", RNS::LOG_ERROR)
            end
          when Packet::LRRTT
            rtt_packet(packet) unless @initiator
          when Packet::LINKCLOSE
            teardown_packet(packet)
          when Packet::KEEPALIVE
            if !@initiator && packet.data == Bytes[0xFF]
              keepalive_response = Packet.new(self, Bytes[0xFE], context: Packet::KEEPALIVE)
              keepalive_response.send
              had_outbound(is_keepalive: true)
            end
          when Packet::CHANNEL
            # NOTE: Channel delivery blocked by Crystal codegen bug preventing @channel storage.
            # When resolved, uncomment:
            # ch = @channel
            # if ch
            #   prove_packet(packet)
            #   plaintext = decrypt_data(packet.data)
            #   if plaintext
            #     ch._receive(plaintext)
            #   end
            # end
            prove_packet(packet)
          end
        elsif packet.packet_type == Packet::PROOF
          if packet.context == Packet::RESOURCE_PRF
            # NOTE: Resource proof routing requires outgoing_resources to hold Resource objects
            # instead of Bytes (hashes). When refactored, iterate resources and call
            # resource.validate_proof(packet.data) for the matching resource hash.
          end
        end
      end

      @watchdog_lock = false
    end

    # ─── Request/response handling ───────────────────────────────────

    def handle_request(request_id : Bytes, unpacked_request : Array(MessagePack::Any))
      return unless @status == ACTIVE
      return unless unpacked_request.size >= 3

      requested_at = unpacked_request[0].as_f? || unpacked_request[0].as_i64?.try(&.to_f64) || 0.0
      path_hash = unpacked_request[1].raw.as(Bytes)
      request_data_any = unpacked_request[2]
      request_data : Bytes? = nil
      begin
        request_data = request_data_any.raw.as(Bytes)
      rescue
        # May be nil or other type
      end

      dest = @destination
      return unless dest

      path_hash_hex = path_hash.hexstring
      handler_entry = dest.request_handlers[path_hash_hex]?
      return unless handler_entry

      path = handler_entry.path
      response_generator = handler_entry.response_generator
      allow = handler_entry.allow
      allowed_list = handler_entry.allowed_list

      allowed = false
      if allow != Destination::ALLOW_NONE
        if allow == Destination::ALLOW_LIST
          ri = @remote_identity
          if ri && allowed_list
            allowed = allowed_list.any? { |hash| hash == ri.hash }
          end
        elsif allow == Destination::ALLOW_ALL
          allowed = true
        end
      end

      if allowed
        RNS.log("Handling request #{RNS.prettyhexrep(request_id)} for: #{path}", RNS::LOG_DEBUG)
        begin
          response = response_generator.call(path, request_data, request_id, @link_id, @remote_identity, requested_at)
          if response
            packed_response = IO::Memory.new
            packer = MessagePack::Packer.new(packed_response)
            packer.write_array_start(2)
            request_id.to_msgpack(packed_response)
            response.to_msgpack(packed_response)
            packed_bytes = packed_response.to_slice

            if packed_bytes.size <= @mdu
              resp_pkt = Packet.new(self, packed_bytes, packet_type: Packet::DATA, context: Packet::RESPONSE)
              resp_pkt.send
              had_outbound
            else
              # Large responses would go via Resource — not yet implemented
              RNS.log("Response too large for packet MDU and Resource not yet implemented", RNS::LOG_ERROR)
            end
          end
        rescue ex
          RNS.log("Error while generating response for request #{RNS.prettyhexrep(request_id)}: #{ex}", RNS::LOG_ERROR)
        end
      else
        identity_string = @remote_identity.try(&.to_s) || "<Unknown>"
        RNS.log("Request #{RNS.prettyhexrep(request_id)} from #{identity_string} not allowed for: #{path}", RNS::LOG_DEBUG)
      end
    end

    def handle_response(request_id : Bytes, response_data : MessagePack::Any)
      return unless @status == ACTIVE

      remove : RequestReceipt? = nil
      @pending_requests.each do |pending_request|
        if pending_request.request_id == request_id
          remove = pending_request
          begin
            pending_request.response_received(response_data)
          rescue ex
            RNS.log("Error occurred while handling response: #{ex}", RNS::LOG_ERROR)
          end
          break
        end
      end

      if remove
        @pending_requests.delete(remove)
      end
    end

    # ─── Phy stats ───────────────────────────────────────────────────

    def track_phy_stats(track : Bool)
      @track_phy_stats = track
    end

    def get_rssi : Float64?
      @track_phy_stats ? @rssi : nil
    end

    def get_snr : Float64?
      @track_phy_stats ? @snr : nil
    end

    def get_q : Float64?
      @track_phy_stats ? @q : nil
    end

    def get_establishment_rate : Float64?
      er = @establishment_rate
      er ? er * 8 : nil
    end

    def get_mtu : Int32?
      @status == ACTIVE ? @mtu : nil
    end

    def get_mdu : Int32?
      @status == ACTIVE ? @mdu : nil
    end

    def get_expected_rate : Float64?
      @status == ACTIVE ? @expected_rate : nil
    end

    def get_mode : UInt8
      @mode
    end

    def get_remote_identity : Identity?
      @remote_identity
    end

    # ─── Channel ─────────────────────────────────────────────────────

    # NOTE: get_channel deferred — Crystal codegen bug prevents storing Channel(Packet)
    # as instance variable on Link. Channel class exists in channel.cr.
    # def get_channel : Channel(Packet)
    #   ch = @channel
    #   if ch.nil?
    #     @channel = Channel(Packet).new(LinkChannelOutlet.new(self))
    #     ch = @channel.not_nil!
    #   end
    #   ch
    # end

    # ─── Resource strategy ───────────────────────────────────────────

    def set_resource_strategy(strategy : UInt8)
      raise TypeError.new("Unsupported resource strategy") unless RESOURCE_STRATEGIES.includes?(strategy)
      @resource_strategy = strategy
    end

    # ─── Callback setters ────────────────────────────────────────────

    def set_link_established_callback(callback : Proc(Link, Nil))
      @callbacks.link_established = callback
    end

    def set_link_closed_callback(callback : Proc(Link, Nil))
      @callbacks.link_closed = callback
    end

    def set_packet_callback(callback : Proc(Bytes, Packet, Nil))
      @callbacks.packet = callback
    end

    def set_remote_identified_callback(callback : Proc(Link, Identity, Nil))
      @callbacks.remote_identified = callback
    end

    def set_resource_callback(callback : Proc(Resource, Bool))
      @callbacks.resource = callback
    end

    def set_resource_started_callback(callback : Proc(Resource, Nil))
      @callbacks.resource_started = callback
    end

    def set_resource_concluded_callback(callback : Proc(Resource, Nil))
      @callbacks.resource_concluded = callback
    end

    # ─── String representation ───────────────────────────────────────

    def to_s(io : IO)
      io << RNS.prettyhexrep(@link_id)
    end

    def to_s : String
      RNS.prettyhexrep(@link_id)
    end
  end

  # ─── LinkChannelOutlet ─────────────────────────────────────────────

  class LinkChannelOutlet < ChannelOutletBase(Packet)
    getter link : Link

    def initialize(@link : Link)
    end

    def send(raw : Bytes) : Packet
      packet = Packet.new(@link, raw, packet_type: Packet::DATA, context: Packet::CHANNEL)
      packet.send
      @link.had_outbound
      packet
    end

    def resend(packet : Packet) : Packet
      new_packet = Packet.new(@link, packet.data, packet_type: Packet::DATA, context: Packet::CHANNEL)
      new_packet.send
      @link.had_outbound
      new_packet
    end

    def mdu : Int32
      @link.mdu
    end

    def rtt : Float64
      @link.rtt || 0.0
    end

    def is_usable : Bool
      @link.status == Link::ACTIVE
    end

    def get_packet_state(packet : Packet) : Int32
      receipt = packet.receipt
      if receipt
        receipt.get_status.to_i32
      else
        PacketReceipt::SENT.to_i32
      end
    end

    def timed_out
      @link.teardown
    end

    def set_packet_timeout_callback(packet : Packet, callback : (Packet -> Nil)?, timeout : Float64?)
      receipt = packet.receipt
      if receipt && callback
        receipt.set_timeout(timeout || (@link.rtt || 1.0) * Link::TRAFFIC_TIMEOUT_FACTOR)
        receipt.set_timeout_callback(->(_pr : PacketReceipt) { callback.call(packet); nil })
      end
    end

    def set_packet_delivered_callback(packet : Packet, callback : (Packet -> Nil)?)
      receipt = packet.receipt
      if receipt && callback
        receipt.set_delivery_callback(->(_pr : PacketReceipt) { callback.call(packet); nil })
      end
    end

    def get_packet_id(packet : Packet) : Bytes
      packet.get_hash
    end
  end

  # ─── RequestReceipt ────────────────────────────────────────────────

  class RequestReceipt
    FAILED    = 0x00_u8
    SENT      = 0x01_u8
    DELIVERED = 0x02_u8
    RECEIVING = 0x03_u8
    READY     = 0x04_u8

    property request_id : Bytes
    property request_size : Int32?
    property response : MessagePack::Any?
    property response_transfer_size : Int32?
    property response_size : Int32?
    property metadata : Bytes?
    property status : UInt8
    property sent_at : Float64
    property progress : Float64
    property concluded_at : Float64?
    property response_concluded_at : Float64?
    property timeout : Float64
    property started_at : Float64?
    property callbacks : RequestReceiptCallbacks
    property link : Link
    property packet_receipt : PacketReceipt?
    @resource_response_timeout : Float64?

    def initialize(link : Link,
                   packet_receipt : PacketReceipt? = nil,
                   resource = nil,
                   response_callback : Proc(RequestReceipt, Nil)? = nil,
                   failed_callback : Proc(RequestReceipt, Nil)? = nil,
                   progress_callback : Proc(RequestReceipt, Nil)? = nil,
                   timeout : Float64 = 0.0,
                   request_size : Int32? = nil)
      @packet_receipt = packet_receipt
      @started_at = nil
      @link = link

      if packet_receipt
        @request_id = packet_receipt.truncated_hash
        packet_receipt.set_timeout_callback(->(pr : PacketReceipt) { request_timed_out(pr) })
        @started_at = Time.utc.to_unix_f
      else
        @request_id = Bytes.new(16)
      end

      @request_size = request_size
      @response = nil
      @response_transfer_size = nil
      @response_size = nil
      @metadata = nil
      @status = SENT
      @sent_at = Time.utc.to_unix_f
      @progress = 0.0
      @concluded_at = nil
      @response_concluded_at = nil
      @resource_response_timeout = nil
      @timeout = timeout

      @callbacks = RequestReceiptCallbacks.new
      @callbacks.response = response_callback
      @callbacks.failed = failed_callback
      @callbacks.progress = progress_callback

      @link.pending_requests << self
    end

    def request_timed_out(packet_receipt : PacketReceipt?)
      if @link.pending_requests.includes?(self) && @status == DELIVERED
        @status = FAILED
        @concluded_at = Time.utc.to_unix_f
        @link.pending_requests.delete(self)

        cb = @callbacks.failed
        if cb
          begin
            cb.call(self)
          rescue ex
            RNS.log("Error while executing request timed out callback: #{ex}", RNS::LOG_ERROR)
          end
        end
      end
    end

    # Called when a request sent as a Resource completes transfer
    def request_resource_concluded(resource_status : UInt8, resource_complete : UInt8 = 0x00_u8)
      if resource_status == resource_complete
        RNS.log("Request #{RNS.prettyhexrep(@request_id)} successfully sent as resource.", RNS::LOG_DEBUG)
        @started_at = Time.utc.to_unix_f if @started_at.nil?
        @status = DELIVERED
        @resource_response_timeout = Time.utc.to_unix_f + @timeout
        spawn { response_timeout_job }
      else
        RNS.log("Sending request #{RNS.prettyhexrep(@request_id)} as resource failed", RNS::LOG_DEBUG)
        @status = FAILED
        @concluded_at = Time.utc.to_unix_f
        @link.pending_requests.delete(self)

        cb = @callbacks.failed
        if cb
          begin
            cb.call(self)
          rescue ex
            RNS.log("Error while executing request failed callback: #{ex}", RNS::LOG_ERROR)
          end
        end
      end
    end

    # Monitors timeout for resource-based request responses
    private def response_timeout_job
      while @status == DELIVERED
        now = Time.utc.to_unix_f
        rrt = @resource_response_timeout
        if rrt && now > rrt
          request_timed_out(nil)
          break
        end
        sleep 0.1.seconds
      end
    end

    # Called when progress is made receiving a response resource
    def response_resource_progress(resource_progress : Float64)
      return if @status == FAILED

      @status = RECEIVING

      pr = @packet_receipt
      if pr && pr.status != PacketReceipt::DELIVERED
        pr.status = PacketReceipt::DELIVERED
        pr.proved = true
        pr.concluded_at = Time.utc.to_unix_f
        delivery_cb = pr.callbacks.delivery
        delivery_cb.call(pr) if delivery_cb
      end

      @progress = resource_progress

      progress_cb = @callbacks.progress
      if progress_cb
        begin
          progress_cb.call(self)
        rescue ex
          RNS.log("Error while executing response progress callback: #{ex}", RNS::LOG_ERROR)
        end
      end
    end

    def response_received(response : MessagePack::Any, metadata : Bytes? = nil)
      return if @status == FAILED

      @progress = 1.0
      @response = response
      @metadata = metadata
      @status = READY
      @response_concluded_at = Time.utc.to_unix_f

      pr = @packet_receipt
      if pr
        pr.status = PacketReceipt::DELIVERED
        pr.proved = true
        pr.concluded_at = Time.utc.to_unix_f
        delivery_cb = pr.callbacks.delivery
        delivery_cb.call(pr) if delivery_cb
      end

      progress_cb = @callbacks.progress
      if progress_cb
        begin
          progress_cb.call(self)
        rescue ex
          RNS.log("Error while executing response progress callback: #{ex}", RNS::LOG_ERROR)
        end
      end

      response_cb = @callbacks.response
      if response_cb
        begin
          response_cb.call(self)
        rescue ex
          RNS.log("Error while executing response received callback: #{ex}", RNS::LOG_ERROR)
        end
      end
    end

    def get_request_id : Bytes
      @request_id
    end

    def get_status : UInt8
      @status
    end

    def get_progress : Float64
      @progress
    end

    def get_response : MessagePack::Any?
      @status == READY ? @response : nil
    end

    def get_response_time : Float64?
      if @status == READY
        sa = @started_at
        rca = @response_concluded_at
        (sa && rca) ? rca - sa : nil
      else
        nil
      end
    end

    def concluded? : Bool
      @status == READY || @status == FAILED
    end
  end

  class RequestReceiptCallbacks
    property response : Proc(RequestReceipt, Nil)?
    property failed : Proc(RequestReceipt, Nil)?
    property progress : Proc(RequestReceipt, Nil)?

    def initialize
      @response = nil
      @failed = nil
      @progress = nil
    end
  end
end
