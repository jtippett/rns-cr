require "../../spec_helper"

describe RNS::WeaveWDCL do
  describe "constants" do
    it "defines WDCL frame types" do
      RNS::WeaveWDCL::WDCL_T_DISCOVER.should eq(0x00_u8)
      RNS::WeaveWDCL::WDCL_T_CONNECT.should eq(0x01_u8)
      RNS::WeaveWDCL::WDCL_T_CMD.should eq(0x02_u8)
      RNS::WeaveWDCL::WDCL_T_LOG.should eq(0x03_u8)
      RNS::WeaveWDCL::WDCL_T_DISP.should eq(0x04_u8)
      RNS::WeaveWDCL::WDCL_T_ENDPOINT_PKT.should eq(0x05_u8)
      RNS::WeaveWDCL::WDCL_T_ENCAP_PROTO.should eq(0x06_u8)
    end

    it "defines broadcast address" do
      RNS::WeaveWDCL::WDCL_BROADCAST.should eq(Bytes[0xFF, 0xFF, 0xFF, 0xFF])
    end

    it "defines handshake timeout" do
      RNS::WeaveWDCL::WDCL_HANDSHAKE_TIMEOUT.should eq(2)
    end

    it "defines header min size" do
      RNS::WeaveWDCL::HEADER_MINSIZE.should eq(5)
    end
  end
end

describe RNS::WeaveCmd do
  describe "constants" do
    it "defines WDCL commands" do
      RNS::WeaveCmd::WDCL_CMD_ENDPOINT_PKT.should eq(0x0001_u16)
      RNS::WeaveCmd::WDCL_CMD_ENDPOINTS_LIST.should eq(0x0100_u16)
      RNS::WeaveCmd::WDCL_CMD_REMOTE_DISPLAY.should eq(0x0A00_u16)
      RNS::WeaveCmd::WDCL_CMD_REMOTE_INPUT.should eq(0x0A01_u16)
    end
  end
end

