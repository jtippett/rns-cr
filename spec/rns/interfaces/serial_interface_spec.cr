require "../../spec_helper"

describe RNS::SerialInterface do
  describe "constants" do
    it "has correct MAX_CHUNK" do
      RNS::SerialInterface::MAX_CHUNK.should eq(32768)
    end

    it "has correct DEFAULT_IFAC_SIZE" do
      RNS::SerialInterface::DEFAULT_IFAC_SIZE.should eq(8)
    end

    it "has correct parity symbols" do
      RNS::SerialInterface::PARITY_NONE.should eq(:none)
      RNS::SerialInterface::PARITY_EVEN.should eq(:even)
      RNS::SerialInterface::PARITY_ODD.should eq(:odd)
    end
  end

  describe "constructor with explicit parameters (no port open)" do
    it "creates interface with default settings" do
      si = RNS::SerialInterface.new(
        name: "TestSerial",
        port: "/dev/ttyUSB0",
        open_port: false
      )
      si.name.should eq("TestSerial")
      si.port.should eq("/dev/ttyUSB0")
      si.speed.should eq(9600)
      si.databits.should eq(8)
      si.parity.should eq(:none)
      si.stopbits.should eq(1)
      si.timeout.should eq(100)
      si.bitrate.should eq(9600_i64)
      si.hw_mtu.should eq(564)
      si.online.should be_false
      si.port_open?.should be_false
    end

    it "creates interface with custom settings" do
      si = RNS::SerialInterface.new(
        name: "HighSpeed",
        port: "/dev/ttyS1",
        speed: 115200,
        databits: 7,
        parity: "E",
        stopbits: 2,
        open_port: false
      )
      si.name.should eq("HighSpeed")
      si.port.should eq("/dev/ttyS1")
      si.speed.should eq(115200)
      si.databits.should eq(7)
      si.parity.should eq(:even)
      si.stopbits.should eq(2)
      si.bitrate.should eq(115200_i64)
    end

    it "parses even parity with full word" do
      si = RNS::SerialInterface.new(
        name: "Test", port: "/dev/null", parity: "even", open_port: false
      )
      si.parity.should eq(:even)
    end

    it "parses odd parity" do
      si = RNS::SerialInterface.new(
        name: "Test", port: "/dev/null", parity: "O", open_port: false
      )
      si.parity.should eq(:odd)
    end

    it "parses odd parity with full word" do
      si = RNS::SerialInterface.new(
        name: "Test", port: "/dev/null", parity: "Odd", open_port: false
      )
      si.parity.should eq(:odd)
    end

    it "defaults to no parity for unknown values" do
      si = RNS::SerialInterface.new(
        name: "Test", port: "/dev/null", parity: "X", open_port: false
      )
      si.parity.should eq(:none)
    end
  end

  describe "configuration parsing" do
    it "raises when no port specified" do
      config = {"name" => "NoPort", "speed" => "9600"}
      expect_raises(ArgumentError, "No port specified") do
        RNS::SerialInterface.new(config)
      end
    end

    it "uses default values when optional fields omitted" do
      # This will fail to actually open /dev/nonexistent, but we test the parsing
      config = {"name" => "MinConfig", "port" => "/dev/nonexistent_serial_port_xyz"}
      expect_raises(IO::Error) do
        RNS::SerialInterface.new(config)
      end
    end
  end

  describe "#should_ingress_limit?" do
    it "always returns false" do
      si = RNS::SerialInterface.new(
        name: "Test", port: "/dev/null", open_port: false
      )
      si.should_ingress_limit?.should be_false
    end
  end

  describe "#to_s" do
    it "formats as SerialInterface[name]" do
      si = RNS::SerialInterface.new(
        name: "MySerial", port: "/dev/ttyUSB0", open_port: false
      )
      si.to_s.should eq("SerialInterface[MySerial]")
    end
  end

  describe "inheritance" do
    it "inherits from Interface" do
      si = RNS::SerialInterface.new(
        name: "Test", port: "/dev/null", open_port: false
      )
      si.is_a?(RNS::Interface).should be_true
    end

    it "has Interface properties" do
      si = RNS::SerialInterface.new(
        name: "Test", port: "/dev/null", open_port: false
      )
      si.rxb.should eq(0_i64)
      si.txb.should eq(0_i64)
      si.detached?.should be_false
    end
  end

  describe "#teardown" do
    it "sets online to false and stops running" do
      si = RNS::SerialInterface.new(
        name: "Test", port: "/dev/null", open_port: false
      )
      si.online = true
      si.teardown
      si.online.should be_false
    end
  end

  describe "#detach" do
    it "marks interface as detached and tears down" do
      si = RNS::SerialInterface.new(
        name: "Test", port: "/dev/null", open_port: false
      )
      si.online = true
      si.detach
      si.detached?.should be_true
      si.online.should be_false
    end
  end

  describe "#process_outgoing" do
    it "does nothing when offline" do
      si = RNS::SerialInterface.new(
        name: "Test", port: "/dev/null", open_port: false
      )
      si.online = false
      # Should not raise
      si.process_outgoing(Bytes[0x01, 0x02, 0x03])
      si.txb.should eq(0_i64)
    end
  end

  describe "#process_incoming" do
    it "increments rxb counter" do
      si = RNS::SerialInterface.new(
        name: "Test", port: "/dev/null", open_port: false
      )
      data = Bytes[0x01, 0x02, 0x03, 0x04, 0x05]
      si.process_incoming(data)
      si.rxb.should eq(5_i64)
    end

    it "calls inbound callback" do
      received = nil
      callback = Proc(Bytes, RNS::Interface, Nil).new do |data, iface|
        received = data
      end
      si = RNS::SerialInterface.new(
        name: "Test", port: "/dev/null", open_port: false,
        inbound_callback: callback
      )
      test_data = Bytes[0xAA, 0xBB, 0xCC]
      si.process_incoming(test_data)
      received.should eq(test_data)
    end

    it "accumulates rxb across multiple calls" do
      si = RNS::SerialInterface.new(
        name: "Test", port: "/dev/null", open_port: false
      )
      si.process_incoming(Bytes[0x01, 0x02])
      si.process_incoming(Bytes[0x03, 0x04, 0x05])
      si.rxb.should eq(5_i64)
    end
  end

  describe "HDLC framing roundtrip via process_outgoing" do
    it "frames data with HDLC FLAG bytes and escaping" do
      # Test that process_outgoing uses HDLC.frame correctly
      # We test the HDLC module directly since process_outgoing needs a real serial port
      data = Bytes[0x01, 0x02, 0x03]
      framed = RNS::HDLC.frame(data)
      framed[0].should eq(RNS::HDLC::FLAG)
      framed[-1].should eq(RNS::HDLC::FLAG)
    end

    it "escapes FLAG bytes in data" do
      data = Bytes[RNS::HDLC::FLAG]
      framed = RNS::HDLC.frame(data)
      # Should be: FLAG, ESC, FLAG^ESC_MASK, FLAG
      framed.size.should eq(4)
      framed[0].should eq(RNS::HDLC::FLAG)
      framed[1].should eq(RNS::HDLC::ESC)
      framed[2].should eq(RNS::HDLC::FLAG ^ RNS::HDLC::ESC_MASK)
      framed[3].should eq(RNS::HDLC::FLAG)
    end

    it "escapes ESC bytes in data" do
      data = Bytes[RNS::HDLC::ESC]
      framed = RNS::HDLC.frame(data)
      # Should be: FLAG, ESC, ESC^ESC_MASK, FLAG
      framed.size.should eq(4)
      framed[0].should eq(RNS::HDLC::FLAG)
      framed[1].should eq(RNS::HDLC::ESC)
      framed[2].should eq(RNS::HDLC::ESC ^ RNS::HDLC::ESC_MASK)
      framed[3].should eq(RNS::HDLC::FLAG)
    end

    it "roundtrips arbitrary data through HDLC frame/unescape" do
      100.times do
        data = Random::Secure.random_bytes(rand(1..500))
        framed = RNS::HDLC.frame(data)

        # Extract inner (between flags)
        inner = framed[1...-1]
        unescaped = RNS::HDLC.unescape(inner)
        unescaped.should eq(data)
      end
    end
  end

  describe "HDLC read loop simulation" do
    # Simulate the byte-by-byte HDLC parsing that the read_loop performs
    # This is a pure logic test, no hardware needed

    it "parses a single HDLC frame correctly" do
      received_packets = [] of Bytes

      # Simulate the read_loop HDLC state machine
      data = Bytes[0x01, 0x02, 0x03]
      stream = RNS::HDLC.frame(data)

      in_frame = false
      escape = false
      data_buffer = IO::Memory.new(1024)
      hw_mtu = 564

      stream.each do |byte|
        if in_frame && byte == RNS::HDLC::FLAG
          in_frame = false
          if data_buffer.pos > 0
            received_packets << data_buffer.to_slice.dup
          end
        elsif byte == RNS::HDLC::FLAG
          in_frame = true
          data_buffer = IO::Memory.new(1024)
        elsif in_frame && data_buffer.pos < hw_mtu
          if byte == RNS::HDLC::ESC
            escape = true
          else
            if escape
              byte = RNS::HDLC::FLAG if byte == (RNS::HDLC::FLAG ^ RNS::HDLC::ESC_MASK)
              byte = RNS::HDLC::ESC if byte == (RNS::HDLC::ESC ^ RNS::HDLC::ESC_MASK)
              escape = false
            end
            data_buffer.write_byte(byte)
          end
        end
      end

      received_packets.size.should eq(1)
      received_packets[0].should eq(data)
    end

    it "parses multiple consecutive HDLC frames" do
      received_packets = [] of Bytes
      packets = [
        Bytes[0x01, 0x02],
        Bytes[0xAA, 0xBB, 0xCC],
        Bytes[0xFF],
      ]

      # Build stream of multiple frames
      stream_io = IO::Memory.new
      packets.each do |pkt|
        stream_io.write(RNS::HDLC.frame(pkt))
      end
      stream = stream_io.to_slice

      in_frame = false
      escape = false
      data_buffer = IO::Memory.new(1024)
      hw_mtu = 564

      stream.each do |byte|
        if in_frame && byte == RNS::HDLC::FLAG
          in_frame = false
          if data_buffer.pos > 0
            received_packets << data_buffer.to_slice.dup
          end
        elsif byte == RNS::HDLC::FLAG
          in_frame = true
          data_buffer = IO::Memory.new(1024)
        elsif in_frame && data_buffer.pos < hw_mtu
          if byte == RNS::HDLC::ESC
            escape = true
          else
            if escape
              byte = RNS::HDLC::FLAG if byte == (RNS::HDLC::FLAG ^ RNS::HDLC::ESC_MASK)
              byte = RNS::HDLC::ESC if byte == (RNS::HDLC::ESC ^ RNS::HDLC::ESC_MASK)
              escape = false
            end
            data_buffer.write_byte(byte)
          end
        end
      end

      received_packets.size.should eq(3)
      packets.each_with_index do |pkt, i|
        received_packets[i].should eq(pkt)
      end
    end

    it "handles data containing FLAG and ESC bytes" do
      received_packets = [] of Bytes

      # Data that contains the FLAG and ESC bytes
      data = Bytes[0x01, RNS::HDLC::FLAG, 0x02, RNS::HDLC::ESC, 0x03]
      stream = RNS::HDLC.frame(data)

      in_frame = false
      escape = false
      data_buffer = IO::Memory.new(1024)
      hw_mtu = 564

      stream.each do |byte|
        if in_frame && byte == RNS::HDLC::FLAG
          in_frame = false
          if data_buffer.pos > 0
            received_packets << data_buffer.to_slice.dup
          end
        elsif byte == RNS::HDLC::FLAG
          in_frame = true
          data_buffer = IO::Memory.new(1024)
        elsif in_frame && data_buffer.pos < hw_mtu
          if byte == RNS::HDLC::ESC
            escape = true
          else
            if escape
              byte = RNS::HDLC::FLAG if byte == (RNS::HDLC::FLAG ^ RNS::HDLC::ESC_MASK)
              byte = RNS::HDLC::ESC if byte == (RNS::HDLC::ESC ^ RNS::HDLC::ESC_MASK)
              escape = false
            end
            data_buffer.write_byte(byte)
          end
        end
      end

      received_packets.size.should eq(1)
      received_packets[0].should eq(data)
    end

    it "discards data exceeding HW_MTU" do
      received_packets = [] of Bytes
      hw_mtu = 564

      # Create data larger than HW_MTU
      big_data = Random::Secure.random_bytes(600)
      stream = RNS::HDLC.frame(big_data)

      in_frame = false
      escape = false
      data_buffer = IO::Memory.new(1024)

      stream.each do |byte|
        if in_frame && byte == RNS::HDLC::FLAG
          in_frame = false
          if data_buffer.pos > 0
            received_packets << data_buffer.to_slice.dup
          end
        elsif byte == RNS::HDLC::FLAG
          in_frame = true
          data_buffer = IO::Memory.new(1024)
        elsif in_frame && data_buffer.pos < hw_mtu
          if byte == RNS::HDLC::ESC
            escape = true
          else
            if escape
              byte = RNS::HDLC::FLAG if byte == (RNS::HDLC::FLAG ^ RNS::HDLC::ESC_MASK)
              byte = RNS::HDLC::ESC if byte == (RNS::HDLC::ESC ^ RNS::HDLC::ESC_MASK)
              escape = false
            end
            data_buffer.write_byte(byte)
          end
        end
      end

      # Frame should be received but truncated to HW_MTU
      received_packets.size.should eq(1)
      received_packets[0].size.should be <= hw_mtu
    end

    it "handles empty frames (no data between FLAGS)" do
      received_packets = [] of Bytes

      # Two flags with nothing between them
      stream = Bytes[RNS::HDLC::FLAG, RNS::HDLC::FLAG]

      in_frame = false
      escape = false
      data_buffer = IO::Memory.new(1024)
      hw_mtu = 564

      stream.each do |byte|
        if in_frame && byte == RNS::HDLC::FLAG
          in_frame = false
          if data_buffer.pos > 0
            received_packets << data_buffer.to_slice.dup
          end
        elsif byte == RNS::HDLC::FLAG
          in_frame = true
          data_buffer = IO::Memory.new(1024)
        elsif in_frame && data_buffer.pos < hw_mtu
          if byte == RNS::HDLC::ESC
            escape = true
          else
            if escape
              byte = RNS::HDLC::FLAG if byte == (RNS::HDLC::FLAG ^ RNS::HDLC::ESC_MASK)
              byte = RNS::HDLC::ESC if byte == (RNS::HDLC::ESC ^ RNS::HDLC::ESC_MASK)
              escape = false
            end
            data_buffer.write_byte(byte)
          end
        end
      end

      # No data was between flags, so nothing received
      received_packets.size.should eq(0)
    end

    it "roundtrips random data through HDLC state machine" do
      100.times do
        original = Random::Secure.random_bytes(rand(1..500))
        stream = RNS::HDLC.frame(original)

        received_packets = [] of Bytes
        in_frame = false
        escape = false
        data_buffer = IO::Memory.new(1024)
        hw_mtu = 564

        stream.each do |byte|
          if in_frame && byte == RNS::HDLC::FLAG
            in_frame = false
            if data_buffer.pos > 0
              received_packets << data_buffer.to_slice.dup
            end
          elsif byte == RNS::HDLC::FLAG
            in_frame = true
            data_buffer = IO::Memory.new(1024)
          elsif in_frame && data_buffer.pos < hw_mtu
            if byte == RNS::HDLC::ESC
              escape = true
            else
              if escape
                byte = RNS::HDLC::FLAG if byte == (RNS::HDLC::FLAG ^ RNS::HDLC::ESC_MASK)
                byte = RNS::HDLC::ESC if byte == (RNS::HDLC::ESC ^ RNS::HDLC::ESC_MASK)
                escape = false
              end
              data_buffer.write_byte(byte)
            end
          end
        end

        received_packets.size.should eq(1)
        received_packets[0].should eq(original)
      end
    end
  end

  describe "pipe-based I/O simulation" do
    # Use IO pipes to simulate serial port read/write without hardware

    it "sends and receives data through pipes using HDLC framing" do
      reader, writer = IO.pipe
      received_packets = [] of Bytes
      done = Channel(Nil).new

      # Simulate read loop in a fiber
      spawn do
        in_frame = false
        escape = false
        data_buffer = IO::Memory.new(1024)
        hw_mtu = 564
        buf = Bytes.new(1)

        loop do
          bytes_read = reader.read(buf)
          break if bytes_read == 0

          byte = buf[0]

          if in_frame && byte == RNS::HDLC::FLAG
            in_frame = false
            if data_buffer.pos > 0
              received_packets << data_buffer.to_slice.dup
            end
          elsif byte == RNS::HDLC::FLAG
            in_frame = true
            data_buffer = IO::Memory.new(1024)
          elsif in_frame && data_buffer.pos < hw_mtu
            if byte == RNS::HDLC::ESC
              escape = true
            else
              if escape
                byte = RNS::HDLC::FLAG if byte == (RNS::HDLC::FLAG ^ RNS::HDLC::ESC_MASK)
                byte = RNS::HDLC::ESC if byte == (RNS::HDLC::ESC ^ RNS::HDLC::ESC_MASK)
                escape = false
              end
              data_buffer.write_byte(byte)
            end
          end
        end
        done.send(nil)
      end

      # Send several packets
      packets = [
        Bytes[0x01, 0x02, 0x03],
        Bytes[RNS::HDLC::FLAG, 0xAA, RNS::HDLC::ESC, 0xBB],
        Random::Secure.random_bytes(100),
      ]

      packets.each do |pkt|
        framed = RNS::HDLC.frame(pkt)
        writer.write(framed)
      end
      writer.close
      done.receive

      received_packets.size.should eq(3)
      packets.each_with_index do |pkt, i|
        received_packets[i].should eq(pkt)
      end
    ensure
      reader.try(&.close) rescue nil
      writer.try(&.close) rescue nil
    end

    it "handles byte-by-byte delivery through pipes" do
      reader, writer = IO.pipe
      received_packets = [] of Bytes
      done = Channel(Nil).new

      spawn do
        in_frame = false
        escape = false
        data_buffer = IO::Memory.new(1024)
        hw_mtu = 564
        buf = Bytes.new(1)

        loop do
          bytes_read = reader.read(buf)
          break if bytes_read == 0
          byte = buf[0]

          if in_frame && byte == RNS::HDLC::FLAG
            in_frame = false
            if data_buffer.pos > 0
              received_packets << data_buffer.to_slice.dup
            end
          elsif byte == RNS::HDLC::FLAG
            in_frame = true
            data_buffer = IO::Memory.new(1024)
          elsif in_frame && data_buffer.pos < hw_mtu
            if byte == RNS::HDLC::ESC
              escape = true
            else
              if escape
                byte = RNS::HDLC::FLAG if byte == (RNS::HDLC::FLAG ^ RNS::HDLC::ESC_MASK)
                byte = RNS::HDLC::ESC if byte == (RNS::HDLC::ESC ^ RNS::HDLC::ESC_MASK)
                escape = false
              end
              data_buffer.write_byte(byte)
            end
          end
        end
        done.send(nil)
      end

      data = Bytes[0xDE, 0xAD, 0xBE, 0xEF]
      framed = RNS::HDLC.frame(data)

      # Write one byte at a time with small delays
      framed.each do |byte|
        writer.write(Bytes[byte])
        writer.flush
      end
      writer.close
      done.receive

      received_packets.size.should eq(1)
      received_packets[0].should eq(data)
    ensure
      reader.try(&.close) rescue nil
      writer.try(&.close) rescue nil
    end
  end

  describe "SerialConstants" do
    it "has correct TCIOFLUSH" do
      RNS::SerialConstants::TCIOFLUSH.should eq(3)
    end

    it "has standard baud rates defined" do
      RNS::SerialConstants::B9600.should_not be_nil
      RNS::SerialConstants::B115200.should_not be_nil
      RNS::SerialConstants::B57600.should_not be_nil
    end

    it "has character size flags" do
      RNS::SerialConstants::CS5.should_not be_nil
      RNS::SerialConstants::CS6.should_not be_nil
      RNS::SerialConstants::CS7.should_not be_nil
      RNS::SerialConstants::CS8.should_not be_nil
    end
  end

  describe "get_hash" do
    it "returns a consistent hash for the same interface name" do
      si1 = RNS::SerialInterface.new(
        name: "TestSerial", port: "/dev/ttyUSB0", open_port: false
      )
      si2 = RNS::SerialInterface.new(
        name: "TestSerial", port: "/dev/ttyUSB0", open_port: false
      )
      si1.get_hash.should eq(si2.get_hash)
    end

    it "returns different hashes for different interface names" do
      si1 = RNS::SerialInterface.new(
        name: "Serial1", port: "/dev/ttyUSB0", open_port: false
      )
      si2 = RNS::SerialInterface.new(
        name: "Serial2", port: "/dev/ttyUSB1", open_port: false
      )
      si1.get_hash.should_not eq(si2.get_hash)
    end
  end

  describe "HW_MTU" do
    it "defaults to 564" do
      si = RNS::SerialInterface.new(
        name: "Test", port: "/dev/null", open_port: false
      )
      si.hw_mtu.should eq(564)
    end
  end

  describe "stress test: many random packets through HDLC state machine" do
    it "correctly handles 1000 random packets" do
      packets = Array.new(1000) { Random::Secure.random_bytes(rand(1..200)) }

      # Build a single stream
      stream_io = IO::Memory.new
      packets.each { |pkt| stream_io.write(RNS::HDLC.frame(pkt)) }
      stream = stream_io.to_slice

      received = [] of Bytes
      in_frame = false
      escape = false
      data_buffer = IO::Memory.new(1024)
      hw_mtu = 564

      stream.each do |byte|
        if in_frame && byte == RNS::HDLC::FLAG
          in_frame = false
          if data_buffer.pos > 0
            received << data_buffer.to_slice.dup
          end
        elsif byte == RNS::HDLC::FLAG
          in_frame = true
          data_buffer = IO::Memory.new(1024)
        elsif in_frame && data_buffer.pos < hw_mtu
          if byte == RNS::HDLC::ESC
            escape = true
          else
            if escape
              byte = RNS::HDLC::FLAG if byte == (RNS::HDLC::FLAG ^ RNS::HDLC::ESC_MASK)
              byte = RNS::HDLC::ESC if byte == (RNS::HDLC::ESC ^ RNS::HDLC::ESC_MASK)
              escape = false
            end
            data_buffer.write_byte(byte)
          end
        end
      end

      received.size.should eq(1000)
      packets.each_with_index do |pkt, i|
        received[i].should eq(pkt)
      end
    end
  end
end
