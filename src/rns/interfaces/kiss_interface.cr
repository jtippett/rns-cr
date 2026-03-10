module RNS
  # KISS TNC interface for serial port communication.
  # Ports RNS/Interfaces/KISSInterface.py using POSIX termios + KISS framing.
  class KISSInterface < Interface
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
    property timeout : Int32 = 100 # milliseconds

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

    # Beacon / identification
    property beacon_interval : Int32? = nil
    property beacon_data : Bytes = Bytes.empty
    property first_tx : Float64? = nil

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
    def initialize(name : String, port : String, speed : Int32 = 9600,
                   databits : Int32 = 8, parity_str : String = "N",
                   stopbits : Int32 = 1, open_port : Bool = true,
                   preamble : Int32 = 350, txtail : Int32 = 20,
                   persistence : Int32 = 64, slottime : Int32 = 20,
                   flow_control : Bool = false,
                   beacon_interval : Int32? = nil, beacon_data : String = "",
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

      @preamble = preamble
      @txtail = txtail
      @persistence = persistence
      @slottime = slottime
      @flow_control = flow_control
      @flow_control_locked = Time.utc.to_unix_f

      @beacon_interval = beacon_interval
      @beacon_data = beacon_data.encode("UTF-8")

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
      beacon_interval = c["id_interval"]?.try(&.to_i)
      beacon_data_str = c["id_callsign"]? || ""

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

      @flow_control = flow_ctrl
      @interface_ready = false
      @flow_control_timeout = 5
      @flow_control_locked = Time.utc.to_unix_f

      @preamble    = preamble || 350
      @txtail      = txtail || 20
      @persistence = persistence || 64
      @slottime    = slottime || 20

      @beacon_interval = beacon_interval
      @beacon_data = beacon_data_str.encode("UTF-8")

      begin
        do_open_port
      rescue ex
        RNS.log("Could not open serial port #{@port}", RNS::LOG_ERROR)
        raise ex
      end

      if @fd
        configure_device
      else
        raise IO::Error.new("Could not open serial port")
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
      RNS.log("Configuring KISS interface parameters...")
      set_preamble(@preamble)
      set_tx_tail(@txtail)
      set_persistence(@persistence)
      set_slot_time(@slottime)
      set_flow_control(@flow_control)
      @interface_ready = true
      RNS.log("KISS interface configured")
    end

    # KISS configuration commands

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

    # Build a KISS data frame: FEND + 0x00 + escaped(data) + FEND
    def self.build_kiss_frame(data : Bytes) : Bytes
      KISS.frame(data)
    end

    def process_incoming(data : Bytes)
      @rxb += data.size.to_i64
      if cb = @inbound_callback
        cb.call(data, self)
      end
    end

    def process_outgoing(data : Bytes)
      return unless @online

      if @interface_ready
        if @flow_control
          @interface_ready = false
          @flow_control_locked = Time.utc.to_unix_f
        end

        frame = KISS.frame(data)

        if io = @io
          begin
            io.write(frame)
            io.flush
            @txb += data.size.to_i64
          rescue ex
            raise IO::Error.new("Serial interface only wrote partial data: #{ex.message}")
          end
        end

        # Beacon tracking
        if data == @beacon_data
          @first_tx = nil
        else
          if @first_tx.nil?
            @first_tx = Time.utc.to_unix_f
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
            elsif in_frame && data_buffer.pos < hw_mtu_value
              if data_buffer.pos == 0 && command == KISS::CMD_UNKNOWN
                # Strip port nibble, keep command
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

            # Flow control timeout
            if @flow_control && !@interface_ready
              if Time.utc.to_unix_f > @flow_control_locked + @flow_control_timeout
                RNS.log("Interface #{self} is unlocking flow control due to time-out. This should not happen. Your hardware might have missed a flow-control READY command, or maybe it does not support flow-control.", RNS::LOG_WARNING)
                process_queue
              end
            end

            # Beacon transmission
            if (bi = @beacon_interval) && @beacon_data.size > 0
              if ftx = @first_tx
                if Time.utc.to_unix_f > ftx + bi
                  RNS.log("Interface #{self} is transmitting beacon data: #{String.new(@beacon_data)}", RNS::LOG_DEBUG)
                  @first_tx = nil

                  # Pad to minimum length of 15 bytes
                  frame = IO::Memory.new(Math.max(@beacon_data.size, 15))
                  frame.write(@beacon_data)
                  while frame.pos < 15
                    frame.write_byte(0x00_u8)
                  end
                  process_outgoing(frame.to_slice)
                end
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
        rescue
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

    # Expose IO for testing
    def serial_io : IO::FileDescriptor?
      @io
    end

    # Allow setting IO for pipe-based testing
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
      io << "KISSInterface[" << @name << "]"
    end
  end
end