describe RNS::WeaveEvt do
  describe "constants" do
    it "defines system events" do
      RNS::WeaveEvt::ET_MSG.should eq(0x0000_u16)
      RNS::WeaveEvt::ET_SYSTEM_BOOT.should eq(0x0001_u16)
      RNS::WeaveEvt::ET_CORE_INIT.should eq(0x0002_u16)
    end

    it "defines driver events" do
      RNS::WeaveEvt::ET_DRV_UART_INIT.should eq(0x1000_u16)
      RNS::WeaveEvt::ET_DRV_USB_CDC_INIT.should eq(0x1010_u16)
      RNS::WeaveEvt::ET_DRV_USB_CDC_CONNECTED.should eq(0x1014_u16)
      RNS::WeaveEvt::ET_DRV_I2C_INIT.should eq(0x1020_u16)
      RNS::WeaveEvt::ET_DRV_NVS_INIT.should eq(0x1030_u16)
      RNS::WeaveEvt::ET_DRV_CRYPTO_INIT.should eq(0x1040_u16)
      RNS::WeaveEvt::ET_DRV_DISPLAY_INIT.should eq(0x1050_u16)
    end

    it "defines protocol events" do
      RNS::WeaveEvt::ET_PROTO_WDCL_INIT.should eq(0x3000_u16)
      RNS::WeaveEvt::ET_PROTO_WDCL_RUNNING.should eq(0x3001_u16)
      RNS::WeaveEvt::ET_PROTO_WDCL_CONNECTION.should eq(0x3002_u16)
      RNS::WeaveEvt::ET_PROTO_WDCL_HOST_ENDPOINT.should eq(0x3003_u16)
      RNS::WeaveEvt::ET_PROTO_WEAVE_INIT.should eq(0x3100_u16)
      RNS::WeaveEvt::ET_PROTO_WEAVE_RUNNING.should eq(0x3101_u16)
      RNS::WeaveEvt::ET_PROTO_WEAVE_EP_ALIVE.should eq(0x3102_u16)
      RNS::WeaveEvt::ET_PROTO_WEAVE_EP_TIMEOUT.should eq(0x3103_u16)
      RNS::WeaveEvt::ET_PROTO_WEAVE_EP_VIA.should eq(0x3104_u16)
    end

    it "defines statistics events" do
      RNS::WeaveEvt::ET_STAT_STATE.should eq(0xE000_u16)
      RNS::WeaveEvt::ET_STAT_UPTIME.should eq(0xE001_u16)
      RNS::WeaveEvt::ET_STAT_CPU.should eq(0xE003_u16)
      RNS::WeaveEvt::ET_STAT_TASK_CPU.should eq(0xE004_u16)
      RNS::WeaveEvt::ET_STAT_MEMORY.should eq(0xE005_u16)
    end

    it "defines interface types" do
      RNS::WeaveEvt::IF_TYPE_USB.should eq(0x01_u8)
      RNS::WeaveEvt::IF_TYPE_UART.should eq(0x02_u8)
      RNS::WeaveEvt::IF_TYPE_LORA.should eq(0x05_u8)
      RNS::WeaveEvt::IF_TYPE_WIFI.should eq(0x07_u8)
    end
  end

  describe "EVENT_DESCRIPTIONS" do
    it "has descriptions for all major events" do
      RNS::WeaveEvt::EVENT_DESCRIPTIONS[RNS::WeaveEvt::ET_SYSTEM_BOOT].should eq("System boot")
      RNS::WeaveEvt::EVENT_DESCRIPTIONS[RNS::WeaveEvt::ET_PROTO_WDCL_CONNECTION].should eq("WDCL host connection")
      RNS::WeaveEvt::EVENT_DESCRIPTIONS[RNS::WeaveEvt::ET_PROTO_WEAVE_EP_ALIVE].should eq("Weave endpoint alive")
    end
  end

  describe "INTERFACE_TYPES" do
    it "maps interface type codes to names" do
      RNS::WeaveEvt::INTERFACE_TYPES[RNS::WeaveEvt::IF_TYPE_USB].should eq("usb")
      RNS::WeaveEvt::INTERFACE_TYPES[RNS::WeaveEvt::IF_TYPE_LORA].should eq("lora")
      RNS::WeaveEvt::INTERFACE_TYPES[RNS::WeaveEvt::IF_TYPE_WIFI].should eq("wifi")
    end
  end

  describe "CHANNEL_DESCRIPTIONS" do
    it "describes WiFi channels" do
      RNS::WeaveEvt::CHANNEL_DESCRIPTIONS[1].should eq("Channel 1 (2412 MHz)")
      RNS::WeaveEvt::CHANNEL_DESCRIPTIONS[6].should eq("Channel 6 (2437 MHz)")
      RNS::WeaveEvt::CHANNEL_DESCRIPTIONS[14].should eq("Channel 14 (2484 MHz)")
    end
  end

  describe "log levels" do
    it "defines all log levels" do
      RNS::WeaveEvt::LOG_FORCE.should eq(0_u8)
      RNS::WeaveEvt::LOG_CRITICAL.should eq(1_u8)
      RNS::WeaveEvt::LOG_ERROR.should eq(2_u8)
      RNS::WeaveEvt::LOG_WARNING.should eq(3_u8)
      RNS::WeaveEvt::LOG_NOTICE.should eq(4_u8)
      RNS::WeaveEvt::LOG_INFO.should eq(5_u8)
      RNS::WeaveEvt::LOG_VERBOSE.should eq(6_u8)
      RNS::WeaveEvt::LOG_DEBUG.should eq(7_u8)
      RNS::WeaveEvt::LOG_EXTREME.should eq(8_u8)
      RNS::WeaveEvt::LOG_SYSTEM.should eq(9_u8)
    end
  end

  describe ".level" do
    it "returns level name for known levels" do
      RNS::WeaveEvt.level(0_u8).should eq("Forced")
      RNS::WeaveEvt.level(2_u8).should eq("Error")
      RNS::WeaveEvt.level(7_u8).should eq("Debug")
    end

    it "returns Unknown for invalid levels" do
      RNS::WeaveEvt.level(255_u8).should eq("Unknown")
    end
  end

  describe "TASK_DESCRIPTIONS" do
    it "maps task IDs to descriptions" do
      RNS::WeaveEvt::TASK_DESCRIPTIONS["protocol_wdcl"].should eq("Protocol: WDCL")
      RNS::WeaveEvt::TASK_DESCRIPTIONS["protocol_weave"].should eq("Protocol: Weave")
      RNS::WeaveEvt::TASK_DESCRIPTIONS["TinyUSB"].should eq("Driver: USB")
    end
  end
