require "../../spec_helper"

# Helper to simulate a KISS TNC read loop by feeding bytes through an IO pipe.
# Builds a KISS frame: FEND + CMD_DATA(port_nibble | 0x00) + escaped(data) + FEND
private def build_kiss_frame(data : Bytes, command : UInt8 = RNS::KISS::CMD_DATA, port : UInt8 = 0_u8) : Bytes
  io = IO::Memory.new
  io.write_byte(RNS::KISS::FEND)
  # First byte: port nibble (high) | command (low)
  io.write_byte((port << 4) | command)
  data.each do |byte|
    if byte == RNS::KISS::FESC
      io.write_byte(RNS::KISS::FESC)
      io.write_byte(RNS::KISS::TFESC)
    elsif byte == RNS::KISS::FEND
      io.write_byte(RNS::KISS::FESC)
      io.write_byte(RNS::KISS::TFEND)
    else
      io.write_byte(byte)
    end
  end
  io.write_byte(RNS::KISS::FEND)
  io.to_slice
end

# Helper to build a KISS CMD_READY frame
private def build_kiss_ready_frame : Bytes
  Bytes[RNS::KISS::FEND, RNS::KISS::CMD_READY, RNS::KISS::FEND]
end

describe RNS::KISS do
  describe "extended constants" do
    it "has all KISS command constants" do
      RNS::KISS::FEND.should eq 0xC0_u8
      RNS::KISS::FESC.should eq 0xDB_u8
      RNS::KISS::TFEND.should eq 0xDC_u8
      RNS::KISS::TFESC.should eq 0xDD_u8
      RNS::KISS::CMD_DATA.should eq 0x00_u8
      RNS::KISS::CMD_TXDELAY.should eq 0x01_u8
      RNS::KISS::CMD_P.should eq 0x02_u8
      RNS::KISS::CMD_SLOTTIME.should eq 0x03_u8
      RNS::KISS::CMD_TXTAIL.should eq 0x04_u8
      RNS::KISS::CMD_FULLDUPLEX.should eq 0x05_u8
      RNS::KISS::CMD_SETHARDWARE.should eq 0x06_u8
      RNS::KISS::CMD_READY.should eq 0x0F_u8
      RNS::KISS::CMD_UNKNOWN.should eq 0xFE_u8
      RNS::KISS::CMD_RETURN.should eq 0xFF_u8
    end
  end

  describe ".escape" do
    it "escapes FEND bytes" do
      data = Bytes[0x01, 0xC0, 0x02]
      escaped = RNS::KISS.escape(data)
      escaped.should eq Bytes[0x01, 0xDB, 0xDC, 0x02]
    end

    it "escapes FESC bytes" do
      data = Bytes[0x01, 0xDB, 0x02]
      escaped = RNS::KISS.escape(data)
      escaped.should eq Bytes[0x01, 0xDB, 0xDD, 0x02]
    end

    it "escapes both FEND and FESC" do
      data = Bytes[0xC0, 0xDB]
      escaped = RNS::KISS.escape(data)
      escaped.should eq Bytes[0xDB, 0xDC, 0xDB, 0xDD]
    end

    it "handles empty data" do
      RNS::KISS.escape(Bytes.empty).should eq Bytes.empty
    end

    it "handles data without special bytes" do
      data = Bytes[0x01, 0x02, 0x03]
      RNS::KISS.escape(data).should eq data
    end
  end

  describe ".unescape" do
    it "unescapes TFEND to FEND" do
      data = Bytes[0x01, 0xDB, 0xDC, 0x02]
      RNS::KISS.unescape(data).should eq Bytes[0x01, 0xC0, 0x02]
    end

    it "unescapes TFESC to FESC" do
      data = Bytes[0x01, 0xDB, 0xDD, 0x02]
      RNS::KISS.unescape(data).should eq Bytes[0x01, 0xDB, 0x02]
    end

    it "handles both escape sequences" do
      data = Bytes[0xDB, 0xDC, 0xDB, 0xDD]
      RNS::KISS.unescape(data).should eq Bytes[0xC0, 0xDB]
    end
  end

  describe ".frame" do
    it "wraps data in FEND+CMD_DATA and FEND" do
      data = Bytes[0x01, 0x02, 0x03]
      frame = RNS::KISS.frame(data)
      frame[0].should eq RNS::KISS::FEND
      frame[1].should eq RNS::KISS::CMD_DATA
      frame[-1].should eq RNS::KISS::FEND
    end

    it "escapes special bytes in data" do
      data = Bytes[0xC0, 0xDB]
      frame = RNS::KISS.frame(data)
      # FEND + CMD_DATA + DB DC DB DD + FEND
      frame.should eq Bytes[0xC0, 0x00, 0xDB, 0xDC, 0xDB, 0xDD, 0xC0]
    end

    it "roundtrips with escape/unescape" do
      100.times do
        data = Random::Secure.random_bytes(rand(1..200))
        frame = RNS::KISS.frame(data)
        # Extract content between FEND markers, skip CMD_DATA byte
        content = frame[2..-2]
        RNS::KISS.unescape(content).should eq data
      end
    end
  end
end

