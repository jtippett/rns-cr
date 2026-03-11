module RNS
  # ═══════════════════════════════════════════════════════════════
  # System message type identifiers (reserved range >= 0xf000)
  # ═══════════════════════════════════════════════════════════════

  module SystemMessageTypes
    SMT_STREAM_DATA = 0xff00_u16
  end

  # ═══════════════════════════════════════════════════════════════
  # ChannelException type codes
  # ═══════════════════════════════════════════════════════════════

  module CEType
    ME_NO_MSG_TYPE      = 0
    ME_INVALID_MSG_TYPE = 1
    ME_NOT_REGISTERED   = 2
    ME_LINK_NOT_READY   = 3
    ME_ALREADY_SENT     = 4
    ME_TOO_BIG          = 5
  end

  # ═══════════════════════════════════════════════════════════════
  # Custom exception with type code
  # ═══════════════════════════════════════════════════════════════

  class ChannelException < Exception
    getter type : Int32

    def initialize(@type : Int32, message : String = "")
      super(message)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Message state constants
  # ═══════════════════════════════════════════════════════════════

  module MessageState
    MSGSTATE_NEW       = 0
    MSGSTATE_SENT      = 1
    MSGSTATE_DELIVERED = 2
    MSGSTATE_FAILED    = 3
  end

  # ═══════════════════════════════════════════════════════════════
  # Abstract base class for channel messages
  # ═══════════════════════════════════════════════════════════════

  abstract class MessageBase
    # Subclasses must define: class_getter msgtype : UInt16
    # MSGTYPE must be unique and < 0xf000 (values >= 0xf000 reserved)

    abstract def pack : Bytes
    abstract def unpack(raw : Bytes)
  end

  # ═══════════════════════════════════════════════════════════════
  # Abstract transport layer interface for Channel (generic over TPacket)
  # Matches Python's ChannelOutletBase(ABC, Generic[TPacket])
  # ═══════════════════════════════════════════════════════════════

  abstract class ChannelOutletBase(TPacket)
    abstract def send(raw : Bytes) : TPacket
    abstract def resend(packet : TPacket) : TPacket
    abstract def mdu : Int32
    abstract def rtt : Float64
    abstract def is_usable : Bool
    abstract def get_packet_state(packet : TPacket) : Int32
    abstract def timed_out
    abstract def set_packet_timeout_callback(packet : TPacket, callback : (TPacket -> Nil)?, timeout : Float64?)
    abstract def set_packet_delivered_callback(packet : TPacket, callback : (TPacket -> Nil)?)
    abstract def get_packet_id(packet : TPacket) : Bytes
  end

  # ═══════════════════════════════════════════════════════════════
  # Envelope — internal wrapper for transporting messages
  # ═══════════════════════════════════════════════════════════════

  class Envelope(TPacket)
    property ts : Float64
    property message : MessageBase?
    property raw : Bytes?
    property packet : TPacket?
    property sequence : UInt16
    property outlet : ChannelOutletBase(TPacket)
    property tries : Int32
    property unpacked : Bool
    property packed : Bool
    property tracked : Bool

    def initialize(@outlet : ChannelOutletBase(TPacket),
                   @message : MessageBase? = nil,
                   raw : Bytes? = nil,
                   @sequence : UInt16 = 0_u16)
      @ts = Time.utc.to_unix_f
      @raw = raw
      @packet = nil
      @tries = 0
      @unpacked = false
      @packed = false
      @tracked = false
    end

    def pack : Bytes
      msg = @message
      raise ChannelException.new(CEType::ME_NO_MSG_TYPE, "Message lacks MSGTYPE") if msg.nil?

      msgtype = msg.class.responds_to?(:msgtype) ? msg.class.msgtype : nil
      raise ChannelException.new(CEType::ME_NO_MSG_TYPE, "#{msg.class} lacks MSGTYPE") if msgtype.nil?

      data = msg.pack
      io = IO::Memory.new(6 + data.size)
      io.write_bytes(msgtype.as(UInt16), IO::ByteFormat::BigEndian)
      io.write_bytes(@sequence, IO::ByteFormat::BigEndian)
      io.write_bytes(data.size.to_u16, IO::ByteFormat::BigEndian)
      io.write(data)
      @raw = io.to_slice.dup
      @packed = true
      @raw.not_nil!
    end

    def unpack(message_factories : Hash(UInt16, MessageBase.class)) : MessageBase
      raw = @raw
      raise ChannelException.new(CEType::ME_NOT_REGISTERED, "No raw data to unpack") if raw.nil? || raw.size < 6

      io = IO::Memory.new(raw)
      msgtype = io.read_bytes(UInt16, IO::ByteFormat::BigEndian)
      @sequence = io.read_bytes(UInt16, IO::ByteFormat::BigEndian)
      _length = io.read_bytes(UInt16, IO::ByteFormat::BigEndian)
      payload = raw[6..]

      ctor = message_factories[msgtype]?
      raise ChannelException.new(CEType::ME_NOT_REGISTERED, "Unable to find constructor for Channel MSGTYPE #{msgtype.to_s(16)}") if ctor.nil?

      message = ctor.new
      message.unpack(payload)
      @unpacked = true
      @message = message
      message
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Channel — reliable bi-directional message delivery over a Link
  # Generic over TPacket matching the outlet's packet type
  # ═══════════════════════════════════════════════════════════════

  class Channel(TPacket)
    # ─── Window constants ───────────────────────────────────────
    WINDOW                  =  2
    WINDOW_MIN              =  2
    WINDOW_MIN_LIMIT_SLOW   =  2
    WINDOW_MIN_LIMIT_MEDIUM =  5
    WINDOW_MIN_LIMIT_FAST   = 16

    WINDOW_MAX_SLOW   =  5
    WINDOW_MAX_MEDIUM = 12
    WINDOW_MAX_FAST   = 48
    WINDOW_MAX        = WINDOW_MAX_FAST

    FAST_RATE_THRESHOLD = 10

    RTT_FAST   = 0.18
    RTT_MEDIUM = 0.75
    RTT_SLOW   = 1.45

    WINDOW_FLEXIBILITY = 4

    SEQ_MAX     =  0xFFFF_u16
    SEQ_MODULUS = 0x10000_u32

    # ─── Instance state ─────────────────────────────────────────
    property window : Int32
    property window_max : Int32
    property window_min : Int32
    property window_flexibility : Int32
    property fast_rate_rounds : Int32
    property medium_rate_rounds : Int32

    def initialize(@outlet : ChannelOutletBase(TPacket))
      @lock = Mutex.new(:reentrant)
      @tx_ring = Deque(Envelope(TPacket)).new
      @rx_ring = Deque(Envelope(TPacket)).new
      @message_callbacks = [] of (MessageBase -> Bool)
      @next_sequence = 0_u16
      @next_rx_sequence = 0_u16
      @message_factories = {} of UInt16 => MessageBase.class
      @max_tries = 5
      @fast_rate_rounds = 0
      @medium_rate_rounds = 0

      if @outlet.rtt > RTT_SLOW
        @window = 1
        @window_max = 1
        @window_min = 1
        @window_flexibility = 1
      else
        @window = WINDOW
        @window_max = WINDOW_MAX_SLOW
        @window_min = WINDOW_MIN
        @window_flexibility = WINDOW_FLEXIBILITY
      end
    end

    # Register a message class for reception over this Channel.
    def register_message_type(message_class : MessageBase.class)
      _register_message_type(message_class, is_system_type: false)
    end

    def _register_message_type(message_class : MessageBase.class, *, is_system_type : Bool = false)
      @lock.synchronize do
        msgtype = message_class.responds_to?(:msgtype) ? message_class.msgtype : nil
        if msgtype.nil?
          raise ChannelException.new(CEType::ME_INVALID_MSG_TYPE, "#{message_class} has invalid MSGTYPE class attribute")
        end
        mt = msgtype.as(UInt16)
        if mt >= 0xf000_u16 && !is_system_type
          raise ChannelException.new(CEType::ME_INVALID_MSG_TYPE, "#{message_class} has system-reserved message type")
        end
        @message_factories[mt] = message_class
      end
    end

    # Add a handler for incoming messages.
    # Signature: (message : MessageBase) -> Bool
    # Return true to stop processing further handlers.
    def add_message_handler(callback : MessageBase -> Bool)
      @lock.synchronize do
        unless @message_callbacks.includes?(callback)
          @message_callbacks << callback
        end
      end
    end

    # Remove a previously added handler.
    def remove_message_handler(callback : MessageBase -> Bool)
      @lock.synchronize do
        @message_callbacks.delete(callback)
      end
    end

    # Maximum Data Unit available for messages.
    # Accounts for 6-byte envelope header (msgtype + sequence + length).
    def mdu : Int32
      m = @outlet.mdu - 6
      m = 0xFFFF if m > 0xFFFF
      m
    end

    # Check if Channel is ready to send.
    def is_ready_to_send? : Bool
      return false unless @outlet.is_usable

      @lock.synchronize do
        outstanding = 0
        @tx_ring.each do |envelope|
          if envelope.outlet == @outlet
            pkt = envelope.packet
            if pkt.nil? || @outlet.get_packet_state(pkt) != MessageState::MSGSTATE_DELIVERED
              outstanding += 1
            end
          end
        end
        return false if outstanding >= @window
      end

      true
    end

    # Send a message. Raises ChannelException if not ready.
    def send(message : MessageBase) : Envelope(TPacket)
      envelope : Envelope(TPacket)? = nil

      @lock.synchronize do
        raise ChannelException.new(CEType::ME_LINK_NOT_READY, "Link is not ready") unless is_ready_to_send?
        envelope = Envelope(TPacket).new(@outlet, message: message, sequence: @next_sequence)
        @next_sequence = ((@next_sequence.to_u32 + 1_u32) % SEQ_MODULUS).to_u16
        _emplace_envelope(envelope.not_nil!, @tx_ring)
      end

      env = envelope.not_nil!
      env.pack
      raw = env.raw
      if raw && raw.size > @outlet.mdu
        raise ChannelException.new(CEType::ME_TOO_BIG, "Packed message too big for packet: #{raw.size} > #{@outlet.mdu}")
      end

      packet = @outlet.send(raw.not_nil!)
      env.packet = packet
      env.tries += 1

      delivered_cb = ->(pkt : TPacket) { _packet_delivered(pkt); nil }
      timeout_cb = ->(pkt : TPacket) { _packet_timeout(pkt); nil }

      @outlet.set_packet_delivered_callback(packet, delivered_cb)
      @outlet.set_packet_timeout_callback(packet, timeout_cb, _get_packet_timeout_time(env.tries))
      _update_packet_timeouts

      env
    end

    # Process incoming raw bytes as a channel message.
    def _receive(raw : Bytes)
      envelope = Envelope(TPacket).new(outlet: @outlet, raw: raw)
      is_new = false

      @lock.synchronize do
        envelope.unpack(@message_factories)

        if envelope.sequence < @next_rx_sequence
          window_overflow = ((@next_rx_sequence.to_u32 + WINDOW_MAX.to_u32) % SEQ_MODULUS).to_u16
          if window_overflow < @next_rx_sequence
            if envelope.sequence > window_overflow
              RNS.log("Invalid packet sequence (#{envelope.sequence}) received on channel #{self}", RNS::LOG_EXTREME)
              return
            end
          else
            RNS.log("Invalid packet sequence (#{envelope.sequence}) received on channel #{self}", RNS::LOG_EXTREME)
            return
          end
        end

        is_new = _emplace_envelope(envelope, @rx_ring)
      end

      if !is_new
        RNS.log("Duplicate message received on channel #{self}", RNS::LOG_EXTREME)
        return
      end

      @lock.synchronize do
        contiguous = [] of Envelope(TPacket)
        @rx_ring.each do |e|
          if e.sequence == @next_rx_sequence
            contiguous << e
            @next_rx_sequence = ((@next_rx_sequence.to_u32 + 1_u32) % SEQ_MODULUS).to_u16
            if @next_rx_sequence == 0_u16
              @rx_ring.each do |e2|
                if e2.sequence == @next_rx_sequence
                  contiguous << e2
                  @next_rx_sequence = ((@next_rx_sequence.to_u32 + 1_u32) % SEQ_MODULUS).to_u16
                end
              end
            end
          end
        end

        contiguous.each do |e|
          m = if !e.unpacked
                e.unpack(@message_factories)
              else
                e.message.not_nil!
              end
          @rx_ring.delete(e)
          _run_callbacks(m)
        end
      end
    rescue ex
      RNS.log("An error occurred while receiving data on #{self}. The contained exception was: #{ex}", RNS::LOG_ERROR)
    end

    # Shut down the channel, clearing callbacks and rings.
    def shutdown
      @lock.synchronize do
        @message_callbacks.clear
        _clear_rings
      end
    end

    # Test helper: set the next outbound sequence number.
    def _set_next_sequence(seq : UInt16)
      @next_sequence = seq
    end

    # Compute packet timeout based on tries, RTT, and tx_ring size.
    def _get_packet_timeout_time(tries : Int32) : Float64
      (1.5 ** (tries - 1)) * Math.max(@outlet.rtt * 2.5, 0.025) * (@tx_ring.size + 1.5)
    end

    # ─── Private methods ────────────────────────────────────────

    private def _clear_rings
      @tx_ring.each do |envelope|
        pkt = envelope.packet
        if pkt
          @outlet.set_packet_timeout_callback(pkt, nil, nil)
          @outlet.set_packet_delivered_callback(pkt, nil)
        end
      end
      @tx_ring.clear
      @rx_ring.clear
    end

    private def _emplace_envelope(envelope : Envelope(TPacket), ring : Deque(Envelope(TPacket))) : Bool
      i = 0
      ring.each do |existing|
        if envelope.sequence == existing.sequence
          RNS.log("Envelope: Emplacement of duplicate envelope with sequence #{envelope.sequence}", RNS::LOG_EXTREME)
          return false
        end

        if envelope.sequence < existing.sequence && !((@next_rx_sequence.to_i32 - envelope.sequence.to_i32).abs > (SEQ_MAX // 2).to_i32)
          ring.insert(i, envelope)
          envelope.tracked = true
          return true
        end

        i += 1
      end

      envelope.tracked = true
      ring.push(envelope)
      true
    end

    private def _run_callbacks(message : MessageBase)
      cbs = @message_callbacks.dup
      cbs.each do |cb|
        begin
          return if cb.call(message)
        rescue e
          RNS.log("Channel #{self} experienced an error while running a message callback. The contained exception was: #{e}", RNS::LOG_ERROR)
        end
      end
    end

    private def _packet_delivered(packet : TPacket)
      _packet_tx_op(packet) { |_env| true }
    end

    private def _packet_timeout(packet : TPacket)
      pkt_state = @outlet.get_packet_state(packet)
      return if pkt_state == MessageState::MSGSTATE_DELIVERED

      _packet_tx_op(packet) do |envelope|
        if envelope.tries >= @max_tries
          RNS.log("Retry count exceeded on #{self}, tearing down Link.", RNS::LOG_ERROR)
          shutdown
          @outlet.timed_out
          next true
        end

        envelope.tries += 1
        epkt = envelope.packet
        @outlet.resend(epkt) if epkt

        delivered_cb = ->(pkt : TPacket) { _packet_delivered(pkt); nil }
        timeout_cb = ->(pkt : TPacket) { _packet_timeout(pkt); nil }
        @outlet.set_packet_delivered_callback(epkt.not_nil!, delivered_cb)
        @outlet.set_packet_timeout_callback(epkt.not_nil!, timeout_cb, _get_packet_timeout_time(envelope.tries))
        _update_packet_timeouts

        if @window > @window_min
          @window -= 1
          if @window_max > (@window_min + @window_flexibility)
            @window_max -= 1
          end
        end

        false
      end
    end

    private def _packet_tx_op(packet : TPacket, &op : Envelope(TPacket) -> Bool)
      found_envelope : Envelope(TPacket)? = nil

      @lock.synchronize do
        packet_id = @outlet.get_packet_id(packet)
        @tx_ring.each do |e|
          ep = e.packet
          next if ep.nil?
          if @outlet.get_packet_id(ep) == packet_id
            found_envelope = e
            break
          end
        end

        env = found_envelope
        if env && op.call(env)
          env.tracked = false
          if @tx_ring.includes?(env)
            @tx_ring.delete(env)

            if @window < @window_max
              @window += 1
            end

            if @outlet.rtt != 0.0
              if @outlet.rtt > RTT_FAST
                @fast_rate_rounds = 0

                if @outlet.rtt > RTT_MEDIUM
                  @medium_rate_rounds = 0
                else
                  @medium_rate_rounds += 1
                  if @window_max < WINDOW_MAX_MEDIUM && @medium_rate_rounds == FAST_RATE_THRESHOLD
                    @window_max = WINDOW_MAX_MEDIUM
                    @window_min = WINDOW_MIN_LIMIT_MEDIUM
                  end
                end
              else
                @fast_rate_rounds += 1
                if @window_max < WINDOW_MAX_FAST && @fast_rate_rounds == FAST_RATE_THRESHOLD
                  @window_max = WINDOW_MAX_FAST
                  @window_min = WINDOW_MIN_LIMIT_FAST
                end
              end
            end
          else
            RNS.log("Envelope not found in TX ring for #{self}", RNS::LOG_EXTREME)
          end
        end
      end

      if found_envelope.nil?
        RNS.log("Spurious message received on #{self}", RNS::LOG_EXTREME)
      end
    end

    private def _update_packet_timeouts
      # In the full implementation with Link, this updates
      # packet receipt timeouts. For now, a no-op placeholder.
    end
  end
end