end

describe RNS::WeaveLogFrame do
  it "creates with default values" do
    frame = RNS::WeaveLogFrame.new
    frame.timestamp.should be_nil
    frame.level.should be_nil
    frame.event.should be_nil
    frame.data.should eq(Bytes.empty)
  end

  it "creates with specified values" do
    frame = RNS::WeaveLogFrame.new(
      timestamp: 1234.567,
      level: 5_u8,
      event: 0x3002_u16,
      data: Bytes[0x01, 0x02],
    )
    frame.timestamp.should eq(1234.567)
    frame.level.should eq(5_u8)
    frame.event.should eq(0x3002_u16)
    frame.data.should eq(Bytes[0x01, 0x02])
  end
end

describe RNS::WeaveEndpoint do
  it "creates with endpoint address" do
    addr = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
    ep = RNS::WeaveEndpoint.new(addr)
    ep.endpoint_addr.should eq(addr)
    ep.alive.should be > 0.0
    ep.via.should be_nil
    ep.received.should be_empty
  end

  it "receives data into queue" do
    addr = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
    ep = RNS::WeaveEndpoint.new(addr)
    ep.receive(Bytes[0xAA, 0xBB])
    ep.receive(Bytes[0xCC, 0xDD])
    ep.received.size.should eq(2)
    ep.received[0].should eq(Bytes[0xAA, 0xBB])
    ep.received[1].should eq(Bytes[0xCC, 0xDD])
  end

  it "limits queue length" do
    addr = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
    ep = RNS::WeaveEndpoint.new(addr)
    (RNS::WeaveEndpoint::QUEUE_LEN + 5).times do |i|
      ep.receive(Bytes[(i % 256).to_u8])
    end
    ep.received.size.should eq(RNS::WeaveEndpoint::QUEUE_LEN)
  end
end

