require "../spec_helper"

# ═══════════════════════════════════════════════════════════════════
# Test helpers — mock packet and outlet for Channel testing
# ═══════════════════════════════════════════════════════════════════

class BufMockPacket
  property hash : Bytes
  property raw : Bytes
  property state : Int32
  property timeout_callback : (BufMockPacket -> Nil)?
  property delivered_callback : (BufMockPacket -> Nil)?
  property timeout_value : Float64?

  def initialize(@raw : Bytes = Bytes.new(0))
    @hash = Random::Secure.random_bytes(16)
    @state = RNS::MessageState::MSGSTATE_SENT
    @timeout_callback = nil
    @delivered_callback = nil
    @timeout_value = nil
  end
end

class BufTestOutlet < RNS::ChannelOutletBase(BufMockPacket)
  property _mdu : Int32
  property _rtt : Float64
  property _is_usable : Bool
  property sent_packets : Array(BufMockPacket)
  property resent_packets : Array(BufMockPacket)

  def initialize(@_mdu : Int32 = 400, @_rtt : Float64 = 0.1, @_is_usable : Bool = true)
    @sent_packets = [] of BufMockPacket
    @resent_packets = [] of BufMockPacket
  end

  def send(raw : Bytes) : BufMockPacket
    pkt = BufMockPacket.new(raw)
    @sent_packets << pkt
    pkt
  end

  def resend(packet : BufMockPacket) : BufMockPacket
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

  def get_packet_state(packet : BufMockPacket) : Int32
    packet.state
  end

  def timed_out
  end

  def set_packet_timeout_callback(packet : BufMockPacket, callback : (BufMockPacket -> Nil)?, timeout : Float64? = nil)
    packet.timeout_callback = callback
    packet.timeout_value = timeout if timeout
  end

  def set_packet_delivered_callback(packet : BufMockPacket, callback : (BufMockPacket -> Nil)?)
    packet.delivered_callback = callback
  end

  def get_packet_id(packet : BufMockPacket) : Bytes
    packet.hash
  end
end

# Helper: build raw envelope bytes from msgtype, sequence, payload
def buf_build_raw_envelope(msgtype : UInt16, sequence : UInt16, payload : Bytes) : Bytes
  io = IO::Memory.new
  io.write_bytes(msgtype, IO::ByteFormat::BigEndian)
  io.write_bytes(sequence, IO::ByteFormat::BigEndian)
  io.write_bytes(payload.size.to_u16, IO::ByteFormat::BigEndian)
  io.write(payload)
  io.to_slice.dup
end

# Helper: create a test channel with outlet
def buf_create_channel(mdu : Int32 = 400, rtt : Float64 = 0.1) : {RNS::Channel(BufMockPacket), BufTestOutlet}
  outlet = BufTestOutlet.new(_mdu: mdu, _rtt: rtt)
  channel = RNS::Channel(BufMockPacket).new(outlet)
  {channel, outlet}
end

# Helper: inject a StreamDataMessage into a channel as if received
def buf_inject_stream(channel : RNS::Channel(BufMockPacket), stream_id : Int32,
                      data : Bytes, eof : Bool = false, sequence : UInt16 = 0_u16)
  msg = RNS::StreamDataMessage.new(stream_id, data, eof)
  packed = msg.pack
  raw_envelope = buf_build_raw_envelope(RNS::StreamDataMessage.msgtype, sequence, packed)
  channel._receive(raw_envelope)
end

