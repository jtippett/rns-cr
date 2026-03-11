module RNS
  # AX.25 protocol constants for amateur radio addressing.
  module AX25
    PID_NOLAYER3 = 0xF0_u8
    CTRL_UI      = 0x03_u8
    CRC_CORRECT  = Bytes[0xF0, 0xB8]
    HEADER_SIZE  = 16

    # Encode a callsign into AX.25 address field format.
    # Each character is shifted left 1 bit, padded with spaces to 6 chars.
    def self.encode_call(callsign : Bytes, ssid : Int32, last : Bool = false) : Bytes
      addr = IO::Memory.new(7)
      6.times do |i|
        if i < callsign.size
          addr.write_byte((callsign[i].to_u8 << 1).to_u8)
        else
          addr.write_byte(0x20_u8) # space, already shifted would be 0x40, but Python uses 0x20
        end
      end
      # SSID byte: 0x60 | (ssid << 1) | last_bit
      ssid_byte = (0x60_u8 | ((ssid & 0x0F) << 1).to_u8)
      ssid_byte = ssid_byte | 0x01_u8 if last
      addr.write_byte(ssid_byte)
      addr.to_slice
    end

    # Build the full 16-byte AX.25 header (14 address + CTRL + PID).
    def self.build_header(src_call : Bytes, src_ssid : Int32,
                          dst_call : Bytes, dst_ssid : Int32) : Bytes
      io = IO::Memory.new(HEADER_SIZE)
      # Destination address (not last)
      io.write(encode_call(dst_call, dst_ssid, last: false))
      # Source address (last)
      io.write(encode_call(src_call, src_ssid, last: true))
      # Control field: UI frame
      io.write_byte(CTRL_UI)
      # PID: No layer 3
      io.write_byte(PID_NOLAYER3)
      io.to_slice
    end
  end

  # AX.25 KISS TNC interface for amateur radio serial communication.
  # Adds AX.25 addressing (callsign/SSID) on top of KISS framing.
  # Ports RNS/Interfaces/AX25KISSInterface.py.
  class AX25KISSInterface < Interface
    MAX_CHUNK         = 32768
    BITRATE_GUESS     = 1200_i64
    DEFAULT_IFAC_SIZE = 8

    PARITY_NONE = :none
    PARITY_EVEN = :even
    PARITY_ODD  = :odd

    property port : String = ""
    property speed : Int32 = 9600
    property databits : Int32 = 8
    property parity : Symbol = PARITY_NONE
    property stopbits : Int32 = 1
    property timeout : Int32 = 100

    # KISS TNC parameters
    property preamble : Int32 = 350
    property txtail : Int32 = 20
    property persistence : Int32 = 64
    property slottime : Int32 = 20

    # Flow control
    property flow_control : Bool = false
    property interface_ready : Bool = false
    property flow_control_timeout : Int32 = 5
    property flow_control_locked : Float64 = 0.0
    property packet_queue : Array(Bytes) = [] of Bytes

    # AX.25 addressing
    property src_call : Bytes = Bytes.empty
    property src_ssid : Int32 = 0
    property dst_call : Bytes = "APZRNS".encode("ASCII")
    property dst_ssid : Int32 = 0

    @fd : Int32? = nil
    @io : IO::FileDescriptor? = nil
    @running : Bool = false
    @read_fiber : Fiber? = nil
    @inbound_callback : Proc(Bytes, Interface, Nil)? = nil

    # Config hash constructor (normal usage)
    def initialize(configuration : Hash(String, String),
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback
      configure(configuration)
    end

    # Explicit params constructor (for testing without opening port)
    def initialize(name : String, port : String, callsign : String, ssid : Int32,
                   speed : Int32 = 9600, databits : Int32 = 8, parity_str : String = "N",
                   stopbits : Int32 = 1, open_port : Bool = true,
                   preamble : Int32 = 350, txtail : Int32 = 20,
                   persistence : Int32 = 64, slottime : Int32 = 20,
                   flow_control : Bool = false,
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback
      @name = name
      @port = port
      @speed = speed
      @databits = databits
      @stopbits = stopbits
      @parity = parse_parity(parity_str)
      @timeout = 100
      @hw_mtu = 564
      @bitrate = BITRATE_GUESS
      @online = false

      @src_call = callsign.upcase.encode("ASCII")
      @src_ssid = ssid
      @dst_call = "APZRNS".encode("ASCII")
      @dst_ssid = 0

      validate_callsign!

      @preamble = preamble
      @txtail = txtail
      @persistence = persistence
      @slottime = slottime
      @flow_control = flow_control
      @flow_control_locked = Time.utc.to_unix_f

      if open_port
        do_open_port
        configure_device
      end
    end

    private def configure(c : Hash(String, String))
      name        = c["name"]? || ""
      port        = c["port"]?
      speed       = c["speed"]?.try(&.to_i) || 9600
      databits    = c["databits"]?.try(&.to_i) || 8
      parity_str  = c["parity"]? || "N"
      stopbits    = c["stopbits"]?.try(&.to_i) || 1
      flow_ctrl   = c["flow_control"]?.try { |v| v.downcase == "true" } || false
      preamble    = c["preamble"]?.try(&.to_i)
      txtail      = c["txtail"]?.try(&.to_i)
      persistence = c["persistence"]?.try(&.to_i)
      slottime    = c["slottime"]?.try(&.to_i)
      callsign    = c["callsign"]? || ""
      ssid        = c["ssid"]?.try(&.to_i) || -1

      raise ArgumentError.new("No port specified for serial interface") unless port

      @hw_mtu  = 564
      @name    = name
      @port    = port
      @speed   = speed
      @databits = databits
      @parity  = parse_parity(parity_str)
      @stopbits = stopbits
      @timeout = 100
      @online  = false
      @bitrate = BITRATE_GUESS

      @src_call = callsign.upcase.encode("ASCII")
      @src_ssid = ssid
      @dst_call = "APZRNS".encode("ASCII")
      @dst_ssid = 0

      validate_callsign!

      @flow_control = flow_ctrl
      @interface_ready = false
      @flow_control_timeout = 5
      @flow_control_locked = Time.utc.to_unix_f

      @preamble    = preamble || 350
      @txtail      = txtail || 20
      @persistence = persistence || 64
      @slottime    = slottime || 20

      begin
        do_open_port
      rescue ex
        RNS.log("Could not open serial port for interface #{self}", RNS::LOG_ERROR)
        raise ex
      end

      if @fd
        configure_device
      else
        raise IO::Error.new("Could not open serial port")
      end
    end

    private def validate_callsign!
      if @src_call.size < 3 || @src_call.size > 6
        raise ArgumentError.new("Invalid callsign for #{self}")
      end
      if @src_ssid < 0 || @src_ssid > 15
        raise ArgumentError.new("Invalid SSID for #{self}")
      end
    end

    private def parse_parity(parity : String) : Symbol
      case parity.downcase
      when "e", "even" then PARITY_EVEN
      when "o", "odd"  then PARITY_ODD
      else                  PARITY_NONE
      end
    end

    def do_open_port
      RNS.log("Opening serial port #{@port}...", RNS::LOG_VERBOSE)

      o_noctty = {% if flag?(:darwin) %}0x20000{% else %}0o0400{% end %}
      fd = LibC.open(@port, LibC::O_RDWR | o_noctty | LibC::O_NONBLOCK)
      raise IO::Error.new("Could not open serial port #{@port}") if fd < 0

      flags = LibC.fcntl(fd, LibC::F_GETFL, 0)
      LibC.fcntl(fd, LibC::F_SETFL, flags & ~LibC::O_NONBLOCK)

      configure_termios(fd)
      LibSerial.tcflush(fd, SerialConstants::TCIOFLUSH)

      @fd = fd
      io = IO::FileDescriptor.new(fd)
      IO::FileDescriptor.set_blocking(fd, false)
      @io = io
    end

    private def configure_termios(fd : Int32)
      tio = LibC::Termios.new
      ret = LibC.tcgetattr(fd, pointerof(tio))
      raise IO::Error.new("tcgetattr failed") if ret != 0

      LibC.cfmakeraw(pointerof(tio))

      tio_ptr = pointerof(tio).as(Void*)
      baud = speed_to_baud(@speed)
      LibSerial.cfsetispeed(tio_ptr, baud)
      LibSerial.cfsetospeed(tio_ptr, baud)

      tio.c_cflag = tio.c_cflag & ~SerialConstants::CSIZE
      tio.c_cflag = tio.c_cflag | databits_flag(@databits)
      tio.c_cflag = tio.c_cflag | SerialConstants::CLOCAL | SerialConstants::CREAD

      if @stopbits == 2
        tio.c_cflag = tio.c_cflag | SerialConstants::CSTOPB
      else
        tio.c_cflag = tio.c_cflag & ~SerialConstants::CSTOPB
      end

      case @parity
      when PARITY_EVEN
        tio.c_cflag = tio.c_cflag | SerialConstants::PARENB
        tio.c_cflag = tio.c_cflag & ~SerialConstants::PARODD
      when PARITY_ODD
        tio.c_cflag = tio.c_cflag | SerialConstants::PARENB | SerialConstants::PARODD
      else
        tio.c_cflag = tio.c_cflag & ~SerialConstants::PARENB
      end

      tio.c_cflag = tio.c_cflag & ~SerialConstants::CRTSCTS
      tio.c_iflag = tio.c_iflag & ~(SerialConstants::IXON | SerialConstants::IXOFF | SerialConstants::IXANY)

      tio.c_cc[SerialConstants::VMIN] = 0_u8
      tio.c_cc[SerialConstants::VTIME] = 0_u8

      ret = LibC.tcsetattr(fd, LibC::TCSANOW, pointerof(tio))
      raise IO::Error.new("tcsetattr failed") if ret != 0
    end

    private def speed_to_baud(speed : Int32) : UInt64
      {% if flag?(:darwin) %}
        speed.to_u64
      {% else %}
        case speed
        when    9600 then SerialConstants::B9600
        when   19200 then SerialConstants::B19200
        when   38400 then SerialConstants::B38400
        when   57600 then SerialConstants::B57600
        when  115200 then SerialConstants::B115200
        when  230400 then SerialConstants::B230400
        else              SerialConstants::B9600
        end
      {% end %}
    end

    private def databits_flag(bits : Int32) : UInt64
      case bits
      when 5 then SerialConstants::CS5
      when 6 then SerialConstants::CS6
      when 7 then SerialConstants::CS7
      else        SerialConstants::CS8
      end
    end

    def configure_device
      sleep 2.seconds
      @running = true
      @read_fiber = spawn { read_loop }
      @online = true
      RNS.log("Serial port #{@port} is now open")
      RNS.log("Configuring AX.25 KISS interface parameters...")
      set_preamble(@preamble)
      set_tx_tail(@txtail)
      set_persistence(@persistence)
      set_slot_time(@slottime)
      set_flow_control(@flow_control)
      @interface_ready = true
      RNS.log("AX.25 KISS interface configured")
    end

    def set_preamble(preamble_ms : Int32)
      value = (preamble_ms // 10).clamp(0, 255).to_u8
      write_kiss_command(KISS::CMD_TXDELAY, value)
    end

    def set_tx_tail(txtail_ms : Int32)
      value = (txtail_ms // 10).clamp(0, 255).to_u8
      write_kiss_command(KISS::CMD_TXTAIL, value)
    end

    def set_persistence(persistence : Int32)
      value = persistence.clamp(0, 255).to_u8
      write_kiss_command(KISS::CMD_P, value)
    end

    def set_slot_time(slottime_ms : Int32)
      value = (slottime_ms // 10).clamp(0, 255).to_u8
      write_kiss_command(KISS::CMD_SLOTTIME, value)
    end

    def set_flow_control(flow_control : Bool)
      write_kiss_command(KISS::CMD_READY, 0x01_u8)
    end

    private def write_kiss_command(cmd : UInt8, value : UInt8)
      command = Bytes[KISS::FEND, cmd, value, KISS::FEND]
      if io = @io
        io.write(command)
        io.flush
      end
    end

    def process_incoming(data : Bytes)
      # Strip AX.25 header (16 bytes) before passing data upstream
      if data.size > AX25::HEADER_SIZE
        @rxb += data.size.to_i64
        if cb = @inbound_callback
          cb.call(data[AX25::HEADER_SIZE..], self)
        end
      end
    end

    def process_outgoing(data : Bytes)
      return unless @online

      if @interface_ready
        if @flow_control
          @interface_ready = false
          @flow_control_locked = Time.utc.to_unix_f
        end

        # Build AX.25 header
        header = AX25.build_header(@src_call, @src_ssid, @dst_call, @dst_ssid)

        # Combine header + data
        ax25_data = IO::Memory.new(header.size + data.size)
        ax25_data.write(header)
        ax25_data.write(data)
        payload = ax25_data.to_slice

        # KISS frame: FEND + CMD_DATA + escaped(payload) + FEND
        frame = KISS.frame(payload)

        if io = @io
          begin
            io.write(frame)
            io.flush
            @txb += data.size.to_i64
          rescue ex
            if @flow_control
              @interface_ready = true
            end
            raise IO::Error.new("AX.25 interface only wrote partial data: #{ex.message}")
          end
        end
      else
        queue(data)
      end
    end

    def queue(data : Bytes)
      @packet_queue << data
    end

    def process_queue
      if @packet_queue.size > 0
        data = @packet_queue.shift
        @interface_ready = true
        process_outgoing(data)
      else
        @interface_ready = true
      end
    end

    private def read_loop
      in_frame = false
      escape = false
      command = KISS::CMD_UNKNOWN
      data_buffer = IO::Memory.new(1024)
      last_read_ms = (Time.utc.to_unix_f * 1000).to_i64
      buf = Bytes.new(1)
      mtu_with_header = hw_mtu_value + AX25::HEADER_SIZE

      while @running
        io = @io
        break unless io

        begin
          bytes_read = io.read(buf)
          if bytes_read > 0
            byte = buf[0]
            last_read_ms = (Time.utc.to_unix_f * 1000).to_i64

            if in_frame && byte == KISS::FEND && command == KISS::CMD_DATA
              in_frame = false
              if data_buffer.pos > 0
                process_incoming(data_buffer.to_slice.dup)
              end
            elsif byte == KISS::FEND
              in_frame = true
              command = KISS::CMD_UNKNOWN
              data_buffer = IO::Memory.new(1024)
            elsif in_frame && data_buffer.pos < mtu_with_header
              if data_buffer.pos == 0 && command == KISS::CMD_UNKNOWN
                byte = byte & 0x0F_u8
                command = byte
              elsif command == KISS::CMD_DATA
                if byte == KISS::FESC
                  escape = true
                else
                  if escape
                    byte = KISS::FEND if byte == KISS::TFEND
                    byte = KISS::FESC if byte == KISS::TFESC
                    escape = false
                  end
                  data_buffer.write_byte(byte)
                end
              elsif command == KISS::CMD_READY
                process_queue
              end
            end
          else
            time_since_last = (Time.utc.to_unix_f * 1000).to_i64 - last_read_ms
            if data_buffer.pos > 0 && time_since_last > @timeout
              data_buffer = IO::Memory.new(1024)
              in_frame = false
              command = KISS::CMD_UNKNOWN
              escape = false
            end
            sleep 0.05.seconds

            if @flow_control && !@interface_ready
              if Time.utc.to_unix_f > @flow_control_locked + @flow_control_timeout
                RNS.log("Interface #{self} is unlocking flow control due to time-out. This should not happen. Your hardware might have missed a flow-control READY command, or maybe it does not support flow-control.", RNS::LOG_WARNING)
                process_queue
              end
            end
          end
        rescue ex : IO::Error
          break unless @running
          @online = false
          RNS.log("A serial port error occurred, the contained exception was: #{ex.message}", RNS::LOG_ERROR)
          RNS.log("The interface #{self} experienced an unrecoverable error and is now offline.", RNS::LOG_ERROR)
          if Reticulum.panic_on_interface_error
            RNS.panic
          end
          RNS.log("Reticulum will attempt to reconnect the interface periodically.", RNS::LOG_ERROR)
          break
        rescue ex
          break unless @running
          @online = false
          RNS.log("A serial port error occurred, the contained exception was: #{ex.message}", RNS::LOG_ERROR)
          break
        end
      end

      @online = false
      close_port
      spawn { reconnect_port } if @running
    end

    def reconnect_port
      while !@online && @running
        begin
          sleep 5.seconds
          RNS.log("Attempting to reconnect serial port #{@port} for #{self}...", RNS::LOG_VERBOSE)
          do_open_port
          if @fd
            configure_device
          end
        rescue ex
          RNS.log("Error while reconnecting port, the contained exception was: #{ex.message}", RNS::LOG_ERROR)
        end
      end

      if @online
        RNS.log("Reconnected serial port for #{self}")
      end
    end

    def should_ingress_limit? : Bool
      false
    end

    def close_port
      if io = @io
        begin
          io.close unless io.closed?
        rescue ex
          RNS.log("Error closing port: #{ex.message}", RNS::LOG_DEBUG)
        end
        @io = nil
      end
      @fd = nil
    end

    def teardown
      @running = false
      @online = false
      close_port
    end

    def detach
      @detached = true
      teardown
    end

    def port_open? : Bool
      !@fd.nil?
    end

    private def hw_mtu_value : Int32
      @hw_mtu || 564
    end

    def serial_io : IO::FileDescriptor?
      @io
    end

    def serial_io=(io : IO::FileDescriptor?)
      @io = io
    end

    def running? : Bool
      @running
    end

    def running=(v : Bool)
      @running = v
    end

    def to_s(io : IO)
      io << "AX25KISSInterface[" << @name << "]"
    end
  end
end