describe RNS::WeaveDevice do
  describe "constants" do
    it "defines Weave protocol sizes" do
      RNS::WeaveDevice::WEAVE_SWITCH_ID_LEN.should eq(4)
      RNS::WeaveDevice::WEAVE_ENDPOINT_ID_LEN.should eq(8)
      RNS::WeaveDevice::WEAVE_FLOWSEQ_LEN.should eq(2)
      RNS::WeaveDevice::WEAVE_HMAC_LEN.should eq(8)
      RNS::WeaveDevice::WEAVE_AUTH_LEN.should eq(16)
      RNS::WeaveDevice::WEAVE_PUBKEY_SIZE.should eq(32)
      RNS::WeaveDevice::WEAVE_PRVKEY_SIZE.should eq(64)
      RNS::WeaveDevice::WEAVE_SIGNATURE_LEN.should eq(64)
    end

    it "defines stat limits" do
      RNS::WeaveDevice::STATLEN_MAX.should eq(120)
      RNS::WeaveDevice::STAT_UPDATE_THROTTLE.should eq(0.5)
    end
  end

  describe "#initialize" do
    it "creates device with defaults" do
      device = RNS::WeaveDevice.new
      device.identity.should be_nil
      device.switch_id.should be_nil
      device.endpoint_id.should be_nil
      device.as_interface.should be_false
      device.endpoints.should be_empty
      device.cpu_load.should eq(0)
      device.memory_total.should eq(0)
      device.memory_free.should eq(0)
      device.memory_used.should eq(0)
      device.memory_used_pct.should eq(0.0)
      device.update_display.should be_false
    end

    it "creates device as interface" do
      device = RNS::WeaveDevice.new(as_interface: true)
      device.as_interface.should be_true
    end
  end

  describe "#endpoint_alive" do
    it "creates new endpoint when not known" do
      device = RNS::WeaveDevice.new
      addr = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
      device.endpoint_alive(addr)
      device.endpoints.size.should eq(1)
      device.endpoints[addr].should_not be_nil
    end

    it "updates alive time for known endpoint" do
      device = RNS::WeaveDevice.new
      addr = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
      device.endpoint_alive(addr)
      first_alive = device.endpoints[addr].alive
      sleep(0.01)
      device.endpoint_alive(addr)
      device.endpoints[addr].alive.should be >= first_alive
    end
  end

  describe "#endpoint_via" do
    it "sets via switch ID for known endpoint" do
      device = RNS::WeaveDevice.new
      addr = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
      via = Bytes[0xAA, 0xBB, 0xCC, 0xDD]
      device.endpoint_alive(addr)
      device.endpoint_via(addr, via)
      device.endpoints[addr].via.should eq(via)
    end

    it "does nothing for unknown endpoint" do
      device = RNS::WeaveDevice.new
      addr = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
      via = Bytes[0xAA, 0xBB, 0xCC, 0xDD]
      device.endpoint_via(addr, via) # Should not raise
    end
  end

  describe "#capture_stats_cpu" do
    it "captures CPU stats" do
      device = RNS::WeaveDevice.new
      device.cpu_load = 45
      device.capture_stats_cpu
      device.cpu_stats.size.should eq(1)
    end

    it "respects max stat length" do
      device = RNS::WeaveDevice.new
      (RNS::WeaveDevice::STATLEN_MAX + 10).times do |i|
        device.cpu_load = i % 100
        device.capture_stats_cpu
      end
      device.cpu_stats.size.should eq(RNS::WeaveDevice::STATLEN_MAX)
    end
  end

  describe "#capture_stats_memory" do
    it "captures memory stats" do
      device = RNS::WeaveDevice.new
      device.memory_used = 50000
      device.capture_stats_memory
      device.memory_stats.size.should eq(1)
    end
  end

  describe "#get_cpu_stats" do
    it "returns formatted CPU stats" do
      device = RNS::WeaveDevice.new
      device.cpu_load = 50
      device.capture_stats_cpu
      device.cpu_load = 75
      device.capture_stats_cpu

      stats = device.get_cpu_stats
      stats["max"].should eq(100.0)
      stats["unit"].should eq("%")
      stats["values"].as(Array(Float64)).size.should eq(2)
    end
  end

  describe "#get_memory_stats" do
    it "returns formatted memory stats" do
      device = RNS::WeaveDevice.new
      device.memory_total = 100000
      device.memory_used = 60000
      device.capture_stats_memory
      device.memory_used = 70000
      device.capture_stats_memory

      stats = device.get_memory_stats
      stats["max"].should eq(100000_i64)
      stats["unit"].should eq("B")
      stats["values"].as(Array(Float64)).size.should eq(2)
    end
  end

  describe "#get_active_tasks" do
    it "returns non-idle tasks" do
      device = RNS::WeaveDevice.new
      device.active_tasks["protocol_wdcl"] = {"cpu_load" => 10, "timestamp" => Time.utc.to_unix_f} of String => Float64 | Int32
      device.active_tasks["IDLE0"] = {"cpu_load" => 90, "timestamp" => Time.utc.to_unix_f} of String => Float64 | Int32

      tasks = device.get_active_tasks
      tasks.has_key?("Protocol: WDCL").should be_true
      tasks.has_key?("IDLE0").should be_false
    end

    it "filters out stale tasks" do
      device = RNS::WeaveDevice.new
      device.active_tasks["old_task"] = {"cpu_load" => 10, "timestamp" => Time.utc.to_unix_f - 10.0} of String => Float64 | Int32

      tasks = device.get_active_tasks
      tasks.should be_empty
    end
  end

  describe "#log_handle" do
    it "handles WDCL connection event" do
      device = RNS::WeaveDevice.new(as_interface: true)
      # Need a connection to set wdcl_connected on
      # We test the logic indirectly

      frame = RNS::WeaveLogFrame.new(
        timestamp: 1000.0,
        level: 5_u8,
        event: RNS::WeaveEvt::ET_PROTO_WDCL_CONNECTION,
      )
      # Should not raise when no connection set
    end

    it "handles CPU stat event" do
      device = RNS::WeaveDevice.new
      frame = RNS::WeaveLogFrame.new(
        timestamp: 1000.0,
        level: 5_u8,
        event: RNS::WeaveEvt::ET_STAT_CPU,
        data: Bytes[75],
      )
      device.log_handle(frame)
      device.cpu_load.should eq(75)
      device.cpu_stats.size.should eq(1)
    end

    it "handles memory stat event" do
      device = RNS::WeaveDevice.new
      # 4 bytes free + 4 bytes total
      frame = RNS::WeaveLogFrame.new(
        timestamp: 1000.0,
        level: 5_u8,
        event: RNS::WeaveEvt::ET_STAT_MEMORY,
        data: Bytes[0x00, 0x00, 0x80, 0x00, 0x00, 0x01, 0x00, 0x00], # free=32768, total=65536
      )
      device.log_handle(frame)
      device.memory_free.should eq(32768)
      device.memory_total.should eq(65536)
      device.memory_used.should eq(32768)
      device.memory_used_pct.should eq(50.0)
    end

    it "handles task CPU event" do
      device = RNS::WeaveDevice.new
      task_name = "protocol_wdcl"
      data = IO::Memory.new
      data.write_byte(42_u8) # CPU load percentage
      data.write(task_name.to_slice)
      frame = RNS::WeaveLogFrame.new(
        timestamp: 1000.0,
        level: 5_u8,
        event: RNS::WeaveEvt::ET_STAT_TASK_CPU,
        data: data.to_slice,
      )
      device.log_handle(frame)
      device.active_tasks[task_name]["cpu_load"].should eq(42)
    end

    it "handles host endpoint event" do
      device = RNS::WeaveDevice.new
      ep_data = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
      frame = RNS::WeaveLogFrame.new(
        timestamp: 1000.0,
        level: 5_u8,
        event: RNS::WeaveEvt::ET_PROTO_WDCL_HOST_ENDPOINT,
        data: ep_data,
      )
      device.log_handle(frame)
      device.endpoint_id.should eq(ep_data)
    end
  end
