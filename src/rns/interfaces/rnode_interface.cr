module RNS
  # Extended KISS command constants for RNode hardware communication.
  # These supplement the base KISS constants in interface.cr.
  module RNodeKISS
    # Frame delimiters (same as base KISS)
    FEND  = KISS::FEND
    FESC  = KISS::FESC
    TFEND = KISS::TFEND
    TFESC = KISS::TFESC

    # RNode-specific KISS commands
    CMD_UNKNOWN     = 0xFE_u8
    CMD_DATA        = 0x00_u8
    CMD_FREQUENCY   = 0x01_u8
    CMD_BANDWIDTH   = 0x02_u8
    CMD_TXPOWER     = 0x03_u8
    CMD_SF          = 0x04_u8
    CMD_CR          = 0x05_u8
    CMD_RADIO_STATE = 0x06_u8
    CMD_RADIO_LOCK  = 0x07_u8
    CMD_ST_ALOCK    = 0x0B_u8
    CMD_LT_ALOCK    = 0x0C_u8
    CMD_DETECT      = 0x08_u8
    CMD_LEAVE       = 0x0A_u8
    CMD_READY       = 0x0F_u8
    CMD_STAT_RX     = 0x21_u8
    CMD_STAT_TX     = 0x22_u8
    CMD_STAT_RSSI   = 0x23_u8
    CMD_STAT_SNR    = 0x24_u8
    CMD_STAT_CHTM   = 0x25_u8
    CMD_STAT_PHYPRM = 0x26_u8
    CMD_STAT_BAT    = 0x27_u8
    CMD_STAT_CSMA   = 0x28_u8
    CMD_STAT_TEMP   = 0x29_u8
    CMD_BLINK       = 0x30_u8
    CMD_RANDOM      = 0x40_u8
    CMD_FB_EXT      = 0x41_u8
    CMD_FB_READ     = 0x42_u8
    CMD_DISP_READ   = 0x66_u8
    CMD_FB_WRITE    = 0x43_u8
    CMD_BT_CTRL     = 0x46_u8
    CMD_PLATFORM    = 0x48_u8
    CMD_MCU         = 0x49_u8
    CMD_FW_VERSION  = 0x50_u8
    CMD_ROM_READ    = 0x51_u8
    CMD_RESET       = 0x55_u8

    # Detection
    DETECT_REQ  = 0x73_u8
    DETECT_RESP = 0x46_u8

    # Radio states
    RADIO_STATE_OFF = 0x00_u8
    RADIO_STATE_ON  = 0x01_u8
    RADIO_STATE_ASK = 0xFF_u8

    # Error codes
    CMD_ERROR           = 0x90_u8
    ERROR_INITRADIO     = 0x01_u8
    ERROR_TXFAILED      = 0x02_u8
    ERROR_EEPROM_LOCKED = 0x03_u8
    ERROR_QUEUE_FULL    = 0x04_u8
    ERROR_MEMORY_LOW    = 0x05_u8
    ERROR_MODEM_TIMEOUT = 0x06_u8

    # Platform types
    PLATFORM_AVR   = 0x90_u8
    PLATFORM_ESP32 = 0x80_u8
    PLATFORM_NRF52 = 0x70_u8

    def self.escape(data : Bytes) : Bytes
      KISS.escape(data)
    end
  end

  # TCP connection for RNode communication over network.
  # Ports TCPConnection from RNS/Interfaces/RNodeInterface.py.
  class RNodeTCPConnection
    TARGET_PORT             = 7633
    CONNECT_TIMEOUT         = 5.0
    INITIAL_CONNECT_TIMEOUT = 5.0
    RECONNECT_WAIT          = 4.0
    ACTIVITY_TIMEOUT        = 6.0
    ACTIVITY_KEEPALIVE      = ACTIVITY_TIMEOUT - 2.5

    TCP_USER_TIMEOUT   = 24
    TCP_PROBE_AFTER    = 5
    TCP_PROBE_INTERVAL = 2
    TCP_PROBES         = 12

    property connected : Bool = false
    property running : Bool = false
    property should_run : Bool = false
    property must_disconnect : Bool = false
    property last_write : Float64 = Time.utc.to_unix_f

    @owner : RNodeInterface
    @target_host : String
    @socket : TCPSocket? = nil
    @rx_queue : IO::Memory = IO::Memory.new(4096)
    @tx_queue : IO::Memory = IO::Memory.new(4096)
    @rx_mutex : Mutex = Mutex.new
    @tx_mutex : Mutex = Mutex.new

    def initialize(@owner : RNodeInterface, @target_host : String)
      @should_run = true
      spawn { initial_connect }
    end

    # For testing: create without connecting
    def initialize(@owner : RNodeInterface, @target_host : String, connect : Bool = true)
      @should_run = true
      spawn { initial_connect } if connect
    end

    def is_open : Bool
      @connected
    end

    def in_waiting : Bool
      @rx_mutex.synchronize { @rx_queue.pos < @rx_queue.size || @rx_queue.pos > 0 }
    end

    def write(data : Bytes) : Int32
      if @connected && (sock = @socket)
        @tx_mutex.synchronize do
          if @tx_queue.pos > 0
            sock.write(@tx_queue.to_slice)
            @tx_queue = IO::Memory.new(4096)
          end
        end
        sock.write(data)
        @last_write = Time.utc.to_unix_f
      else
        @tx_mutex.synchronize { @tx_queue.write(data) }
      end
      data.size
    end

    def read(n : Int32) : Bytes
      @rx_mutex.synchronize do
        available = @rx_queue.to_slice
        take = Math.min(n, available.size)
        result = available[0, take].dup
        remaining = available[take..]
        @rx_queue = IO::Memory.new(Math.max(4096, remaining.size))
        @rx_queue.write(remaining)
        result
      end
    end

    def receive(data : Bytes)
      @rx_mutex.synchronize { @rx_queue.write(data) }
    end

    def close
      if @connected
        RNS.log("Disconnecting TCP socket for #{@owner}", RNS::LOG_DEBUG)
        @must_disconnect = true
        @socket.try(&.close)
      end
    end

    def cleanup
      @socket.try do |s|
        s.close unless s.closed?
      rescue
      end
      @should_run = false
    end

    private def initial_connect
      if connect(initial: true)
        spawn { read_loop }
      end
    end

    def connect(initial : Bool = false) : Bool
      if initial
        RNS.log("Establishing TCP connection to device for #{@owner}...", RNS::LOG_DEBUG)
      end

      sock = TCPSocket.new(@target_host, TARGET_PORT, connect_timeout: INITIAL_CONNECT_TIMEOUT.seconds)
      sock.tcp_nodelay = true
      sock.keepalive = true
      @socket = sock
      @connected = true
      @last_write = Time.utc.to_unix_f

      RNS.log("TCP connection to device for #{@owner} established", RNS::LOG_DEBUG)

      {% if flag?(:linux) %}
        set_timeouts_linux(sock)
      {% elsif flag?(:darwin) %}
        set_timeouts_osx(sock)
      {% end %}

      true
    rescue ex
      if initial
        RNS.log("TCP connection to device for #{@owner} could not be established: #{ex.message}", RNS::LOG_ERROR)
        false
      else
        raise ex
      end
    end

    private def read_loop
      buf = Bytes.new(4096)
      while !@must_disconnect
        begin
          sock = @socket
          break unless sock
          bytes_read = sock.read(buf)
          if bytes_read > 0
            receive(buf[0, bytes_read])
          else
            @connected = false
            RNS.log("The TCP socket for #{@owner} was closed", RNS::LOG_WARNING)
            break
          end
        rescue ex
          @connected = false
          RNS.log("A TCP read error occurred for #{@owner}: #{ex.message}", RNS::LOG_WARNING)
          break
        end
      end
    end

    {% if flag?(:linux) %}
      private def set_timeouts_linux(sock : TCPSocket)
        val = TCP_USER_TIMEOUT * 1000
        LibC.setsockopt(sock.fd, LibC::IPPROTO_TCP, 18, pointerof(val).as(Void*), sizeof(typeof(val)).to_u32)
        sock.keepalive = true
        idle = TCP_PROBE_AFTER
        LibC.setsockopt(sock.fd, LibC::IPPROTO_TCP, 4, pointerof(idle).as(Void*), sizeof(typeof(idle)).to_u32)
        intvl = TCP_PROBE_INTERVAL
        LibC.setsockopt(sock.fd, LibC::IPPROTO_TCP, 5, pointerof(intvl).as(Void*), sizeof(typeof(intvl)).to_u32)
        cnt = TCP_PROBES
        LibC.setsockopt(sock.fd, LibC::IPPROTO_TCP, 6, pointerof(cnt).as(Void*), sizeof(typeof(cnt)).to_u32)
      end
    {% end %}

    {% if flag?(:darwin) %}
      private def set_timeouts_osx(sock : TCPSocket)
        sock.keepalive = true
        val = TCP_PROBE_AFTER
        LibC.setsockopt(sock.fd, LibC::IPPROTO_TCP, 0x10, pointerof(val).as(Void*), sizeof(typeof(val)).to_u32)
      end
    {% end %}
  end

  # RNode LoRa radio interface.
  # Ports RNS/Interfaces/RNodeInterface.py (1558 LOC).
  # Communicates with RNode hardware via KISS-based command protocol over
  # serial, TCP, or BLE connections.
  class RNodeInterface < Interface
    MAX_CHUNK         = 32768
    DEFAULT_IFAC_SIZE = 8

    FREQ_MIN = 137_000_000_i64
    FREQ_MAX = 3_000_000_000_i64

    RSSI_OFFSET = 157

    CALLSIGN_MAX_LEN = 32

    REQUIRED_FW_VER_MAJ = 1
    REQUIRED_FW_VER_MIN = 52

    RECONNECT_WAIT = 5

    Q_SNR_MIN_BASE = -9
    Q_SNR_MAX      = 6
    Q_SNR_STEP     = 2

    BATTERY_STATE_UNKNOWN     = 0x00_u8
    BATTERY_STATE_DISCHARGING = 0x01_u8
    BATTERY_STATE_CHARGING    = 0x02_u8
    BATTERY_STATE_CHARGED     = 0x03_u8

    DISPLAY_READ_INTERVAL = 1.0

    FB_PIXEL_WIDTH     = 64
    FB_BITS_PER_PIXEL  = 1
    FB_PIXELS_PER_BYTE = 8 // FB_BITS_PER_PIXEL
    FB_BYTES_PER_LINE  = FB_PIXEL_WIDTH // FB_PIXELS_PER_BYTE

    # Configuration properties
    property port : String? = nil
    property speed : Int32 = 115200
    property databits : Int32 = 8
    property stopbits : Int32 = 1
    property timeout : Int32 = 100 # milliseconds

    # Radio parameters
    property frequency : Int64 = 0_i64
    property bandwidth : Int64 = 0_i64
    property txpower : Int32 = 0
    property sf : Int32 = 0
    property cr : Int32 = 0
    property st_alock : Float64? = nil
    property lt_alock : Float64? = nil

    # Connection state
    property reconnecting : Bool = false
    property interface_ready : Bool = false
    property flow_control : Bool = false

    # TCP connection
    property use_tcp : Bool = false
    property tcp : RNodeTCPConnection? = nil
    property tcp_host : String? = nil

    # BLE connection (stub — BLE not fully implementable in Crystal without native lib)
    property use_ble : Bool = false
    property ble_name : String? = nil
    property ble_addr : String? = nil

    # Reported radio state (from RNode device)
    property r_frequency : Int64? = nil
    property r_bandwidth : Int64? = nil
    property r_txpower : Int32? = nil
    property r_sf : Int32? = nil
    property r_cr : Int32? = nil
    property r_state : UInt8? = nil
    property r_lock : UInt8? = nil

    # Statistics
    property r_stat_rx : Int64? = nil
    property r_stat_tx : Int64? = nil
    property r_stat_rssi : Int32? = nil
    property r_stat_snr : Float64? = nil
    property r_stat_q : Float64? = nil

    # Airtime limits reported by device
    property r_st_alock : Float64? = nil
    property r_lt_alock : Float64? = nil

    # Channel and airtime metrics
    property r_airtime_short : Float64 = 0.0
    property r_airtime_long : Float64 = 0.0
    property r_channel_load_short : Float64 = 0.0
    property r_channel_load_long : Float64 = 0.0
    property r_symbol_time_ms : Float64? = nil
    property r_symbol_rate : Int32? = nil
    property r_preamble_symbols : Int32? = nil
    property r_premable_time_ms : Int32? = nil  # Note: typo matches Python
    property r_csma_slot_time_ms : Int32? = nil
    property r_csma_difs_ms : Int32? = nil
    property r_csma_cw_band : UInt8? = nil
    property r_csma_cw_min : UInt8? = nil
    property r_csma_cw_max : UInt8? = nil

    # Signal quality
    property r_current_rssi : Int32? = nil
    property r_noise_floor : Int32? = nil
    property r_interference : Int32? = nil
    property r_interference_l : Array(Float64)? = nil

    # Device info
    property detected : Bool = false
    property firmware_ok : Bool = false
    property maj_version : Int32 = 0
    property min_version : Int32 = 0
    property platform : UInt8? = nil
    property mcu : UInt8? = nil
    property cpu_temp : Int32? = nil
    property r_random : UInt8? = nil
    property display : Bool? = nil

    # Battery
    property r_battery_state : UInt8 = BATTERY_STATE_UNKNOWN
    property r_battery_percent : Int32 = 0
    property r_temperature : Int32? = nil

    # Framebuffer
    property r_framebuffer : Bytes = Bytes.empty
    property r_framebuffer_readtime : Float64 = 0.0
    property r_framebuffer_latency : Float64 = 0.0
    property r_disp : Bytes = Bytes.empty
    property r_disp_readtime : Float64 = 0.0
    property r_disp_latency : Float64 = 0.0
    property should_read_display : Bool = false
    property read_display_interval : Float64 = DISPLAY_READ_INTERVAL

    # Operational state
    property state : UInt8 = RNodeKISS::RADIO_STATE_OFF
    property bitrate_kbps : Float64 = 0.0
    property validcfg : Bool = true
    property hw_errors : Array(NamedTuple(error: UInt8, description: String)) = [] of NamedTuple(error: UInt8, description: String)
    property packet_queue : Array(Bytes) = [] of Bytes

    # ID beacon
    property id_interval : Int32? = nil
    property id_callsign : Bytes? = nil
    property last_id : Float64 = 0.0
    property first_tx : Float64? = nil

    @fd : Int32? = nil
    @io : IO? = nil
    @running : Bool = false
    @read_fiber : Fiber? = nil
    @inbound_callback : Proc(Bytes, Interface, Nil)? = nil
    @reconnect_w : Int32 = RECONNECT_WAIT

    # Config hash constructor (normal usage)
    def initialize(configuration : Hash(String, String),
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback
      configure(configuration)
    end

    # Explicit constructor for testing (no port opening)
    def initialize(name : String,
                   port : String? = nil,
                   frequency : Int64 = 0_i64,
                   bandwidth : Int64 = 0_i64,
                   txpower : Int32 = 0,
                   sf : Int32 = 0,
                   cr : Int32 = 0,
                   flow_control : Bool = false,
                   id_interval : Int32? = nil,
                   id_callsign : String? = nil,
                   st_alock : Float64? = nil,
                   lt_alock : Float64? = nil,
                   open_port : Bool = false,
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback
      @name = name
      @port = port
      @hw_mtu = 508
      @frequency = frequency
      @bandwidth = bandwidth
      @txpower = txpower
      @sf = sf
      @cr = cr
      @flow_control = flow_control
      @st_alock = st_alock
      @lt_alock = lt_alock
      @state = RNodeKISS::RADIO_STATE_OFF
      @supports_discovery = true

      if id_interval && id_callsign
        cs_bytes = id_callsign.encode("UTF-8")
        if cs_bytes.size <= CALLSIGN_MAX_LEN
          @id_interval = id_interval
          @id_callsign = cs_bytes
        end
      end

      validate_config!

      if open_port && @validcfg
        do_open_port
        configure_device if @io
      end
    end

    private def configure(c : Hash(String, String))
      name = c["name"]? || ""
      port = c["port"]?
      freq = c["frequency"]?.try(&.to_i64) || 0_i64
      bw = c["bandwidth"]?.try(&.to_i64) || 0_i64
      txp = c["txpower"]?.try(&.to_i) || 0
      spreading = c["spreadingfactor"]?.try(&.to_i) || 0
      coding = c["codingrate"]?.try(&.to_i) || 0
      flow_ctrl = c["flow_control"]?.try { |v| v.downcase == "true" } || false
      id_interval = c["id_interval"]?.try(&.to_i)
      id_callsign_str = c["id_callsign"]?
      st_alock_val = c["airtime_limit_short"]?.try(&.to_f)
      lt_alock_val = c["airtime_limit_long"]?.try(&.to_f)

      raise ArgumentError.new("No port specified for RNode interface") unless port

      # Parse connection type from port URI
      force_ble = false
      force_tcp = false
      serial_port : String? = port

      tcp_uri_scheme = "tcp://"
      ble_uri_scheme = "ble://"

      if port.downcase.starts_with?(ble_uri_scheme)
        force_ble = true
        ble_string = port[ble_uri_scheme.size..]
        serial_port = nil
        if ble_string.size > 0
          if ble_string.split(":").size == 6 && ble_string.size == 17
            @ble_addr = ble_string
          else
            @ble_name = ble_string
          end
        end
      elsif port.downcase.starts_with?(tcp_uri_scheme)
        force_tcp = true
        tcp_string = port[tcp_uri_scheme.size..]
        serial_port = nil
        @tcp_host = tcp_string if tcp_string.size > 0
      end

      @hw_mtu = 508
      @name = name
      @port = serial_port
      @speed = 115200
      @databits = 8
      @stopbits = 1
      @timeout = 100
      @online = false
      @frequency = freq
      @bandwidth = bw
      @txpower = txp
      @sf = spreading
      @cr = coding
      @state = RNodeKISS::RADIO_STATE_OFF
      @bitrate = 0_i64
      @st_alock = st_alock_val
      @lt_alock = lt_alock_val
      @flow_control = flow_ctrl
      @interface_ready = false
      @supports_discovery = true

      @use_ble = true if force_ble || @ble_addr || @ble_name
      @use_tcp = true if force_tcp || @tcp_host

      if id_interval && id_callsign_str
        cs_bytes = id_callsign_str.encode("UTF-8")
        if cs_bytes.size <= CALLSIGN_MAX_LEN
          @id_interval = id_interval
          @id_callsign = cs_bytes
        else
          RNS.log("The encoded ID callsign for #{self} exceeds the max length of #{CALLSIGN_MAX_LEN} bytes.", RNS::LOG_ERROR)
          @validcfg = false
        end
      end

      validate_config!

      unless @validcfg
        raise ArgumentError.new("The configuration for #{self} contains errors, interface is offline")
      end

      begin
        do_open_port
        if @io
          configure_device
        else
          raise IO::Error.new("Could not open serial port")
        end
      rescue ex
        RNS.log("Could not open serial port for interface #{self}", RNS::LOG_ERROR)
        RNS.log("The contained exception was: #{ex.message}", RNS::LOG_ERROR)
        RNS.log("Reticulum will attempt to bring up this interface periodically", RNS::LOG_ERROR)
        if !@detached && !@reconnecting
          spawn { reconnect_port }
        end
      end
    end

    private def validate_config!
      @validcfg = true

      if @frequency < FREQ_MIN || @frequency > FREQ_MAX
        RNS.log("Invalid frequency configured for #{self}", RNS::LOG_ERROR)
        @validcfg = false
      end

      if @txpower < 0 || @txpower > 37
        RNS.log("Invalid TX power configured for #{self}", RNS::LOG_ERROR)
        @validcfg = false
      end

      if @bandwidth < 7800 || @bandwidth > 1_625_000
        RNS.log("Invalid bandwidth configured for #{self}", RNS::LOG_ERROR)
        @validcfg = false
      end

      if @sf < 5 || @sf > 12
        RNS.log("Invalid spreading factor configured for #{self}", RNS::LOG_ERROR)
        @validcfg = false
      end

      if @cr < 5 || @cr > 8
        RNS.log("Invalid coding rate configured for #{self}", RNS::LOG_ERROR)
        @validcfg = false
      end

      if (sta = @st_alock) && (sta < 0.0 || sta > 100.0)
        RNS.log("Invalid short-term airtime limit configured for #{self}", RNS::LOG_ERROR)
        @validcfg = false
      end

      if (lta = @lt_alock) && (lta < 0.0 || lta > 100.0)
        RNS.log("Invalid long-term airtime limit configured for #{self}", RNS::LOG_ERROR)
        @validcfg = false
      end
    end

    def do_open_port
      if !@use_ble && !@use_tcp
        p = @port
        raise IO::Error.new("No port specified") unless p

        RNS.log("Opening serial port #{p}...", RNS::LOG_VERBOSE)

        o_noctty = {% if flag?(:darwin) %}0x20000{% else %}0o0400{% end %}
        fd = LibC.open(p, LibC::O_RDWR | o_noctty | LibC::O_NONBLOCK)
        raise IO::Error.new("Could not open serial port #{p}") if fd < 0

        flags = LibC.fcntl(fd, LibC::F_GETFL, 0)
        LibC.fcntl(fd, LibC::F_SETFL, flags & ~LibC::O_NONBLOCK)

        configure_termios(fd)
        LibSerial.tcflush(fd, SerialConstants::TCIOFLUSH)

        @fd = fd
        io = IO::FileDescriptor.new(fd)
        IO::FileDescriptor.set_blocking(fd, false)
        @io = io
      elsif @use_tcp
        host = @tcp_host
        if host
          @timeout = 1500
          tcp_conn = RNodeTCPConnection.new(self, host)
          @tcp = tcp_conn
          @io = nil # TCP uses its own read/write path
        end
      elsif @use_ble
        @timeout = 1250
        RNS.log("BLE connections are not yet supported in the Crystal port", RNS::LOG_ERROR)
      end
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
      tio.c_cflag = tio.c_cflag | SerialConstants::CS8
      tio.c_cflag = tio.c_cflag | SerialConstants::CLOCAL | SerialConstants::CREAD

      tio.c_cflag = tio.c_cflag & ~SerialConstants::CSTOPB
      tio.c_cflag = tio.c_cflag & ~SerialConstants::PARENB
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
        when  115200 then SerialConstants::B115200
        when  230400 then SerialConstants::B230400
        when   57600 then SerialConstants::B57600
        when   38400 then SerialConstants::B38400
        when   19200 then SerialConstants::B19200
        when    9600 then SerialConstants::B9600
        else              SerialConstants::B115200
        end
      {% end %}
    end

    def reset_radio_state
      @r_frequency = nil
      @r_bandwidth = nil
      @r_txpower = nil
      @r_sf = nil
      @r_cr = nil
      @r_state = nil
      @r_lock = nil
      @detected = false
    end

    def configure_device
      reset_radio_state
      sleep 2.seconds

      @running = true
      @read_fiber = spawn { read_loop }

      detect

      if @use_tcp
        detect_time = Time.utc.to_unix_f
        while !@detected && (Time.utc.to_unix_f < detect_time + 5.0)
          sleep 0.1.seconds
        end
        RNS.log("RNode detect timed out over TCP", RNS::LOG_ERROR) unless @detected
      elsif @use_ble
        detect_time = Time.utc.to_unix_f
        while !@detected && (Time.utc.to_unix_f < detect_time + 5.0)
          sleep 0.1.seconds
        end
        RNS.log("RNode detect timed out over BLE", RNS::LOG_ERROR) unless @detected
      else
        sleep 0.2.seconds
      end

      unless @detected
        RNS.log("Could not detect device for #{self}", RNS::LOG_ERROR)
        close_port
        return
      end

      if @platform == RNodeKISS::PLATFORM_ESP32 || @platform == RNodeKISS::PLATFORM_NRF52
        @display = true
      end

      if @use_tcp
        RNS.log("TCP connection to #{@tcp_host} is now open", RNS::LOG_VERBOSE)
      elsif @use_ble
        RNS.log("BLE connection to #{self} is now open", RNS::LOG_VERBOSE)
      else
        RNS.log("Serial port #{@port} is now open", RNS::LOG_VERBOSE)
      end

      RNS.log("Configuring RNode interface...", RNS::LOG_VERBOSE)
      init_radio

      if validate_radio_state
        @interface_ready = true
        RNS.log("#{self} is configured and powered up")
        sleep 0.3.seconds
        @online = true
      else
        RNS.log("After configuring #{self}, the reported radio parameters did not match your configuration.", RNS::LOG_ERROR)
        RNS.log("Make sure that your hardware actually supports the parameters specified in the configuration", RNS::LOG_ERROR)
        RNS.log("Aborting RNode startup", RNS::LOG_ERROR)
        close_port
      end
    end

    def init_radio
      set_frequency
      set_bandwidth
      set_tx_power
      set_spreading_factor
      set_coding_rate
      set_st_alock
      set_lt_alock
      set_radio_state(RNodeKISS::RADIO_STATE_ON)

      sleep 2.seconds if @use_ble
    end

    def detect
      kiss_command = Bytes[
        RNodeKISS::FEND, RNodeKISS::CMD_DETECT, RNodeKISS::DETECT_REQ, RNodeKISS::FEND,
        RNodeKISS::CMD_FW_VERSION, 0x00_u8, RNodeKISS::FEND,
        RNodeKISS::CMD_PLATFORM, 0x00_u8, RNodeKISS::FEND,
        RNodeKISS::CMD_MCU, 0x00_u8, RNodeKISS::FEND
      ]
      write_to_device(kiss_command)
    end

    def leave
      kiss_command = Bytes[RNodeKISS::FEND, RNodeKISS::CMD_LEAVE, 0xFF_u8, RNodeKISS::FEND]
      write_to_device(kiss_command)
    end

    def enable_external_framebuffer
      return unless @display
      kiss_command = Bytes[RNodeKISS::FEND, RNodeKISS::CMD_FB_EXT, 0x01_u8, RNodeKISS::FEND]
      write_to_device(kiss_command)
    end

    def disable_external_framebuffer
      return unless @display
      kiss_command = Bytes[RNodeKISS::FEND, RNodeKISS::CMD_FB_EXT, 0x00_u8, RNodeKISS::FEND]
      write_to_device(kiss_command)
    end

    def display_image(imagedata : Bytes)
      return unless @display
      lines = imagedata.size // 8
      lines.times do |line|
        line_start = line * FB_BYTES_PER_LINE
        line_end = line_start + FB_BYTES_PER_LINE
        line_data = imagedata[line_start...line_end]
        write_framebuffer(line, line_data)
      end
    end

    def write_framebuffer(line : Int32, line_data : Bytes)
      return unless @display
      data = IO::Memory.new(1 + line_data.size)
      data.write_byte(line.to_u8)
      data.write(line_data)
      escaped_data = RNodeKISS.escape(data.to_slice)
      kiss_command = IO::Memory.new(2 + escaped_data.size)
      kiss_command.write_byte(RNodeKISS::FEND)
      kiss_command.write_byte(RNodeKISS::CMD_FB_WRITE)
      kiss_command.write(escaped_data)
      kiss_command.write_byte(RNodeKISS::FEND)
      write_to_device(kiss_command.to_slice)
    end

    def read_framebuffer
      kiss_command = Bytes[RNodeKISS::FEND, RNodeKISS::CMD_FB_READ, 0x01_u8, RNodeKISS::FEND]
      write_to_device(kiss_command)
      @r_framebuffer_readtime = Time.utc.to_unix_f
    end

    def read_display
      kiss_command = Bytes[RNodeKISS::FEND, RNodeKISS::CMD_DISP_READ, 0x01_u8, RNodeKISS::FEND]
      write_to_device(kiss_command)
      @r_disp_readtime = Time.utc.to_unix_f
    end

    def start_display_updates
      unless @should_read_display
        @should_read_display = true
        spawn { display_update_job }
      end
    end

    def stop_display_updates
      @should_read_display = false
    end

    def hard_reset
      kiss_command = Bytes[RNodeKISS::FEND, RNodeKISS::CMD_RESET, 0xF8_u8, RNodeKISS::FEND]
      write_to_device(kiss_command)
      sleep 2.25.seconds
    end

    def set_frequency
      c1 = ((@frequency >> 24) & 0xFF).to_u8
      c2 = ((@frequency >> 16) & 0xFF).to_u8
      c3 = ((@frequency >> 8) & 0xFF).to_u8
      c4 = (@frequency & 0xFF).to_u8
      data = RNodeKISS.escape(Bytes[c1, c2, c3, c4])
      kiss_command = IO::Memory.new(2 + data.size)
      kiss_command.write_byte(RNodeKISS::FEND)
      kiss_command.write_byte(RNodeKISS::CMD_FREQUENCY)
      kiss_command.write(data)
      kiss_command.write_byte(RNodeKISS::FEND)
      write_to_device(kiss_command.to_slice)
    end

    def set_bandwidth
      c1 = ((@bandwidth >> 24) & 0xFF).to_u8
      c2 = ((@bandwidth >> 16) & 0xFF).to_u8
      c3 = ((@bandwidth >> 8) & 0xFF).to_u8
      c4 = (@bandwidth & 0xFF).to_u8
      data = RNodeKISS.escape(Bytes[c1, c2, c3, c4])
      kiss_command = IO::Memory.new(2 + data.size)
      kiss_command.write_byte(RNodeKISS::FEND)
      kiss_command.write_byte(RNodeKISS::CMD_BANDWIDTH)
      kiss_command.write(data)
      kiss_command.write_byte(RNodeKISS::FEND)
      write_to_device(kiss_command.to_slice)
    end

    def set_tx_power
      kiss_command = Bytes[RNodeKISS::FEND, RNodeKISS::CMD_TXPOWER, @txpower.to_u8, RNodeKISS::FEND]
      write_to_device(kiss_command)
    end

    def set_spreading_factor
      kiss_command = Bytes[RNodeKISS::FEND, RNodeKISS::CMD_SF, @sf.to_u8, RNodeKISS::FEND]
      write_to_device(kiss_command)
    end

    def set_coding_rate
      kiss_command = Bytes[RNodeKISS::FEND, RNodeKISS::CMD_CR, @cr.to_u8, RNodeKISS::FEND]
      write_to_device(kiss_command)
    end

    def set_st_alock
      sta = @st_alock
      return unless sta
      at = (sta * 100).to_i32
      c1 = ((at >> 8) & 0xFF).to_u8
      c2 = (at & 0xFF).to_u8
      data = RNodeKISS.escape(Bytes[c1, c2])
      kiss_command = IO::Memory.new(2 + data.size)
      kiss_command.write_byte(RNodeKISS::FEND)
      kiss_command.write_byte(RNodeKISS::CMD_ST_ALOCK)
      kiss_command.write(data)
      kiss_command.write_byte(RNodeKISS::FEND)
      write_to_device(kiss_command.to_slice)
    end

    def set_lt_alock
      lta = @lt_alock
      return unless lta
      at = (lta * 100).to_i32
      c1 = ((at >> 8) & 0xFF).to_u8
      c2 = (at & 0xFF).to_u8
      data = RNodeKISS.escape(Bytes[c1, c2])
      kiss_command = IO::Memory.new(2 + data.size)
      kiss_command.write_byte(RNodeKISS::FEND)
      kiss_command.write_byte(RNodeKISS::CMD_LT_ALOCK)
      kiss_command.write(data)
      kiss_command.write_byte(RNodeKISS::FEND)
      write_to_device(kiss_command.to_slice)
    end

    def set_radio_state(state : UInt8)
      @state = state
      kiss_command = Bytes[RNodeKISS::FEND, RNodeKISS::CMD_RADIO_STATE, state, RNodeKISS::FEND]
      write_to_device(kiss_command)
    end

    def validate_firmware
      if @maj_version > REQUIRED_FW_VER_MAJ
        @firmware_ok = true
      elsif @maj_version >= REQUIRED_FW_VER_MAJ && @min_version >= REQUIRED_FW_VER_MIN
        @firmware_ok = true
      end

      return if @firmware_ok

      RNS.log("The firmware version of the connected RNode is #{@maj_version}.#{@min_version}", RNS::LOG_ERROR)
      RNS.log("This version of Reticulum requires at least version #{REQUIRED_FW_VER_MAJ}.#{REQUIRED_FW_VER_MIN}", RNS::LOG_ERROR)
      RNS.log("Please update your RNode firmware with rnodeconf from https://github.com/markqvist/rnodeconfigutil/")
      RNS.panic
    end

    def validate_radio_state : Bool
      RNS.log("Waiting for radio configuration validation for #{self}...", RNS::LOG_VERBOSE)
      if @use_ble
        sleep 1.0.seconds
      elsif @use_tcp
        sleep 1.5.seconds
      else
        sleep 0.25.seconds
      end

      @validcfg = true

      if (rf = @r_frequency) && (@frequency - rf).abs > 100
        RNS.log("Frequency mismatch", RNS::LOG_ERROR)
        @validcfg = false
      end
      if @bandwidth != @r_bandwidth
        RNS.log("Bandwidth mismatch", RNS::LOG_ERROR)
        @validcfg = false
      end
      if @txpower != @r_txpower
        RNS.log("TX power mismatch", RNS::LOG_ERROR)
        @validcfg = false
      end
      if @sf != @r_sf
        RNS.log("Spreading factor mismatch", RNS::LOG_ERROR)
        @validcfg = false
      end
      if @state != @r_state
        RNS.log("Radio state mismatch", RNS::LOG_ERROR)
        @validcfg = false
      end

      @validcfg
    end

    def update_bitrate
      rsf = @r_sf
      rcr = @r_cr
      rbw = @r_bandwidth
      return unless rsf && rcr && rbw

      @bitrate = (rsf * ((4.0 / rcr) / (2.0 ** rsf / (rbw / 1000.0))) * 1000).to_i64
      @bitrate_kbps = (@bitrate / 1000.0).round(2)
      RNS.log("#{self} On-air bitrate is now #{@bitrate_kbps} kbps", RNS::LOG_VERBOSE)
    rescue
      @bitrate = 0_i64
    end

    def process_incoming(data : Bytes)
      @rxb += data.size.to_i64
      if cb = @inbound_callback
        cb.call(data, self)
      end
      @r_stat_rssi = nil
      @r_stat_snr = nil
    end

    def process_outgoing(data : Bytes)
      return unless @online

      if @interface_ready
        if @flow_control
          @interface_ready = false
        end

        if (cs = @id_callsign) && data == cs
          @first_tx = nil
        else
          @first_tx = Time.utc.to_unix_f if @first_tx.nil?
        end

        escaped = RNodeKISS.escape(data)
        frame = IO::Memory.new(2 + escaped.size)
        frame.write_byte(RNodeKISS::FEND)
        frame.write_byte(RNodeKISS::CMD_DATA)
        frame.write(escaped)
        frame.write_byte(RNodeKISS::FEND)

        write_to_device(frame.to_slice)
        @txb += data.size.to_i64
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

    # Main KISS read loop — processes incoming bytes from RNode device.
    # Handles all KISS command types with escape sequence processing.
    private def read_loop
      in_frame = false
      escape = false
      command = RNodeKISS::CMD_UNKNOWN
      data_buffer = IO::Memory.new(1024)
      command_buffer = IO::Memory.new(64)
      last_read_ms = (Time.utc.to_unix_f * 1000).to_i64
      buf = Bytes.new(1)

      while @running
        byte_available = false
        byte = 0_u8

        if @use_tcp
          tcp_conn = @tcp
          break unless tcp_conn && tcp_conn.is_open
          if tcp_conn.in_waiting
            data = tcp_conn.read(1)
            if data.size > 0
              byte = data[0]
              byte_available = true
            end
          end
        else
          io = @io
          break unless io
          begin
            bytes_read = io.read(buf)
            if bytes_read > 0
              byte = buf[0]
              byte_available = true
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
          end
        end

        if byte_available
          last_read_ms = (Time.utc.to_unix_f * 1000).to_i64

          if in_frame && byte == RNodeKISS::FEND && command == RNodeKISS::CMD_DATA
            in_frame = false
            if data_buffer.pos > 0
              process_incoming(data_buffer.to_slice.dup)
            end
            data_buffer = IO::Memory.new(1024)
            command_buffer = IO::Memory.new(64)

          elsif byte == RNodeKISS::FEND
            in_frame = true
            command = RNodeKISS::CMD_UNKNOWN
            data_buffer = IO::Memory.new(1024)
            command_buffer = IO::Memory.new(64)

          elsif in_frame && data_buffer.pos < hw_mtu_value
            if data_buffer.pos == 0 && command == RNodeKISS::CMD_UNKNOWN
              command = byte

            elsif command == RNodeKISS::CMD_DATA
              if byte == RNodeKISS::FESC
                escape = true
              else
                if escape
                  byte = RNodeKISS::FEND if byte == RNodeKISS::TFEND
                  byte = RNodeKISS::FESC if byte == RNodeKISS::TFESC
                  escape = false
                end
                data_buffer.write_byte(byte)
              end

            elsif command == RNodeKISS::CMD_FREQUENCY
              process_escaped_command_byte(byte, escape, command_buffer) do |esc|
                escape = esc
              end
              if command_buffer.pos == 4
                cb = command_buffer.to_slice
                @r_frequency = (cb[0].to_i64 << 24) | (cb[1].to_i64 << 16) | (cb[2].to_i64 << 8) | cb[3].to_i64
                RNS.log("#{self} Radio reporting frequency is #{@r_frequency.not_nil! / 1_000_000.0} MHz", RNS::LOG_DEBUG)
                update_bitrate
              end

            elsif command == RNodeKISS::CMD_BANDWIDTH
              process_escaped_command_byte(byte, escape, command_buffer) do |esc|
                escape = esc
              end
              if command_buffer.pos == 4
                cb = command_buffer.to_slice
                @r_bandwidth = (cb[0].to_i64 << 24) | (cb[1].to_i64 << 16) | (cb[2].to_i64 << 8) | cb[3].to_i64
                RNS.log("#{self} Radio reporting bandwidth is #{@r_bandwidth.not_nil! / 1000.0} KHz", RNS::LOG_DEBUG)
                update_bitrate
              end

            elsif command == RNodeKISS::CMD_TXPOWER
              @r_txpower = byte.to_i32
              RNS.log("#{self} Radio reporting TX power is #{@r_txpower} dBm", RNS::LOG_DEBUG)

            elsif command == RNodeKISS::CMD_SF
              @r_sf = byte.to_i32
              RNS.log("#{self} Radio reporting spreading factor is #{@r_sf}", RNS::LOG_DEBUG)
              update_bitrate

            elsif command == RNodeKISS::CMD_CR
              @r_cr = byte.to_i32
              RNS.log("#{self} Radio reporting coding rate is #{@r_cr}", RNS::LOG_DEBUG)
              update_bitrate

            elsif command == RNodeKISS::CMD_RADIO_STATE
              @r_state = byte
              unless byte != 0
                RNS.log("#{self} Radio reporting state is offline", RNS::LOG_DEBUG)
              end

            elsif command == RNodeKISS::CMD_RADIO_LOCK
              @r_lock = byte

            elsif command == RNodeKISS::CMD_FW_VERSION
              process_escaped_command_byte(byte, escape, command_buffer) do |esc|
                escape = esc
              end
              if command_buffer.pos == 2
                cb = command_buffer.to_slice
                @maj_version = cb[0].to_i32
                @min_version = cb[1].to_i32
                validate_firmware
              end

            elsif command == RNodeKISS::CMD_STAT_RX
              process_escaped_command_byte(byte, escape, command_buffer) do |esc|
                escape = esc
              end
              if command_buffer.pos == 4
                cb = command_buffer.to_slice
                @r_stat_rx = (cb[0].to_i64 << 24) | (cb[1].to_i64 << 16) | (cb[2].to_i64 << 8) | cb[3].to_i64
              end

            elsif command == RNodeKISS::CMD_STAT_TX
              process_escaped_command_byte(byte, escape, command_buffer) do |esc|
                escape = esc
              end
              if command_buffer.pos == 4
                cb = command_buffer.to_slice
                @r_stat_tx = (cb[0].to_i64 << 24) | (cb[1].to_i64 << 16) | (cb[2].to_i64 << 8) | cb[3].to_i64
              end

            elsif command == RNodeKISS::CMD_STAT_RSSI
              @r_stat_rssi = byte.to_i32 - RSSI_OFFSET

            elsif command == RNodeKISS::CMD_STAT_SNR
              # Signed byte interpretation
              signed = byte.to_i8
              @r_stat_snr = signed.to_f64 * 0.25
              begin
                if rsf = @r_sf
                  sfs = rsf - 7
                  snr = @r_stat_snr.not_nil!
                  q_snr_min = Q_SNR_MIN_BASE - sfs * Q_SNR_STEP
                  q_snr_span = Q_SNR_MAX - q_snr_min
                  quality = ((snr - q_snr_min) / q_snr_span) * 100.0
                  quality = quality.clamp(0.0, 100.0).round(1)
                  @r_stat_q = quality
                end
              rescue
              end

            elsif command == RNodeKISS::CMD_ST_ALOCK
              process_escaped_command_byte(byte, escape, command_buffer) do |esc|
                escape = esc
              end
              if command_buffer.pos == 2
                cb = command_buffer.to_slice
                at = (cb[0].to_i32 << 8) | cb[1].to_i32
                @r_st_alock = at / 100.0
                RNS.log("#{self} Radio reporting short-term airtime limit is #{@r_st_alock}%", RNS::LOG_DEBUG)
              end

            elsif command == RNodeKISS::CMD_LT_ALOCK
              process_escaped_command_byte(byte, escape, command_buffer) do |esc|
                escape = esc
              end
              if command_buffer.pos == 2
                cb = command_buffer.to_slice
                at = (cb[0].to_i32 << 8) | cb[1].to_i32
                @r_lt_alock = at / 100.0
                RNS.log("#{self} Radio reporting long-term airtime limit is #{@r_lt_alock}%", RNS::LOG_DEBUG)
              end

            elsif command == RNodeKISS::CMD_STAT_CHTM
              process_escaped_command_byte(byte, escape, command_buffer) do |esc|
                escape = esc
              end
              if command_buffer.pos == 11
                cb = command_buffer.to_slice
                ats = (cb[0].to_i32 << 8) | cb[1].to_i32
                atl = (cb[2].to_i32 << 8) | cb[3].to_i32
                cus = (cb[4].to_i32 << 8) | cb[5].to_i32
                cul = (cb[6].to_i32 << 8) | cb[7].to_i32
                crs = cb[8].to_i32
                nfl = cb[9].to_i32
                ntf = cb[10]

                @r_airtime_short = ats / 100.0
                @r_airtime_long = atl / 100.0
                @r_channel_load_short = cus / 100.0
                @r_channel_load_long = cul / 100.0
                @r_current_rssi = crs - RSSI_OFFSET
                @r_noise_floor = nfl - RSSI_OFFSET

                if ntf == 0xFF_u8
                  @r_interference = nil
                else
                  @r_interference = ntf.to_i32 - RSSI_OFFSET
                  @r_interference_l = [Time.utc.to_unix_f, @r_interference.not_nil!.to_f64]
                end

                if ri = @r_interference
                  RNS.log("#{self} Radio detected interference at #{ri} dBm", RNS::LOG_DEBUG)
                end
              end

            elsif command == RNodeKISS::CMD_STAT_PHYPRM
              process_escaped_command_byte(byte, escape, command_buffer) do |esc|
                escape = esc
              end
              if command_buffer.pos == 12
                cb = command_buffer.to_slice
                lst = ((cb[0].to_i32 << 8) | cb[1].to_i32) / 1000.0
                lsr = (cb[2].to_i32 << 8) | cb[3].to_i32
                prs = (cb[4].to_i32 << 8) | cb[5].to_i32
                prt = (cb[6].to_i32 << 8) | cb[7].to_i32
                cst = (cb[8].to_i32 << 8) | cb[9].to_i32
                dft = (cb[10].to_i32 << 8) | cb[11].to_i32

                if lst != @r_symbol_time_ms || lsr != @r_symbol_rate || prs != @r_preamble_symbols || prt != @r_premable_time_ms || cst != @r_csma_slot_time_ms || dft != @r_csma_difs_ms
                  @r_symbol_time_ms = lst
                  @r_symbol_rate = lsr
                  @r_preamble_symbols = prs
                  @r_premable_time_ms = prt
                  @r_csma_slot_time_ms = cst
                  @r_csma_difs_ms = dft
                  RNS.log("#{self} Radio reporting symbol time is #{@r_symbol_time_ms.not_nil!.round(2)}ms (#{@r_symbol_rate} baud)", RNS::LOG_DEBUG)
                  RNS.log("#{self} Radio reporting preamble is #{@r_preamble_symbols} symbols (#{@r_premable_time_ms}ms)", RNS::LOG_DEBUG)
                  RNS.log("#{self} Radio reporting CSMA slot time is #{@r_csma_slot_time_ms}ms", RNS::LOG_DEBUG)
                  RNS.log("#{self} Radio reporting DIFS time is #{@r_csma_difs_ms}ms", RNS::LOG_DEBUG)
                end
              end

            elsif command == RNodeKISS::CMD_STAT_CSMA
              process_escaped_command_byte(byte, escape, command_buffer) do |esc|
                escape = esc
              end
              if command_buffer.pos == 3
                cb = command_buffer.to_slice
                cbw = cb[0]
                cbl = cb[1]
                cbh = cb[2]
                if cbw != @r_csma_cw_band || cbl != @r_csma_cw_min || cbh != @r_csma_cw_max
                  @r_csma_cw_band = cbw
                  @r_csma_cw_min = cbl
                  @r_csma_cw_max = cbh
                end
              end

            elsif command == RNodeKISS::CMD_STAT_BAT
              process_escaped_command_byte(byte, escape, command_buffer) do |esc|
                escape = esc
              end
              if command_buffer.pos == 2
                cb = command_buffer.to_slice
                bat_percent = cb[1].to_i32
                bat_percent = 100 if bat_percent > 100
                bat_percent = 0 if bat_percent < 0
                @r_battery_state = cb[0]
                @r_battery_percent = bat_percent
              end

            elsif command == RNodeKISS::CMD_STAT_TEMP
              process_escaped_command_byte(byte, escape, command_buffer) do |esc|
                escape = esc
              end
              if command_buffer.pos == 1
                cb = command_buffer.to_slice
                temp = cb[0].to_i32 - 120
                if temp >= -30 && temp <= 90
                  @r_temperature = temp
                else
                  @r_temperature = nil
                end
                @cpu_temp = @r_temperature
              end

            elsif command == RNodeKISS::CMD_RANDOM
              @r_random = byte

            elsif command == RNodeKISS::CMD_PLATFORM
              @platform = byte

            elsif command == RNodeKISS::CMD_MCU
              @mcu = byte

            elsif command == RNodeKISS::CMD_ERROR
              if byte == RNodeKISS::ERROR_INITRADIO
                RNS.log("#{self} hardware initialisation error (code #{RNS.hexrep(Bytes[byte])})", RNS::LOG_ERROR)
                raise IO::Error.new("Radio initialisation failure")
              elsif byte == RNodeKISS::ERROR_TXFAILED
                RNS.log("#{self} hardware TX error (code #{RNS.hexrep(Bytes[byte])})", RNS::LOG_ERROR)
                raise IO::Error.new("Hardware transmit failure")
              elsif byte == RNodeKISS::ERROR_MEMORY_LOW
                RNS.log("#{self} hardware error (code #{RNS.hexrep(Bytes[byte])}): Memory exhausted", RNS::LOG_ERROR)
                @hw_errors << {error: RNodeKISS::ERROR_MEMORY_LOW, description: "Memory exhausted on connected device"}
              elsif byte == RNodeKISS::ERROR_MODEM_TIMEOUT
                RNS.log("#{self} hardware error (code #{RNS.hexrep(Bytes[byte])}): Modem communication timed out", RNS::LOG_ERROR)
                @hw_errors << {error: RNodeKISS::ERROR_MODEM_TIMEOUT, description: "Modem communication timed out on connected device"}
              else
                RNS.log("#{self} hardware error (code #{RNS.hexrep(Bytes[byte])})", RNS::LOG_ERROR)
                raise IO::Error.new("Unknown hardware failure")
              end

            elsif command == RNodeKISS::CMD_RESET
              if byte == 0xF8_u8
                if @platform == RNodeKISS::PLATFORM_ESP32
                  if @online
                    RNS.log("Detected reset while device was online, reinitialising device...", RNS::LOG_ERROR)
                    raise IO::Error.new("ESP32 reset")
                  end
                end
              end

            elsif command == RNodeKISS::CMD_READY
              process_queue

            elsif command == RNodeKISS::CMD_FB_READ
              process_escaped_command_byte(byte, escape, command_buffer) do |esc|
                escape = esc
              end
              if command_buffer.pos == 512
                @r_framebuffer_latency = Time.utc.to_unix_f - @r_framebuffer_readtime
                @r_framebuffer = command_buffer.to_slice.dup
              end

            elsif command == RNodeKISS::CMD_DISP_READ
              process_escaped_command_byte(byte, escape, command_buffer) do |esc|
                escape = esc
              end
              if command_buffer.pos == 1024
                @r_disp_latency = Time.utc.to_unix_f - @r_disp_readtime
                @r_disp = command_buffer.to_slice.dup
              end

            elsif command == RNodeKISS::CMD_DETECT
              if byte == RNodeKISS::DETECT_RESP
                @detected = true
              else
                @detected = false
              end
            end
          end
        else
          # No data available
          time_since_last = (Time.utc.to_unix_f * 1000).to_i64 - last_read_ms
          if data_buffer.pos > 0 && time_since_last > @timeout
            data_buffer = IO::Memory.new(1024)
            in_frame = false
            command = RNodeKISS::CMD_UNKNOWN
            escape = false
          end

          # ID beacon
          if (idi = @id_interval) && (cs = @id_callsign)
            if ftx = @first_tx
              if Time.utc.to_unix_f > ftx + idi
                RNS.log("Interface #{self} is transmitting beacon data: #{String.new(cs)}", RNS::LOG_DEBUG)
                process_outgoing(cs)
              end
            end
          end

          # TCP keepalive
          if @use_tcp
            tcp_conn = @tcp
            if tcp_conn && tcp_conn.connected
              if Time.utc.to_unix_f > tcp_conn.last_write + RNodeTCPConnection::ACTIVITY_KEEPALIVE
                detect
              end
            end
          end

          sleep 0.08.seconds
        end
      end
    rescue ex
      @online = false
      RNS.log("A serial port error occurred, the contained exception was: #{ex.message}", RNS::LOG_ERROR)
      RNS.log("The interface #{self} experienced an unrecoverable error and is now offline.", RNS::LOG_ERROR)

      if Reticulum.panic_on_interface_error
        RNS.panic
      end

      RNS.log("Reticulum will attempt to reconnect the interface periodically.", RNS::LOG_ERROR)
    ensure
      @online = false
      close_port

      if !@detached && !@reconnecting && @running
        spawn { reconnect_port }
      end
    end

    # Process a byte in a multi-byte KISS command with escape handling.
    private def process_escaped_command_byte(byte : UInt8, escape : Bool, buffer : IO::Memory, &block : Bool -> Nil)
      if byte == RNodeKISS::FESC
        block.call(true)
      else
        actual = byte
        if escape
          actual = RNodeKISS::FEND if byte == RNodeKISS::TFEND
          actual = RNodeKISS::FESC if byte == RNodeKISS::TFESC
          block.call(false)
        end
        buffer.write_byte(actual)
      end
    end

    def reconnect_port
      @reconnecting = true
      while !@online && !@detached
        begin
          sleep 5.seconds
          RNS.log("Attempting to reconnect serial port #{@port} for #{self}...", RNS::LOG_VERBOSE)
          do_open_port
          if @io || @tcp
            configure_device
          end
        rescue ex
          RNS.log("Error while reconnecting port, the contained exception was: #{ex.message}", RNS::LOG_ERROR)
        end
      end
      @reconnecting = false
      RNS.log("Reconnected port for #{self}") if @online
    end

    def detach
      @detached = true
      begin
        disable_external_framebuffer
        set_radio_state(RNodeKISS::RADIO_STATE_OFF)
        leave
      rescue ex
        RNS.log("An error occurred while detaching #{self}: #{ex.message}", RNS::LOG_ERROR)
      end

      if @use_tcp
        sleep 0.5.seconds
        @tcp.try(&.close)
      end

      close_port
    end

    def should_ingress_limit? : Bool
      false
    end

    def get_battery_state : UInt8
      @r_battery_state
    end

    def get_battery_state_string : String
      case @r_battery_state
      when BATTERY_STATE_CHARGED     then "charged"
      when BATTERY_STATE_CHARGING    then "charging"
      when BATTERY_STATE_DISCHARGING then "discharging"
      else                                "unknown"
      end
    end

    def get_battery_percent : Int32
      @r_battery_percent
    end

    def close_port
      if io = @io
        begin
          io.close unless io.responds_to?(:closed?) && io.as(IO::FileDescriptor).closed?
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
      @tcp.try(&.close)
    end

    # Write raw bytes to the device (serial or TCP)
    private def write_to_device(data : Bytes)
      if @use_tcp
        @tcp.try(&.write(data))
      elsif io = @io
        io.write(data)
        if io.responds_to?(:flush)
          io.flush
        end
      end
    end

    private def display_update_job
      while @should_read_display
        read_display
        sleep @read_display_interval.seconds
      end
    end

    private def hw_mtu_value : Int32
      @hw_mtu || 508
    end

    def running? : Bool
      @running
    end

    def running=(v : Bool)
      @running = v
    end

    # Expose IO for testing
    def device_io : IO?
      @io
    end

    def device_io=(io : IO?)
      @io = io
    end

    def to_s(io : IO)
      io << "RNodeInterface[" << @name << "]"
    end
  end
end