describe "RNS::StreamDataMessage" do
  describe "constants" do
    it "STREAM_ID_MAX is 0x3fff" do
      RNS::StreamDataMessage::STREAM_ID_MAX.should eq(0x3fff)
    end

    it "OVERHEAD is 8 (2 header + 6 envelope)" do
      RNS::StreamDataMessage::OVERHEAD.should eq(8)
    end

    it "MAX_DATA_LEN is Link::MDU - OVERHEAD" do
      expected = RNS::Link::MDU - RNS::StreamDataMessage::OVERHEAD
      RNS::StreamDataMessage::MAX_DATA_LEN.should eq(expected)
    end

    it "MSGTYPE is SMT_STREAM_DATA (0xff00)" do
      RNS::StreamDataMessage.msgtype.should eq(0xff00_u16)
    end
  end

  describe "constructor" do
    it "creates with defaults" do
      msg = RNS::StreamDataMessage.new
      msg.stream_id.should be_nil
      msg.data.size.should eq(0)
      msg.eof.should be_false
      msg.compressed.should be_false
    end

    it "creates with stream_id and data" do
      data = "hello".to_slice
      msg = RNS::StreamDataMessage.new(stream_id: 42, data: data)
      msg.stream_id.should eq(42)
      msg.data.should eq(data)
    end

    it "creates with eof flag" do
      msg = RNS::StreamDataMessage.new(stream_id: 1, eof: true)
      msg.eof.should be_true
    end

    it "creates with compressed flag" do
      msg = RNS::StreamDataMessage.new(stream_id: 1, compressed: true)
      msg.compressed.should be_true
    end

    it "raises on stream_id > STREAM_ID_MAX" do
      expect_raises(ArgumentError, "stream_id must be 0-16383") do
        RNS::StreamDataMessage.new(stream_id: 0x4000)
      end
    end

    it "allows stream_id = 0" do
      msg = RNS::StreamDataMessage.new(stream_id: 0)
      msg.stream_id.should eq(0)
    end

    it "allows stream_id = STREAM_ID_MAX" do
      msg = RNS::StreamDataMessage.new(stream_id: RNS::StreamDataMessage::STREAM_ID_MAX)
      msg.stream_id.should eq(0x3fff)
    end
  end

  describe "pack" do
    it "raises without stream_id" do
      msg = RNS::StreamDataMessage.new
      expect_raises(ArgumentError, "stream_id") do
        msg.pack
      end
    end

    it "packs header with stream_id only (no data)" do
      msg = RNS::StreamDataMessage.new(stream_id: 100)
      packed = msg.pack
      packed.size.should eq(2)
      header = IO::ByteFormat::BigEndian.decode(UInt16, packed)
      header.should eq(100_u16)
    end

    it "packs header with data" do
      data = "test".to_slice
      msg = RNS::StreamDataMessage.new(stream_id: 5, data: data.dup)
      packed = msg.pack
      packed.size.should eq(2 + 4)
      packed[2..].should eq(data)
    end

    it "sets eof bit in header" do
      msg = RNS::StreamDataMessage.new(stream_id: 1, eof: true)
      packed = msg.pack
      header = IO::ByteFormat::BigEndian.decode(UInt16, packed)
      (header & 0x8000).should eq(0x8000)
      (header & 0x3fff).should eq(1)
    end

    it "sets compressed bit in header" do
      msg = RNS::StreamDataMessage.new(stream_id: 2, compressed: true)
      packed = msg.pack
      header = IO::ByteFormat::BigEndian.decode(UInt16, packed)
      (header & 0x4000).should eq(0x4000)
      (header & 0x3fff).should eq(2)
    end

    it "sets both eof and compressed bits" do
      msg = RNS::StreamDataMessage.new(stream_id: 3, eof: true, compressed: true)
      packed = msg.pack
      header = IO::ByteFormat::BigEndian.decode(UInt16, packed)
      (header & 0xc000).should eq(0xc000)
      (header & 0x3fff).should eq(3)
    end

    it "preserves full 14-bit stream_id range" do
      msg = RNS::StreamDataMessage.new(stream_id: 0x3fff)
      packed = msg.pack
      header = IO::ByteFormat::BigEndian.decode(UInt16, packed)
      (header & 0x3fff).should eq(0x3fff)
    end
  end

  describe "unpack" do
    it "unpacks stream_id and data" do
      data = "hello".to_slice
      orig = RNS::StreamDataMessage.new(stream_id: 42, data: data.dup)
      packed = orig.pack

      msg = RNS::StreamDataMessage.new
      msg.unpack(packed)
      msg.stream_id.should eq(42)
      msg.data.should eq(data)
      msg.eof.should be_false
      msg.compressed.should be_false
    end

    it "unpacks eof flag" do
      orig = RNS::StreamDataMessage.new(stream_id: 1, eof: true)
      packed = orig.pack

      msg = RNS::StreamDataMessage.new
      msg.unpack(packed)
      msg.eof.should be_true
      msg.stream_id.should eq(1)
    end

    it "unpacks empty data" do
      orig = RNS::StreamDataMessage.new(stream_id: 10)
      packed = orig.pack

      msg = RNS::StreamDataMessage.new
      msg.unpack(packed)
      msg.stream_id.should eq(10)
      msg.data.size.should eq(0)
    end

    it "decompresses compressed data" do
      original_data = ("A" * 200).to_slice
      compressed = RNS::BZip2.compress(original_data)

      # Build raw with compressed bit set
      header_val = (5 | 0x4000).to_u16
      io = IO::Memory.new
      io.write_bytes(header_val, IO::ByteFormat::BigEndian)
      io.write(compressed)

      msg = RNS::StreamDataMessage.new
      msg.unpack(io.to_slice)
      msg.compressed.should be_true
      msg.stream_id.should eq(5)
      msg.data.should eq(original_data)
    end

    it "raises on too-short data" do
      expect_raises(ArgumentError) do
        msg = RNS::StreamDataMessage.new
        msg.unpack(Bytes.new(1))
      end
    end
  end

  describe "pack/unpack roundtrip" do
    it "preserves stream_id, data, and flags" do
      data = Random::Secure.random_bytes(50)
      orig = RNS::StreamDataMessage.new(stream_id: 1234, data: data, eof: true)
      packed = orig.pack

      msg = RNS::StreamDataMessage.new
      msg.unpack(packed)
      msg.stream_id.should eq(1234)
      msg.data.should eq(data)
      msg.eof.should be_true
    end

    it "roundtrips 100 random messages" do
      100.times do
        sid = Random.rand(0x3fff)
        data = Random::Secure.random_bytes(Random.rand(100))
        eof = Random.rand(2) == 1

        orig = RNS::StreamDataMessage.new(stream_id: sid, data: data, eof: eof)
        packed = orig.pack

        msg = RNS::StreamDataMessage.new
        msg.unpack(packed)
        msg.stream_id.should eq(sid)
        msg.data.should eq(data)
        msg.eof.should eq(eof)
      end
    end
  end