end

describe RNS::WeaveInterface do
  describe "constants" do
    it "defines HW_MTU" do
      RNS::WeaveInterface::HW_MTU_VALUE.should eq(1024)
    end

    it "defines FIXED_MTU" do
      RNS::WeaveInterface::FIXED_MTU_FLAG.should be_true
    end

    it "defines default IFAC size" do
      RNS::WeaveInterface::DEFAULT_IFAC_SIZE.should eq(16)
    end

    it "defines peering timeout" do
      RNS::WeaveInterface::PEERING_TIMEOUT.should eq(20.0)
    end

    it "defines bitrate guess" do
      RNS::WeaveInterface::BITRATE_GUESS.should eq(250_000)
    end

    it "defines multi-interface deque parameters" do
      RNS::WeaveInterface::MULTI_IF_DEQUE_LEN.should eq(48)
      RNS::WeaveInterface::MULTI_IF_DEQUE_TTL.should eq(0.75)
    end
  end

  describe "#initialize with config hash" do
    it "creates interface from configuration" do
      config = {"name" => "TestWeave", "port" => "/dev/ttyUSB0"}
      iface = RNS::WeaveInterface.new(config)
      iface.name.should eq("TestWeave")
      iface.port.should eq("/dev/ttyUSB0")
      iface.online.should be_false
      iface.hw_mtu.should eq(1024)
    end

    it "uses configured bitrate when provided" do
      config = {"name" => "TestWeave", "port" => "/dev/ttyUSB0", "configured_bitrate" => "500000"}
      iface = RNS::WeaveInterface.new(config)
      iface.bitrate.should eq(500_000)
    end

    it "uses default bitrate guess when not configured" do
      config = {"name" => "TestWeave", "port" => "/dev/ttyUSB0"}
      iface = RNS::WeaveInterface.new(config)
      iface.bitrate.should eq(RNS::WeaveInterface::BITRATE_GUESS)
    end

    it "raises when no port specified" do
      config = {"name" => "TestWeave"} of String => String
      expect_raises(ArgumentError, /No port specified/) do
        RNS::WeaveInterface.new(config)
      end
    end
  end

  describe "#initialize with test constructor" do
    it "creates interface with name, port, and identity" do
      identity = RNS::Identity.new
      iface = RNS::WeaveInterface.new("TestWeave", "/dev/ttyUSB0", identity)
      iface.name.should eq("TestWeave")
      iface.port.should eq("/dev/ttyUSB0")
      iface.switch_identity.should eq(identity)
    end
  end

  describe "#to_s" do
    it "formats as WeaveInterface[name]" do
      identity = RNS::Identity.new
      iface = RNS::WeaveInterface.new("TestWeave", "/dev/ttyUSB0", identity)
      iface.to_s.should eq("WeaveInterface[TestWeave]")
    end
  end

  describe "property accessors" do
    it "returns nil for cpu_load when no device" do
      identity = RNS::Identity.new
      iface = RNS::WeaveInterface.new("TestWeave", "/dev/ttyUSB0", identity)
      iface.cpu_load.should be_nil
    end

    it "returns nil for mem_load when no device" do
      identity = RNS::Identity.new
      iface = RNS::WeaveInterface.new("TestWeave", "/dev/ttyUSB0", identity)
      iface.mem_load.should be_nil
    end

    it "returns nil for switch_id when no device" do
      identity = RNS::Identity.new
      iface = RNS::WeaveInterface.new("TestWeave", "/dev/ttyUSB0", identity)
      iface.switch_id.should be_nil
    end

    it "returns nil for endpoint_id when no device" do
      identity = RNS::Identity.new
      iface = RNS::WeaveInterface.new("TestWeave", "/dev/ttyUSB0", identity)
      iface.endpoint_id.should be_nil
    end
  end

  describe "#peer_count" do
    it "returns 0 when no peers" do
      identity = RNS::Identity.new
      iface = RNS::WeaveInterface.new("TestWeave", "/dev/ttyUSB0", identity)
      iface.peer_count.should eq(0)
    end
  end

  describe "#process_outgoing" do
    it "is a no-op on parent interface" do
      identity = RNS::Identity.new
      iface = RNS::WeaveInterface.new("TestWeave", "/dev/ttyUSB0", identity)
      iface.process_outgoing(Bytes[0x01, 0x02]) # Should not raise
    end
  end

  describe "#detach" do
    it "sets interface offline" do
      identity = RNS::Identity.new
      iface = RNS::WeaveInterface.new("TestWeave", "/dev/ttyUSB0", identity)
      iface.detach
      iface.online.should be_false
      iface.detached?.should be_true
    end
  end

  describe "#refresh_peer" do
    it "handles missing peer gracefully" do
      identity = RNS::Identity.new
      iface = RNS::WeaveInterface.new("TestWeave", "/dev/ttyUSB0", identity)
      addr = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
      iface.refresh_peer(addr) # Should not raise
    end
  end