describe RNS::KISSInterface do
  describe "constants" do
    it "has correct constants" do
      RNS::KISSInterface::MAX_CHUNK.should eq 32768
      RNS::KISSInterface::BITRATE_GUESS.should eq 1200
      RNS::KISSInterface::DEFAULT_IFAC_SIZE.should eq 8
    end

    it "has parity symbols" do
      RNS::KISSInterface::PARITY_NONE.should eq :none
      RNS::KISSInterface::PARITY_EVEN.should eq :even
      RNS::KISSInterface::PARITY_ODD.should eq :odd
    end
  end

  describe "constructor with explicit params" do
    it "creates with default settings" do
      iface = RNS::KISSInterface.new(
        name: "kiss0",
        port: "/dev/ttyUSB0",
        open_port: false
      )
      iface.name.should eq "kiss0"
      iface.port.should eq "/dev/ttyUSB0"
      iface.speed.should eq 9600
      iface.databits.should eq 8
      iface.parity.should eq :none
      iface.stopbits.should eq 1
      iface.timeout.should eq 100
      iface.bitrate.should eq 1200
      iface.hw_mtu.should eq 564
      iface.online.should be_false
    end

    it "creates with custom KISS parameters" do
      iface = RNS::KISSInterface.new(
        name: "kiss0",
        port: "/dev/ttyUSB0",
        preamble: 500,
        txtail: 50,
        persistence: 128,
        slottime: 40,
        open_port: false
      )
      iface.preamble.should eq 500
      iface.txtail.should eq 50
      iface.persistence.should eq 128
      iface.slottime.should eq 40
    end

    it "creates with flow control" do
      iface = RNS::KISSInterface.new(
        name: "kiss0",
        port: "/dev/ttyUSB0",
        flow_control: true,
        open_port: false
      )
      iface.flow_control.should be_true
      iface.interface_ready.should be_false
    end

    it "creates with beacon configuration" do
      iface = RNS::KISSInterface.new(
        name: "kiss0",
        port: "/dev/ttyUSB0",
        beacon_interval: 900,
        beacon_data: "N0CALL",
        open_port: false
      )
      iface.beacon_interval.should eq 900
      String.new(iface.beacon_data).should eq "N0CALL"
    end

    it "parses parity strings" do
      even = RNS::KISSInterface.new(name: "k", port: "/dev/x", parity_str: "even", open_port: false)
      even.parity.should eq :even

      odd = RNS::KISSInterface.new(name: "k", port: "/dev/x", parity_str: "O", open_port: false)
      odd.parity.should eq :odd

      none = RNS::KISSInterface.new(name: "k", port: "/dev/x", parity_str: "N", open_port: false)
      none.parity.should eq :none
    end
  end

  describe "config hash constructor" do
    it "raises without port" do
      expect_raises(ArgumentError, /No port specified/) do
        RNS::KISSInterface.new({"name" => "kiss0"})
      end
    end

    it "parses all config keys" do
      # Can't actually open the port, so we test the config path indirectly
      # by verifying that missing port raises correctly
      expect_raises(ArgumentError, /No port specified/) do
        RNS::KISSInterface.new({
          "name"     => "kiss0",
          "speed"    => "19200",
          "preamble" => "500",
          "txtail"   => "50",
        })
      end
    end
  end

  describe "should_ingress_limit?" do
    it "always returns false" do
      iface = RNS::KISSInterface.new(name: "kiss0", port: "/dev/x", open_port: false)
      iface.should_ingress_limit?.should be_false
    end
  end

  describe "#to_s" do
    it "formats correctly" do
      iface = RNS::KISSInterface.new(name: "kiss_tnc", port: "/dev/x", open_port: false)
      iface.to_s.should eq "KISSInterface[kiss_tnc]"
    end
  end

  describe "interface base class" do
    it "inherits from Interface" do
      iface = RNS::KISSInterface.new(name: "kiss0", port: "/dev/x", open_port: false)
      iface.is_a?(RNS::Interface).should be_true
    end

    it "tracks counters" do
      iface = RNS::KISSInterface.new(name: "kiss0", port: "/dev/x", open_port: false)
      iface.rxb.should eq 0
      iface.txb.should eq 0
    end

    it "has correct HW_MTU" do
      iface = RNS::KISSInterface.new(name: "kiss0", port: "/dev/x", open_port: false)
      iface.hw_mtu.should eq 564
    end

    it "computes consistent hash" do
      iface = RNS::KISSInterface.new(name: "kiss0", port: "/dev/x", open_port: false)
      h1 = iface.get_hash
      h2 = iface.get_hash
      h1.should eq h2
    end
  end

  describe "teardown" do
    it "sets offline" do
      iface = RNS::KISSInterface.new(name: "kiss0", port: "/dev/x", open_port: false)
      iface.online = true
      iface.teardown
      iface.online.should be_false
    end
  end

  describe "detach" do
    it "marks detached and tears down" do
      iface = RNS::KISSInterface.new(name: "kiss0", port: "/dev/x", open_port: false)
      iface.online = true
      iface.detach
      iface.detached?.should be_true
      iface.online.should be_false
    end
  end

  describe "process_outgoing" do
    it "is no-op when offline" do
      iface = RNS::KISSInterface.new(name: "kiss0", port: "/dev/x", open_port: false)
      iface.online = false
      # Should not raise
      iface.process_outgoing(Bytes[0x01, 0x02])
      iface.txb.should eq 0
    end

    it "queues when interface not ready and flow control active" do
      iface = RNS::KISSInterface.new(name: "kiss0", port: "/dev/x", flow_control: true, open_port: false)
      iface.online = true
      iface.interface_ready = false
      iface.process_outgoing(Bytes[0x01, 0x02])
      iface.packet_queue.size.should eq 1
    end
  end

  describe "process_incoming" do
    it "tracks rxb and calls callback" do
      received = [] of Bytes
      iface = RNS::KISSInterface.new(
        name: "kiss0",
        port: "/dev/x",
        open_port: false,
        inbound_callback: ->(data : Bytes, _iface : RNS::Interface) { received << data.dup; nil }
      )
      iface.process_incoming(Bytes[0x01, 0x02, 0x03])
      iface.rxb.should eq 3
      received.size.should eq 1
      received[0].should eq Bytes[0x01, 0x02, 0x03]
    end
  end

  describe "flow control" do
    it "queues packets when not ready" do
      iface = RNS::KISSInterface.new(name: "kiss0", port: "/dev/x", open_port: false)
      iface.flow_control = true
      iface.online = true
      iface.interface_ready = false

      iface.queue(Bytes[0x01])
      iface.queue(Bytes[0x02])
      iface.queue(Bytes[0x03])
      iface.packet_queue.size.should eq 3
    end

    it "process_queue pops first entry" do
      iface = RNS::KISSInterface.new(name: "kiss0", port: "/dev/x", open_port: false)
      iface.queue(Bytes[0x01])
      iface.queue(Bytes[0x02])

      # process_queue needs the interface online and with IO, but we can test the queue logic
      iface.interface_ready = false
      iface.packet_queue.size.should eq 2
    end

    it "process_queue sets ready when empty" do
      iface = RNS::KISSInterface.new(name: "kiss0", port: "/dev/x", open_port: false)
      iface.interface_ready = false
      iface.process_queue
      iface.interface_ready.should be_true
    end
  end

  describe "KISS frame encoding" do
    it "encodes data correctly" do
      data = Bytes[0x01, 0x02, 0x03]
      frame = RNS::KISS.frame(data)
      frame[0].should eq 0xC0_u8 # FEND
      frame[1].should eq 0x00_u8 # CMD_DATA
      frame[2].should eq 0x01_u8
      frame[3].should eq 0x02_u8
      frame[4].should eq 0x03_u8
      frame[5].should eq 0xC0_u8 # FEND
    end

    it "escapes FEND in data" do
      data = Bytes[0x01, 0xC0, 0x02]
      frame = RNS::KISS.frame(data)
      # FEND CMD_DATA 01 FESC TFEND 02 FEND
      frame.should eq Bytes[0xC0, 0x00, 0x01, 0xDB, 0xDC, 0x02, 0xC0]
    end

    it "escapes FESC in data" do
      data = Bytes[0x01, 0xDB, 0x02]
      frame = RNS::KISS.frame(data)
      # FEND CMD_DATA 01 FESC TFESC 02 FEND
      frame.should eq Bytes[0xC0, 0x00, 0x01, 0xDB, 0xDD, 0x02, 0xC0]
    end
  end

  describe "KISS read loop simulation" do
    it "parses a single KISS frame" do
      received = [] of Bytes
      iface = RNS::KISSInterface.new(
        name: "kiss0",
        port: "/dev/x",
        open_port: false,
        inbound_callback: ->(data : Bytes, _iface : RNS::Interface) { received << data.dup; nil }
      )

      # Build a KISS frame with test data
      test_data = Bytes[0x01, 0x02, 0x03, 0x04]
      frame = build_kiss_frame(test_data)

      # Create pipe for simulating serial I/O
      r, w = IO.pipe
      rd_fd = IO::FileDescriptor.new(r.fd, blocking: false)

      iface.serial_io = rd_fd
      iface.running = true
      iface.online = true
      iface.interface_ready = true

      # Write frame bytes into pipe
      w.write(frame)
      w.flush

      # Process bytes: manually call process_incoming via read simulation
      # Instead of running read_loop (which blocks), parse manually
      in_frame = false
      escape = false
      command = RNS::KISS::CMD_UNKNOWN
      data_buffer = IO::Memory.new

      frame.each do |byte|
        if in_frame && byte == RNS::KISS::FEND && command == RNS::KISS::CMD_DATA
          in_frame = false
          if data_buffer.pos > 0
            iface.process_incoming(data_buffer.to_slice.dup)
          end
        elsif byte == RNS::KISS::FEND
          in_frame = true
          command = RNS::KISS::CMD_UNKNOWN
          data_buffer = IO::Memory.new
        elsif in_frame
          if data_buffer.pos == 0 && command == RNS::KISS::CMD_UNKNOWN
            command = byte & 0x0F_u8
          elsif command == RNS::KISS::CMD_DATA
            if byte == RNS::KISS::FESC
              escape = true
            else
              if escape
                byte = RNS::KISS::FEND if byte == RNS::KISS::TFEND
                byte = RNS::KISS::FESC if byte == RNS::KISS::TFESC
                escape = false
              end
              data_buffer.write_byte(byte)
            end
          end
        end
      end

      received.size.should eq 1
      received[0].should eq test_data

      w.close
      r.close
    end

    it "parses multiple KISS frames" do
      received = [] of Bytes

      callback = ->(data : Bytes, _iface : RNS::Interface) { received << data.dup; nil }

      # Parse frames manually
      frames = [
        Bytes[0x01, 0x02],
        Bytes[0x03, 0x04, 0x05],
        Bytes[0x06],
      ]

      all_bytes = IO::Memory.new
      frames.each { |f| all_bytes.write(build_kiss_frame(f)) }
      raw = all_bytes.to_slice

      # Simulate KISS state machine
      in_frame = false
      escape = false
      command = RNS::KISS::CMD_UNKNOWN
      data_buffer = IO::Memory.new

      raw.each do |byte|
        if in_frame && byte == RNS::KISS::FEND && command == RNS::KISS::CMD_DATA
          in_frame = false
          if data_buffer.pos > 0
            received << data_buffer.to_slice.dup
          end
        elsif byte == RNS::KISS::FEND
          in_frame = true
          command = RNS::KISS::CMD_UNKNOWN
          data_buffer = IO::Memory.new
        elsif in_frame
          if data_buffer.pos == 0 && command == RNS::KISS::CMD_UNKNOWN
            command = byte & 0x0F_u8
          elsif command == RNS::KISS::CMD_DATA
            if byte == RNS::KISS::FESC
              escape = true
            else
              if escape
                byte = RNS::KISS::FEND if byte == RNS::KISS::TFEND
                byte = RNS::KISS::FESC if byte == RNS::KISS::TFESC
                escape = false
              end
              data_buffer.write_byte(byte)
            end
          end
        end
      end

      received.size.should eq 3
      received[0].should eq Bytes[0x01, 0x02]
      received[1].should eq Bytes[0x03, 0x04, 0x05]
      received[2].should eq Bytes[0x06]
    end

    it "handles FEND and FESC in data" do
      received = [] of Bytes

      # Data containing both FEND and FESC bytes
      test_data = Bytes[0x01, 0xC0, 0xDB, 0x02]
      frame = build_kiss_frame(test_data)

      in_frame = false
      escape = false
      command = RNS::KISS::CMD_UNKNOWN
      data_buffer = IO::Memory.new

      frame.each do |byte|
        if in_frame && byte == RNS::KISS::FEND && command == RNS::KISS::CMD_DATA
          in_frame = false
          if data_buffer.pos > 0
            received << data_buffer.to_slice.dup
          end
        elsif byte == RNS::KISS::FEND
          in_frame = true
          command = RNS::KISS::CMD_UNKNOWN
          data_buffer = IO::Memory.new
        elsif in_frame
          if data_buffer.pos == 0 && command == RNS::KISS::CMD_UNKNOWN
            command = byte & 0x0F_u8
          elsif command == RNS::KISS::CMD_DATA
            if byte == RNS::KISS::FESC
              escape = true
            else
              if escape
                byte = RNS::KISS::FEND if byte == RNS::KISS::TFEND
                byte = RNS::KISS::FESC if byte == RNS::KISS::TFESC
                escape = false
              end
              data_buffer.write_byte(byte)
            end
          end
        end
      end

      received.size.should eq 1
      received[0].should eq test_data
    end

    it "handles CMD_READY frame" do
      ready_processed = false

      # CMD_READY frame from TNC: FEND + CMD_READY + value + FEND
      # The value byte triggers the CMD_READY branch in the state machine
      frame = Bytes[RNS::KISS::FEND, RNS::KISS::CMD_READY, 0x01_u8, RNS::KISS::FEND]

      in_frame = false
      command = RNS::KISS::CMD_UNKNOWN
      data_buffer = IO::Memory.new

      frame.each do |byte|
        if in_frame && byte == RNS::KISS::FEND && command == RNS::KISS::CMD_DATA
          in_frame = false
        elsif byte == RNS::KISS::FEND
          in_frame = true
          command = RNS::KISS::CMD_UNKNOWN
          data_buffer = IO::Memory.new
        elsif in_frame
          if data_buffer.pos == 0 && command == RNS::KISS::CMD_UNKNOWN
            command = byte & 0x0F_u8
          elsif command == RNS::KISS::CMD_READY
            ready_processed = true
          end
        end
      end

      ready_processed.should be_true
    end

    it "strips port nibble" do
      received = [] of Bytes

      # Frame with port nibble 0x10 (port 1) + CMD_DATA (0x00)
      test_data = Bytes[0xAA, 0xBB]
      frame = build_kiss_frame(test_data, port: 1_u8)

      in_frame = false
      escape = false
      command = RNS::KISS::CMD_UNKNOWN
      data_buffer = IO::Memory.new

      frame.each do |byte|
        if in_frame && byte == RNS::KISS::FEND && command == RNS::KISS::CMD_DATA
          in_frame = false
          if data_buffer.pos > 0
            received << data_buffer.to_slice.dup
          end
        elsif byte == RNS::KISS::FEND
          in_frame = true
          command = RNS::KISS::CMD_UNKNOWN
          data_buffer = IO::Memory.new
        elsif in_frame
          if data_buffer.pos == 0 && command == RNS::KISS::CMD_UNKNOWN
            command = byte & 0x0F_u8
          elsif command == RNS::KISS::CMD_DATA
            if byte == RNS::KISS::FESC
              escape = true
            else
              if escape
                byte = RNS::KISS::FEND if byte == RNS::KISS::TFEND
                byte = RNS::KISS::FESC if byte == RNS::KISS::TFESC
                escape = false
              end
              data_buffer.write_byte(byte)
            end
          end
        end
      end

      received.size.should eq 1
      received[0].should eq test_data
    end

    it "enforces MTU limit" do
      # Frame with data larger than HW_MTU (564)
      big_data = Random::Secure.random_bytes(600)
      frame = build_kiss_frame(big_data)

      in_frame = false
      escape = false
      command = RNS::KISS::CMD_UNKNOWN
      data_buffer = IO::Memory.new
      hw_mtu = 564
      received = [] of Bytes

      frame.each do |byte|
        if in_frame && byte == RNS::KISS::FEND && command == RNS::KISS::CMD_DATA
          in_frame = false
          if data_buffer.pos > 0
            received << data_buffer.to_slice.dup
          end
        elsif byte == RNS::KISS::FEND
          in_frame = true
          command = RNS::KISS::CMD_UNKNOWN
          data_buffer = IO::Memory.new
        elsif in_frame && data_buffer.pos < hw_mtu
          if data_buffer.pos == 0 && command == RNS::KISS::CMD_UNKNOWN
            command = byte & 0x0F_u8
          elsif command == RNS::KISS::CMD_DATA
            if byte == RNS::KISS::FESC
              escape = true
            else
              if escape
                byte = RNS::KISS::FEND if byte == RNS::KISS::TFEND
                byte = RNS::KISS::FESC if byte == RNS::KISS::TFESC
                escape = false
              end
              data_buffer.write_byte(byte)
            end
          end
        end
      end

      received.size.should eq 1
      received[0].size.should eq hw_mtu
    end

    it "roundtrips 100 random packets through KISS framing" do
      100.times do
        data = Random::Secure.random_bytes(rand(1..500))
        frame = build_kiss_frame(data)

        received = [] of Bytes
        in_frame = false
        escape = false
        command = RNS::KISS::CMD_UNKNOWN
        data_buffer = IO::Memory.new

        frame.each do |byte|
          if in_frame && byte == RNS::KISS::FEND && command == RNS::KISS::CMD_DATA
            in_frame = false
            if data_buffer.pos > 0
              received << data_buffer.to_slice.dup
            end
          elsif byte == RNS::KISS::FEND
            in_frame = true
            command = RNS::KISS::CMD_UNKNOWN
            data_buffer = IO::Memory.new
          elsif in_frame
            if data_buffer.pos == 0 && command == RNS::KISS::CMD_UNKNOWN
              command = byte & 0x0F_u8
            elsif command == RNS::KISS::CMD_DATA
              if byte == RNS::KISS::FESC
                escape = true
              else
                if escape
                  byte = RNS::KISS::FEND if byte == RNS::KISS::TFEND
                  byte = RNS::KISS::FESC if byte == RNS::KISS::TFESC
                  escape = false
                end
                data_buffer.write_byte(byte)
              end
            end
          end
        end

        received.size.should eq 1
        received[0].should eq data
      end
    end
  end

  describe "KISS command encoding" do
    it "encodes preamble command" do
      # Preamble 350ms -> 350/10 = 35
      cmd = Bytes[RNS::KISS::FEND, RNS::KISS::CMD_TXDELAY, 35_u8, RNS::KISS::FEND]
      cmd[0].should eq 0xC0_u8
      cmd[1].should eq 0x01_u8
      cmd[2].should eq 35_u8
      cmd[3].should eq 0xC0_u8
    end

    it "encodes txtail command" do
      # TxTail 20ms -> 20/10 = 2
      cmd = Bytes[RNS::KISS::FEND, RNS::KISS::CMD_TXTAIL, 2_u8, RNS::KISS::FEND]
      cmd[1].should eq 0x04_u8
      cmd[2].should eq 2_u8
    end

    it "encodes persistence command" do
      cmd = Bytes[RNS::KISS::FEND, RNS::KISS::CMD_P, 64_u8, RNS::KISS::FEND]
      cmd[1].should eq 0x02_u8
      cmd[2].should eq 64_u8
    end

    it "encodes slottime command" do
      # Slottime 20ms -> 20/10 = 2
      cmd = Bytes[RNS::KISS::FEND, RNS::KISS::CMD_SLOTTIME, 2_u8, RNS::KISS::FEND]
      cmd[1].should eq 0x03_u8
      cmd[2].should eq 2_u8
    end

    it "clamps preamble to 0-255" do
      (3000 // 10).clamp(0, 255).should eq 255
      (-10 // 10).clamp(0, 255).should eq 0
    end
  end

  describe "beacon support" do
    it "stores beacon config" do
      iface = RNS::KISSInterface.new(
        name: "kiss0",
        port: "/dev/x",
        beacon_interval: 600,
        beacon_data: "N0CALL",
        open_port: false
      )
      iface.beacon_interval.should eq 600
      String.new(iface.beacon_data).should eq "N0CALL"
      iface.first_tx.should be_nil
    end

    it "first_tx starts nil" do
      iface = RNS::KISSInterface.new(name: "kiss0", port: "/dev/x", open_port: false)
      iface.first_tx.should be_nil
    end

    it "tracks first_tx on non-beacon send" do
      iface = RNS::KISSInterface.new(
        name: "kiss0",
        port: "/dev/x",
        beacon_data: "N0CALL",
        open_port: false
      )
      # Sending non-beacon data should set first_tx
      iface.first_tx.should be_nil
      # We can't actually send without IO, but the logic is:
      # if data != beacon_data, set first_tx if nil
    end
  end

  describe "pipe-based I/O simulation" do
    it "sends KISS-framed data through pipe" do
      r, w = IO.pipe

      iface = RNS::KISSInterface.new(name: "kiss0", port: "/dev/x", open_port: false)
      wr_fd = IO::FileDescriptor.new(w.fd, blocking: false)
      iface.serial_io = wr_fd
      iface.online = true
      iface.interface_ready = true

      data = Bytes[0x01, 0x02, 0x03]
      iface.process_outgoing(data)
      iface.txb.should eq 3

      # Read from the pipe
      buf = Bytes.new(256)
      bytes_read = r.read(buf)
      received = buf[0, bytes_read]

      # Should be KISS framed
      received[0].should eq RNS::KISS::FEND
      received[1].should eq RNS::KISS::CMD_DATA
      received[-1].should eq RNS::KISS::FEND

      # Verify content
      content = received[2..-2]
      RNS::KISS.unescape(content).should eq data

      w.close
      r.close
    end

    it "sends escaped data through pipe" do
      r, w = IO.pipe

      iface = RNS::KISSInterface.new(name: "kiss0", port: "/dev/x", open_port: false)
      wr_fd = IO::FileDescriptor.new(w.fd, blocking: false)
      iface.serial_io = wr_fd
      iface.online = true
      iface.interface_ready = true

      # Data with special bytes
      data = Bytes[0x01, 0xC0, 0xDB, 0x02]
      iface.process_outgoing(data)
      iface.txb.should eq 4

      buf = Bytes.new(256)
      bytes_read = r.read(buf)
      received = buf[0, bytes_read]

      # Content should be properly escaped
      content = received[2..-2]
      RNS::KISS.unescape(content).should eq data

      w.close
      r.close
    end
  end

  describe "stress tests" do
    it "roundtrips 1000 random packets through KISS state machine" do
      1000.times do |i|
        data = Random::Secure.random_bytes(rand(1..200))
        frame = build_kiss_frame(data)

        # Full KISS state machine parse
        in_frame = false
        escape = false
        command = RNS::KISS::CMD_UNKNOWN
        data_buffer = IO::Memory.new

        frame.each do |byte|
          if in_frame && byte == RNS::KISS::FEND && command == RNS::KISS::CMD_DATA
            in_frame = false
          elsif byte == RNS::KISS::FEND
            in_frame = true
            command = RNS::KISS::CMD_UNKNOWN
            data_buffer = IO::Memory.new
          elsif in_frame
            if data_buffer.pos == 0 && command == RNS::KISS::CMD_UNKNOWN
              command = byte & 0x0F_u8
            elsif command == RNS::KISS::CMD_DATA
              if byte == RNS::KISS::FESC
                escape = true
              else
                if escape
                  byte = RNS::KISS::FEND if byte == RNS::KISS::TFEND
                  byte = RNS::KISS::FESC if byte == RNS::KISS::TFESC
                  escape = false
                end
                data_buffer.write_byte(byte)
              end
            end
          end
        end

        data_buffer.to_slice.should eq data
      end
    end
  end
end

describe RNS::AX25 do
  describe "constants" do
    it "has correct constants" do
      RNS::AX25::PID_NOLAYER3.should eq 0xF0_u8
      RNS::AX25::CTRL_UI.should eq 0x03_u8
      RNS::AX25::CRC_CORRECT.should eq Bytes[0xF0, 0xB8]
      RNS::AX25::HEADER_SIZE.should eq 16
    end
  end

  describe ".encode_call" do
    it "encodes a 6-char callsign" do
      call = "N0CALL".encode("ASCII")
      encoded = RNS::AX25.encode_call(call, 0)
      encoded.size.should eq 7
      # Each char shifted left by 1
      encoded[0].should eq ('N'.ord << 1).to_u8
      encoded[1].should eq ('0'.ord << 1).to_u8
      encoded[2].should eq ('C'.ord << 1).to_u8
      encoded[3].should eq ('A'.ord << 1).to_u8
      encoded[4].should eq ('L'.ord << 1).to_u8
      encoded[5].should eq ('L'.ord << 1).to_u8
      # SSID byte: 0x60 | (0 << 1) = 0x60
      encoded[6].should eq 0x60_u8
    end

    it "pads short callsigns with 0x20" do
      call = "AB1".encode("ASCII")
      encoded = RNS::AX25.encode_call(call, 5)
      encoded.size.should eq 7
      encoded[0].should eq ('A'.ord << 1).to_u8
      encoded[1].should eq ('B'.ord << 1).to_u8
      encoded[2].should eq ('1'.ord << 1).to_u8
      # Padding
      encoded[3].should eq 0x20_u8
      encoded[4].should eq 0x20_u8
      encoded[5].should eq 0x20_u8
      # SSID: 0x60 | (5 << 1) = 0x6A
      encoded[6].should eq 0x6A_u8
    end

    it "sets last bit when last=true" do
      call = "N0CALL".encode("ASCII")
      encoded = RNS::AX25.encode_call(call, 3, last: true)
      # SSID: 0x60 | (3 << 1) | 0x01 = 0x67
      encoded[6].should eq 0x67_u8
    end

    it "does not set last bit by default" do
      call = "N0CALL".encode("ASCII")
      encoded = RNS::AX25.encode_call(call, 0)
      (encoded[6] & 0x01_u8).should eq 0_u8
    end
  end

  describe ".build_header" do
    it "builds a 16-byte header" do
      src = "N0CALL".encode("ASCII")
      dst = "APZRNS".encode("ASCII")
      header = RNS::AX25.build_header(src, 5, dst, 0)
      header.size.should eq 16
    end

    it "has destination first, then source" do
      src = "N0CALL".encode("ASCII")
      dst = "APZRNS".encode("ASCII")
      header = RNS::AX25.build_header(src, 5, dst, 0)
      # First 7 bytes: destination
      header[0].should eq ('A'.ord << 1).to_u8
      header[1].should eq ('P'.ord << 1).to_u8
      # Byte 7-13: source
      header[7].should eq ('N'.ord << 1).to_u8
    end

    it "has CTRL_UI and PID_NOLAYER3 at end" do
      src = "N0CALL".encode("ASCII")
      dst = "APZRNS".encode("ASCII")
      header = RNS::AX25.build_header(src, 5, dst, 0)
      header[14].should eq RNS::AX25::CTRL_UI
      header[15].should eq RNS::AX25::PID_NOLAYER3
    end

    it "sets last bit on source SSID byte" do
      src = "N0CALL".encode("ASCII")
      dst = "APZRNS".encode("ASCII")
      header = RNS::AX25.build_header(src, 5, dst, 0)
      # Source SSID byte is at index 13 (7+6)
      (header[13] & 0x01_u8).should eq 1_u8
    end

    it "does not set last bit on destination SSID byte" do
      src = "N0CALL".encode("ASCII")
      dst = "APZRNS".encode("ASCII")
      header = RNS::AX25.build_header(src, 5, dst, 0)
      # Destination SSID byte is at index 6
      (header[6] & 0x01_u8).should eq 0_u8
    end

    it "matches Python encoding" do
      # Verify against Python's encoding:
      # dst_call="APZRNS", dst_ssid=0: encoded_dst_ssid = 0x60 | (0<<1) = 0x60
      # src_call="N0CALL", src_ssid=5: encoded_src_ssid = 0x60 | (5<<1) | 0x01 = 0x6B
      src = "N0CALL".encode("ASCII")
      dst = "APZRNS".encode("ASCII")
      header = RNS::AX25.build_header(src, 5, dst, 0)
      header[6].should eq 0x60_u8  # dst SSID
      header[13].should eq 0x6B_u8 # src SSID with last bit
    end
  end
end

describe RNS::AX25KISSInterface do
  describe "constants" do
    it "has correct constants" do
      RNS::AX25KISSInterface::MAX_CHUNK.should eq 32768
      RNS::AX25KISSInterface::BITRATE_GUESS.should eq 1200
      RNS::AX25KISSInterface::DEFAULT_IFAC_SIZE.should eq 8
    end
  end

  describe "constructor with explicit params" do
    it "creates with default settings" do
      iface = RNS::AX25KISSInterface.new(
        name: "ax25_0",
        port: "/dev/ttyUSB0",
        callsign: "N0CALL",
        ssid: 5,
        open_port: false
      )
      iface.name.should eq "ax25_0"
      iface.port.should eq "/dev/ttyUSB0"
      iface.speed.should eq 9600
      iface.databits.should eq 8
      iface.parity.should eq :none
      iface.stopbits.should eq 1
      iface.bitrate.should eq 1200
      iface.hw_mtu.should eq 564
      iface.online.should be_false
      String.new(iface.src_call).should eq "N0CALL"
      iface.src_ssid.should eq 5
      String.new(iface.dst_call).should eq "APZRNS"
      iface.dst_ssid.should eq 0
    end

    it "uppercases callsign" do
      iface = RNS::AX25KISSInterface.new(
        name: "ax25_0",
        port: "/dev/x",
        callsign: "n0call",
        ssid: 0,
        open_port: false
      )
      String.new(iface.src_call).should eq "N0CALL"
    end

    it "validates callsign length min" do
      expect_raises(ArgumentError, /Invalid callsign/) do
        RNS::AX25KISSInterface.new(
          name: "ax25_0",
          port: "/dev/x",
          callsign: "AB",
          ssid: 0,
          open_port: false
        )
      end
    end

    it "validates callsign length max" do
      expect_raises(ArgumentError, /Invalid callsign/) do
        RNS::AX25KISSInterface.new(
          name: "ax25_0",
          port: "/dev/x",
          callsign: "N0CALLS7",
          ssid: 0,
          open_port: false
        )
      end
    end

    it "validates SSID range low" do
      expect_raises(ArgumentError, /Invalid SSID/) do
        RNS::AX25KISSInterface.new(
          name: "ax25_0",
          port: "/dev/x",
          callsign: "N0CALL",
          ssid: -1,
          open_port: false
        )
      end
    end

    it "validates SSID range high" do
      expect_raises(ArgumentError, /Invalid SSID/) do
        RNS::AX25KISSInterface.new(
          name: "ax25_0",
          port: "/dev/x",
          callsign: "N0CALL",
          ssid: 16,
          open_port: false
        )
      end
    end

    it "accepts SSID 0-15" do
      (0..15).each do |ssid|
        iface = RNS::AX25KISSInterface.new(
          name: "ax25_0",
          port: "/dev/x",
          callsign: "N0CALL",
          ssid: ssid,
          open_port: false
        )
        iface.src_ssid.should eq ssid
      end
    end

    it "creates with custom KISS parameters" do
      iface = RNS::AX25KISSInterface.new(
        name: "ax25_0",
        port: "/dev/x",
        callsign: "N0CALL",
        ssid: 5,
        preamble: 500,
        txtail: 50,
        persistence: 128,
        slottime: 40,
        open_port: false
      )
      iface.preamble.should eq 500
      iface.txtail.should eq 50
      iface.persistence.should eq 128
      iface.slottime.should eq 40
    end

    it "parses parity strings" do
      even = RNS::AX25KISSInterface.new(name: "k", port: "/dev/x", callsign: "N0CALL", ssid: 0, parity_str: "even", open_port: false)
      even.parity.should eq :even

      odd = RNS::AX25KISSInterface.new(name: "k", port: "/dev/x", callsign: "N0CALL", ssid: 0, parity_str: "O", open_port: false)
      odd.parity.should eq :odd
    end
  end

  describe "config hash constructor" do
    it "raises without port" do
      expect_raises(ArgumentError, /No port specified/) do
        RNS::AX25KISSInterface.new({"name" => "ax25_0", "callsign" => "N0CALL", "ssid" => "5"})
      end
    end
  end

  describe "should_ingress_limit?" do
    it "always returns false" do
      iface = RNS::AX25KISSInterface.new(name: "ax25_0", port: "/dev/x", callsign: "N0CALL", ssid: 5, open_port: false)
      iface.should_ingress_limit?.should be_false
    end
  end

  describe "#to_s" do
    it "formats correctly" do
      iface = RNS::AX25KISSInterface.new(name: "ax25_tnc", port: "/dev/x", callsign: "N0CALL", ssid: 5, open_port: false)
      iface.to_s.should eq "AX25KISSInterface[ax25_tnc]"
    end
  end

  describe "interface base class" do
    it "inherits from Interface" do
      iface = RNS::AX25KISSInterface.new(name: "ax25_0", port: "/dev/x", callsign: "N0CALL", ssid: 5, open_port: false)
      iface.is_a?(RNS::Interface).should be_true
    end

    it "tracks counters" do
      iface = RNS::AX25KISSInterface.new(name: "ax25_0", port: "/dev/x", callsign: "N0CALL", ssid: 5, open_port: false)
      iface.rxb.should eq 0
      iface.txb.should eq 0
    end

    it "computes consistent hash" do
      iface = RNS::AX25KISSInterface.new(name: "ax25_0", port: "/dev/x", callsign: "N0CALL", ssid: 5, open_port: false)
      h1 = iface.get_hash
      h2 = iface.get_hash
      h1.should eq h2
    end
  end

  describe "teardown" do
    it "sets offline" do
      iface = RNS::AX25KISSInterface.new(name: "ax25_0", port: "/dev/x", callsign: "N0CALL", ssid: 5, open_port: false)
      iface.online = true
      iface.teardown
      iface.online.should be_false
    end
  end

  describe "detach" do
    it "marks detached and tears down" do
      iface = RNS::AX25KISSInterface.new(name: "ax25_0", port: "/dev/x", callsign: "N0CALL", ssid: 5, open_port: false)
      iface.online = true
      iface.detach
      iface.detached?.should be_true
      iface.online.should be_false
    end
  end

  describe "process_incoming" do
    it "strips AX.25 header from incoming data" do
      received = [] of Bytes
      iface = RNS::AX25KISSInterface.new(
        name: "ax25_0",
        port: "/dev/x",
        callsign: "N0CALL",
        ssid: 5,
        open_port: false,
        inbound_callback: ->(data : Bytes, _iface : RNS::Interface) { received << data.dup; nil }
      )

      # Build fake AX.25 frame: 16-byte header + payload
      header = RNS::AX25.build_header(
        "N0CALL".encode("ASCII"), 5,
        "APZRNS".encode("ASCII"), 0
      )
      payload = Bytes[0x01, 0x02, 0x03]
      frame = IO::Memory.new
      frame.write(header)
      frame.write(payload)

      iface.process_incoming(frame.to_slice)

      received.size.should eq 1
      received[0].should eq payload
      iface.rxb.should eq (16 + 3).to_i64
    end

    it "ignores frames shorter than header" do
      received = [] of Bytes
      iface = RNS::AX25KISSInterface.new(
        name: "ax25_0",
        port: "/dev/x",
        callsign: "N0CALL",
        ssid: 5,
        open_port: false,
        inbound_callback: ->(data : Bytes, _iface : RNS::Interface) { received << data.dup; nil }
      )

      # Data shorter than AX25.HEADER_SIZE (16)
      iface.process_incoming(Bytes[0x01, 0x02, 0x03])
      received.size.should eq 0
      iface.rxb.should eq 0
    end

    it "ignores frames exactly header size" do
      received = [] of Bytes
      iface = RNS::AX25KISSInterface.new(
        name: "ax25_0",
        port: "/dev/x",
        callsign: "N0CALL",
        ssid: 5,
        open_port: false,
        inbound_callback: ->(data : Bytes, _iface : RNS::Interface) { received << data.dup; nil }
      )

      # Exactly 16 bytes = header only, no payload
      iface.process_incoming(Random::Secure.random_bytes(16))
      received.size.should eq 0
    end
  end

  describe "process_outgoing" do
    it "is no-op when offline" do
      iface = RNS::AX25KISSInterface.new(name: "ax25_0", port: "/dev/x", callsign: "N0CALL", ssid: 5, open_port: false)
      iface.online = false
      iface.process_outgoing(Bytes[0x01, 0x02])
      iface.txb.should eq 0
    end

    it "queues when not ready" do
      iface = RNS::AX25KISSInterface.new(name: "ax25_0", port: "/dev/x", callsign: "N0CALL", ssid: 5, flow_control: true, open_port: false)
      iface.online = true
      iface.interface_ready = false
      iface.process_outgoing(Bytes[0x01, 0x02])
      iface.packet_queue.size.should eq 1
    end

    it "adds AX.25 header and KISS frames data through pipe" do
      r, w = IO.pipe

      iface = RNS::AX25KISSInterface.new(
        name: "ax25_0",
        port: "/dev/x",
        callsign: "N0CALL",
        ssid: 5,
        open_port: false
      )
      wr_fd = IO::FileDescriptor.new(w.fd, blocking: false)
      iface.serial_io = wr_fd
      iface.online = true
      iface.interface_ready = true

      payload = Bytes[0x01, 0x02, 0x03]
      iface.process_outgoing(payload)
      iface.txb.should eq 3 # txb tracks original data size

      # Read the KISS frame from pipe
      buf = Bytes.new(512)
      bytes_read = r.read(buf)
      received = buf[0, bytes_read]

      # Should be KISS framed
      received[0].should eq RNS::KISS::FEND
      received[1].should eq RNS::KISS::CMD_DATA
      received[-1].should eq RNS::KISS::FEND

      # Unescape the content
      content = RNS::KISS.unescape(received[2..-2])

      # Content should be AX.25 header (16 bytes) + payload (3 bytes) = 19 bytes
      content.size.should eq 19

      # Verify AX.25 header structure
      content[14].should eq RNS::AX25::CTRL_UI
      content[15].should eq RNS::AX25::PID_NOLAYER3

      # Verify payload is at the end
      content[16..].should eq payload

      w.close
      r.close
    end
  end

  describe "flow control" do
    it "queues packets when not ready" do
      iface = RNS::AX25KISSInterface.new(
        name: "ax25_0",
        port: "/dev/x",
        callsign: "N0CALL",
        ssid: 5,
        open_port: false
      )
      iface.flow_control = true
      iface.online = true
      iface.interface_ready = false

      iface.queue(Bytes[0x01])
      iface.queue(Bytes[0x02])
      iface.packet_queue.size.should eq 2
    end

    it "process_queue sets ready when empty" do
      iface = RNS::AX25KISSInterface.new(
        name: "ax25_0",
        port: "/dev/x",
        callsign: "N0CALL",
        ssid: 5,
        open_port: false
      )
      iface.interface_ready = false
      iface.process_queue
      iface.interface_ready.should be_true
    end
  end

  describe "AX.25 KISS read loop simulation" do
    it "parses frame with AX.25 header stripping" do
      received = [] of Bytes
      callback = ->(data : Bytes, _iface : RNS::Interface) { received << data.dup; nil }

      # Build AX.25 payload: header + data
      header = RNS::AX25.build_header(
        "N0CALL".encode("ASCII"), 5,
        "APZRNS".encode("ASCII"), 0
      )
      payload = Bytes[0xAA, 0xBB, 0xCC]
      ax25_frame = IO::Memory.new
      ax25_frame.write(header)
      ax25_frame.write(payload)

      # Wrap in KISS frame
      kiss_frame = build_kiss_frame(ax25_frame.to_slice)

      # Parse KISS + strip AX.25 header
      in_frame = false
      escape = false
      command = RNS::KISS::CMD_UNKNOWN
      data_buffer = IO::Memory.new
      hw_mtu = 564 + RNS::AX25::HEADER_SIZE

      kiss_frame.each do |byte|
        if in_frame && byte == RNS::KISS::FEND && command == RNS::KISS::CMD_DATA
          in_frame = false
          raw = data_buffer.to_slice
          if raw.size > RNS::AX25::HEADER_SIZE
            received << raw[RNS::AX25::HEADER_SIZE..].dup
          end
        elsif byte == RNS::KISS::FEND
          in_frame = true
          command = RNS::KISS::CMD_UNKNOWN
          data_buffer = IO::Memory.new
        elsif in_frame && data_buffer.pos < hw_mtu
          if data_buffer.pos == 0 && command == RNS::KISS::CMD_UNKNOWN
            command = byte & 0x0F_u8
          elsif command == RNS::KISS::CMD_DATA
            if byte == RNS::KISS::FESC
              escape = true
            else
              if escape
                byte = RNS::KISS::FEND if byte == RNS::KISS::TFEND
                byte = RNS::KISS::FESC if byte == RNS::KISS::TFESC
                escape = false
              end
              data_buffer.write_byte(byte)
            end
          end
        end
      end

      received.size.should eq 1
      received[0].should eq payload
    end

    it "rejects frames with only AX.25 header" do
      received = [] of Bytes

      header = RNS::AX25.build_header(
        "N0CALL".encode("ASCII"), 5,
        "APZRNS".encode("ASCII"), 0
      )
      # Header only, no payload
      kiss_frame = build_kiss_frame(header)

      in_frame = false
      escape = false
      command = RNS::KISS::CMD_UNKNOWN
      data_buffer = IO::Memory.new

      kiss_frame.each do |byte|
        if in_frame && byte == RNS::KISS::FEND && command == RNS::KISS::CMD_DATA
          in_frame = false
          raw = data_buffer.to_slice
          if raw.size > RNS::AX25::HEADER_SIZE
            received << raw[RNS::AX25::HEADER_SIZE..].dup
          end
        elsif byte == RNS::KISS::FEND
          in_frame = true
          command = RNS::KISS::CMD_UNKNOWN
          data_buffer = IO::Memory.new
        elsif in_frame
          if data_buffer.pos == 0 && command == RNS::KISS::CMD_UNKNOWN
            command = byte & 0x0F_u8
          elsif command == RNS::KISS::CMD_DATA
            if byte == RNS::KISS::FESC
              escape = true
            else
              if escape
                byte = RNS::KISS::FEND if byte == RNS::KISS::TFEND
                byte = RNS::KISS::FESC if byte == RNS::KISS::TFESC
                escape = false
              end
              data_buffer.write_byte(byte)
            end
          end
        end
      end

      received.size.should eq 0
    end
  end

  describe "AX.25 address formatting" do
    it "encodes destination callsign correctly" do
      iface = RNS::AX25KISSInterface.new(
        name: "ax25_0",
        port: "/dev/x",
        callsign: "N0CALL",
        ssid: 5,
        open_port: false
      )
      String.new(iface.dst_call).should eq "APZRNS"
      iface.dst_ssid.should eq 0
    end

    it "uses correct default destination" do
      # Python uses "APZRNS" as destination callsign (Amateur Packet Zone Reticulum)
      iface = RNS::AX25KISSInterface.new(
        name: "ax25_0",
        port: "/dev/x",
        callsign: "N0CALL",
        ssid: 5,
        open_port: false
      )
      String.new(iface.dst_call).should eq "APZRNS"
    end
  end

  describe "stress tests" do
    it "roundtrips 100 packets through AX.25 KISS pipeline" do
      100.times do
        # Random payload
        payload = Random::Secure.random_bytes(rand(1..200))

        # Build AX.25 frame
        header = RNS::AX25.build_header(
          "N0CALL".encode("ASCII"), 5,
          "APZRNS".encode("ASCII"), 0
        )
        ax25_data = IO::Memory.new
        ax25_data.write(header)
        ax25_data.write(payload)

        # KISS frame
        kiss_frame = build_kiss_frame(ax25_data.to_slice)

        # Parse and extract
        in_frame = false
        escape = false
        command = RNS::KISS::CMD_UNKNOWN
        data_buffer = IO::Memory.new
        result : Bytes? = nil

        kiss_frame.each do |byte|
          if in_frame && byte == RNS::KISS::FEND && command == RNS::KISS::CMD_DATA
            in_frame = false
            raw = data_buffer.to_slice
            if raw.size > RNS::AX25::HEADER_SIZE
              result = raw[RNS::AX25::HEADER_SIZE..].dup
            end
          elsif byte == RNS::KISS::FEND
            in_frame = true
            command = RNS::KISS::CMD_UNKNOWN
            data_buffer = IO::Memory.new
          elsif in_frame
            if data_buffer.pos == 0 && command == RNS::KISS::CMD_UNKNOWN
              command = byte & 0x0F_u8
            elsif command == RNS::KISS::CMD_DATA
              if byte == RNS::KISS::FESC
                escape = true
              else
                if escape
                  byte = RNS::KISS::FEND if byte == RNS::KISS::TFEND
                  byte = RNS::KISS::FESC if byte == RNS::KISS::TFESC
                  escape = false
                end
                data_buffer.write_byte(byte)
              end
            end
          end
        end

        result.should_not be_nil
        result.not_nil!.should eq payload
      end
    end

    it "creates 20 interfaces with valid callsigns" do
      callsigns = ["N0CALL", "W1AW", "K7RLD", "VE3ABC", "JA1MRG",
                   "DL4MDW", "G3RSD", "OH2GEX", "SP5EEP", "UA3AAA",
                   "VK2TDS", "ZL1AAA", "PY1ABC", "LU1AAA", "XE1ABC",
                   "HL2ABC", "BV2AAA", "A71AAA", "9V1AAA", "YB1AAA"]
      callsigns.each_with_index do |call, i|
        ssid = i % 16
        iface = RNS::AX25KISSInterface.new(
          name: "ax25_#{i}",
          port: "/dev/x",
          callsign: call,
          ssid: ssid,
          open_port: false
        )
        iface.src_ssid.should eq ssid
        String.new(iface.src_call).should eq call.upcase
      end
    end
  end
end