end

describe "RNS::RawChannelReader" do
  describe "constructor" do
    it "creates a reader for a stream_id" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)
      reader.readable?.should be_true
      reader.writable?.should be_false
      reader.seekable?.should be_false
      reader.closed?.should be_false
      reader.close
    end
  end

  describe "receiving data" do
    it "receives data from matching stream_id" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)

      buf_inject_stream(channel, 1, "hello".to_slice)
      reader.available.should eq(5)

      result = reader.read(10)
      result.should_not be_nil
      String.new(result.not_nil!).should eq("hello")
      reader.close
    end

    it "ignores data from different stream_id" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)

      buf_inject_stream(channel, 2, "other".to_slice)
      reader.available.should eq(0)
      reader.close
    end

    it "accumulates multiple messages" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)

      buf_inject_stream(channel, 1, "hello ".to_slice, sequence: 0_u16)
      buf_inject_stream(channel, 1, "world".to_slice, sequence: 1_u16)
      reader.available.should eq(11)

      result = reader.read(20)
      result.should_not be_nil
      String.new(result.not_nil!).should eq("hello world")
      reader.close
    end

    it "handles eof flag" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)

      buf_inject_stream(channel, 1, "data".to_slice, eof: true)
      reader.eof?.should be_true
      reader.close
    end

    it "returns nil when no data and not eof" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)

      result = reader.read(10)
      result.should be_nil
      reader.close
    end

    it "returns empty bytes at eof with no remaining data" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)

      buf_inject_stream(channel, 1, "data".to_slice, eof: true, sequence: 0_u16)
      reader.read(10) # consume all data

      result = reader.read(10)
      result.should_not be_nil
      result.not_nil!.size.should eq(0)
      reader.close
    end

    it "receives eof-only message with no data" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)

      buf_inject_stream(channel, 1, Bytes.new(0), eof: true)
      reader.eof?.should be_true
      reader.available.should eq(0)
      reader.close
    end
  end

  describe "readinto" do
    it "reads into provided buffer" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)

      buf_inject_stream(channel, 1, "hello".to_slice)

      buf = Bytes.new(10)
      n = reader.readinto(buf)
      n.should eq(5)
      String.new(buf[0, 5]).should eq("hello")
      reader.close
    end

    it "returns nil when no data" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)

      buf = Bytes.new(10)
      n = reader.readinto(buf)
      n.should be_nil
      reader.close
    end

    it "reads partial when buffer smaller than available" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)

      buf_inject_stream(channel, 1, "hello world".to_slice)

      buf = Bytes.new(5)
      n = reader.readinto(buf)
      n.should eq(5)
      String.new(buf).should eq("hello")
      reader.close
    end
  end

  describe "partial reads" do
    it "reads partial data and retains remainder" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)

      buf_inject_stream(channel, 1, "hello world".to_slice)

      result1 = reader.read(5)
      result1.should_not be_nil
      String.new(result1.not_nil!).should eq("hello")

      result2 = reader.read(20)
      result2.should_not be_nil
      String.new(result2.not_nil!).should eq(" world")
      reader.close
    end

    it "handles byte-by-byte reads" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)

      buf_inject_stream(channel, 1, "abc".to_slice)

      r1 = reader.read(1)
      r1.should_not be_nil
      r1.not_nil![0].should eq('a'.ord.to_u8)

      r2 = reader.read(1)
      r2.should_not be_nil
      r2.not_nil![0].should eq('b'.ord.to_u8)

      r3 = reader.read(1)
      r3.should_not be_nil
      r3.not_nil![0].should eq('c'.ord.to_u8)

      reader.available.should eq(0)
      reader.close
    end
  end

  describe "ready callbacks" do
    it "calls callback when data arrives" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)

      ready_count = 0
      ready_bytes = 0
      cb = ->(bytes : Int32) { ready_count += 1; ready_bytes = bytes; nil }
      reader.add_ready_callback(cb)

      buf_inject_stream(channel, 1, "test".to_slice)
      sleep(50.milliseconds)

      ready_count.should eq(1)
      ready_bytes.should eq(4)
      reader.close
    end

    it "removes callback" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)

      call_count = 0
      cb = ->(bytes : Int32) { call_count += 1; nil }
      reader.add_ready_callback(cb)
      reader.remove_ready_callback(cb)

      buf_inject_stream(channel, 1, "test".to_slice)
      sleep(50.milliseconds)

      call_count.should eq(0)
      reader.close
    end

    it "supports multiple callbacks" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)

      count1 = 0
      count2 = 0
      cb1 = ->(bytes : Int32) { count1 += 1; nil }
      cb2 = ->(bytes : Int32) { count2 += 1; nil }
      reader.add_ready_callback(cb1)
      reader.add_ready_callback(cb2)

      buf_inject_stream(channel, 1, "test".to_slice)
      sleep(50.milliseconds)

      count1.should eq(1)
      count2.should eq(1)
      reader.close
    end

    it "callback receives cumulative byte count" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)

      received_bytes = [] of Int32
      cb = ->(bytes : Int32) { received_bytes << bytes; nil }
      reader.add_ready_callback(cb)

      buf_inject_stream(channel, 1, "hello".to_slice, sequence: 0_u16)
      sleep(50.milliseconds)
      buf_inject_stream(channel, 1, " world".to_slice, sequence: 1_u16)
      sleep(50.milliseconds)

      received_bytes.size.should eq(2)
      received_bytes[0].should eq(5)
      received_bytes[1].should eq(11)
      reader.close
    end
  end

  describe "close" do
    it "removes message handler and clears listeners" do
      channel, _outlet = buf_create_channel
      reader = RNS::RawChannelReader.new(1, channel)

      count = 0
      cb = ->(bytes : Int32) { count += 1; nil }
      reader.add_ready_callback(cb)

      reader.close
      reader.closed?.should be_true

      buf_inject_stream(channel, 1, "test".to_slice, sequence: 0_u16)
      sleep(50.milliseconds)
      count.should eq(0)
    end
  end
