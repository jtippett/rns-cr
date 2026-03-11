require "../spec_helper"

# ═══════════════════════════════════════════════════════════════════
# Test helpers - concrete implementations of abstract types
# ═══════════════════════════════════════════════════════════════════

class TestMessage < RNS::MessageBase
  class_getter msgtype : UInt16 = 0x0101_u16

  property data : String

  def initialize(@data : String = "")
  end

  def pack : Bytes
    @data.to_slice.dup
  end

  def unpack(raw : Bytes)
    @data = String.new(raw)
  end
end

class AnotherMessage < RNS::MessageBase
  class_getter msgtype : UInt16 = 0x0202_u16

  property value : Int32

  def initialize(@value : Int32 = 0)
  end

  def pack : Bytes
    io = IO::Memory.new
    io.write_bytes(@value, IO::ByteFormat::BigEndian)
    io.to_slice.dup
  end

  def unpack(raw : Bytes)
    io = IO::Memory.new(raw)
    @value = io.read_bytes(Int32, IO::ByteFormat::BigEndian)
  end
end

class SystemReservedMessage < RNS::MessageBase
  class_getter msgtype : UInt16 = 0xf001_u16

  def initialize
  end

  def pack : Bytes
    Bytes.new(0)
  end

  def unpack(raw : Bytes)
  end
end

class NoMsgtypeMessage < RNS::MessageBase
  class_getter msgtype : UInt16? = nil

  def initialize
  end

  def pack : Bytes
    Bytes.new(0)
  end

  def unpack(raw : Bytes)
  end
end

# Mock packet for testing outlet interactions
class MockPacket
  property hash : Bytes
  property raw : Bytes
  property state : Int32
  property timeout_callback : (MockPacket -> Nil)?
  property delivered_callback : (MockPacket -> Nil)?
  property timeout_value : Float64?

  def initialize(@raw : Bytes = Bytes.new(0))
    @hash = Random::Secure.random_bytes(16)
    @state = RNS::MessageState::MSGSTATE_SENT
    @timeout_callback = nil
    @delivered_callback = nil
    @timeout_value = nil
  end
end

# Test implementation of ChannelOutletBase
class TestOutlet < RNS::ChannelOutletBase(MockPacket)
  property _mdu : Int32
  property _rtt : Float64
  property _is_usable : Bool
  property sent_packets : Array(MockPacket)
  property resent_packets : Array(MockPacket)

  def initialize(@_mdu : Int32 = 400, @_rtt : Float64 = 0.1, @_is_usable : Bool = true)
    @sent_packets = [] of MockPacket
    @resent_packets = [] of MockPacket
  end

  def send(raw : Bytes) : MockPacket
    pkt = MockPacket.new(raw)
    @sent_packets << pkt
    pkt
  end

  def resend(packet : MockPacket) : MockPacket
    @resent_packets << packet
    packet
  end

  def mdu : Int32
    @_mdu
  end

  def rtt : Float64
    @_rtt
  end

  def is_usable : Bool
    @_is_usable
  end

  def get_packet_state(packet : MockPacket) : Int32
    packet.state
  end

  def timed_out
    # no-op for testing
  end

  def set_packet_timeout_callback(packet : MockPacket, callback : (MockPacket -> Nil)?, timeout : Float64? = nil)
    packet.timeout_callback = callback
    packet.timeout_value = timeout if timeout
  end

  def set_packet_delivered_callback(packet : MockPacket, callback : (MockPacket -> Nil)?)
    packet.delivered_callback = callback
  end

  def get_packet_id(packet : MockPacket) : Bytes
    packet.hash
  end

  def to_s(io : IO)
    io << "TestOutlet"
  end
end

# Helper to build a raw envelope from a message
def build_raw_envelope(msgtype : UInt16, sequence : UInt16, payload : Bytes) : Bytes
  io = IO::Memory.new
  io.write_bytes(msgtype, IO::ByteFormat::BigEndian)
  io.write_bytes(sequence, IO::ByteFormat::BigEndian)
  io.write_bytes(payload.size.to_u16, IO::ByteFormat::BigEndian)
  io.write(payload)
  io.to_slice.dup
