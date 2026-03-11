module RNS
  # Additional termios functions not in Crystal's standard LibC bindings.
  # Crystal already provides: tcgetattr, tcsetattr, cfmakeraw.
  # We add: cfsetispeed, cfsetospeed, tcflush.
  lib LibSerial
    fun cfsetispeed(termios_p : Void*, speed : UInt64) : Int32
    fun cfsetospeed(termios_p : Void*, speed : UInt64) : Int32
    fun tcflush(fd : Int32, queue_selector : Int32) : Int32
  end

  # Serial port termios constants.
  # Grouped here to avoid polluting LibC with platform-specific ifdefs.
  module SerialConstants
    # tcflush queue selectors
    TCIOFLUSH = 3

    # Control flag bits
    CSIZE   = 0x00000300_u64
    CS5     = 0x00000000_u64
    CS6     = 0x00000100_u64
    CS7     = 0x00000200_u64
    CS8     = 0x00000300_u64
    CSTOPB  = 0x00000400_u64
    CREAD   = 0x00000800_u64
    PARENB  = 0x00001000_u64
    PARODD  = 0x00002000_u64
    CLOCAL  = 0x00008000_u64
    CRTSCTS = {% if flag?(:darwin) %}0x00030000_u64{% else %}0x80000000_u64{% end %}

    # Input flag bits
    IXON  = 0x00000200_u64
    IXOFF = {% if flag?(:darwin) %}0x00000400_u64{% else %}0x00001000_u64{% end %}
    IXANY = 0x00000800_u64

    # c_cc indices
    VMIN  = {% if flag?(:darwin) %}16{% else %}6{% end %}
    VTIME = {% if flag?(:darwin) %}17{% else %}5{% end %}

    # Baud rate constants
    {% if flag?(:darwin) %}
      # macOS uses actual baud rate values directly
      B9600   =     9600_u64
      B19200  =    19200_u64
      B38400  =    38400_u64
      B57600  =    57600_u64
      B115200 =   115200_u64
      B230400 =   230400_u64
    {% else %}
      B9600   = 0o000015_u64
      B19200  = 0o000016_u64
      B38400  = 0o000017_u64
      B57600  = 0o010001_u64
      B115200 = 0o010002_u64
      B230400 = 0o010003_u64
    {% end %}
  end

  # Serial port communication interface using HDLC framing.
  # Ports RNS/Interfaces/SerialInterface.py using POSIX termios.
  class SerialInterface < Interface
    MAX_CHUNK         = 32768
    DEFAULT_IFAC_SIZE = 8

    # Parity modes
    PARITY_NONE = :none
    PARITY_EVEN = :even
    PARITY_ODD  = :odd

    property port : String = ""
    property speed : Int32 = 9600
    property databits : Int32 = 8
    property parity : Symbol = PARITY_NONE
    property stopbits : Int32 = 1
    property timeout : Int32 = 100  # milliseconds

    @fd : Int32? = nil
    @io : IO::FileDescriptor? = nil
    @running : Bool = false
    @read_fiber : Fiber? = nil
    @inbound_callback : Proc(Bytes, Interface, Nil)? = nil

    def initialize(configuration : Hash(String, String),
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback
      configure(configuration)
    end

    # Constructor for testing: create with explicit parameters, no port opening
    def initialize(name : String, port : String, speed : Int32 = 9600,
                   databits : Int32 = 8, parity : String = "N",
                   stopbits : Int32 = 1, open_port : Bool = true,
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback
      @name = name
      @port = port
      @speed = speed
      @databits = databits
      @stopbits = stopbits
      @timeout = 100
      @hw_mtu = 564
      @bitrate = speed.to_i64
      @parity = parse_parity(parity)

      if open_port
        do_open_port
        configure_device
      end
    end

    private def configure(c : Hash(String, String))
      name     = c["name"]? || ""
      port     = c["port"]?
      speed    = c["speed"]?.try(&.to_i) || 9600
      databits = c["databits"]?.try(&.to_i) || 8
      parity   = c["parity"]? || "N"
      stopbits = c["stopbits"]?.try(&.to_i) || 1

      raise ArgumentError.new("No port specified for serial interface") unless port

      @hw_mtu  = 564
      @name    = name
      @port    = port
      @speed   = speed
      @databits = databits
      @parity  = parse_parity(parity)
      @stopbits = stopbits
      @timeout = 100
      @online  = false
      @bitrate = speed.to_i64

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

      # Clear O_NONBLOCK after opening (we'll use fiber-friendly IO)
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

      # Start with raw mode
      LibC.cfmakeraw(pointerof(tio))

      # Set baud rate
      tio_ptr = pointerof(tio).as(Void*)
      baud = speed_to_baud(@speed)
      LibSerial.cfsetispeed(tio_ptr, baud)
      LibSerial.cfsetospeed(tio_ptr, baud)

      # Configure control flags
      tio.c_cflag = tio.c_cflag & ~SerialConstants::CSIZE
      tio.c_cflag = tio.c_cflag | databits_flag(@databits)
      tio.c_cflag = tio.c_cflag | SerialConstants::CLOCAL | SerialConstants::CREAD

      # Stopbits
      if @stopbits == 2
        tio.c_cflag = tio.c_cflag | SerialConstants::CSTOPB
      else
        tio.c_cflag = tio.c_cflag & ~SerialConstants::CSTOPB
      end

      # Parity
      case @parity
      when PARITY_EVEN
        tio.c_cflag = tio.c_cflag | SerialConstants::PARENB
        tio.c_cflag = tio.c_cflag & ~SerialConstants::PARODD
      when PARITY_ODD
        tio.c_cflag = tio.c_cflag | SerialConstants::PARENB | SerialConstants::PARODD
      else
        tio.c_cflag = tio.c_cflag & ~SerialConstants::PARENB
      end

      # No hardware flow control
      tio.c_cflag = tio.c_cflag & ~SerialConstants::CRTSCTS

      # No software flow control
      tio.c_iflag = tio.c_iflag & ~(SerialConstants::IXON | SerialConstants::IXOFF | SerialConstants::IXANY)

      # VMIN=0, VTIME=0: non-blocking read
      tio.c_cc[SerialConstants::VMIN] = 0_u8
      tio.c_cc[SerialConstants::VTIME] = 0_u8

      ret = LibC.tcsetattr(fd, LibC::TCSANOW, pointerof(tio))
      raise IO::Error.new("tcsetattr failed") if ret != 0
    end

    private def speed_to_baud(speed : Int32) : UInt64
      {% if flag?(:darwin) %}
        # macOS uses actual baud rate values directly
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
      sleep 0.5.seconds
      @running = true
      @read_fiber = spawn { read_loop }
      @online = true
      RNS.log("Serial port #{@port} is now open", RNS::LOG_VERBOSE)
    end

    def process_incoming(data : Bytes)
      @rxb += data.size.to_i64
      if cb = @inbound_callback
        cb.call(data, self)
      end
    end

    def process_outgoing(data : Bytes)
      return unless @online

      framed = HDLC.frame(data)
      if io = @io
        begin
          io.write(framed)
          io.flush
          @txb += framed.size.to_i64
        rescue ex
          raise IO::Error.new("Serial interface only wrote partial data: #{ex.message}")
        end
      end
    end

    private def read_loop
      in_frame = false
      escape = false
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

            if in_frame && byte == HDLC::FLAG
              in_frame = false
              if data_buffer.pos > 0
                process_incoming(data_buffer.to_slice.dup)
              end
            elsif byte == HDLC::FLAG
              in_frame = true
              data_buffer = IO::Memory.new(1024)
            elsif in_frame && data_buffer.pos < hw_mtu_value
              if byte == HDLC::ESC
                escape = true
              else
                if escape
                  byte = HDLC::FLAG if byte == (HDLC::FLAG ^ HDLC::ESC_MASK)
                  byte = HDLC::ESC if byte == (HDLC::ESC ^ HDLC::ESC_MASK)
                  escape = false
                end
                data_buffer.write_byte(byte)
              end
            end
          else
            time_since_last = (Time.utc.to_unix_f * 1000).to_i64 - last_read_ms
            if data_buffer.pos > 0 && time_since_last > @timeout
              data_buffer = IO::Memory.new(1024)
              in_frame = false
              escape = false
            end
            sleep 0.08.seconds
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
      # Note: IO::FileDescriptor.close already closes the underlying fd
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

    # For testing: check if port is open
    def port_open? : Bool
      !@fd.nil?
    end

    private def hw_mtu_value : Int32
      @hw_mtu || 564
    end

    def to_s(io : IO)
      io << "SerialInterface[" << @name << "]"
    end
  end
end