end

describe "RNS::RawChannelWriter" do
  describe "constants" do
    it "MAX_CHUNK_LEN is 16384" do
      RNS::RawChannelWriter::MAX_CHUNK_LEN.should eq(16384)
    end

    it "COMPRESSION_TRIES is 4" do
      RNS::RawChannelWriter::COMPRESSION_TRIES.should eq(4)
    end
  end

  describe "constructor" do
    it "creates a writer" do
      channel, _outlet = buf_create_channel
      writer = RNS::RawChannelWriter.new(1, channel)
      writer.writable?.should be_true
      writer.readable?.should be_false
      writer.seekable?.should be_false
    end
  end

  describe "write" do
    it "sends data over channel" do
      channel, outlet = buf_create_channel
      writer = RNS::RawChannelWriter.new(1, channel)

      data = "hello".to_slice
      n = writer.write(data)
      n.should be > 0
      outlet.sent_packets.size.should eq(1)
    end

    it "returns bytes consumed" do
      channel, _outlet = buf_create_channel
      writer = RNS::RawChannelWriter.new(1, channel)

      data = "hello world".to_slice
      n = writer.write(data)
      n.should eq(data.size)
    end

    it "caps write at MAX_CHUNK_LEN" do
      channel, outlet = buf_create_channel(mdu: 20000)
      writer = RNS::RawChannelWriter.new(1, channel)

      large_data = Random::Secure.random_bytes(RNS::RawChannelWriter::MAX_CHUNK_LEN + 1000)
      n = writer.write(large_data)
      n.should be <= RNS::RawChannelWriter::MAX_CHUNK_LEN
    end

    it "returns 0 when channel not ready" do
      channel, outlet = buf_create_channel
      outlet._is_usable = false
      writer = RNS::RawChannelWriter.new(1, channel)

      n = writer.write("hello".to_slice)
      n.should eq(0)
    end

    it "sends packet through outlet" do
      channel, outlet = buf_create_channel
      writer = RNS::RawChannelWriter.new(42, channel)

      writer.write("test".to_slice)
      outlet.sent_packets.size.should eq(1)
      outlet.sent_packets[0].raw.size.should be > 6
    end

    it "handles empty write" do
      channel, outlet = buf_create_channel
      writer = RNS::RawChannelWriter.new(1, channel)

      # Empty data (0 bytes) won't trigger compression (chunk_len <= 32)
      # and will send a 0-byte chunk
      n = writer.write(Bytes.new(0))
      n.should eq(0) # empty data sends 0-length chunk
      outlet.sent_packets.size.should eq(1)
    end
  end

  describe "compression" do
    it "compresses compressible data" do
      channel, outlet = buf_create_channel(mdu: 500)
      writer = RNS::RawChannelWriter.new(1, channel)

      # Highly compressible data (300 bytes of 'A')
      data = ("A" * 300).to_slice
      n = writer.write(data)
      n.should be > 0
      outlet.sent_packets.size.should eq(1)
    end

    it "skips compression for small data (<= 32 bytes)" do
      channel, outlet = buf_create_channel
      writer = RNS::RawChannelWriter.new(1, channel)

      data = "short".to_slice
      n = writer.write(data)
      n.should eq(5)
    end

    it "falls back to uncompressed when compression doesn't help" do
      channel, outlet = buf_create_channel(mdu: 500)
      writer = RNS::RawChannelWriter.new(1, channel)

      # Random data doesn't compress well
      data = Random::Secure.random_bytes(100)
      n = writer.write(data)
      n.should be > 0
    end
  end