end

describe "RNS::Channel module" do
  # ════════════════════════════════════════════════════════════════
  #  SystemMessageTypes constants
  # ════════════════════════════════════════════════════════════════

  describe "SystemMessageTypes" do
    it "defines SMT_STREAM_DATA as 0xff00" do
      RNS::SystemMessageTypes::SMT_STREAM_DATA.should eq(0xff00_u16)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  CEType constants
  # ════════════════════════════════════════════════════════════════

  describe "CEType" do
    it "defines ME_NO_MSG_TYPE as 0" do
      RNS::CEType::ME_NO_MSG_TYPE.should eq(0)
    end

    it "defines ME_INVALID_MSG_TYPE as 1" do
      RNS::CEType::ME_INVALID_MSG_TYPE.should eq(1)
    end

    it "defines ME_NOT_REGISTERED as 2" do
      RNS::CEType::ME_NOT_REGISTERED.should eq(2)
    end

    it "defines ME_LINK_NOT_READY as 3" do
      RNS::CEType::ME_LINK_NOT_READY.should eq(3)
    end

    it "defines ME_ALREADY_SENT as 4" do
      RNS::CEType::ME_ALREADY_SENT.should eq(4)
    end

    it "defines ME_TOO_BIG as 5" do
      RNS::CEType::ME_TOO_BIG.should eq(5)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  MessageState constants
  # ════════════════════════════════════════════════════════════════

  describe "MessageState" do
    it "defines MSGSTATE_NEW as 0" do
      RNS::MessageState::MSGSTATE_NEW.should eq(0)
    end

    it "defines MSGSTATE_SENT as 1" do
      RNS::MessageState::MSGSTATE_SENT.should eq(1)
    end

    it "defines MSGSTATE_DELIVERED as 2" do
      RNS::MessageState::MSGSTATE_DELIVERED.should eq(2)
    end

    it "defines MSGSTATE_FAILED as 3" do
      RNS::MessageState::MSGSTATE_FAILED.should eq(3)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  ChannelException
  # ════════════════════════════════════════════════════════════════

  describe "ChannelException" do
    it "stores the type code" do
      ex = RNS::ChannelException.new(RNS::CEType::ME_NO_MSG_TYPE, "test")
      ex.type.should eq(RNS::CEType::ME_NO_MSG_TYPE)
    end

    it "stores the message" do
      ex = RNS::ChannelException.new(RNS::CEType::ME_TOO_BIG, "too big")
      ex.message.should eq("too big")
    end

    it "is an Exception subclass" do
      ex = RNS::ChannelException.new(RNS::CEType::ME_LINK_NOT_READY, "not ready")
      ex.is_a?(Exception).should be_true
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  MessageBase
  # ════════════════════════════════════════════════════════════════

  describe "MessageBase" do
    it "has a MSGTYPE class getter" do
      TestMessage.msgtype.should eq(0x0101_u16)
    end

    it "can be constructed with no args" do
      msg = TestMessage.new
      msg.data.should eq("")
    end

    it "packs to bytes" do
      msg = TestMessage.new("hello")
      String.new(msg.pack).should eq("hello")
    end

    it "unpacks from bytes" do
      msg = TestMessage.new
      msg.unpack("world".to_slice)
      msg.data.should eq("world")
    end

    it "roundtrips pack/unpack" do
      original = TestMessage.new("roundtrip test")
      packed = original.pack
      restored = TestMessage.new
      restored.unpack(packed)
      restored.data.should eq("roundtrip test")
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Envelope
  # ════════════════════════════════════════════════════════════════

  describe "Envelope" do
    it "initializes with message" do
      outlet = TestOutlet.new
      msg = TestMessage.new("test")
      env = RNS::Envelope(MockPacket).new(outlet, message: msg, sequence: 0_u16)
      env.message.should eq(msg)
      env.sequence.should eq(0_u16)
      env.tries.should eq(0)
      env.unpacked.should be_false
      env.packed.should be_false
      env.tracked.should be_false
    end

    it "initializes with raw bytes" do
      outlet = TestOutlet.new
      raw = Bytes.new(10)
      env = RNS::Envelope(MockPacket).new(outlet, raw: raw)
      env.raw.should eq(raw)
      env.message.should be_nil
    end

    it "packs a message into header + payload" do
      outlet = TestOutlet.new
      msg = TestMessage.new("hello")
      env = RNS::Envelope(MockPacket).new(outlet, message: msg, sequence: 42_u16)
      packed = env.pack
      packed.should_not be_nil
      # Header: 2 bytes msgtype + 2 bytes sequence + 2 bytes length = 6
      packed.size.should eq(6 + 5) # 6 header + "hello" length
      env.packed.should be_true
    end

    it "encodes header correctly (big-endian)" do
      outlet = TestOutlet.new
      msg = TestMessage.new("AB")
      env = RNS::Envelope(MockPacket).new(outlet, message: msg, sequence: 1_u16)
      packed = env.pack
      # MSGTYPE = 0x0101, big-endian
      packed[0].should eq(0x01_u8)
      packed[1].should eq(0x01_u8)
      # Sequence = 1, big-endian
      packed[2].should eq(0x00_u8)
      packed[3].should eq(0x01_u8)
      # Length = 2, big-endian
      packed[4].should eq(0x00_u8)
      packed[5].should eq(0x02_u8)
      # Payload
      packed[6].should eq('A'.ord.to_u8)
      packed[7].should eq('B'.ord.to_u8)
    end

    it "unpacks raw bytes into a message" do
      outlet = TestOutlet.new
      raw = build_raw_envelope(0x0101_u16, 0_u16, "hello".to_slice)

      factories = {0x0101_u16 => TestMessage.as(RNS::MessageBase.class)}
      env = RNS::Envelope(MockPacket).new(outlet, raw: raw)
      message = env.unpack(factories)
      message.should be_a(TestMessage)
      message.as(TestMessage).data.should eq("hello")
      env.unpacked.should be_true
      env.sequence.should eq(0_u16)
    end

    it "raises ChannelException for unregistered MSGTYPE" do
      outlet = TestOutlet.new
      raw = build_raw_envelope(0x9999_u16, 0_u16, Bytes.new(0))

      factories = {} of UInt16 => RNS::MessageBase.class
      env = RNS::Envelope(MockPacket).new(outlet, raw: raw)
      expect_raises(RNS::ChannelException) do
        env.unpack(factories)
      end
    end

    it "roundtrips pack then unpack" do
      outlet = TestOutlet.new
      msg = TestMessage.new("roundtrip")
      env1 = RNS::Envelope(MockPacket).new(outlet, message: msg, sequence: 7_u16)
      packed = env1.pack

      factories = {0x0101_u16 => TestMessage.as(RNS::MessageBase.class)}
      env2 = RNS::Envelope(MockPacket).new(outlet, raw: packed)
      result = env2.unpack(factories)
      result.as(TestMessage).data.should eq("roundtrip")
      env2.sequence.should eq(7_u16)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Channel — Window constants
  # ════════════════════════════════════════════════════════════════

  describe "Channel window constants" do
    it "defines WINDOW as 2" do
      RNS::Channel::WINDOW.should eq(2)
    end

    it "defines WINDOW_MIN as 2" do
      RNS::Channel::WINDOW_MIN.should eq(2)
    end

    it "defines WINDOW_MIN_LIMIT_SLOW as 2" do
      RNS::Channel::WINDOW_MIN_LIMIT_SLOW.should eq(2)
    end

    it "defines WINDOW_MIN_LIMIT_MEDIUM as 5" do
      RNS::Channel::WINDOW_MIN_LIMIT_MEDIUM.should eq(5)
    end

    it "defines WINDOW_MIN_LIMIT_FAST as 16" do
      RNS::Channel::WINDOW_MIN_LIMIT_FAST.should eq(16)
    end

    it "defines WINDOW_MAX_SLOW as 5" do
      RNS::Channel::WINDOW_MAX_SLOW.should eq(5)
    end

    it "defines WINDOW_MAX_MEDIUM as 12" do
      RNS::Channel::WINDOW_MAX_MEDIUM.should eq(12)
    end

    it "defines WINDOW_MAX_FAST as 48" do
      RNS::Channel::WINDOW_MAX_FAST.should eq(48)
    end

    it "defines WINDOW_MAX equal to WINDOW_MAX_FAST" do
      RNS::Channel::WINDOW_MAX.should eq(RNS::Channel::WINDOW_MAX_FAST)
    end

    it "defines WINDOW_FLEXIBILITY as 4" do
      RNS::Channel::WINDOW_FLEXIBILITY.should eq(4)
    end

    it "defines FAST_RATE_THRESHOLD as 10" do
      RNS::Channel::FAST_RATE_THRESHOLD.should eq(10)
    end

    it "defines RTT_FAST as 0.18" do
      RNS::Channel::RTT_FAST.should eq(0.18)
    end

    it "defines RTT_MEDIUM as 0.75" do
      RNS::Channel::RTT_MEDIUM.should eq(0.75)
    end

    it "defines RTT_SLOW as 1.45" do
      RNS::Channel::RTT_SLOW.should eq(1.45)
    end

    it "defines SEQ_MAX as 0xFFFF" do
      RNS::Channel::SEQ_MAX.should eq(0xFFFF_u16)
    end

    it "defines SEQ_MODULUS as 0x10000" do
      RNS::Channel::SEQ_MODULUS.should eq(0x10000_u32)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Channel — Constructor
  # ════════════════════════════════════════════════════════════════

  describe "Channel constructor" do
    it "initializes with normal RTT" do
      outlet = TestOutlet.new(_rtt: 0.1)
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.window.should eq(RNS::Channel::WINDOW)
      ch.window_max.should eq(RNS::Channel::WINDOW_MAX_SLOW)
      ch.window_min.should eq(RNS::Channel::WINDOW_MIN)
      ch.window_flexibility.should eq(RNS::Channel::WINDOW_FLEXIBILITY)
    end

    it "initializes with very slow RTT (> RTT_SLOW)" do
      outlet = TestOutlet.new(_rtt: 2.0)
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.window.should eq(1)
      ch.window_max.should eq(1)
      ch.window_min.should eq(1)
      ch.window_flexibility.should eq(1)
    end

    it "initializes with fast_rate_rounds and medium_rate_rounds at 0" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.fast_rate_rounds.should eq(0)
      ch.medium_rate_rounds.should eq(0)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Channel — register_message_type
  # ════════════════════════════════════════════════════════════════

  describe "#register_message_type" do
    it "registers a valid message type" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      # Should not raise
    end

    it "registers multiple different message types" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      ch.register_message_type(AnotherMessage)
      # Should not raise
    end

    it "rejects system-reserved MSGTYPE (>= 0xf000)" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      expect_raises(RNS::ChannelException) do
        ch.register_message_type(SystemReservedMessage)
      end
    end

    it "rejects message class without MSGTYPE" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      expect_raises(RNS::ChannelException) do
        ch.register_message_type(NoMsgtypeMessage)
      end
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Channel — message handlers
  # ════════════════════════════════════════════════════════════════

  describe "#add_message_handler / #remove_message_handler" do
    it "adds a message handler" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      called = false
      handler = ->(_msg : RNS::MessageBase) { called = true; true }
      ch.add_message_handler(handler)
    end

    it "does not add duplicate handlers" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      count = 0
      handler = ->(_msg : RNS::MessageBase) { count += 1; true }
      ch.add_message_handler(handler)
      ch.add_message_handler(handler) # duplicate
      ch.register_message_type(TestMessage)
      raw = build_raw_envelope(TestMessage.msgtype, 0_u16, "test".to_slice)
      ch._receive(raw)
      count.should eq(1)
    end

    it "removes a handler" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      called = false
      handler = ->(_msg : RNS::MessageBase) { called = true; true }
      ch.add_message_handler(handler)
      ch.remove_message_handler(handler)
      ch.register_message_type(TestMessage)
      raw = build_raw_envelope(TestMessage.msgtype, 0_u16, "test".to_slice)
      ch._receive(raw)
      called.should be_false
    end

    it "removing non-existent handler does nothing" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      handler = ->(_msg : RNS::MessageBase) { true }
      ch.remove_message_handler(handler) # should not raise
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Channel — MDU
  # ════════════════════════════════════════════════════════════════

  describe "#mdu" do
    it "is outlet.mdu minus 6 (header overhead)" do
      outlet = TestOutlet.new(_mdu: 400)
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.mdu.should eq(394)
    end

    it "caps at 0xFFFF" do
      outlet = TestOutlet.new(_mdu: 70000)
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.mdu.should eq(0xFFFF)
    end

    it "handles small MDU" do
      outlet = TestOutlet.new(_mdu: 10)
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.mdu.should eq(4)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Channel — is_ready_to_send?
  # ════════════════════════════════════════════════════════════════

  describe "#is_ready_to_send?" do
    it "returns true when outlet is usable and window is not full" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.is_ready_to_send?.should be_true
    end

    it "returns false when outlet is not usable" do
      outlet = TestOutlet.new(_is_usable: false)
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.is_ready_to_send?.should be_false
    end

    it "returns false when window is full" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      # Fill the window (default window = 2)
      ch.send(TestMessage.new("a"))
      ch.send(TestMessage.new("b"))
      ch.is_ready_to_send?.should be_false
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Channel — send
  # ════════════════════════════════════════════════════════════════

  describe "#send" do
    it "sends a message and returns an envelope" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      env = ch.send(TestMessage.new("hello"))
      env.should_not be_nil
      env.packed.should be_true
      env.tries.should eq(1)
      outlet.sent_packets.size.should eq(1)
    end

    it "increments sequence number" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      env1 = ch.send(TestMessage.new("a"))
      env1.sequence.should eq(0_u16)
      # Deliver first to free window
      outlet.sent_packets[0].state = RNS::MessageState::MSGSTATE_DELIVERED
      outlet.sent_packets[0].delivered_callback.try &.call(outlet.sent_packets[0])
      env2 = ch.send(TestMessage.new("b"))
      env2.sequence.should eq(1_u16)
    end

    it "raises ChannelException when not ready" do
      outlet = TestOutlet.new(_is_usable: false)
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      expect_raises(RNS::ChannelException) do
        ch.send(TestMessage.new("fail"))
      end
    end

    it "raises ChannelException when message too big" do
      outlet = TestOutlet.new(_mdu: 10) # mdu=10, channel mdu=4
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      expect_raises(RNS::ChannelException) do
        ch.send(TestMessage.new("this is way too long for the tiny mdu"))
      end
    end

    it "sets up delivered and timeout callbacks on packet" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      ch.send(TestMessage.new("test"))
      pkt = outlet.sent_packets[0]
      pkt.delivered_callback.should_not be_nil
      pkt.timeout_callback.should_not be_nil
    end

    it "sends raw bytes through outlet" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      ch.send(TestMessage.new("data"))
      outlet.sent_packets.size.should eq(1)
      pkt = outlet.sent_packets[0]
      pkt.raw.size.should eq(6 + 4) # header + "data"
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Channel — _receive
  # ════════════════════════════════════════════════════════════════

  describe "#_receive" do
    it "receives and dispatches a message to handler" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      received_data = ""
      handler = ->(msg : RNS::MessageBase) {
        received_data = msg.as(TestMessage).data
        true
      }
      ch.add_message_handler(handler)

      raw = build_raw_envelope(0x0101_u16, 0_u16, "hello".to_slice)
      ch._receive(raw)

      received_data.should eq("hello")
    end

    it "processes messages in sequence order" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      received = [] of String
      handler = ->(msg : RNS::MessageBase) {
        received << msg.as(TestMessage).data
        true
      }
      ch.add_message_handler(handler)

      # Send sequence 1 first (out of order)
      raw1 = build_raw_envelope(0x0101_u16, 1_u16, "second".to_slice)
      ch._receive(raw1)

      # Sequence 1 should be held (waiting for 0)
      received.size.should eq(0)

      # Now send sequence 0
      raw0 = build_raw_envelope(0x0101_u16, 0_u16, "first".to_slice)
      ch._receive(raw0)

      # Both should be delivered in order
      received.should eq(["first", "second"])
    end

    it "rejects duplicate sequences" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      count = 0
      handler = ->(_msg : RNS::MessageBase) {
        count += 1
        true
      }
      ch.add_message_handler(handler)

      raw = build_raw_envelope(0x0101_u16, 0_u16, "dup".to_slice)
      ch._receive(raw)
      ch._receive(raw.dup)

      count.should eq(1)
    end

    it "calls multiple handlers in order, stops on true" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      call_order = [] of Int32
      handler1 = ->(_msg : RNS::MessageBase) { call_order << 1; true }
      handler2 = ->(_msg : RNS::MessageBase) { call_order << 2; true }
      ch.add_message_handler(handler1)
      ch.add_message_handler(handler2)

      raw = build_raw_envelope(0x0101_u16, 0_u16, "test".to_slice)
      ch._receive(raw)

      call_order.should eq([1]) # handler2 not called because handler1 returned true
    end

    it "calls next handler when previous returns false" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      call_order = [] of Int32
      handler1 = ->(_msg : RNS::MessageBase) { call_order << 1; false }
      handler2 = ->(_msg : RNS::MessageBase) { call_order << 2; true }
      ch.add_message_handler(handler1)
      ch.add_message_handler(handler2)

      raw = build_raw_envelope(0x0101_u16, 0_u16, "test".to_slice)
      ch._receive(raw)

      call_order.should eq([1, 2])
    end

    it "handles unregistered message type gracefully" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      # Don't register TestMessage
      raw = build_raw_envelope(0x0101_u16, 0_u16, "test".to_slice)
      # Should not raise, just log error
      ch._receive(raw)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Channel — delivery and timeout
  # ════════════════════════════════════════════════════════════════

  describe "delivery callbacks" do
    it "removes envelope from tx_ring on delivery" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      ch.send(TestMessage.new("a"))

      pkt = outlet.sent_packets[0]
      pkt.state = RNS::MessageState::MSGSTATE_DELIVERED

      # Trigger delivery callback
      pkt.delivered_callback.try &.call(pkt)

      # Window should allow sending again
      ch.is_ready_to_send?.should be_true
    end

    it "increases window on delivery" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)

      # Set window to less than max
      ch.window = 2
      ch.send(TestMessage.new("a"))

      pkt = outlet.sent_packets[0]
      pkt.state = RNS::MessageState::MSGSTATE_DELIVERED
      pkt.delivered_callback.try &.call(pkt)

      ch.window.should eq(3)
    end
  end

  describe "timeout handling" do
    it "retries on timeout" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      ch.send(TestMessage.new("retry"))

      pkt = outlet.sent_packets[0]
      # Trigger timeout
      pkt.timeout_callback.try &.call(pkt)

      # Should have been resent
      outlet.resent_packets.size.should eq(1)
    end

    it "decreases window on timeout" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      ch.window = 4
      ch.window_min = 2
      ch.send(TestMessage.new("retry"))

      pkt = outlet.sent_packets[0]
      pkt.timeout_callback.try &.call(pkt)

      ch.window.should eq(3)
    end

    it "does not decrease window below window_min" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      ch.window = 2
      ch.window_min = 2
      ch.send(TestMessage.new("retry"))

      pkt = outlet.sent_packets[0]
      pkt.timeout_callback.try &.call(pkt)

      ch.window.should eq(2)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Channel — window rate adaptation
  # ════════════════════════════════════════════════════════════════

  describe "window rate adaptation" do
    it "increments fast_rate_rounds for fast RTT" do
      outlet = TestOutlet.new(_rtt: 0.05) # < RTT_FAST (0.18)
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      ch.send(TestMessage.new("fast"))

      pkt = outlet.sent_packets[0]
      pkt.state = RNS::MessageState::MSGSTATE_DELIVERED
      pkt.delivered_callback.try &.call(pkt)

      ch.fast_rate_rounds.should eq(1)
    end

    it "resets fast_rate_rounds for slower RTT" do
      outlet = TestOutlet.new(_rtt: 0.5) # > RTT_FAST, < RTT_MEDIUM
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      ch.fast_rate_rounds = 5
      ch.send(TestMessage.new("test"))

      pkt = outlet.sent_packets[0]
      pkt.state = RNS::MessageState::MSGSTATE_DELIVERED
      pkt.delivered_callback.try &.call(pkt)

      ch.fast_rate_rounds.should eq(0)
    end

    it "increments medium_rate_rounds for medium RTT" do
      outlet = TestOutlet.new(_rtt: 0.5) # > RTT_FAST, < RTT_MEDIUM
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      ch.send(TestMessage.new("test"))

      pkt = outlet.sent_packets[0]
      pkt.state = RNS::MessageState::MSGSTATE_DELIVERED
      pkt.delivered_callback.try &.call(pkt)

      ch.medium_rate_rounds.should eq(1)
    end

    it "resets medium_rate_rounds for slow RTT" do
      outlet = TestOutlet.new(_rtt: 1.0) # > RTT_MEDIUM
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      ch.medium_rate_rounds = 5
      ch.send(TestMessage.new("test"))

      pkt = outlet.sent_packets[0]
      pkt.state = RNS::MessageState::MSGSTATE_DELIVERED
      pkt.delivered_callback.try &.call(pkt)

      ch.medium_rate_rounds.should eq(0)
    end

    it "upgrades to WINDOW_MAX_FAST after sustained fast rate" do
      outlet = TestOutlet.new(_rtt: 0.05)
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      ch.fast_rate_rounds = RNS::Channel::FAST_RATE_THRESHOLD - 1

      ch.send(TestMessage.new("fast"))
      pkt = outlet.sent_packets[0]
      pkt.state = RNS::MessageState::MSGSTATE_DELIVERED
      pkt.delivered_callback.try &.call(pkt)

      ch.window_max.should eq(RNS::Channel::WINDOW_MAX_FAST)
      ch.window_min.should eq(RNS::Channel::WINDOW_MIN_LIMIT_FAST)
    end

    it "upgrades to WINDOW_MAX_MEDIUM after sustained medium rate" do
      outlet = TestOutlet.new(_rtt: 0.5)
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      ch.medium_rate_rounds = RNS::Channel::FAST_RATE_THRESHOLD - 1

      ch.send(TestMessage.new("med"))
      pkt = outlet.sent_packets[0]
      pkt.state = RNS::MessageState::MSGSTATE_DELIVERED
      pkt.delivered_callback.try &.call(pkt)

      ch.window_max.should eq(RNS::Channel::WINDOW_MAX_MEDIUM)
      ch.window_min.should eq(RNS::Channel::WINDOW_MIN_LIMIT_MEDIUM)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Channel — shutdown
  # ════════════════════════════════════════════════════════════════

  describe "#shutdown" do
    it "clears callbacks and rings" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      handler = ->(_msg : RNS::MessageBase) { true }
      ch.add_message_handler(handler)
      ch.send(TestMessage.new("test"))

      ch.shutdown

      # Should be able to send again (rings cleared)
      ch.is_ready_to_send?.should be_true
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Channel — sequence wrapping
  # ════════════════════════════════════════════════════════════════

  describe "sequence wrapping" do
    it "wraps sequence at SEQ_MODULUS" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)

      # Set sequence near max
      ch._set_next_sequence(0xFFFF_u16)
      env = ch.send(TestMessage.new("wrap"))
      env.sequence.should eq(0xFFFF_u16)

      # Deliver to free window
      pkt = outlet.sent_packets[0]
      pkt.state = RNS::MessageState::MSGSTATE_DELIVERED
      pkt.delivered_callback.try &.call(pkt)

      # Next should wrap to 0
      env2 = ch.send(TestMessage.new("wrapped"))
      env2.sequence.should eq(0_u16)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Channel — _get_packet_timeout_time
  # ════════════════════════════════════════════════════════════════

  describe "#_get_packet_timeout_time" do
    it "computes timeout based on tries, RTT, and tx_ring size" do
      outlet = TestOutlet.new(_rtt: 0.1)
      ch = RNS::Channel(MockPacket).new(outlet)
      # Formula: pow(1.5, tries-1) * max(rtt*2.5, 0.025) * (tx_ring_size + 1.5)
      timeout = ch._get_packet_timeout_time(1)
      expected = (1.5 ** 0) * Math.max(0.1 * 2.5, 0.025) * (0 + 1.5)
      timeout.should be_close(expected, 0.001)
    end

    it "increases timeout with more tries" do
      outlet = TestOutlet.new(_rtt: 0.1)
      ch = RNS::Channel(MockPacket).new(outlet)
      t1 = ch._get_packet_timeout_time(1)
      t2 = ch._get_packet_timeout_time(2)
      t3 = ch._get_packet_timeout_time(3)
      (t2 > t1).should be_true
      (t3 > t2).should be_true
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Channel — send/receive roundtrip
  # ════════════════════════════════════════════════════════════════

  describe "send/receive roundtrip" do
    it "roundtrips a message through pack and receive" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      received_msg : RNS::MessageBase? = nil
      handler = ->(msg : RNS::MessageBase) {
        received_msg = msg
        true
      }
      ch.add_message_handler(handler)

      # Send produces packed bytes on the outlet
      env = ch.send(TestMessage.new("roundtrip"))
      raw = env.raw.not_nil!

      # Create a new channel (simulating the other end)
      ch2 = RNS::Channel(MockPacket).new(outlet)
      ch2.register_message_type(TestMessage)
      ch2.add_message_handler(handler)
      ch2._receive(raw)

      received_msg.should_not be_nil
      received_msg.as(TestMessage).data.should eq("roundtrip")
    end

    it "handles AnotherMessage type" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(AnotherMessage)

      received_value = 0
      handler = ->(msg : RNS::MessageBase) {
        received_value = msg.as(AnotherMessage).value
        true
      }
      ch.add_message_handler(handler)

      env = ch.send(AnotherMessage.new(42))
      raw = env.raw.not_nil!

      ch2 = RNS::Channel(MockPacket).new(outlet)
      ch2.register_message_type(AnotherMessage)
      ch2.add_message_handler(handler)
      ch2._receive(raw)

      received_value.should eq(42)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Channel — stress tests
  # ════════════════════════════════════════════════════════════════

  describe "stress tests" do
    it "sends and receives 50 messages with delivery acknowledgment" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)

      50.times do |i|
        # May need to deliver previous messages to free window
        while !ch.is_ready_to_send?
          outlet.sent_packets.each do |pkt|
            if pkt.state == RNS::MessageState::MSGSTATE_SENT
              pkt.state = RNS::MessageState::MSGSTATE_DELIVERED
              pkt.delivered_callback.try &.call(pkt)
              break
            end
          end
        end
        ch.send(TestMessage.new("msg_#{i}"))
      end

      outlet.sent_packets.size.should eq(50)
    end

    it "receives 30 in-order messages" do
      outlet = TestOutlet.new
      ch = RNS::Channel(MockPacket).new(outlet)
      ch.register_message_type(TestMessage)
      received = [] of String
      handler = ->(msg : RNS::MessageBase) {
        received << msg.as(TestMessage).data
        true
      }
      ch.add_message_handler(handler)

      30.times do |i|
        raw = build_raw_envelope(TestMessage.msgtype, i.to_u16, "msg_#{i}".to_slice)
        ch._receive(raw)
      end

      received.size.should eq(30)
      received.first.should eq("msg_0")
      received.last.should eq("msg_29")
    end

    it "handles 20 pack/unpack roundtrips with random data" do
      outlet = TestOutlet.new
      20.times do |i|
        msg = TestMessage.new(Random::Secure.random_bytes(rand(1..100)).hexstring)
        env1 = RNS::Envelope(MockPacket).new(outlet, message: msg, sequence: i.to_u16)
        packed = env1.pack

        factories = {TestMessage.msgtype => TestMessage.as(RNS::MessageBase.class)}
        env2 = RNS::Envelope(MockPacket).new(outlet, raw: packed)
        result = env2.unpack(factories)
        result.as(TestMessage).data.should eq(msg.data)
      end
    end
  end
end
