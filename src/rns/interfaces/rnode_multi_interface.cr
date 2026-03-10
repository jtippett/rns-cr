module RNS
  # Extended KISS command constants for RNode Multi-interface hardware communication.
  # Supplements the base RNodeKISS constants with multi-interface selection commands.
  module RNodeMultiKISS
    # Frame delimiters (same as base KISS)
    FEND  = KISS::FEND
    FESC  = KISS::FESC
    TFEND = KISS::TFEND
    TFESC = KISS::TFESC

    # Re-export base RNode KISS commands
    CMD_UNKNOWN     = RNodeKISS::CMD_UNKNOWN
    CMD_DATA        = RNodeKISS::CMD_DATA
    CMD_FREQUENCY   = RNodeKISS::CMD_FREQUENCY
    CMD_BANDWIDTH   = RNodeKISS::CMD_BANDWIDTH
    CMD_TXPOWER     = RNodeKISS::CMD_TXPOWER
    CMD_SF          = RNodeKISS::CMD_SF
    CMD_CR          = RNodeKISS::CMD_CR
    CMD_RADIO_STATE = RNodeKISS::CMD_RADIO_STATE
    CMD_RADIO_LOCK  = RNodeKISS::CMD_RADIO_LOCK
    CMD_ST_ALOCK    = RNodeKISS::CMD_ST_ALOCK
    CMD_LT_ALOCK    = RNodeKISS::CMD_LT_ALOCK
    CMD_DETECT      = RNodeKISS::CMD_DETECT
    CMD_LEAVE       = RNodeKISS::CMD_LEAVE
    CMD_READY       = RNodeKISS::CMD_READY
    CMD_STAT_RX     = RNodeKISS::CMD_STAT_RX
    CMD_STAT_TX     = RNodeKISS::CMD_STAT_TX
    CMD_STAT_RSSI   = RNodeKISS::CMD_STAT_RSSI
    CMD_STAT_SNR    = RNodeKISS::CMD_STAT_SNR
    CMD_STAT_CHTM   = RNodeKISS::CMD_STAT_CHTM
    CMD_STAT_PHYPRM = RNodeKISS::CMD_STAT_PHYPRM
    CMD_BLINK       = RNodeKISS::CMD_BLINK
    CMD_RANDOM      = RNodeKISS::CMD_RANDOM
    CMD_FB_EXT      = RNodeKISS::CMD_FB_EXT
    CMD_FB_READ     = RNodeKISS::CMD_FB_READ
    CMD_FB_WRITE    = RNodeKISS::CMD_FB_WRITE
    CMD_BT_CTRL     = RNodeKISS::CMD_BT_CTRL
    CMD_PLATFORM    = RNodeKISS::CMD_PLATFORM
    CMD_MCU         = RNodeKISS::CMD_MCU
    CMD_FW_VERSION  = RNodeKISS::CMD_FW_VERSION
    CMD_ROM_READ    = RNodeKISS::CMD_ROM_READ
    CMD_RESET       = RNodeKISS::CMD_RESET
    CMD_ERROR       = RNodeKISS::CMD_ERROR

    ERROR_INITRADIO     = RNodeKISS::ERROR_INITRADIO
    ERROR_TXFAILED      = RNodeKISS::ERROR_TXFAILED
    ERROR_EEPROM_LOCKED = RNodeKISS::ERROR_EEPROM_LOCKED

    DETECT_REQ  = RNodeKISS::DETECT_REQ
    DETECT_RESP = RNodeKISS::DETECT_RESP

    RADIO_STATE_OFF = RNodeKISS::RADIO_STATE_OFF
    RADIO_STATE_ON  = RNodeKISS::RADIO_STATE_ON
    RADIO_STATE_ASK = RNodeKISS::RADIO_STATE_ASK

    PLATFORM_AVR   = RNodeKISS::PLATFORM_AVR
    PLATFORM_ESP32 = RNodeKISS::PLATFORM_ESP32
    PLATFORM_NRF52 = RNodeKISS::PLATFORM_NRF52

    # Chip types
    SX127X = 0x00_u8
    SX1276 = 0x01_u8
    SX1278 = 0x02_u8
    SX126X = 0x10_u8
    SX1262 = 0x11_u8
    SX128X = 0x20_u8
    SX1280 = 0x21_u8

    # Multi-interface selection command
    CMD_SEL_INT   = 0x1F_u8
    CMD_INTERFACES = 0x71_u8

    # Per-interface data commands (virtual port indices)
    CMD_INT0_DATA  = 0x00_u8
    CMD_INT1_DATA  = 0x10_u8
    CMD_INT2_DATA  = 0x20_u8
    CMD_INT3_DATA  = 0x70_u8
    CMD_INT4_DATA  = 0x75_u8
    CMD_INT5_DATA  = 0x90_u8
    CMD_INT6_DATA  = 0xA0_u8
    CMD_INT7_DATA  = 0xB0_u8
    CMD_INT8_DATA  = 0xC0_u8
    CMD_INT9_DATA  = 0xD0_u8
    CMD_INT10_DATA = 0xE0_u8
    CMD_INT11_DATA = 0xF0_u8

    INT_DATA_CMDS = [
      CMD_INT0_DATA, CMD_INT1_DATA, CMD_INT2_DATA, CMD_INT3_DATA,
      CMD_INT4_DATA, CMD_INT5_DATA, CMD_INT6_DATA, CMD_INT7_DATA,
      CMD_INT8_DATA, CMD_INT9_DATA, CMD_INT10_DATA, CMD_INT11_DATA,
    ]

    def self.interface_type_to_str(interface_type : UInt8) : String
      case interface_type
      when SX126X, SX1262
        "SX126X"
      when SX127X, SX1276, SX1278
        "SX127X"
      when SX128X, SX1280
        "SX128X"
      else
        "SX127X"
      end
    end

    def self.is_data_cmd?(cmd : UInt8) : Bool
      INT_DATA_CMDS.includes?(cmd)
    end

    def self.escape(data : Bytes) : Bytes
      KISS.escape(data)
    end
  end

  # Subinterface configuration record
  record SubIntConfig,
    name : String,
    vport : Int32,
    frequency : Int64?,
    bandwidth : Int64?,
    txpower : Int32?,
    sf : Int32?,
    cr : Int32?,
    flow_control : Bool,
    st_alock : Float64?,
    lt_alock : Float64?,
    outgoing : Bool

  # RNode Multi-interface for dual-radio LoRa setups.
  # Ports RNS/Interfaces/RNodeMultiInterface.py.
  # Manages multiple RNodeSubInterfaces through a single serial connection.
  class RNodeMultiInterface < Interface
    MAX_CHUNK         = 32768
    DEFAULT_IFAC_SIZE = 8
    CALLSIGN_MAX_LEN  = 32
    REQUIRED_FW_VER_MAJ = 1
    REQUIRED_FW_VER_MIN = 74
    RECONNECT_WAIT      = 5
    MAX_SUBINTERFACES   = 11

    FB_PIXEL_WIDTH     = 64
    FB_BITS_PER_PIXEL  = 1
    FB_PIXELS_PER_BYTE = 8 // FB_BITS_PER_PIXEL
    FB_BYTES_PER_LINE  = FB_PIXEL_WIDTH // FB_PIXELS_PER_BYTE

    property port : String
    property speed : Int32 = 115200
    property databits : Int32 = 8
    property stopbits : Int32 = 1
    property timeout : Int32 = 100
    property clients : Int32 = 0
    property selected_index : Int32 = 0

    property detected : Bool = false
    property firmware_ok : Bool = false
    property maj_version : Int32 = 0
    property min_version : Int32 = 0
    property platform : UInt8? = nil
    property display : Bool? = nil
    property mcu : UInt8? = nil
    property reconnecting : Bool = false

    property r_stat_rx : UInt32? = nil
    property r_stat_tx : UInt32? = nil
    property r_stat_rssi : Int32? = nil
    property r_stat_snr : Float64? = nil
    property r_st_alock : Float64? = nil
    property r_lt_alock : Float64? = nil
    property r_random : UInt8? = nil
    property r_airtime_short : Float64 = 0.0
    property r_airtime_long : Float64 = 0.0
    property r_channel_load_short : Float64 = 0.0
    property r_channel_load_long : Float64 = 0.0

    property interface_ready : Bool = false
    property last_id : Float64 = 0.0
    property first_tx : Float64? = nil
    property packet_queue : Array(Bytes) = [] of Bytes

    property subinterfaces : Array(RNodeSubInterface?) = Array(RNodeSubInterface?).new(MAX_SUBINTERFACES, nil)
    property subinterface_types : Array(String) = [] of String
    property subint_config : Array(SubIntConfig) = [] of SubIntConfig

    property should_id : Bool = false
    property id_callsign : Bytes? = nil
    property id_interval : Int32? = nil

    @serial : IO? = nil
    @write_mutex : Mutex = Mutex.new

    def initialize(configuration : Hash(String, String | Hash(String, String)))
      super()

      name = configuration["name"].as(String)
      port_val = configuration["port"]?
      raise ArgumentError.new("No port specified for #{name}") unless port_val
      @port = port_val.as(String)
      @name = name
      @hw_mtu = 508
      @online = false
      @mode = Interface::MODE_FULL

      # Parse subinterface configurations
      enabled = configuration["enabled"]?.try { |v| v == "true" } || false
      subint_configs = [] of SubIntConfig

      configuration.each do |key, value|
        next unless value.is_a?(Hash(String, String))
        subinterface_config = value
        sub_enabled = subinterface_config["interface_enabled"]?.try { |v| v == "true" } || enabled
        next unless sub_enabled

        vport = subinterface_config["vport"]?.try(&.to_i) || 0
        frequency = subinterface_config["frequency"]?.try(&.to_i64)
        bandwidth = subinterface_config["bandwidth"]?.try(&.to_i64)
        txpower = subinterface_config["txpower"]?.try(&.to_i)
        sf = subinterface_config["spreadingfactor"]?.try(&.to_i)
        cr = subinterface_config["codingrate"]?.try(&.to_i)
        flow_control = subinterface_config["flow_control"]?.try { |v| v == "true" } || false
        st_alock = subinterface_config["airtime_limit_short"]?.try(&.to_f64)
        lt_alock = subinterface_config["airtime_limit_long"]?.try(&.to_f64)
        outgoing = subinterface_config["outgoing"]?.try { |v| v != "false" } || true

        subint_configs << SubIntConfig.new(
          name: key,
          vport: vport,
          frequency: frequency,
          bandwidth: bandwidth,
          txpower: txpower,
          sf: sf,
          cr: cr,
          flow_control: flow_control,
          st_alock: st_alock,
          lt_alock: lt_alock,
          outgoing: outgoing,
        )
      end

      raise ArgumentError.new("No subinterfaces configured for #{name}") if subint_configs.empty?
      @subint_config = subint_configs

      # ID beacon configuration
      id_interval = configuration["id_interval"]?.try { |v| v.as(String).to_i }
      id_callsign = configuration["id_callsign"]?.try { |v| v.as(String) }

      if id_interval && id_callsign
        callsign_bytes = id_callsign.to_slice
        if callsign_bytes.size <= CALLSIGN_MAX_LEN
          @should_id = true
          @id_callsign = callsign_bytes.dup
          @id_interval = id_interval
        else
          RNS.log("The encoded ID callsign for #{self} exceeds the max length of #{CALLSIGN_MAX_LEN} bytes.", RNS::LOG_ERROR)
          raise ArgumentError.new("The configuration for #{self} contains errors, interface is offline")
        end
      end
    end

    # Simplified constructor for testing without config hash
    def initialize(@name : String, @port : String)
      super()
      @hw_mtu = 508
      @online = false
      @mode = Interface::MODE_FULL
    end

    def start
      open_port
      if serial = @serial
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

    def open_port
      RNS.log("Opening serial port #{@port}...")
      fd = LibC.open(@port, LibC::O_RDWR | LibC::O_NOCTTY | LibC::O_NONBLOCK)
      raise IO::Error.new("Could not open serial port #{@port}") if fd < 0

      configure_termios(fd)
      @serial = IO::FileDescriptor.new(fd, blocking: false)
    end

    private def configure_termios(fd : Int32)
      termios = LibC::Termios.new
      LibC.tcgetattr(fd, pointerof(termios))

      # Raw mode
      termios.c_iflag = LibC::TcflagT.new(0)
      termios.c_oflag = LibC::TcflagT.new(0)
      termios.c_lflag = LibC::TcflagT.new(0)

      # 8N1
      termios.c_cflag = LibC::TcflagT.new(SerialConstants::CS8 | SerialConstants::CREAD | SerialConstants::CLOCAL)

      # Speed 115200
      LibSerial.cfsetispeed(pointerof(termios).as(Void*), SerialConstants::B115200)
      LibSerial.cfsetospeed(pointerof(termios).as(Void*), SerialConstants::B115200)

      # Non-blocking
      termios.c_cc[SerialConstants::VMIN] = 0_u8
      termios.c_cc[SerialConstants::VTIME] = 0_u8

      LibC.tcsetattr(fd, LibC::TCSANOW, pointerof(termios))
      LibSerial.tcflush(fd, SerialConstants::TCIOFLUSH)
    end

    def configure_device
      sleep(2.0)

      spawn { read_loop }

      detect
      sleep(0.2)

      if !@detected
        RNS.log("Could not detect device for #{self}", RNS::LOG_ERROR)
        @serial.try(&.close)
        return
      end

      if @platform == RNodeMultiKISS::PLATFORM_ESP32 || @platform == RNodeMultiKISS::PLATFORM_NRF52
        @display = true
      end

      RNS.log("Serial port #{@port} is now open")
      RNS.log("Creating subinterfaces...", RNS::LOG_VERBOSE)

      @subint_config.each do |subint|
        vport = subint.vport
        if vport < @subinterface_types.size
          interface = RNodeSubInterface.new(
            name: subint.name,
            parent_interface: self,
            index: vport,
            interface_type: @subinterface_types[vport],
            frequency: subint.frequency,
            bandwidth: subint.bandwidth,
            txpower: subint.txpower,
            sf: subint.sf,
            cr: subint.cr,
            flow_control: subint.flow_control,
            st_alock: subint.st_alock,
            lt_alock: subint.lt_alock,
          )

          interface.dir_out = subint.outgoing
          interface.dir_in = true
          interface.announce_rate_target = @announce_rate_target
          interface.mode = @mode
          interface.hw_mtu = @hw_mtu
          interface.detected = true

          RNS.log("Spawned new RNode subinterface: #{interface}", RNS::LOG_VERBOSE)
          @clients += 1
        else
          raise ArgumentError.new("Virtual port \"#{subint.vport}\" for subinterface #{subint.name} does not exist on #{@name}")
        end
      end

      @online = true
    end

    def detect
      kiss_command = Bytes[
        RNodeMultiKISS::FEND, RNodeMultiKISS::CMD_DETECT, RNodeMultiKISS::DETECT_REQ,
        RNodeMultiKISS::FEND, RNodeMultiKISS::CMD_FW_VERSION, 0x00_u8,
        RNodeMultiKISS::FEND, RNodeMultiKISS::CMD_PLATFORM, 0x00_u8,
        RNodeMultiKISS::FEND, RNodeMultiKISS::CMD_MCU, 0x00_u8,
        RNodeMultiKISS::FEND, RNodeMultiKISS::CMD_INTERFACES, 0x00_u8,
        RNodeMultiKISS::FEND,
      ]
      write_serial(kiss_command)
    end

    def leave
      kiss_command = Bytes[RNodeMultiKISS::FEND, RNodeMultiKISS::CMD_LEAVE, 0xFF_u8, RNodeMultiKISS::FEND]
      write_serial(kiss_command)
    end

    def enable_external_framebuffer
      return unless @display
      kiss_command = Bytes[RNodeMultiKISS::FEND, RNodeMultiKISS::CMD_FB_EXT, 0x01_u8, RNodeMultiKISS::FEND]
      write_serial(kiss_command)
    end

    def disable_external_framebuffer
      return unless @display
      kiss_command = Bytes[RNodeMultiKISS::FEND, RNodeMultiKISS::CMD_FB_EXT, 0x00_u8, RNodeMultiKISS::FEND]
      write_serial(kiss_command)
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
      escaped_data = RNodeMultiKISS.escape(data.to_slice)

      io = IO::Memory.new(escaped_data.size + 3)
      io.write_byte(RNodeMultiKISS::FEND)
      io.write_byte(RNodeMultiKISS::CMD_FB_WRITE)
      io.write(escaped_data)
      io.write_byte(RNodeMultiKISS::FEND)
      write_serial(io.to_slice)
    end

    def hard_reset
      kiss_command = Bytes[RNodeMultiKISS::FEND, RNodeMultiKISS::CMD_RESET, 0xF8_u8, RNodeMultiKISS::FEND]
      write_serial(kiss_command)
      sleep(2.25)
    end

    def set_frequency(frequency : Int64, interface : RNodeSubInterface)
      c1 = ((frequency >> 24) & 0xFF).to_u8
      c2 = ((frequency >> 16) & 0xFF).to_u8
      c3 = ((frequency >> 8) & 0xFF).to_u8
      c4 = (frequency & 0xFF).to_u8
      data = RNodeMultiKISS.escape(Bytes[c1, c2, c3, c4])
      write_sel_command(RNodeMultiKISS::CMD_FREQUENCY, data, interface)
    end

    def set_bandwidth(bandwidth : Int64, interface : RNodeSubInterface)
      c1 = ((bandwidth >> 24) & 0xFF).to_u8
      c2 = ((bandwidth >> 16) & 0xFF).to_u8
      c3 = ((bandwidth >> 8) & 0xFF).to_u8
      c4 = (bandwidth & 0xFF).to_u8
      data = RNodeMultiKISS.escape(Bytes[c1, c2, c3, c4])
      write_sel_command(RNodeMultiKISS::CMD_BANDWIDTH, data, interface)
    end

    def set_tx_power(txpower : Int32, interface : RNodeSubInterface)
      txp = txpower.to_i8.to_u8
      write_sel_command(RNodeMultiKISS::CMD_TXPOWER, Bytes[txp], interface)
    end

    def set_spreading_factor(sf : Int32, interface : RNodeSubInterface)
      write_sel_command(RNodeMultiKISS::CMD_SF, Bytes[sf.to_u8], interface)
    end

    def set_coding_rate(cr : Int32, interface : RNodeSubInterface)
      write_sel_command(RNodeMultiKISS::CMD_CR, Bytes[cr.to_u8], interface)
    end

    def set_st_alock(st_alock : Float64?, interface : RNodeSubInterface)
      return unless st_alock
      at = (st_alock * 100).to_i
      c1 = ((at >> 8) & 0xFF).to_u8
      c2 = (at & 0xFF).to_u8
      data = RNodeMultiKISS.escape(Bytes[c1, c2])
      write_sel_command(RNodeMultiKISS::CMD_ST_ALOCK, data, interface)
    end

    def set_lt_alock(lt_alock : Float64?, interface : RNodeSubInterface)
      return unless lt_alock
      at = (lt_alock * 100).to_i
      c1 = ((at >> 8) & 0xFF).to_u8
      c2 = (at & 0xFF).to_u8
      data = RNodeMultiKISS.escape(Bytes[c1, c2])
      write_sel_command(RNodeMultiKISS::CMD_LT_ALOCK, data, interface)
    end

    def set_radio_state(state : UInt8, interface : RNodeSubInterface)
      write_sel_command(RNodeMultiKISS::CMD_RADIO_STATE, Bytes[state], interface)
    end

    def validate_firmware
      if @maj_version > REQUIRED_FW_VER_MAJ || (@maj_version == REQUIRED_FW_VER_MAJ && @min_version >= REQUIRED_FW_VER_MIN)
        @firmware_ok = true
      end
      return if @firmware_ok

      RNS.log("The firmware version of the connected RNode is #{@maj_version}.#{@min_version}", RNS::LOG_ERROR)
      RNS.log("This version of Reticulum requires at least version #{REQUIRED_FW_VER_MAJ}.#{REQUIRED_FW_VER_MIN}", RNS::LOG_ERROR)
      RNS.log("Please update your RNode firmware with rnodeconf")
      RNS.panic()
    end

    def process_outgoing(data : Bytes)
      # Do nothing if RNS tries to transmit on this interface directly (no subinterface)
    end

    def process_outgoing(data : Bytes, interface : RNodeSubInterface)
      escaped = RNodeMultiKISS.escape(data)
      io = IO::Memory.new(escaped.size + 8)
      io.write_byte(RNodeMultiKISS::FEND)
      io.write_byte(RNodeMultiKISS::CMD_SEL_INT)
      io.write_byte(interface.index.to_u8)
      io.write_byte(RNodeMultiKISS::FEND)
      io.write_byte(RNodeMultiKISS::FEND)
      io.write_byte(RNodeMultiKISS::CMD_DATA)
      io.write(escaped)
      io.write_byte(RNodeMultiKISS::FEND)
      frame = io.to_slice

      written = write_serial(frame)
      @txb += data.size
    end

    def received_announce(from_spawned : Bool = false)
      @ia_freq_deque.push(Time.utc.to_unix_f) if from_spawned
    end

    def sent_announce(from_spawned : Bool = false)
      @oa_freq_deque.push(Time.utc.to_unix_f) if from_spawned
    end

    def read_loop
      in_frame = false
      escape = false
      command = RNodeMultiKISS::CMD_UNKNOWN
      data_buffer = IO::Memory.new(512)
      command_buffer = IO::Memory.new(16)
      last_read_ms = (Time.utc.to_unix_f * 1000).to_i64
      buf = Bytes.new(1)

      while (serial = @serial) && !serial.closed?
        begin
          bytes_read = serial.read(buf)
          if bytes_read > 0
            byte = buf[0]
            last_read_ms = (Time.utc.to_unix_f * 1000).to_i64

            if in_frame && byte == RNodeMultiKISS::FEND && command == RNodeMultiKISS::CMD_DATA
              in_frame = false
              subint = @subinterfaces[@selected_index]?
              subint.try(&.process_incoming(data_buffer.to_slice.dup))
              data_buffer = IO::Memory.new(512)
              command_buffer = IO::Memory.new(16)
            elsif byte == RNodeMultiKISS::FEND
              in_frame = true
              command = RNodeMultiKISS::CMD_UNKNOWN
              data_buffer = IO::Memory.new(512)
              command_buffer = IO::Memory.new(16)
            elsif in_frame && data_buffer.size < (@hw_mtu || Reticulum::MTU)
              if data_buffer.size == 0 && command == RNodeMultiKISS::CMD_UNKNOWN
                command = byte
              elsif RNodeMultiKISS.is_data_cmd?(command)
                if byte == RNodeMultiKISS::FESC
                  escape = true
                else
                  if escape
                    byte = RNodeMultiKISS::FEND if byte == RNodeMultiKISS::TFEND
                    byte = RNodeMultiKISS::FESC if byte == RNodeMultiKISS::TFESC
                    escape = false
                  end
                  data_buffer.write_byte(byte)
                end
              elsif command == RNodeMultiKISS::CMD_FREQUENCY
                byte = handle_escape(byte, escape) { |e| escape = e }
                next if escape
                command_buffer.write_byte(byte)
                if command_buffer.size == 4
                  cb = command_buffer.to_slice
                  freq = cb[0].to_u32 << 24 | cb[1].to_u32 << 16 | cb[2].to_u32 << 8 | cb[3].to_u32
                  subint = @subinterfaces[@selected_index]?
                  if subint
                    subint.r_frequency = freq.to_i64
                    RNS.log("#{subint} Radio reporting frequency is #{subint.r_frequency.not_nil! / 1_000_000.0} MHz", RNS::LOG_DEBUG)
                    subint.update_bitrate
                  end
                end
              elsif command == RNodeMultiKISS::CMD_BANDWIDTH
                byte = handle_escape(byte, escape) { |e| escape = e }
                next if escape
                command_buffer.write_byte(byte)
                if command_buffer.size == 4
                  cb = command_buffer.to_slice
                  bw = cb[0].to_u32 << 24 | cb[1].to_u32 << 16 | cb[2].to_u32 << 8 | cb[3].to_u32
                  subint = @subinterfaces[@selected_index]?
                  if subint
                    subint.r_bandwidth = bw.to_i64
                    RNS.log("#{subint} Radio reporting bandwidth is #{subint.r_bandwidth.not_nil! / 1000.0} KHz", RNS::LOG_DEBUG)
                    subint.update_bitrate
                  end
                end
              elsif command == RNodeMultiKISS::CMD_SEL_INT
                @selected_index = byte.to_i32
              elsif command == RNodeMultiKISS::CMD_TXPOWER
                txp = byte > 127 ? byte.to_i32 - 256 : byte.to_i32
                if (subint = @subinterfaces[@selected_index]?)
                  subint.r_txpower = txp
                  RNS.log("#{subint} Radio reporting TX power is #{subint.r_txpower} dBm", RNS::LOG_DEBUG)
                end
              elsif command == RNodeMultiKISS::CMD_SF
                if (subint = @subinterfaces[@selected_index]?)
                  subint.r_sf = byte.to_i32
                  RNS.log("#{subint} Radio reporting spreading factor is #{subint.r_sf}", RNS::LOG_DEBUG)
                  subint.update_bitrate
                end
              elsif command == RNodeMultiKISS::CMD_CR
                if (subint = @subinterfaces[@selected_index]?)
                  subint.r_cr = byte.to_i32
                  RNS.log("#{subint} Radio reporting coding rate is #{subint.r_cr}", RNS::LOG_DEBUG)
                  subint.update_bitrate
                end
              elsif command == RNodeMultiKISS::CMD_RADIO_STATE
                if (subint = @subinterfaces[@selected_index]?)
                  subint.r_state = byte
                  unless subint.r_state == RNodeMultiKISS::RADIO_STATE_ON
                    RNS.log("#{subint} Radio reporting state is offline", RNS::LOG_DEBUG)
                  end
                end
              elsif command == RNodeMultiKISS::CMD_RADIO_LOCK
                if (si = @subinterfaces[@selected_index]?)
                  si.r_lock = byte
                end
              elsif command == RNodeMultiKISS::CMD_FW_VERSION
                byte = handle_escape(byte, escape) { |e| escape = e }
                next if escape
                command_buffer.write_byte(byte)
                if command_buffer.size == 2
                  cb = command_buffer.to_slice
                  @maj_version = cb[0].to_i32
                  @min_version = cb[1].to_i32
                  validate_firmware
                end
              elsif command == RNodeMultiKISS::CMD_STAT_RSSI
                if (subint = @subinterfaces[@selected_index]?)
                  subint.r_stat_rssi = byte.to_i32 - RNodeSubInterface::RSSI_OFFSET
                end
              elsif command == RNodeMultiKISS::CMD_STAT_SNR
                if (subint = @subinterfaces[@selected_index]?)
                  update_snr_stats(subint, byte)
                end
              elsif command == RNodeMultiKISS::CMD_ST_ALOCK
                byte = handle_escape(byte, escape) { |e| escape = e }
                next if escape
                command_buffer.write_byte(byte)
                if command_buffer.size == 2
                  cb = command_buffer.to_slice
                  at = cb[0].to_u32 << 8 | cb[1].to_u32
                  if (subint = @subinterfaces[@selected_index]?)
                    subint.r_st_alock = at / 100.0
                    RNS.log("#{subint} Radio reporting short-term airtime limit is #{subint.r_st_alock}%", RNS::LOG_DEBUG)
                  end
                end
              elsif command == RNodeMultiKISS::CMD_LT_ALOCK
                byte = handle_escape(byte, escape) { |e| escape = e }
                next if escape
                command_buffer.write_byte(byte)
                if command_buffer.size == 2
                  cb = command_buffer.to_slice
                  at = cb[0].to_u32 << 8 | cb[1].to_u32
                  if (subint = @subinterfaces[@selected_index]?)
                    subint.r_lt_alock = at / 100.0
                    RNS.log("#{subint} Radio reporting long-term airtime limit is #{subint.r_lt_alock}%", RNS::LOG_DEBUG)
                  end
                end
              elsif command == RNodeMultiKISS::CMD_STAT_CHTM
                byte = handle_escape(byte, escape) { |e| escape = e }
                next if escape
                command_buffer.write_byte(byte)
                if command_buffer.size == 8
                  cb = command_buffer.to_slice
                  ats = cb[0].to_u32 << 8 | cb[1].to_u32
                  atl = cb[2].to_u32 << 8 | cb[3].to_u32
                  cus = cb[4].to_u32 << 8 | cb[5].to_u32
                  cul = cb[6].to_u32 << 8 | cb[7].to_u32
                  @r_airtime_short = ats / 100.0
                  @r_airtime_long = atl / 100.0
                  @r_channel_load_short = cus / 100.0
                  @r_channel_load_long = cul / 100.0
                end
              elsif command == RNodeMultiKISS::CMD_STAT_PHYPRM
                byte = handle_escape(byte, escape) { |e| escape = e }
                next if escape
                command_buffer.write_byte(byte)
                if command_buffer.size == 10
                  cb = command_buffer.to_slice
                  lst = (cb[0].to_u32 << 8 | cb[1].to_u32) / 1000.0
                  lsr = cb[2].to_u32 << 8 | cb[3].to_u32
                  prs = cb[4].to_u32 << 8 | cb[5].to_u32
                  prt = cb[6].to_u32 << 8 | cb[7].to_u32
                  cst = cb[8].to_u32 << 8 | cb[9].to_u32

                  if (subint = @subinterfaces[@selected_index]?)
                    if lst != subint.r_symbol_time_ms || lsr.to_i32 != subint.r_symbol_rate || prs.to_i32 != subint.r_preamble_symbols || prt.to_i32 != subint.r_premable_time_ms || cst.to_i32 != subint.r_csma_slot_time_ms
                      subint.r_symbol_time_ms = lst
                      subint.r_symbol_rate = lsr.to_i32
                      subint.r_preamble_symbols = prs.to_i32
                      subint.r_premable_time_ms = prt.to_i32
                      subint.r_csma_slot_time_ms = cst.to_i32
                      RNS.log("#{subint} Radio reporting symbol time is #{subint.r_symbol_time_ms.try(&.round(2))}ms (at #{subint.r_symbol_rate} baud)", RNS::LOG_DEBUG)
                      RNS.log("#{subint} Radio reporting preamble is #{subint.r_preamble_symbols} symbols (#{subint.r_premable_time_ms}ms)", RNS::LOG_DEBUG)
                      RNS.log("#{subint} Radio reporting CSMA slot time is #{subint.r_csma_slot_time_ms}ms", RNS::LOG_DEBUG)
                    end
                  end
                end
              elsif command == RNodeMultiKISS::CMD_RANDOM
                @r_random = byte
              elsif command == RNodeMultiKISS::CMD_PLATFORM
                @platform = byte
              elsif command == RNodeMultiKISS::CMD_MCU
                @mcu = byte
              elsif command == RNodeMultiKISS::CMD_ERROR
                if byte == RNodeMultiKISS::ERROR_INITRADIO
                  RNS.log("#{self} hardware initialisation error (code #{byte.to_s(16)})", RNS::LOG_ERROR)
                  raise IO::Error.new("Radio initialisation failure")
                elsif byte == RNodeMultiKISS::ERROR_TXFAILED
                  RNS.log("#{self} hardware TX error (code #{byte.to_s(16)})", RNS::LOG_ERROR)
                  raise IO::Error.new("Hardware transmit failure")
                else
                  RNS.log("#{self} hardware error (code #{byte.to_s(16)})", RNS::LOG_ERROR)
                  raise IO::Error.new("Unknown hardware failure")
                end
              elsif command == RNodeMultiKISS::CMD_RESET
                if byte == 0xF8_u8
                  if @platform == RNodeMultiKISS::PLATFORM_ESP32
                    if @online
                      RNS.log("Detected reset while device was online, reinitialising device...", RNS::LOG_ERROR)
                      raise IO::Error.new("ESP32 reset")
                    end
                  end
                end
              elsif command == RNodeMultiKISS::CMD_READY
                process_queue
              elsif command == RNodeMultiKISS::CMD_DETECT
                if byte == RNodeMultiKISS::DETECT_RESP
                  @detected = true
                else
                  @detected = false
                end
              elsif command == RNodeMultiKISS::CMD_INTERFACES
                command_buffer.write_byte(byte)
                if command_buffer.size == 2
                  cb = command_buffer.to_slice
                  @subinterface_types << RNodeMultiKISS.interface_type_to_str(cb[1])
                  command_buffer = IO::Memory.new(16)
                end
              end
            end
          else
            time_since_last = (Time.utc.to_unix_f * 1000).to_i64 - last_read_ms
            if data_buffer.size > 0 && time_since_last > @timeout
              RNS.log("#{self} serial read timeout in command #{command}", RNS::LOG_WARNING)
              data_buffer = IO::Memory.new(512)
              in_frame = false
              command = RNodeMultiKISS::CMD_UNKNOWN
              escape = false
            end

            # ID beacon
            if @id_interval && @id_callsign
              if ft = @first_tx
                if Time.utc.to_unix_f > ft + @id_interval.not_nil!
                  interface_available = false
                  @subinterfaces.each do |subint|
                    next unless subint
                    next unless subint.online
                    interface_available = true
                    subint.process_outgoing(@id_callsign.not_nil!)
                  end
                  if interface_available
                    RNS.log("Interface #{self} is transmitting beacon data on all subinterfaces: #{String.new(@id_callsign.not_nil!)}", RNS::LOG_DEBUG)
                  end
                end
              end
            end

            sleep(0.08)
          end
        rescue ex
          break
        end
      end
    rescue ex
      @online = false
      RNS.log("A serial port error occurred, the contained exception was: #{ex.message}", RNS::LOG_ERROR)
      RNS.log("The interface #{self} experienced an unrecoverable error and is now offline.", RNS::LOG_ERROR)
      teardown_subinterfaces
    ensure
      @online = false
      @serial.try do |s|
        s.close unless s.closed?
      rescue
      end
      if !@detached && !@reconnecting
        reconnect_port
      end
    end

    def reconnect_port
      @reconnecting = true
      while !@online && !@detached
        begin
          sleep(5)
          RNS.log("Attempting to reconnect serial port #{@port} for #{self}...", RNS::LOG_VERBOSE)
          open_port
          if @serial
            configure_device
          end
        rescue ex
          RNS.log("Error while reconnecting port, the contained exception was: #{ex.message}", RNS::LOG_ERROR)
        end
      end
      @reconnecting = false
      RNS.log("Reconnected serial port for #{self}") if @online
    end

    def detach
      @detached = true
      disable_external_framebuffer
      @subinterfaces.each do |subint|
        next unless subint
        set_radio_state(RNodeMultiKISS::RADIO_STATE_OFF, subint)
      end
      leave
    end

    def teardown_subinterfaces
      @subinterfaces.each_with_index do |subint, idx|
        next unless subint
        @subinterfaces[idx] = nil
      end
    end

    def should_ingress_limit? : Bool
      false
    end

    def process_queue
      @subinterfaces.each do |subint|
        next unless subint
        subint.process_queue
      end
    end

    def to_s(io : IO)
      io << "RNodeMultiInterface[" << @name << "]"
    end

    private def write_serial(data : Bytes) : Int32
      @write_mutex.synchronize do
        serial = @serial
        raise IO::Error.new("Serial port not open") unless serial
        serial.write(data)
        data.size
      end
    end

    private def write_sel_command(cmd : UInt8, data : Bytes, interface : RNodeSubInterface)
      io = IO::Memory.new(data.size + 8)
      io.write_byte(RNodeMultiKISS::FEND)
      io.write_byte(RNodeMultiKISS::CMD_SEL_INT)
      io.write_byte(interface.index.to_u8)
      io.write_byte(RNodeMultiKISS::FEND)
      io.write_byte(RNodeMultiKISS::FEND)
      io.write_byte(cmd)
      io.write(data)
      io.write_byte(RNodeMultiKISS::FEND)
      write_serial(io.to_slice)
    end

    private def update_snr_stats(subint : RNodeSubInterface, byte : UInt8)
      snr_val = (byte > 127 ? byte.to_i32 - 256 : byte.to_i32) * 0.25
      subint.r_stat_snr = snr_val
      begin
        sfs = (subint.r_sf || 7) - 7
        q_snr_min = RNodeSubInterface::Q_SNR_MIN_BASE - sfs * RNodeSubInterface::Q_SNR_STEP
        q_snr_max = RNodeSubInterface::Q_SNR_MAX
        q_snr_span = q_snr_max - q_snr_min
        quality = ((snr_val - q_snr_min) / q_snr_span * 100).round(1)
        quality = 100.0 if quality > 100.0
        quality = 0.0 if quality < 0.0
        subint.r_stat_q = quality
      rescue
      end
    end

    private def handle_escape(byte : UInt8, escape : Bool, &) : UInt8
      if byte == RNodeMultiKISS::FESC
        yield true
        return byte
      end
      if escape
        byte = RNodeMultiKISS::FEND if byte == RNodeMultiKISS::TFEND
        byte = RNodeMultiKISS::FESC if byte == RNodeMultiKISS::TFESC
        yield false
      end
      byte
    end
  end

  # Individual virtual radio sub-interface on RNode multi-interface device.
  # Ports RNodeSubInterface from RNS/Interfaces/RNodeMultiInterface.py.
  class RNodeSubInterface < Interface
    LOW_FREQ_MIN  = 137_000_000_i64
    LOW_FREQ_MAX  = 1_000_000_000_i64
    HIGH_FREQ_MIN = 2_200_000_000_i64
    HIGH_FREQ_MAX = 2_600_000_000_i64

    RSSI_OFFSET = 157

    Q_SNR_MIN_BASE = -9
    Q_SNR_MAX      = 6
    Q_SNR_STEP     = 2

    property index : Int32
    property interface_type : String
    property flow_control : Bool = false
    property detected : Bool = false

    property frequency : Int64? = nil
    property bandwidth : Int64? = nil
    property txpower : Int32? = nil
    property sf : Int32? = nil
    property cr : Int32? = nil
    property state : UInt8 = RNodeMultiKISS::RADIO_STATE_OFF
    property st_alock : Float64? = nil
    property lt_alock : Float64? = nil

    property r_frequency : Int64? = nil
    property r_bandwidth : Int64? = nil
    property r_txpower : Int32? = nil
    property r_sf : Int32? = nil
    property r_cr : Int32? = nil
    property r_state : UInt8? = nil
    property r_lock : UInt8? = nil
    property r_stat_rx : UInt32? = nil
    property r_stat_tx : UInt32? = nil
    property r_stat_rssi : Int32? = nil
    property r_stat_snr : Float64? = nil
    property r_stat_q : Float64? = nil
    property r_st_alock : Float64? = nil
    property r_lt_alock : Float64? = nil
    property r_airtime_short : Float64 = 0.0
    property r_airtime_long : Float64 = 0.0
    property r_channel_load_short : Float64 = 0.0
    property r_channel_load_long : Float64 = 0.0
    property r_symbol_time_ms : Float64? = nil
    property r_symbol_rate : Int32? = nil
    property r_preamble_symbols : Int32? = nil
    property r_premable_time_ms : Int32? = nil
    property r_csma_slot_time_ms : Int32? = nil

    property dir_out : Bool = false
    property dir_in : Bool = false
    property interface_ready : Bool = false
    property packet_queue : Array(Bytes) = [] of Bytes
    property rnode_parent : RNodeMultiInterface
    property bitrate_kbps : Float64 = 0.0

    def initialize(
      @name : String = "",
      parent_interface : RNodeMultiInterface = RNodeMultiInterface.new("", ""),
      @index : Int32 = 0,
      @interface_type : String = "SX127X",
      frequency : Int64? = nil,
      bandwidth : Int64? = nil,
      txpower : Int32? = nil,
      sf : Int32? = nil,
      cr : Int32? = nil,
      @flow_control : Bool = false,
      st_alock : Float64? = nil,
      lt_alock : Float64? = nil
    )
      super()
      @rnode_parent = parent_interface
      @parent_interface = parent_interface
      @frequency = frequency
      @bandwidth = bandwidth
      @txpower = txpower
      @sf = sf
      @cr = cr
      @st_alock = st_alock
      @lt_alock = lt_alock
      @online = false

      # Register with parent
      @rnode_parent.subinterfaces[@index] = self

      validate_config!
      configure_device
    end

    # Simple test constructor
    def initialize(@name : String, parent_interface : RNodeMultiInterface, @index : Int32, @interface_type : String, skip_configure : Bool = false)
      super()
      @rnode_parent = parent_interface
      @parent_interface = parent_interface
      @online = false
      @rnode_parent.subinterfaces[@index] = self
      unless skip_configure
        validate_config!
        configure_device
      end
    end

    private def validate_config!
      if @interface_type == "SX126X" || @interface_type == "SX127X"
        freq = @frequency
        if freq && (freq < LOW_FREQ_MIN || freq > LOW_FREQ_MAX)
          RNS.log("Invalid frequency configured for #{self}", RNS::LOG_ERROR)
          raise ArgumentError.new("The configuration for #{self} contains errors, interface is offline")
        end
      elsif @interface_type == "SX128X"
        freq = @frequency
        if freq && (freq < HIGH_FREQ_MIN || freq > HIGH_FREQ_MAX)
          RNS.log("Invalid frequency configured for #{self}", RNS::LOG_ERROR)
          raise ArgumentError.new("The configuration for #{self} contains errors, interface is offline")
        end
      else
        RNS.log("Invalid interface type configured for #{self}", RNS::LOG_ERROR)
        raise ArgumentError.new("The configuration for #{self} contains errors, interface is offline")
      end

      if tp = @txpower
        if tp < -9 || tp > 37
          RNS.log("Invalid TX power configured for #{self}", RNS::LOG_ERROR)
          raise ArgumentError.new("The configuration for #{self} contains errors, interface is offline")
        end
      end

      if bw = @bandwidth
        if bw < 7800 || bw > 1_625_000
          RNS.log("Invalid bandwidth configured for #{self}", RNS::LOG_ERROR)
          raise ArgumentError.new("The configuration for #{self} contains errors, interface is offline")
        end
      end

      if s = @sf
        if s < 5 || s > 12
          RNS.log("Invalid spreading factor configured for #{self}", RNS::LOG_ERROR)
          raise ArgumentError.new("The configuration for #{self} contains errors, interface is offline")
        end
      end

      if c = @cr
        if c < 5 || c > 8
          RNS.log("Invalid coding rate configured for #{self}", RNS::LOG_ERROR)
          raise ArgumentError.new("The configuration for #{self} contains errors, interface is offline")
        end
      end

      if sta = @st_alock
        if sta < 0.0 || sta > 100.0
          RNS.log("Invalid short-term airtime limit configured for #{self}", RNS::LOG_ERROR)
          raise ArgumentError.new("The configuration for #{self} contains errors, interface is offline")
        end
      end

      if lta = @lt_alock
        if lta < 0.0 || lta > 100.0
          RNS.log("Invalid long-term airtime limit configured for #{self}", RNS::LOG_ERROR)
          raise ArgumentError.new("The configuration for #{self} contains errors, interface is offline")
        end
      end
    end

    def configure_device
      @r_frequency = nil
      @r_bandwidth = nil
      @r_txpower = nil
      @r_sf = nil
      @r_cr = nil
      @r_state = nil
      @r_lock = nil

      RNS.log("Configuring RNode subinterface #{self}...", RNS::LOG_VERBOSE)
      init_radio
      if validate_radio_state
        @interface_ready = true
        RNS.log("#{self} is configured and powered up")
        @online = true
      else
        RNS.log("After configuring #{self}, the reported radio parameters did not match your configuration.", RNS::LOG_ERROR)
        RNS.log("Make sure that your hardware actually supports the parameters specified in the configuration", RNS::LOG_ERROR)
        RNS.log("Aborting RNode startup", RNS::LOG_ERROR)
      end
    end

    def init_radio
      freq = @frequency
      bw = @bandwidth
      tp = @txpower
      s = @sf
      c = @cr

      @rnode_parent.set_frequency(freq.not_nil!, self) if freq
      @rnode_parent.set_bandwidth(bw.not_nil!, self) if bw
      @rnode_parent.set_tx_power(tp.not_nil!, self) if tp
      @rnode_parent.set_spreading_factor(s.not_nil!, self) if s
      @rnode_parent.set_coding_rate(c.not_nil!, self) if c
      @rnode_parent.set_st_alock(@st_alock, self)
      @rnode_parent.set_lt_alock(@lt_alock, self)
      @rnode_parent.set_radio_state(RNodeMultiKISS::RADIO_STATE_ON, self)
      @state = RNodeMultiKISS::RADIO_STATE_ON
    end

    def validate_radio_state : Bool
      RNS.log("Waiting for radio configuration validation for #{self}...", RNS::LOG_VERBOSE)
      sleep(0.25)

      valid = true
      if rf = @r_frequency
        if freq = @frequency
          if (freq - rf).abs > 100
            RNS.log("Frequency mismatch", RNS::LOG_ERROR)
            valid = false
          end
        end
      end
      if @bandwidth != @r_bandwidth
        RNS.log("Bandwidth mismatch", RNS::LOG_ERROR)
        valid = false
      end
      if @txpower != @r_txpower
        RNS.log("TX power mismatch", RNS::LOG_ERROR)
        valid = false
      end
      if @sf != @r_sf
        RNS.log("Spreading factor mismatch", RNS::LOG_ERROR)
        valid = false
      end
      if @state != @r_state
        RNS.log("Radio state mismatch", RNS::LOG_ERROR)
        valid = false
      end
      valid
    end

    def update_bitrate
      begin
        r_sf = @r_sf
        r_cr = @r_cr
        r_bw = @r_bandwidth
        return unless r_sf && r_cr && r_bw
        @bitrate = (r_sf * (4.0 / r_cr) / ((2_f64 ** r_sf) / (r_bw / 1000.0)) * 1000).to_i64
        @bitrate_kbps = (@bitrate / 1000.0).round(2)
        RNS.log("#{self} On-air bitrate is now #{@bitrate_kbps} kbps", RNS::LOG_VERBOSE)
      rescue
        @bitrate = 0
      end
    end

    def process_incoming(data : Bytes)
      @rxb += data.size
      @r_stat_rssi = nil
      @r_stat_snr = nil
    end

    def process_outgoing(data : Bytes)
      return unless @online
      if @interface_ready
        @interface_ready = false if @flow_control

        id_cs = @rnode_parent.id_callsign
        if id_cs && data == id_cs
          @rnode_parent.first_tx = nil
        else
          @rnode_parent.first_tx = Time.utc.to_unix_f unless @rnode_parent.first_tx
        end

        @txb += data.size
        @rnode_parent.process_outgoing(data, self)
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

    def to_s(io : IO)
      io << @rnode_parent.name << "[" << @name << "]"
    end
  end
end