end

describe "RNS::Buffer" do
  describe ".create_reader" do
    it "creates a RawChannelReader" do
      channel, _outlet = buf_create_channel
      reader = RNS::Buffer.create_reader(1, channel)
      reader.should be_a(RNS::RawChannelReader(BufMockPacket))
      reader.readable?.should be_true
      reader.close
    end

    it "attaches ready callback" do
      channel, _outlet = buf_create_channel
      called = false
      cb = ->(bytes : Int32) { called = true; nil }
      reader = RNS::Buffer.create_reader(1, channel, cb)

      buf_inject_stream(channel, 1, "data".to_slice)
      sleep(50.milliseconds)
      called.should be_true
      reader.close
    end

    it "works without callback" do
      channel, _outlet = buf_create_channel
      reader = RNS::Buffer.create_reader(1, channel)
      buf_inject_stream(channel, 1, "data".to_slice)
      reader.available.should eq(4)
      reader.close
    end
  end

  describe ".create_writer" do
    it "creates a RawChannelWriter" do
      channel, _outlet = buf_create_channel
      writer = RNS::Buffer.create_writer(1, channel)
      writer.should be_a(RNS::RawChannelWriter(BufMockPacket))
      writer.writable?.should be_true
    end
  end

  describe ".create_bidirectional_buffer" do
    it "creates a reader/writer tuple" do
      channel, _outlet = buf_create_channel
      reader, writer = RNS::Buffer.create_bidirectional_buffer(1, 2, channel)
      reader.should be_a(RNS::RawChannelReader(BufMockPacket))
      writer.should be_a(RNS::RawChannelWriter(BufMockPacket))
      reader.close
    end

    it "uses different stream_ids for reader and writer" do
      channel, outlet = buf_create_channel
      reader, writer = RNS::Buffer.create_bidirectional_buffer(10, 20, channel)

      # Writer sends on stream 20
      writer.write("hello".to_slice)
      outlet.sent_packets.size.should eq(1)

      # Reader receives on stream 10 (sequence 0 since rx starts at 0)
      buf_inject_stream(channel, 10, "world".to_slice, sequence: 0_u16)
      reader.available.should eq(5)

      # Reader ignores stream 20
      buf_inject_stream(channel, 20, "other".to_slice, sequence: 1_u16)
      reader.available.should eq(5) # unchanged
      reader.close
    end

    it "attaches ready callback to reader" do
      channel, _outlet = buf_create_channel
      called = false
      cb = ->(bytes : Int32) { called = true; nil }
      reader, _writer = RNS::Buffer.create_bidirectional_buffer(1, 2, channel, cb)

      buf_inject_stream(channel, 1, "data".to_slice)
      sleep(50.milliseconds)
      called.should be_true
      reader.close
    end
  end
