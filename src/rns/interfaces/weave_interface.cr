module RNS
  # Weave Device Command Language (WDCL) protocol constants and types.
  # Ports WDCL, Cmd, Evt, LogFrame classes from RNS/Interfaces/WeaveInterface.py.
  module WeaveWDCL
    WDCL_T_DISCOVER     = 0x00_u8
    WDCL_T_CONNECT      = 0x01_u8
    WDCL_T_CMD          = 0x02_u8
    WDCL_T_LOG          = 0x03_u8
    WDCL_T_DISP         = 0x04_u8
    WDCL_T_ENDPOINT_PKT = 0x05_u8
    WDCL_T_ENCAP_PROTO  = 0x06_u8

    WDCL_BROADCAST = Bytes[0xFF, 0xFF, 0xFF, 0xFF]

    WDCL_HANDSHAKE_TIMEOUT = 2

    HEADER_MINSIZE = 4 + 1
    MAX_CHUNK      = 32768
  end

  module WeaveCmd
    WDCL_CMD_ENDPOINT_PKT   = 0x0001_u16
    WDCL_CMD_ENDPOINTS_LIST = 0x0100_u16
    WDCL_CMD_REMOTE_DISPLAY = 0x0A00_u16
    WDCL_CMD_REMOTE_INPUT   = 0x0A01_u16
  end

  module WeaveEvt
    ET_MSG                       = 0x0000_u16
    ET_SYSTEM_BOOT               = 0x0001_u16
    ET_CORE_INIT                 = 0x0002_u16
    ET_DRV_UART_INIT             = 0x1000_u16
    ET_DRV_USB_CDC_INIT          = 0x1010_u16
    ET_DRV_USB_CDC_HOST_AVAIL    = 0x1011_u16
    ET_DRV_USB_CDC_HOST_SUSPEND  = 0x1012_u16
    ET_DRV_USB_CDC_HOST_RESUME   = 0x1013_u16
    ET_DRV_USB_CDC_CONNECTED     = 0x1014_u16
    ET_DRV_USB_CDC_READ_ERR      = 0x1015_u16
    ET_DRV_USB_CDC_OVERFLOW      = 0x1016_u16
    ET_DRV_USB_CDC_DROPPED       = 0x1017_u16
    ET_DRV_USB_CDC_TX_TIMEOUT    = 0x1018_u16
    ET_DRV_I2C_INIT              = 0x1020_u16
    ET_DRV_NVS_INIT              = 0x1030_u16
    ET_DRV_NVS_ERASE             = 0x1031_u16
    ET_DRV_CRYPTO_INIT           = 0x1040_u16
    ET_DRV_DISPLAY_INIT          = 0x1050_u16
    ET_DRV_DISPLAY_BUS_AVAILABLE = 0x1051_u16
    ET_DRV_DISPLAY_IO_CONFIGURED = 0x1052_u16
    ET_DRV_DISPLAY_PANEL_CREATED = 0x1053_u16
    ET_DRV_DISPLAY_PANEL_RESET   = 0x1054_u16
    ET_DRV_DISPLAY_PANEL_INIT    = 0x1055_u16
    ET_DRV_DISPLAY_PANEL_ENABLE  = 0x1056_u16
    ET_DRV_DISPLAY_REMOTE_ENABLE = 0x1057_u16
    ET_DRV_W80211_INIT           = 0x1060_u16
    ET_DRV_W80211_CHANNEL        = 0x1062_u16
    ET_DRV_W80211_POWER          = 0x1063_u16
    ET_KRN_LOGGER_INIT           = 0x2000_u16
    ET_KRN_LOGGER_OUTPUT         = 0x2001_u16
    ET_KRN_UI_INIT               = 0x2010_u16
    ET_PROTO_WDCL_INIT           = 0x3000_u16
    ET_PROTO_WDCL_RUNNING        = 0x3001_u16
    ET_PROTO_WDCL_CONNECTION     = 0x3002_u16
    ET_PROTO_WDCL_HOST_ENDPOINT  = 0x3003_u16
    ET_PROTO_WEAVE_INIT          = 0x3100_u16
    ET_PROTO_WEAVE_RUNNING       = 0x3101_u16
    ET_PROTO_WEAVE_EP_ALIVE      = 0x3102_u16
    ET_PROTO_WEAVE_EP_TIMEOUT    = 0x3103_u16
    ET_PROTO_WEAVE_EP_VIA        = 0x3104_u16
    ET_SRVCTL_REMOTE_DISPLAY     = 0xA000_u16
    ET_INTERFACE_REGISTERED      = 0xD000_u16
    ET_STAT_STATE                = 0xE000_u16
    ET_STAT_UPTIME               = 0xE001_u16
    ET_STAT_TIMEBASE             = 0xE002_u16
    ET_STAT_CPU                  = 0xE003_u16
    ET_STAT_TASK_CPU             = 0xE004_u16
    ET_STAT_MEMORY               = 0xE005_u16
    ET_STAT_STORAGE              = 0xE006_u16
    ET_SYSERR_MEM_EXHAUSTED      = 0xF000_u16

    IF_TYPE_USB      = 0x01_u8
    IF_TYPE_UART     = 0x02_u8
    IF_TYPE_W80211   = 0x03_u8
    IF_TYPE_BLE      = 0x04_u8
    IF_TYPE_LORA     = 0x05_u8
    IF_TYPE_ETHERNET = 0x06_u8
    IF_TYPE_WIFI     = 0x07_u8
    IF_TYPE_TCP      = 0x08_u8
    IF_TYPE_UDP      = 0x09_u8
    IF_TYPE_IR       = 0x0A_u8
    IF_TYPE_AFSK     = 0x0B_u8
    IF_TYPE_GPIO     = 0x0C_u8
    IF_TYPE_SPI      = 0x0D_u8
    IF_TYPE_I2C      = 0x0E_u8
    IF_TYPE_CAN      = 0x0F_u8
    IF_TYPE_DMA      = 0x10_u8

    EVENT_DESCRIPTIONS = {
      ET_SYSTEM_BOOT               => "System boot",
      ET_CORE_INIT                 => "Core initialization",
      ET_DRV_UART_INIT             => "UART driver initialization",
      ET_DRV_USB_CDC_INIT          => "USB CDC driver initialization",
      ET_DRV_USB_CDC_HOST_AVAIL    => "USB CDC host became available",
      ET_DRV_USB_CDC_HOST_SUSPEND  => "USB CDC host suspend",
      ET_DRV_USB_CDC_HOST_RESUME   => "USB CDC host resume",
      ET_DRV_USB_CDC_CONNECTED     => "USB CDC host connection",
      ET_DRV_USB_CDC_READ_ERR      => "USB CDC read error",
      ET_DRV_USB_CDC_OVERFLOW      => "USB CDC overflow occurred",
      ET_DRV_USB_CDC_DROPPED       => "USB CDC dropped bytes",
      ET_DRV_USB_CDC_TX_TIMEOUT    => "USB CDC TX flush timeout",
      ET_DRV_I2C_INIT              => "I2C driver initialization",
      ET_DRV_NVS_INIT              => "NVS driver initialization",
      ET_DRV_CRYPTO_INIT           => "Cryptography driver initialization",
      ET_DRV_W80211_INIT           => "W802.11 driver initialization",
      ET_DRV_W80211_CHANNEL        => "W802.11 channel configuration",
      ET_DRV_W80211_POWER          => "W802.11 TX power configuration",
      ET_DRV_DISPLAY_INIT          => "Display driver initialization",
      ET_DRV_DISPLAY_BUS_AVAILABLE => "Display bus availability",
      ET_DRV_DISPLAY_IO_CONFIGURED => "Display I/O configuration",
      ET_DRV_DISPLAY_PANEL_CREATED => "Display panel allocation",
      ET_DRV_DISPLAY_PANEL_RESET   => "Display panel reset",
      ET_DRV_DISPLAY_PANEL_INIT    => "Display panel initialization",
      ET_DRV_DISPLAY_PANEL_ENABLE  => "Display panel activation",
      ET_DRV_DISPLAY_REMOTE_ENABLE => "Remote display output activation",
      ET_KRN_LOGGER_INIT           => "Logging service initialization",
      ET_KRN_LOGGER_OUTPUT         => "Logging service output activation",
      ET_KRN_UI_INIT               => "User interface service initialization",
      ET_PROTO_WDCL_INIT           => "WDCL protocol initialization",
      ET_PROTO_WDCL_RUNNING        => "WDCL protocol activation",
      ET_PROTO_WDCL_CONNECTION     => "WDCL host connection",
      ET_PROTO_WDCL_HOST_ENDPOINT  => "Weave host endpoint",
      ET_PROTO_WEAVE_INIT          => "Weave protocol initialization",
      ET_PROTO_WEAVE_RUNNING       => "Weave protocol activation",
      ET_PROTO_WEAVE_EP_ALIVE      => "Weave endpoint alive",
      ET_PROTO_WEAVE_EP_TIMEOUT    => "Weave endpoint disappeared",
      ET_SRVCTL_REMOTE_DISPLAY     => "Remote display service control event",
      ET_INTERFACE_REGISTERED      => "Interface registration",
      ET_SYSERR_MEM_EXHAUSTED      => "System memory exhausted",
    }

    INTERFACE_TYPES = {
      IF_TYPE_USB      => "usb",
      IF_TYPE_UART     => "uart",
      IF_TYPE_W80211   => "mw",
      IF_TYPE_BLE      => "ble",
      IF_TYPE_LORA     => "lora",
      IF_TYPE_ETHERNET => "eth",
      IF_TYPE_WIFI     => "wifi",
      IF_TYPE_TCP      => "tcp",
      IF_TYPE_UDP      => "udp",
      IF_TYPE_IR       => "ir",
      IF_TYPE_AFSK     => "afsk",
      IF_TYPE_GPIO     => "gpio",
      IF_TYPE_SPI      => "spi",
      IF_TYPE_I2C      => "i2c",
      IF_TYPE_CAN      => "can",
      IF_TYPE_DMA      => "dma",
    }

    CHANNEL_DESCRIPTIONS = {
       1 => "Channel 1 (2412 MHz)",
       2 => "Channel 2 (2417 MHz)",
       3 => "Channel 3 (2422 MHz)",
       4 => "Channel 4 (2427 MHz)",
       5 => "Channel 5 (2432 MHz)",
       6 => "Channel 6 (2437 MHz)",
       7 => "Channel 7 (2442 MHz)",
       8 => "Channel 8 (2447 MHz)",
       9 => "Channel 9 (2452 MHz)",
      10 => "Channel 10 (2457 MHz)",
      11 => "Channel 11 (2462 MHz)",
      12 => "Channel 12 (2467 MHz)",
      13 => "Channel 13 (2472 MHz)",
      14 => "Channel 14 (2484 MHz)",
    }

    LOG_FORCE    = 0_u8
    LOG_CRITICAL = 1_u8
    LOG_ERROR    = 2_u8
    LOG_WARNING  = 3_u8
    LOG_NOTICE   = 4_u8
    LOG_INFO     = 5_u8
    LOG_VERBOSE  = 6_u8
    LOG_DEBUG    = 7_u8
    LOG_EXTREME  = 8_u8
    LOG_SYSTEM   = 9_u8

    LEVELS = {
      LOG_FORCE    => "Forced",
      LOG_CRITICAL => "Critical",
      LOG_ERROR    => "Error",
      LOG_WARNING  => "Warning",
      LOG_NOTICE   => "Notice",
      LOG_INFO     => "Info",
      LOG_VERBOSE  => "Verbose",
      LOG_DEBUG    => "Debug",
      LOG_EXTREME  => "Extreme",
      LOG_SYSTEM   => "System",
    }

    TASK_DESCRIPTIONS = {
      "taskLVGL"       => "Driver: UI Renderer",
      "ui_service"     => "Service: User Interface",
      "TinyUSB"        => "Driver: USB",
      "drv_w80211"     => "Driver: W802.11",
      "system_stats"   => "System: Stats",
      "core"           => "System: Core",
      "protocol_wdcl"  => "Protocol: WDCL",
      "protocol_weave" => "Protocol: Weave",
      "tiT"            => "Protocol: TCP/IP",
      "ipc0"           => "System: CPU 0 IPC",
      "ipc1"           => "System: CPU 1 IPC",
      "esp_timer"      => "Driver: Timers",
      "Tmr Svc"        => "Service: Timers",
      "kernel_logger"  => "Service: Logging",
      "remote_display" => "Service: Remote Display",
      "wifi"           => "System: WiFi Hardware",
      "sys_evt"        => "System: Kernel Events",
    }

    def self.level(level : UInt8) : String
      LEVELS[level]? || "Unknown"
    end
  end

  # A log/event frame from a remote Weave device.
  class WeaveLogFrame
    property timestamp : Float64?
    property level : UInt8?
    property event : UInt16?
    property data : Bytes

    def initialize(@timestamp = nil, @level = nil, @event = nil, @data = Bytes.empty)
    end
  end

  # Represents a remote Weave endpoint with a packet receive queue.
  class WeaveEndpoint
    QUEUE_LEN = 1024

    property endpoint_addr : Bytes
    property alive : Float64
    property via : Bytes?
    property received : Deque(Bytes)

    def initialize(@endpoint_addr : Bytes)
      @alive = Time.utc.to_unix_f
      @received = Deque(Bytes).new(QUEUE_LEN)
    end

    def receive(data : Bytes)
      @received.shift if @received.size >= QUEUE_LEN
      @received.push(data)
    end
  end

  # Central Weave device management.
  # Handles remote device identity, authentication, endpoint discovery,
  # and system statistics tracking.
  class WeaveDevice
    STATLEN_MAX          = 120
    STAT_UPDATE_THROTTLE = 0.5

    WEAVE_SWITCH_ID_LEN   = 4
    WEAVE_ENDPOINT_ID_LEN = 8
    WEAVE_FLOWSEQ_LEN     = 2
    WEAVE_HMAC_LEN        = 8
    WEAVE_AUTH_LEN        = WEAVE_ENDPOINT_ID_LEN + WEAVE_HMAC_LEN

    WEAVE_PUBKEY_SIZE   = 32
    WEAVE_PRVKEY_SIZE   = 64
    WEAVE_SIGNATURE_LEN = 64

    property identity : Identity? = nil
    property switch_id : Bytes? = nil
    property endpoint_id : Bytes? = nil
    property rns_interface : WeaveInterface? = nil
    property as_interface : Bool = false
    property endpoints : Hash(Bytes, WeaveEndpoint) = {} of Bytes => WeaveEndpoint
    property active_tasks : Hash(String, Hash(String, Float64 | Int32)) = {} of String => Hash(String, Float64 | Int32)
    property cpu_load : Int32 = 0
    property memory_total : Int64 = 0
    property memory_free : Int64 = 0
    property memory_used : Int64 = 0
    property memory_used_pct : Float64 = 0.0
    property log_queue : Deque(String) = Deque(String).new
    property memory_stats : Deque(Hash(String, Float64 | Int64)) = Deque(Hash(String, Float64 | Int64)).new(STATLEN_MAX)
    property cpu_stats : Deque(Hash(String, Float64 | Int32)) = Deque(Hash(String, Float64 | Int32)).new(STATLEN_MAX)
    property display_buffer : Bytes = Bytes.empty
    property update_display : Bool = false

    property next_update_memory : Float64 = 0.0
    property next_update_cpu : Float64 = 0.0

    @connection : WeaveWDCLConnection? = nil

    def connection=(conn : WeaveWDCLConnection)
      @connection = conn
    end

    def connection : WeaveWDCLConnection
      @connection.not_nil!
    end

    def initialize(@as_interface : Bool = false, @rns_interface : WeaveInterface? = nil)
    end

    def wdcl_send(packet_type : UInt8, data : Bytes)
      sid = @switch_id
      unless sid
        RNS.log("Attempt to transmit while remote Weave device identity is unknown", RNS::LOG_ERROR)
        return
      end

      io = IO::Memory.new(sid.size + 1 + data.size)
      io.write(sid)
      io.write_byte(packet_type)
      io.write(data)
      connection.process_outgoing(io.to_slice)
    end

    def wdcl_broadcast(packet_type : UInt8, data : Bytes)
      io = IO::Memory.new(WeaveWDCL::WDCL_BROADCAST.size + 1 + data.size)
      io.write(WeaveWDCL::WDCL_BROADCAST)
      io.write_byte(packet_type)
      io.write(data)
      connection.process_outgoing(io.to_slice)
    end

    def wdcl_send_command(command : UInt16, data : Bytes)
      io = IO::Memory.new(2 + data.size)
      io.write_byte((command >> 8).to_u8)
      io.write_byte((command & 0xFF).to_u8)
      io.write(data)
      wdcl_send(WeaveWDCL::WDCL_T_CMD, io.to_slice)
    end

    def discover
      wdcl_broadcast(WeaveWDCL::WDCL_T_DISCOVER, connection.switch_id)
    end

    def handshake
      unless @identity
        RNS.log("Attempt to perform handshake before remote device discovery completion", RNS::LOG_ERROR)
        return
      end

      signed_id = @switch_id.not_nil!
      signature = connection.switch_identity.sign(signed_id)
      io = IO::Memory.new(connection.switch_pub_bytes.size + signature.size)
      io.write(connection.switch_pub_bytes)
      io.write(signature)
      wdcl_send(WeaveWDCL::WDCL_T_CONNECT, io.to_slice)
      RNS.log("WDCL connection handshake sent", RNS::LOG_VERBOSE)
    end

    def capture_stats_cpu
      cpu_stats.shift if cpu_stats.size >= STATLEN_MAX
      cpu_stats.push({"timestamp" => Time.utc.to_unix_f, "cpu_load" => @cpu_load.to_f64} of String => Float64 | Int32)
    end

    def capture_stats_memory
      memory_stats.shift if memory_stats.size >= STATLEN_MAX
      memory_stats.push({"timestamp" => Time.utc.to_unix_f, "memory_used" => @memory_used} of String => Float64 | Int64)
    end

    def get_cpu_stats : Hash(String, Array(Float64) | Float64 | String)
      tbegin : Float64? = nil
      stats = {
        "timestamps" => [] of Float64,
        "values"     => [] of Float64,
        "max"        => 100.0,
        "unit"       => "%",
      } of String => Array(Float64) | Float64 | String
      cpu_stats.each do |entry|
        ts = entry["timestamp"].as(Float64)
        tbegin = cpu_stats.last["timestamp"].as(Float64) unless tbegin
        stats["timestamps"].as(Array(Float64)) << ts - tbegin.not_nil!
        stats["values"].as(Array(Float64)) << entry["cpu_load"].as(Float64)
      end
      stats
    end

    def get_memory_stats : Hash(String, Array(Float64) | Float64 | Int64 | String)
      tbegin : Float64? = nil
      stats = {
        "timestamps" => [] of Float64,
        "values"     => [] of Float64,
        "max"        => @memory_total,
        "unit"       => "B",
      } of String => Array(Float64) | Float64 | Int64 | String
      memory_stats.each do |entry|
        ts = entry["timestamp"].as(Float64)
        tbegin = memory_stats.last["timestamp"].as(Float64) unless tbegin
        stats["timestamps"].as(Array(Float64)) << ts - tbegin.not_nil!
        stats["values"].as(Array(Float64)) << entry["memory_used"].as(Int64).to_f64
      end
      stats
    end

    def get_active_tasks : Hash(String, Hash(String, Float64 | Int32))
      result = {} of String => Hash(String, Float64 | Int32)
      now = Time.utc.to_unix_f
      @active_tasks.each do |task_id, task_info|
        next if task_id.starts_with?("IDLE")
        description = WeaveEvt::TASK_DESCRIPTIONS[task_id]? || task_id
        ts = task_info["timestamp"].as(Float64)
        if now - ts < 5
          result[description] = task_info
        end
      end
      result
    end

    def disconnect_display
      wdcl_send_command(WeaveCmd::WDCL_CMD_REMOTE_DISPLAY, Bytes[0x00])
      @update_display = false
    end

    def connect_display
      wdcl_send_command(WeaveCmd::WDCL_CMD_REMOTE_DISPLAY, Bytes[0x01])
      @update_display = true
    end

    def endpoint_alive(endpoint_id : Bytes)
      if ep = @endpoints[endpoint_id]?
        ep.alive = Time.utc.to_unix_f
      else
        @endpoints[endpoint_id] = WeaveEndpoint.new(endpoint_id)
      end
      @rns_interface.try(&.add_peer(endpoint_id))
    end

    def endpoint_via(endpoint_id : Bytes, via_switch_id : Bytes)
      @endpoints[endpoint_id]?.try { |ep| ep.via = via_switch_id }
      @rns_interface.try(&.endpoint_via(endpoint_id, via_switch_id))
    end

    def deliver_packet(endpoint_id : Bytes, data : Bytes)
      io = IO::Memory.new(endpoint_id.size + data.size)
      io.write(endpoint_id)
      io.write(data)
      wdcl_send_command(WeaveCmd::WDCL_CMD_ENDPOINT_PKT, io.to_slice)
    end

    def received_packet(source : Bytes, data : Bytes)
      endpoint_alive(source)
      if @as_interface
        @rns_interface.try(&.process_incoming(data, source))
      end
    end

    def incoming_frame(data : Bytes)
      sid = connection.switch_id

      # Endpoint packet
      if data.size > WEAVE_SWITCH_ID_LEN + 2 &&
         data[WEAVE_SWITCH_ID_LEN] == WeaveWDCL::WDCL_T_ENDPOINT_PKT &&
         data[0, WEAVE_SWITCH_ID_LEN] == sid
        payload = data[WEAVE_SWITCH_ID_LEN + 1..-(WEAVE_ENDPOINT_ID_LEN + 1)]
        src_endpoint = data[-(WEAVE_ENDPOINT_ID_LEN)..]
        received_packet(src_endpoint, payload)

        # Discovery response
      elsif data.size > WEAVE_SWITCH_ID_LEN + 1 && data[WEAVE_SWITCH_ID_LEN] == WeaveWDCL::WDCL_T_DISCOVER
        discovery_response_len = WEAVE_SWITCH_ID_LEN + 1 + WEAVE_PUBKEY_SIZE + WEAVE_SIGNATURE_LEN
        if data.size == discovery_response_len
          signed_id = data[0, WEAVE_SWITCH_ID_LEN]
          remote_pub_key = data[WEAVE_SWITCH_ID_LEN + 1, WEAVE_PUBKEY_SIZE]
          remote_switch_id = remote_pub_key[-(4)..]
          remote_signature = data[WEAVE_SWITCH_ID_LEN + 1 + WEAVE_PUBKEY_SIZE, WEAVE_SIGNATURE_LEN]

          remote_identity = Identity.new(create_keys: false)
          # Load public key: signing key duplicated as both enc + sig key
          doubled_key = IO::Memory.new(remote_pub_key.size * 2)
          doubled_key.write(remote_pub_key)
          doubled_key.write(remote_pub_key)
          remote_identity.load_public_key(doubled_key.to_slice)

          if remote_identity.validate(remote_signature, signed_id)
            RNS.log("Remote Weave device #{RNS.hexrep(remote_switch_id)} discovered", RNS::LOG_VERBOSE)
            @identity = remote_identity
            @switch_id = remote_switch_id.dup
            handshake
          else
            RNS.log("Invalid remote device discovery response received", RNS::LOG_ERROR)
          end
        end

        # Log frame
      elsif data.size > WEAVE_SWITCH_ID_LEN + 1 && data[WEAVE_SWITCH_ID_LEN] == WeaveWDCL::WDCL_T_LOG
        fd = data[WEAVE_SWITCH_ID_LEN + 2..]
        if fd.size >= 9
          ts = fd[1].to_u32 << 24 | fd[2].to_u32 << 16 | fd[3].to_u32 << 8 | fd[4].to_u32
          lvl = fd[5]
          evt = fd[6].to_u16 << 8 | fd[7].to_u16
          frame_data = fd[8..]
          log_handle(WeaveLogFrame.new(timestamp: ts / 1000.0, level: lvl, event: evt, data: frame_data))
        end

        # Display frame
      elsif data.size > WEAVE_SWITCH_ID_LEN + 10 && data[WEAVE_SWITCH_ID_LEN] == WeaveWDCL::WDCL_T_DISP
        fd = data[WEAVE_SWITCH_ID_LEN + 1..]
        if fd.size >= 10
          ofs = fd[1].to_u32 << 24 | fd[2].to_u32 << 16 | fd[3].to_u32 << 8 | fd[4].to_u32
          dsz = fd[5].to_u32 << 24 | fd[6].to_u32 << 16 | fd[7].to_u32 << 8 | fd[8].to_u32
          fbf = fd[9..]

          if dsz > @display_buffer.size
            @display_buffer = Bytes.new(dsz.to_i32)
          end
          fbf.copy_to(@display_buffer[ofs.to_i32, fbf.size])
        end
      end
    end

    def log_handle(frame : WeaveLogFrame)
      evt = frame.event || 0_u16

      # Handle system event signalling
      if evt == WeaveEvt::ET_PROTO_WDCL_CONNECTION
        connection.wdcl_connected = true
      end
      if evt == WeaveEvt::ET_PROTO_WDCL_HOST_ENDPOINT && frame.data.size == WEAVE_ENDPOINT_ID_LEN
        @endpoint_id = frame.data.dup
      end
      if evt == WeaveEvt::ET_PROTO_WEAVE_EP_ALIVE && frame.data.size == WEAVE_ENDPOINT_ID_LEN
        endpoint_alive(frame.data.dup)
      end
      if evt == WeaveEvt::ET_PROTO_WEAVE_EP_VIA && frame.data.size == WEAVE_ENDPOINT_ID_LEN + WEAVE_SWITCH_ID_LEN
        endpoint_via(frame.data[0, WEAVE_ENDPOINT_ID_LEN].dup, frame.data[WEAVE_ENDPOINT_ID_LEN..].dup)
      elsif evt == WeaveEvt::ET_STAT_TASK_CPU && frame.data.size > 1
        task_name = String.new(frame.data[1..])
        @active_tasks[task_name] = {
          "cpu_load"  => frame.data[0].to_i32,
          "timestamp" => Time.utc.to_unix_f,
        } of String => Float64 | Int32
      elsif evt == WeaveEvt::ET_STAT_CPU && frame.data.size >= 1
        @cpu_load = frame.data[0].to_i32
        capture_stats_cpu
      elsif evt == WeaveEvt::ET_STAT_MEMORY && frame.data.size >= 8
        @memory_free = frame.data[0].to_i64 << 24 | frame.data[1].to_i64 << 16 | frame.data[2].to_i64 << 8 | frame.data[3].to_i64
        @memory_total = frame.data[4].to_i64 << 24 | frame.data[5].to_i64 << 16 | frame.data[6].to_i64 << 8 | frame.data[7].to_i64
        @memory_used = @memory_total - @memory_free
        @memory_used_pct = (@memory_used.to_f64 / @memory_total.to_f64 * 100).round(2) if @memory_total > 0
        capture_stats_memory
      else
        # Log rendering for generic events
        ts_val = frame.timestamp
        ts = ts_val ? RNS.prettytime(ts_val) : "0s"
        lvl = frame.level || 0_u8

        if evt == WeaveEvt::ET_MSG
          data_string = frame.data.size > 0 ? String.new(frame.data) : ""
          rendered = "[#{ts}] [#{WeaveEvt.level(lvl)}]: #{data_string}"
        else
          event_description = WeaveEvt::EVENT_DESCRIPTIONS[evt]? || "0x#{evt.to_s(16).rjust(4, '0')}"
          data_string = ""
          if frame.data.size > 0
            data_string = ": #{RNS.hexrep(frame.data)}"
          end
          rendered = "[#{ts}] [#{WeaveEvt.level(lvl)}] [#{event_description}]#{data_string}"
        end

        if @as_interface
          RNS.log("#{@rns_interface}: #{rendered}", RNS::LOG_EXTREME)
        end
      end
    end
  end

  # WDCL serial connection handler.
  # Manages the physical serial connection and HDLC framing for WDCL protocol.
  class WeaveWDCLConnection
    property switch_identity : Identity
    property switch_id : Bytes
    property switch_pub_bytes : Bytes
    property port : String
    property speed : Int32 = 3_000_000
    property online : Bool = false
    property wdcl_connected : Bool = false
    property reconnecting : Bool = false
    property should_run : Bool = true

    @serial : IO? = nil
    @device : WeaveDevice
    @as_interface : Bool
    @owner : WeaveInterface
    @frame_buffer : IO::Memory = IO::Memory.new(4096)
    @frame_queue : Deque(Bytes) = Deque(Bytes).new

    def initialize(@owner : WeaveInterface, @device : WeaveDevice, @port : String, @as_interface : Bool = false)
      @switch_identity = @owner.switch_identity
      @switch_id = @switch_identity.sign(Bytes.new(0))[-4..].dup     # Last 4 bytes of signing pub key
      @switch_pub_bytes = @switch_identity.sign(Bytes.new(0))[0, 32] # Signing pub key bytes
      @device.connection = self

      if @as_interface
        begin
          open_port
          if @serial
            configure_device
          else
            raise IO::Error.new("Could not open serial port")
          end
        rescue ex
          RNS.log("Could not open serial port for interface #{self}", RNS::LOG_ERROR)
          RNS.log("The contained exception was: #{ex.message}", RNS::LOG_ERROR)
          RNS.log("Reticulum will attempt to bring up this interface periodically", RNS::LOG_ERROR)
          if !@owner.detached? && !@reconnecting
            spawn { reconnect_port }
          end
        end
      else
        open_port
        serial = @serial
        if serial
          configure_device
        else
          raise IO::Error.new("Could not open serial port")
        end
      end
    end

    # Test constructor: create without opening ports
    def initialize(@owner : WeaveInterface, @device : WeaveDevice, @switch_identity : Identity, no_connect : Bool = true)
      @port = ""
      @as_interface = true
      @switch_id = Bytes.new(4)         # placeholder
      @switch_pub_bytes = Bytes.new(32) # placeholder
      @device.connection = self
    end

    def open_port
      RNS.log("Opening serial port #{@port}...", RNS::LOG_VERBOSE)
      fd = LibC.open(@port, LibC::O_RDWR | LibC::O_NOCTTY | LibC::O_NONBLOCK)
      raise IO::Error.new("Could not open serial port #{@port}") if fd < 0
      configure_termios(fd)
      @serial = IO::FileDescriptor.new(fd, blocking: false)
    end

    private def configure_termios(fd : Int32)
      termios = LibC::Termios.new
      LibC.tcgetattr(fd, pointerof(termios))
      termios.c_iflag = LibC::TcflagT.new(0)
      termios.c_oflag = LibC::TcflagT.new(0)
      termios.c_lflag = LibC::TcflagT.new(0)
      termios.c_cflag = LibC::TcflagT.new(SerialConstants::CS8 | SerialConstants::CREAD | SerialConstants::CLOCAL)
      LibSerial.cfsetispeed(pointerof(termios).as(Void*), SerialConstants::B115200)
      LibSerial.cfsetospeed(pointerof(termios).as(Void*), SerialConstants::B115200)
      termios.c_cc[SerialConstants::VMIN] = 0_u8
      termios.c_cc[SerialConstants::VTIME] = 0_u8
      LibC.tcsetattr(fd, LibC::TCSANOW, pointerof(termios))
      LibSerial.tcflush(fd, SerialConstants::TCIOFLUSH)
    end

    def close
      @should_run = false
      @online = false
      @wdcl_connected = false
      @serial.try do |s|
        s.close unless s.closed?
      rescue ex
        RNS.log("Error closing serial port: #{ex.message}", RNS::LOG_DEBUG)
      end
      RNS.log("Closed serial port #{@port} for #{self}", RNS::LOG_VERBOSE)
    end

    def configure_device
      spawn { read_loop }
      RNS.log("Serial port #{@port} is now open, discovering remote device...", RNS::LOG_VERBOSE)
      @device.discover

      if @as_interface
        timeout = Time.utc.to_unix_f + WeaveWDCL::WDCL_HANDSHAKE_TIMEOUT
        while Time.utc.to_unix_f < timeout && !@wdcl_connected
          sleep(0.1)
        end
        unless @wdcl_connected
          raise IO::Error.new("WDCL connection handshake timed out for #{self}")
        end
      end

      @online = true
    end

    def process_incoming(data : Bytes)
      if @device
        while @frame_queue.size > 0
          @device.incoming_frame(@frame_queue.shift)
        end
        @device.incoming_frame(data)
      else
        @frame_queue.push(data)
      end
    end

    def process_outgoing(data : Bytes)
      serial = @serial
      return unless serial
      escaped = HDLC.escape(data)
      io = IO::Memory.new(escaped.size + 2)
      io.write_byte(HDLC::FLAG)
      io.write(escaped)
      io.write_byte(HDLC::FLAG)
      frame = io.to_slice
      serial.write(frame)
    end

    def read_loop
      buf = Bytes.new(1500)
      frame_buf = IO::Memory.new(4096)

      while @should_run
        serial = @serial
        break unless serial && !serial.closed?

        begin
          bytes_read = serial.read(buf)
          if bytes_read > 0
            frame_buf.write(buf[0, bytes_read])
            process_frames(frame_buf)
          else
            sleep(0.01)
          end
        rescue ex
          break
        end
      end
    rescue ex
      @online = false
      @wdcl_connected = false
      if @should_run
        RNS.log("A serial port error occurred, the contained exception was: #{ex.message}", RNS::LOG_ERROR)
        RNS.log("Will attempt to reconnect the interface periodically.", RNS::LOG_ERROR)
      end
    ensure
      @online = false
      @wdcl_connected = false
      @serial.try do |s|
        s.close unless s.closed?
      rescue ex
        RNS.log("Error closing serial port: #{ex.message}", RNS::LOG_DEBUG)
      end
      reconnect_port if @should_run
    end

    private def process_frames(frame_buf : IO::Memory)
      data = frame_buf.to_slice
      loop do
        frame_start = data.index(HDLC::FLAG)
        break unless frame_start

        remaining = data[frame_start + 1..]
        frame_end_idx = remaining.index(HDLC::FLAG)
        break unless frame_end_idx

        frame = remaining[0, frame_end_idx]
        unescaped = HDLC.unescape(frame)
        process_incoming(unescaped) if unescaped.size > WeaveWDCL::HEADER_MINSIZE

        data = remaining[frame_end_idx..]
      end

      # Keep unprocessed data in buffer
      new_buf = IO::Memory.new(data.size)
      new_buf.write(data)
      frame_buf.clear
      frame_buf.write(new_buf.to_slice)
    end

    def reconnect_port
      return if @reconnecting
      @reconnecting = true
      @wdcl_connected = false
      while !@online && @should_run
        begin
          sleep(5)
          RNS.log("Attempting to reconnect serial port #{@port} for #{@owner}...", RNS::LOG_DEBUG)
          open_port
          if @serial
            configure_device
          end
        rescue ex
          RNS.log("Error while reconnecting port, the contained exception was: #{ex.message}", RNS::LOG_ERROR)
        end
      end
      @reconnecting = false
      RNS.log("Reconnected serial port for #{self}", RNS::LOG_INFO) if @online
    end

    def to_s(io : IO)
      io << "WDCL over " << @port
    end
  end

  # Primary Weave interface for the Reticulum network stack.
  # Manages WDCL serial connections and spawns WeaveInterfacePeer instances
  # for each discovered remote endpoint.
  class WeaveInterface < Interface
    HW_MTU_VALUE   = 1024
    FIXED_MTU_FLAG = true

    DEFAULT_IFAC_SIZE =   16
    PEERING_TIMEOUT   = 20.0
    BITRATE_GUESS     = 250_i64 * 1000

    MULTI_IF_DEQUE_LEN =   48
    MULTI_IF_DEQUE_TTL = 0.75

    property dir_in : Bool = true
    property dir_out : Bool = false
    property switch_identity : Identity
    property port : String
    property hw_errors : Array(String) = [] of String
    property peers : Hash(Bytes, Array(Bytes | Float64 | WeaveInterfacePeer)) = {} of Bytes => Array(Bytes | Float64 | WeaveInterfacePeer)
    property timed_out_interfaces : Hash(Bytes, WeaveInterfacePeer) = {} of Bytes => WeaveInterfacePeer
    property peer_spawned_interfaces : Hash(Bytes, WeaveInterfacePeer) = {} of Bytes => WeaveInterfacePeer
    property write_lock : Mutex = Mutex.new
    property mif_deque : Deque(Bytes) = Deque(Bytes).new(MULTI_IF_DEQUE_LEN)
    property mif_deque_times : Deque(Tuple(Bytes, Float64)) = Deque(Tuple(Bytes, Float64)).new(MULTI_IF_DEQUE_LEN)
    property peer_job_interval : Float64 = PEERING_TIMEOUT * 1.1
    property peering_timeout : Float64 = PEERING_TIMEOUT
    property final_init_done : Bool = false

    @_online : Bool = false
    @device : WeaveDevice? = nil
    @connection : WeaveWDCLConnection? = nil

    def initialize(configuration : Hash(String, String))
      super()
      name = configuration["name"]? || "WeaveInterface"
      port = configuration["port"]?
      raise ArgumentError.new("No port specified for #{name}") unless port

      configured_bitrate = configuration["configured_bitrate"]?.try(&.to_i64)

      @hw_mtu = HW_MTU_VALUE
      @dir_in = true
      @dir_out = false
      @name = name
      @port = port
      @switch_identity = Identity.new
      @announce_rate_target = nil

      @bitrate = configured_bitrate || BITRATE_GUESS
    end

    # Test constructor
    def initialize(@name : String, @port : String, @switch_identity : Identity)
      super()
      @hw_mtu = HW_MTU_VALUE
      @dir_in = true
      @dir_out = false
    end

    def cpu_load : Int32?
      @device.try(&.cpu_load)
    end

    def mem_load : Float64?
      @device.try(&.memory_used_pct)
    end

    def switch_id : Bytes?
      @device.try(&.switch_id)
    end

    def endpoint_id : Bytes?
      @device.try(&.endpoint_id)
    end

    def device : WeaveDevice?
      @device
    end

    def connection : WeaveWDCLConnection?
      @connection
    end

    def final_init
      @device = WeaveDevice.new(as_interface: true, rns_interface: self)
      @connection = WeaveWDCLConnection.new(
        owner: self,
        device: @device.not_nil!,
        port: @port,
        as_interface: true,
      )

      spawn { peer_jobs }

      @_online = true
      @final_init_done = true
    end

    def peer_jobs
      loop do
        sleep(@peer_job_interval)
        now = Time.utc.to_unix_f
        timed_out_peers = [] of Bytes

        @peers.each do |peer_addr, peer|
          last_heard = peer[1].as(Float64)
          if now > last_heard + @peering_timeout
            timed_out_peers << peer_addr
          end
        end

        timed_out_peers.each do |peer_addr|
          removed_peer = @peers.delete(peer_addr)
          if si = @peer_spawned_interfaces[peer_addr]?
            si.detach
            si.teardown
          end
          if removed_peer
            RNS.log("#{self} removed peer #{RNS.hexrep(peer_addr)} on #{RNS.hexrep(removed_peer[0].as(Bytes))}", RNS::LOG_DEBUG)
          end
        end
      end
    end

    def peer_count : Int32
      @peer_spawned_interfaces.size
    end

    def endpoint_via(endpoint_addr : Bytes, via_switch_addr : Bytes)
      if peer = @peers[endpoint_addr]?
        peer[2].as(WeaveInterfacePeer).via_switch_id = via_switch_addr
      end
    end

    def add_peer(endpoint_addr : Bytes)
      unless @peers.has_key?(endpoint_addr)
        spawned_interface = WeaveInterfacePeer.new(self, endpoint_addr)
        spawned_interface.dir_out = @dir_out
        spawned_interface.dir_in = @dir_in
        spawned_interface.parent_interface = self.as(Interface)
        spawned_interface.bitrate = @bitrate

        spawned_interface.ifac_size = @ifac_size
        spawned_interface.ifac_netname = @ifac_netname
        spawned_interface.ifac_netkey = @ifac_netkey

        spawned_interface.announce_rate_target = @announce_rate_target
        spawned_interface.announce_rate_grace = @announce_rate_grace
        spawned_interface.announce_rate_penalty = @announce_rate_penalty
        spawned_interface.mode = @mode
        spawned_interface.hw_mtu = @hw_mtu
        spawned_interface._online = true

        # Clean up existing interface for this endpoint
        if old = @peer_spawned_interfaces[endpoint_addr]?
          old.detach
          old.teardown
        end

        @peer_spawned_interfaces[endpoint_addr] = spawned_interface
        @peers[endpoint_addr] = [endpoint_addr, Time.utc.to_unix_f, spawned_interface] of Bytes | Float64 | WeaveInterfacePeer

        RNS.log("#{self} added peer #{RNS.hexrep(endpoint_addr)}", RNS::LOG_DEBUG)
      else
        refresh_peer(endpoint_addr)
      end
    end

    def refresh_peer(endpoint_addr : Bytes)
      if peer = @peers[endpoint_addr]?
        peer[1] = Time.utc.to_unix_f
      end
    rescue ex
      RNS.log("An error occurred while refreshing peer #{RNS.hexrep(endpoint_addr)} on #{self}: #{ex.message}", RNS::LOG_ERROR)
    end

    def process_incoming(data : Bytes, endpoint_addr : Bytes? = nil)
      return unless @online
      ea = endpoint_addr
      return unless ea
      if si = @peer_spawned_interfaces[ea]?
        si.process_incoming(data, ea)
      end
    end

    def process_outgoing(data : Bytes)
      # No-op on parent interface
    end

    def detach
      @_online = false
      @detached = true
    end

    def online : Bool
      return false unless @_online
      @connection.try(&.online) || false
    end

    def online=(value : Bool)
      @_online = value
    end

    def to_s(io : IO)
      io << "WeaveInterface[" << @name << "]"
    end
  end

  # Represents an individual Weave peer connection.
  # Handles per-peer packet processing with deduplication.
  class WeaveInterfacePeer < Interface
    property dir_in : Bool = false
    property dir_out : Bool = false
    property endpoint_addr : Bytes
    property via_switch_id : Bytes? = nil
    property peer_addr : Bytes? = nil
    property _online : Bool = false

    @owner : WeaveInterface

    def initialize(@owner : WeaveInterface, @endpoint_addr : Bytes)
      super()
      @parent_interface = @owner.as(Interface)
      @hw_mtu = @owner.hw_mtu
      @name = "WeaveInterfacePeer[#{RNS.hexrep(@endpoint_addr)}]"
    end

    def online : Bool
      return false unless @_online
      @owner.online
    end

    def online=(value : Bool)
      @_online = value
    end

    def process_incoming(data : Bytes, endpoint_addr : Bytes? = nil)
      return unless online

      data_hash = RNS::Cryptography.full_hash(data)
      deque_hit = false

      if @owner.mif_deque.includes?(data_hash)
        @owner.mif_deque_times.each do |te|
          if te[0] == data_hash && Time.utc.to_unix_f < te[1] + WeaveInterface::MULTI_IF_DEQUE_TTL
            deque_hit = true
            break
          end
        end
      end

      unless deque_hit
        @owner.refresh_peer(@endpoint_addr)
        @owner.mif_deque.shift if @owner.mif_deque.size >= WeaveInterface::MULTI_IF_DEQUE_LEN
        @owner.mif_deque.push(data_hash)
        @owner.mif_deque_times.shift if @owner.mif_deque_times.size >= WeaveInterface::MULTI_IF_DEQUE_LEN
        @owner.mif_deque_times.push({data_hash, Time.utc.to_unix_f})
        @rxb += data.size
        @owner.rxb += data.size
      end
    end

    def process_outgoing(data : Bytes)
      return unless online
      @owner.write_lock.synchronize do
        @owner.device.try(&.deliver_packet(@endpoint_addr, data))
        @txb += data.size
        @owner.txb += data.size
      rescue ex
        RNS.log("Could not transmit on #{self}. The contained exception was: #{ex.message}", RNS::LOG_ERROR)
      end
    end

    def detach
      @_online = false
      @detached = true
    end

    def teardown
      if !@detached
        RNS.log("The interface #{self} experienced an unrecoverable error and is being torn down.", RNS::LOG_ERROR)
      else
        RNS.log("The interface #{self} is being torn down.", RNS::LOG_VERBOSE)
      end

      @_online = false
      @dir_out = false
      @dir_in = false

      @owner.peer_spawned_interfaces.delete(@endpoint_addr)
    end

    def to_s(io : IO)
      io << "WeaveInterfacePeer[" << RNS.hexrep(@endpoint_addr) << "]"
    end
  end
end
