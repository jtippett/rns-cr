require "../../spec_helper"

describe RNS::PipeInterface do
  describe "constants" do
    it "has correct MAX_CHUNK" do
      RNS::PipeInterface::MAX_CHUNK.should eq(32768)
    end

    it "has correct BITRATE_GUESS" do
      RNS::PipeInterface::BITRATE_GUESS.should eq(1_000_000_i64)
    end

    it "has correct DEFAULT_IFAC_SIZE" do
      RNS::PipeInterface::DEFAULT_IFAC_SIZE.should eq(8)
    end
  end

  describe "constructor with explicit parameters (no spawn)" do
    it "creates interface with default settings" do
      pi = RNS::PipeInterface.new(
        name: "TestPipe",
        command: "cat",
        spawn_process: false
      )
      pi.name.should eq("TestPipe")
      pi.command.should eq("cat")
      pi.respawn_delay.should eq(5.0)
      pi.bitrate.should eq(1_000_000_i64)
      pi.hw_mtu.should eq(1064)
      pi.online.should be_false
      pi.pipe_is_open?.should be_false
    end

    it "creates interface with custom respawn_delay" do
      pi = RNS::PipeInterface.new(
        name: "CustomPipe",
        command: "echo hello",
        respawn_delay: 10.0,
        spawn_process: false
      )
      pi.name.should eq("CustomPipe")
      pi.command.should eq("echo hello")
      pi.respawn_delay.should eq(10.0)
    end
  end

  describe "configuration parsing" do
    it "raises when no command specified" do
      config = {"name" => "NoCmdPipe"}
      expect_raises(ArgumentError, "No command specified") do
        RNS::PipeInterface.new(config)
      end
    end

    it "uses default respawn_delay when not specified" do
      pi = RNS::PipeInterface.new(
        name: "Test",
        command: "cat",
        spawn_process: false
      )
      pi.respawn_delay.should eq(5.0)
    end
  end

  describe "inheritance" do
    it "inherits from Interface" do
      pi = RNS::PipeInterface.new(
        name: "Test",
        command: "cat",
        spawn_process: false
      )
      pi.is_a?(RNS::Interface).should be_true
    end

    it "has Interface properties" do
      pi = RNS::PipeInterface.new(
        name: "Test",
        command: "cat",
        spawn_process: false
      )
      pi.rxb.should eq(0_i64)
      pi.txb.should eq(0_i64)
      pi.detached?.should be_false
    end
  end

  describe "#process_incoming" do
    it "increments rxb counter" do
      pi = RNS::PipeInterface.new(
        name: "Test",
        command: "cat",
        spawn_process: false
      )
      data = Bytes[0x01, 0x02, 0x03, 0x04, 0x05]
      pi.process_incoming(data)
      pi.rxb.should eq(5_i64)
    end

    it "calls inbound callback" do
      received = nil
      callback = Proc(Bytes, RNS::Interface, Nil).new do |data, _|
        received = data
      end
      pi = RNS::PipeInterface.new(
        name: "Test",
        command: "cat",
        spawn_process: false,
        inbound_callback: callback
      )
      test_data = Bytes[0xAA, 0xBB, 0xCC]
      pi.process_incoming(test_data)
      received.should eq(test_data)
    end

    it "accumulates rxb across multiple calls" do
      pi = RNS::PipeInterface.new(
        name: "Test",
        command: "cat",
        spawn_process: false
      )
      pi.process_incoming(Bytes[0x01, 0x02])
      pi.process_incoming(Bytes[0x03, 0x04, 0x05])
      pi.rxb.should eq(5_i64)
    end
  end

  describe "#process_outgoing" do
    it "does nothing when offline" do
      pi = RNS::PipeInterface.new(
        name: "Test",
        command: "cat",
        spawn_process: false
      )
      pi.online = false
      pi.process_outgoing(Bytes[0x01, 0x02, 0x03])
      pi.txb.should eq(0_i64)
    end
  end

  describe "#teardown" do
    it "sets online to false and stops running" do
      pi = RNS::PipeInterface.new(
        name: "Test",
        command: "cat",
        spawn_process: false
      )
      pi.online = true
      pi.teardown
      pi.online.should be_false
    end
  end

  describe "#detach" do
    it "marks interface as detached and tears down" do
      pi = RNS::PipeInterface.new(
        name: "Test",
        command: "cat",
        spawn_process: false
      )
      pi.online = true
      pi.detach
      pi.detached?.should be_true
      pi.online.should be_false
    end
  end

  describe "#to_s" do
    it "formats as PipeInterface[name]" do
      pi = RNS::PipeInterface.new(
        name: "MyPipe",
        command: "cat",
        spawn_process: false
      )
      pi.to_s.should eq("PipeInterface[MyPipe]")
    end
  end

  describe "get_hash" do
    it "returns a consistent hash for the same interface name" do
      pi1 = RNS::PipeInterface.new(
        name: "TestPipe", command: "cat", spawn_process: false
      )
      pi2 = RNS::PipeInterface.new(
        name: "TestPipe", command: "cat", spawn_process: false
      )
      pi1.get_hash.should eq(pi2.get_hash)
    end

    it "returns different hashes for different interface names" do
      pi1 = RNS::PipeInterface.new(
        name: "Pipe1", command: "cat", spawn_process: false
      )
      pi2 = RNS::PipeInterface.new(
        name: "Pipe2", command: "cat", spawn_process: false
      )
      pi1.get_hash.should_not eq(pi2.get_hash)
    end
  end

  describe "HW_MTU" do
    it "defaults to 1064" do
      pi = RNS::PipeInterface.new(
        name: "Test", command: "cat", spawn_process: false
      )
      pi.hw_mtu.should eq(1064)
    end
  end

  describe "HDLC framing for pipe communication" do
    it "frames data with HDLC FLAG bytes" do
      data = Bytes[0x01, 0x02, 0x03]
      framed = RNS::HDLC.frame(data)
      framed[0].should eq(RNS::HDLC::FLAG)
      framed[-1].should eq(RNS::HDLC::FLAG)
    end

    it "escapes FLAG bytes in data" do
      data = Bytes[RNS::HDLC::FLAG]
      framed = RNS::HDLC.frame(data)
      framed.size.should eq(4)
      framed[1].should eq(RNS::HDLC::ESC)
      framed[2].should eq(RNS::HDLC::FLAG ^ RNS::HDLC::ESC_MASK)
    end

    it "escapes ESC bytes in data" do
      data = Bytes[RNS::HDLC::ESC]
      framed = RNS::HDLC.frame(data)
      framed.size.should eq(4)
      framed[1].should eq(RNS::HDLC::ESC)
      framed[2].should eq(RNS::HDLC::ESC ^ RNS::HDLC::ESC_MASK)
    end

    it "roundtrips arbitrary data through HDLC frame/unescape" do
      100.times do
        data = Random::Secure.random_bytes(rand(1..500))
        framed = RNS::HDLC.frame(data)
        inner = framed[1...-1]
        unescaped = RNS::HDLC.unescape(inner)
        unescaped.should eq(data)
      end
    end
  end

  describe "subprocess pipe communication" do
    it "sends and receives data via cat subprocess" do
      received_packets = [] of Bytes
      done = Channel(Nil).new(1)

      callback = Proc(Bytes, RNS::Interface, Nil).new do |data, _|
        received_packets << data.dup
        done.send(nil) if received_packets.size >= 1
      end

      pi = RNS::PipeInterface.new(
        name: "CatPipe",
        command: "cat",
        spawn_process: true,
        inbound_callback: callback
      )

      pi.online.should be_true
      pi.pipe_is_open?.should be_true

      # Send data — cat echoes it back with HDLC framing
      test_data = Bytes[0x01, 0x02, 0x03, 0x04, 0x05]
      pi.process_outgoing(test_data)

      # Wait for the echo to come back
      select
      when done.receive
        # Got it
      when timeout(3.seconds)
        fail "Timed out waiting for pipe echo"
      end

      received_packets.size.should eq(1)
      received_packets[0].should eq(test_data)
      pi.txb.should be > 0
      pi.rxb.should be > 0
    ensure
      pi.try(&.teardown)
    end

    it "sends and receives multiple packets via cat subprocess" do
      received_packets = [] of Bytes
      done = Channel(Nil).new(1)
      expected_count = 3

      callback = Proc(Bytes, RNS::Interface, Nil).new do |data, _|
        received_packets << data.dup
        done.send(nil) if received_packets.size >= expected_count
      end

      pi = RNS::PipeInterface.new(
        name: "MultiPipe",
        command: "cat",
        spawn_process: true,
        inbound_callback: callback
      )

      packets = [
        Bytes[0x01, 0x02, 0x03],
        Bytes[0xAA, 0xBB, 0xCC, 0xDD],
        Bytes[0xFF, 0xFE, 0xFD],
      ]

      packets.each do |pkt|
        pi.process_outgoing(pkt)
      end

      select
      when done.receive
        # Got all packets
      when timeout(3.seconds)
        fail "Timed out waiting for pipe echo (got #{received_packets.size}/#{expected_count})"
      end

      received_packets.size.should eq(expected_count)
      packets.each_with_index do |pkt, i|
        received_packets[i].should eq(pkt)
      end
    ensure
      pi.try(&.teardown)
    end

    it "handles data containing HDLC special bytes" do
      received_packets = [] of Bytes
      done = Channel(Nil).new(1)

      callback = Proc(Bytes, RNS::Interface, Nil).new do |data, _|
        received_packets << data.dup
        done.send(nil)
      end

      pi = RNS::PipeInterface.new(
        name: "SpecialPipe",
        command: "cat",
        spawn_process: true,
        inbound_callback: callback
      )

      # Data containing FLAG and ESC bytes
      test_data = Bytes[0x01, RNS::HDLC::FLAG, 0x02, RNS::HDLC::ESC, 0x03]
      pi.process_outgoing(test_data)

      select
      when done.receive
        # Got it
      when timeout(3.seconds)
        fail "Timed out waiting for pipe echo"
      end

      received_packets.size.should eq(1)
      received_packets[0].should eq(test_data)
    ensure
      pi.try(&.teardown)
    end

    it "handles process termination gracefully" do
      pi = RNS::PipeInterface.new(
        name: "ShortLived",
        command: "echo done",
        spawn_process: true,
        inbound_callback: nil
      )

      pi.pipe_is_open?.should be_true
      # The echo process terminates quickly — wait for it
      sleep 0.5.seconds
      pi.teardown
      pi.online.should be_false
    end

    it "sends random data through cat and receives it back correctly" do
      received_packets = [] of Bytes
      done = Channel(Nil).new(1)
      count = 10

      callback = Proc(Bytes, RNS::Interface, Nil).new do |data, _|
        received_packets << data.dup
        done.send(nil) if received_packets.size >= count
      end

      pi = RNS::PipeInterface.new(
        name: "RandomPipe",
        command: "cat",
        spawn_process: true,
        inbound_callback: callback
      )

      packets = Array.new(count) { Random::Secure.random_bytes(rand(1..200)) }
      packets.each do |pkt|
        pi.process_outgoing(pkt)
      end

      select
      when done.receive
        # Done
      when timeout(5.seconds)
        fail "Timed out waiting for pipe echo (got #{received_packets.size}/#{count})"
      end

      received_packets.size.should eq(count)
      packets.each_with_index do |pkt, i|
        received_packets[i].should eq(pkt)
      end
    ensure
      pi.try(&.teardown)
    end
  end

  describe "HDLC read loop simulation (state machine)" do
    it "parses a single HDLC frame correctly" do
      received_packets = [] of Bytes
      data = Bytes[0x01, 0x02, 0x03]
      stream = RNS::HDLC.frame(data)

      in_frame = false
      escape = false
      data_buffer = IO::Memory.new(1024)
      hw_mtu = 1064

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

      stream_io = IO::Memory.new
      packets.each { |pkt| stream_io.write(RNS::HDLC.frame(pkt)) }
      stream = stream_io.to_slice

      in_frame = false
      escape = false
      data_buffer = IO::Memory.new(1024)
      hw_mtu = 1064

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

    it "discards data exceeding HW_MTU of 1064" do
      received_packets = [] of Bytes
      hw_mtu = 1064

      big_data = Random::Secure.random_bytes(1200)
      stream = RNS::HDLC.frame(big_data)

      in_frame = false
      escape = false
      data_buffer = IO::Memory.new(2048)

      stream.each do |byte|
        if in_frame && byte == RNS::HDLC::FLAG
          in_frame = false
          if data_buffer.pos > 0
            received_packets << data_buffer.to_slice.dup
          end
        elsif byte == RNS::HDLC::FLAG
          in_frame = true
          data_buffer = IO::Memory.new(2048)
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
      received_packets[0].size.should be <= hw_mtu
    end

    it "handles empty frames" do
      received_packets = [] of Bytes
      stream = Bytes[RNS::HDLC::FLAG, RNS::HDLC::FLAG]

      in_frame = false
      escape = false
      data_buffer = IO::Memory.new(1024)
      hw_mtu = 1064

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

      received_packets.size.should eq(0)
    end

    it "roundtrips 500 random packets through HDLC state machine" do
      packets = Array.new(500) { Random::Secure.random_bytes(rand(1..300)) }

      stream_io = IO::Memory.new
      packets.each { |pkt| stream_io.write(RNS::HDLC.frame(pkt)) }
      stream = stream_io.to_slice

      received = [] of Bytes
      in_frame = false
      escape = false
      data_buffer = IO::Memory.new(2048)
      hw_mtu = 1064

      stream.each do |byte|
        if in_frame && byte == RNS::HDLC::FLAG
          in_frame = false
          if data_buffer.pos > 0
            received << data_buffer.to_slice.dup
          end
        elsif byte == RNS::HDLC::FLAG
          in_frame = true
          data_buffer = IO::Memory.new(2048)
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

      received.size.should eq(500)
      packets.each_with_index do |pkt, i|
        received[i].should eq(pkt)
      end
    end
  end
end