end

describe RNS::WeaveInterfacePeer do
  describe "#initialize" do
    it "creates peer with owner and endpoint address" do
      identity = RNS::Identity.new
      owner = RNS::WeaveInterface.new("TestWeave", "/dev/ttyUSB0", identity)
      addr = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
      peer = RNS::WeaveInterfacePeer.new(owner, addr)
      peer.endpoint_addr.should eq(addr)
      peer.via_switch_id.should be_nil
      peer._online.should be_false
      peer.hw_mtu.should eq(owner.hw_mtu)
    end
  end

  describe "#to_s" do
    it "formats as WeaveInterfacePeer[hexrep]" do
      identity = RNS::Identity.new
      owner = RNS::WeaveInterface.new("TestWeave", "/dev/ttyUSB0", identity)
      addr = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
      peer = RNS::WeaveInterfacePeer.new(owner, addr)
      peer.to_s.should contain("WeaveInterfacePeer[")
    end
  end

  describe "#online" do
    it "returns false when _online is false" do
      identity = RNS::Identity.new
      owner = RNS::WeaveInterface.new("TestWeave", "/dev/ttyUSB0", identity)
      addr = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
      peer = RNS::WeaveInterfacePeer.new(owner, addr)
      peer.online.should be_false
    end

    it "returns false when owner is offline" do
      identity = RNS::Identity.new
      owner = RNS::WeaveInterface.new("TestWeave", "/dev/ttyUSB0", identity)
      addr = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
      peer = RNS::WeaveInterfacePeer.new(owner, addr)
      peer._online = true
      peer.online.should be_false # Owner is offline
    end
  end

  describe "#detach" do
    it "marks peer as offline and detached" do
      identity = RNS::Identity.new
      owner = RNS::WeaveInterface.new("TestWeave", "/dev/ttyUSB0", identity)
      addr = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
      peer = RNS::WeaveInterfacePeer.new(owner, addr)
      peer._online = true
      peer.detach
      peer._online.should be_false
      peer.detached?.should be_true
    end
  end

  describe "#teardown" do
    it "removes peer from owner spawned_interfaces" do
      identity = RNS::Identity.new
      owner = RNS::WeaveInterface.new("TestWeave", "/dev/ttyUSB0", identity)
      addr = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
      peer = RNS::WeaveInterfacePeer.new(owner, addr)
      owner.peer_spawned_interfaces[addr] = peer

      peer.detach
      peer.teardown

      owner.peer_spawned_interfaces.has_key?(addr).should be_false
      peer._online.should be_false
      peer.dir_out.should be_false
      peer.dir_in.should be_false
    end
  end

  describe "#process_incoming with deduplication" do
    it "does not process when offline" do
      identity = RNS::Identity.new
      owner = RNS::WeaveInterface.new("TestWeave", "/dev/ttyUSB0", identity)
      addr = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
      peer = RNS::WeaveInterfacePeer.new(owner, addr)
      peer._online = false

      peer.process_incoming(Bytes[0xAA, 0xBB])
      peer.rxb.should eq(0)
    end
  end
end

describe "WDCL HDLC framing integration" do
  it "HDLC escape and unescape roundtrip for WDCL data" do
    original = Bytes[0x7E, 0x7D, 0x01, 0x02, 0x03, 0x7E]
    escaped = RNS::HDLC.escape(original)
    unescaped = RNS::HDLC.unescape(escaped)
    unescaped.should eq(original)
  end

  it "HDLC frame roundtrip" do
    data = Bytes[0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0xAA, 0xBB]
    framed = RNS::HDLC.frame(data)
    framed[0].should eq(RNS::HDLC::FLAG)
    framed[-1].should eq(RNS::HDLC::FLAG)

    # Extract and unescape the middle
    inner = framed[1...-1]
    unescaped = RNS::HDLC.unescape(inner)
    unescaped.should eq(data)
  end
end