end

describe "Buffer integration" do
  it "data sent by writer is received by reader via channel loopback" do
    channel, outlet = buf_create_channel
    reader = RNS::Buffer.create_reader(1, channel)
    writer = RNS::Buffer.create_writer(1, channel)

    writer.write("hello world".to_slice)
    outlet.sent_packets.size.should eq(1)

    # Loopback: feed sent packet raw bytes back through channel._receive
    raw = outlet.sent_packets[0].raw
    channel._receive(raw)

    result = reader.read(20)
    result.should_not be_nil
    result.not_nil!.size.should be > 0
    reader.close
  end

  it "handles multiple sequential writes with delivery simulation" do
    channel, outlet = buf_create_channel
    writer = RNS::Buffer.create_writer(1, channel)

    messages = ["first", "second", "third"]
    messages.each_with_index do |msg, i|
      writer.write(msg.to_slice)

      # Simulate delivery of previous to allow next send
      pkt = outlet.sent_packets[i]
      pkt.state = RNS::MessageState::MSGSTATE_DELIVERED
      if cb = pkt.delivered_callback
        cb.call(pkt)
      end
    end

    outlet.sent_packets.size.should eq(3)
  end

  it "eof message from writer sets eof on reader" do
    channel, outlet = buf_create_channel
    reader = RNS::Buffer.create_reader(1, channel)

    # Manually send an eof-flagged message
    msg = RNS::StreamDataMessage.new(stream_id: 1, data: Bytes.new(0), eof: true)
    channel.send(msg)
    outlet.sent_packets.size.should eq(1)

    # Loopback
    channel._receive(outlet.sent_packets[0].raw)
    reader.eof?.should be_true
    reader.close
  end

  it "eof message contains correct flags when parsed" do
    msg = RNS::StreamDataMessage.new(stream_id: 1, data: Bytes.new(0), eof: true)
    packed = msg.pack

    msg2 = RNS::StreamDataMessage.new
    msg2.unpack(packed)
    msg2.eof.should be_true
    msg2.stream_id.should eq(1)
    msg2.data.size.should eq(0)
  end

  it "stress: 50 write/delivery cycles" do
    channel, outlet = buf_create_channel(mdu: 500)
    writer = RNS::Buffer.create_writer(1, channel)

    50.times do |i|
      data = Random::Secure.random_bytes(Random.rand(1..100))
      n = writer.write(data)
      n.should be > 0

      pkt = outlet.sent_packets.last
      pkt.state = RNS::MessageState::MSGSTATE_DELIVERED
      if cb = pkt.delivered_callback
        cb.call(pkt)
      end
    end

    outlet.sent_packets.size.should eq(50)
  end

  it "stress: 20 bidirectional buffer creation" do
    20.times do |i|
      channel, _outlet = buf_create_channel
      reader, writer = RNS::Buffer.create_bidirectional_buffer(i, i + 100, channel)
      reader.should be_a(RNS::RawChannelReader(BufMockPacket))
      writer.should be_a(RNS::RawChannelWriter(BufMockPacket))
      reader.close
    end
  end

  it "stress: 30 random read/write roundtrips via loopback" do
    channel, outlet = buf_create_channel(mdu: 500)
    reader = RNS::Buffer.create_reader(1, channel)
    writer = RNS::Buffer.create_writer(1, channel)

    30.times do |i|
      data = Random::Secure.random_bytes(Random.rand(1..50))
      writer.write(data)

      # Simulate delivery for next write
      pkt = outlet.sent_packets.last
      pkt.state = RNS::MessageState::MSGSTATE_DELIVERED
      if cb = pkt.delivered_callback
        cb.call(pkt)
      end

      # Loopback through channel
      channel._receive(outlet.sent_packets.last.raw)
    end

    # Reader should have accumulated data
    reader.available.should be > 0
    reader.close
  end
end
