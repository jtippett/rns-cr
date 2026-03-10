require "../../spec_helper"

describe RNS::RNodeMultiKISS do
  describe "constants" do
    it "defines frame delimiters matching base KISS" do
      RNS::RNodeMultiKISS::FEND.should eq(0xC0_u8)
      RNS::RNodeMultiKISS::FESC.should eq(0xDB_u8)
      RNS::RNodeMultiKISS::TFEND.should eq(0xDC_u8)
      RNS::RNodeMultiKISS::TFESC.should eq(0xDD_u8)
    end

    it "defines multi-interface selection command" do
      RNS::RNodeMultiKISS::CMD_SEL_INT.should eq(0x1F_u8)
    end

    it "defines interfaces command" do
      RNS::RNodeMultiKISS::CMD_INTERFACES.should eq(0x71_u8)
    end

    it "defines all per-interface data commands" do
      RNS::RNodeMultiKISS::CMD_INT0_DATA.should eq(0x00_u8)
      RNS::RNodeMultiKISS::CMD_INT1_DATA.should eq(0x10_u8)
      RNS::RNodeMultiKISS::CMD_INT2_DATA.should eq(0x20_u8)
      RNS::RNodeMultiKISS::CMD_INT3_DATA.should eq(0x70_u8)
      RNS::RNodeMultiKISS::CMD_INT4_DATA.should eq(0x75_u8)
      RNS::RNodeMultiKISS::CMD_INT5_DATA.should eq(0x90_u8)
      RNS::RNodeMultiKISS::CMD_INT6_DATA.should eq(0xA0_u8)
      RNS::RNodeMultiKISS::CMD_INT7_DATA.should eq(0xB0_u8)
      RNS::RNodeMultiKISS::CMD_INT8_DATA.should eq(0xC0_u8)
      RNS::RNodeMultiKISS::CMD_INT9_DATA.should eq(0xD0_u8)
      RNS::RNodeMultiKISS::CMD_INT10_DATA.should eq(0xE0_u8)
      RNS::RNodeMultiKISS::CMD_INT11_DATA.should eq(0xF0_u8)
    end

    it "defines chip types" do
      RNS::RNodeMultiKISS::SX127X.should eq(0x00_u8)
      RNS::RNodeMultiKISS::SX1276.should eq(0x01_u8)
      RNS::RNodeMultiKISS::SX1278.should eq(0x02_u8)
      RNS::RNodeMultiKISS::SX126X.should eq(0x10_u8)
      RNS::RNodeMultiKISS::SX1262.should eq(0x11_u8)
      RNS::RNodeMultiKISS::SX128X.should eq(0x20_u8)
      RNS::RNodeMultiKISS::SX1280.should eq(0x21_u8)
    end

    it "defines INT_DATA_CMDS array with all 12 commands" do
      RNS::RNodeMultiKISS::INT_DATA_CMDS.size.should eq(12)
    end

    it "re-exports base RNode KISS commands" do
      RNS::RNodeMultiKISS::CMD_DATA.should eq(RNS::RNodeKISS::CMD_DATA)
      RNS::RNodeMultiKISS::CMD_FREQUENCY.should eq(RNS::RNodeKISS::CMD_FREQUENCY)
      RNS::RNodeMultiKISS::CMD_BANDWIDTH.should eq(RNS::RNodeKISS::CMD_BANDWIDTH)
      RNS::RNodeMultiKISS::CMD_TXPOWER.should eq(RNS::RNodeKISS::CMD_TXPOWER)
      RNS::RNodeMultiKISS::CMD_SF.should eq(RNS::RNodeKISS::CMD_SF)
      RNS::RNodeMultiKISS::CMD_CR.should eq(RNS::RNodeKISS::CMD_CR)
      RNS::RNodeMultiKISS::CMD_DETECT.should eq(RNS::RNodeKISS::CMD_DETECT)
      RNS::RNodeMultiKISS::CMD_READY.should eq(RNS::RNodeKISS::CMD_READY)
      RNS::RNodeMultiKISS::CMD_ERROR.should eq(RNS::RNodeKISS::CMD_ERROR)
    end
  end

  describe ".interface_type_to_str" do
    it "returns SX127X for SX127X chip types" do
      RNS::RNodeMultiKISS.interface_type_to_str(RNS::RNodeMultiKISS::SX127X).should eq("SX127X")
      RNS::RNodeMultiKISS.interface_type_to_str(RNS::RNodeMultiKISS::SX1276).should eq("SX127X")
      RNS::RNodeMultiKISS.interface_type_to_str(RNS::RNodeMultiKISS::SX1278).should eq("SX127X")
    end

    it "returns SX126X for SX126X chip types" do
      RNS::RNodeMultiKISS.interface_type_to_str(RNS::RNodeMultiKISS::SX126X).should eq("SX126X")
      RNS::RNodeMultiKISS.interface_type_to_str(RNS::RNodeMultiKISS::SX1262).should eq("SX126X")
    end

    it "returns SX128X for SX128X chip types" do
      RNS::RNodeMultiKISS.interface_type_to_str(RNS::RNodeMultiKISS::SX128X).should eq("SX128X")
      RNS::RNodeMultiKISS.interface_type_to_str(RNS::RNodeMultiKISS::SX1280).should eq("SX128X")
    end

    it "returns SX127X for unknown types" do
      RNS::RNodeMultiKISS.interface_type_to_str(0xFF_u8).should eq("SX127X")
    end
  end

  describe ".is_data_cmd?" do
    it "returns true for all data commands" do
      RNS::RNodeMultiKISS.is_data_cmd?(RNS::RNodeMultiKISS::CMD_INT0_DATA).should be_true
      RNS::RNodeMultiKISS.is_data_cmd?(RNS::RNodeMultiKISS::CMD_INT1_DATA).should be_true
      RNS::RNodeMultiKISS.is_data_cmd?(RNS::RNodeMultiKISS::CMD_INT11_DATA).should be_true
    end

    it "returns false for non-data commands" do
      RNS::RNodeMultiKISS.is_data_cmd?(RNS::RNodeMultiKISS::CMD_FREQUENCY).should be_false
      RNS::RNodeMultiKISS.is_data_cmd?(RNS::RNodeMultiKISS::CMD_DETECT).should be_false
      RNS::RNodeMultiKISS.is_data_cmd?(0xFF_u8).should be_false
    end
  end

  describe ".escape" do
    it "escapes KISS control bytes" do
      data = Bytes[0xC0, 0xDB, 0x42]
      escaped = RNS::RNodeMultiKISS.escape(data)
      escaped.should eq(Bytes[0xDB, 0xDC, 0xDB, 0xDD, 0x42])
    end

    it "passes through data with no special bytes" do
      data = Bytes[0x01, 0x02, 0x03]
      RNS::RNodeMultiKISS.escape(data).should eq(data)
    end
  end
end

describe RNS::SubIntConfig do
  it "creates a subinterface configuration record" do
    config = RNS::SubIntConfig.new(
      name: "sub0",
      vport: 0,
      frequency: 868_000_000_i64,
      bandwidth: 125_000_i64,
      txpower: 17,
      sf: 7,
      cr: 5,
      flow_control: false,
      st_alock: 50.0,
      lt_alock: 80.0,
      outgoing: true,
    )
    config.name.should eq("sub0")
    config.vport.should eq(0)
    config.frequency.should eq(868_000_000_i64)
    config.bandwidth.should eq(125_000_i64)
    config.txpower.should eq(17)
    config.sf.should eq(7)
    config.cr.should eq(5)
    config.flow_control.should be_false
    config.st_alock.should eq(50.0)
    config.lt_alock.should eq(80.0)
    config.outgoing.should be_true
  end
end

describe RNS::RNodeMultiInterface do
  describe "constants" do
    it "defines interface limits" do
      RNS::RNodeMultiInterface::MAX_SUBINTERFACES.should eq(11)
      RNS::RNodeMultiInterface::MAX_CHUNK.should eq(32768)
      RNS::RNodeMultiInterface::CALLSIGN_MAX_LEN.should eq(32)
      RNS::RNodeMultiInterface::DEFAULT_IFAC_SIZE.should eq(8)
    end

    it "defines firmware version requirements" do
      RNS::RNodeMultiInterface::REQUIRED_FW_VER_MAJ.should eq(1)
      RNS::RNodeMultiInterface::REQUIRED_FW_VER_MIN.should eq(74)
    end

    it "defines reconnect wait time" do
      RNS::RNodeMultiInterface::RECONNECT_WAIT.should eq(5)
    end

    it "defines framebuffer constants" do
      RNS::RNodeMultiInterface::FB_PIXEL_WIDTH.should eq(64)
      RNS::RNodeMultiInterface::FB_BITS_PER_PIXEL.should eq(1)
      RNS::RNodeMultiInterface::FB_PIXELS_PER_BYTE.should eq(8)
      RNS::RNodeMultiInterface::FB_BYTES_PER_LINE.should eq(8)
    end
  end

  describe "#initialize with test constructor" do
    it "creates an interface with name and port" do
      iface = RNS::RNodeMultiInterface.new("TestMulti", "/dev/ttyUSB0")
      iface.name.should eq("TestMulti")
      iface.port.should eq("/dev/ttyUSB0")
      iface.online.should be_false
      iface.hw_mtu.should eq(508)
    end

    it "initializes subinterfaces array" do
      iface = RNS::RNodeMultiInterface.new("TestMulti", "/dev/ttyUSB0")
      iface.subinterfaces.size.should eq(RNS::RNodeMultiInterface::MAX_SUBINTERFACES)
      iface.subinterfaces.all?(&.nil?).should be_true
    end

    it "initializes subinterface_types as empty" do
      iface = RNS::RNodeMultiInterface.new("TestMulti", "/dev/ttyUSB0")
      iface.subinterface_types.should be_empty
    end
  end

  describe "#initialize with config hash" do
    it "raises when no port specified" do
      config = {"name" => "Test"} of String => String | Hash(String, String)
      expect_raises(ArgumentError, /No port specified/) do
        RNS::RNodeMultiInterface.new(config)
      end
    end

    it "raises when no subinterfaces configured" do
      config = {
        "name" => "Test",
        "port" => "/dev/ttyUSB0",
      } of String => String | Hash(String, String)
      expect_raises(ArgumentError, /No subinterfaces configured/) do
        RNS::RNodeMultiInterface.new(config)
      end
    end

    it "parses subinterface configurations" do
      config = {
        "name"    => "TestMulti",
        "port"    => "/dev/ttyUSB0",
        "enabled" => "true",
        "sub0"    => {
          "interface_enabled" => "true",
          "vport"             => "0",
          "frequency"         => "868000000",
          "bandwidth"         => "125000",
          "txpower"           => "17",
          "spreadingfactor"   => "7",
          "codingrate"        => "5",
        } of String => String,
      } of String => String | Hash(String, String)

      iface = RNS::RNodeMultiInterface.new(config)
      iface.name.should eq("TestMulti")
      iface.port.should eq("/dev/ttyUSB0")
      iface.subint_config.size.should eq(1)
      iface.subint_config[0].name.should eq("sub0")
      iface.subint_config[0].vport.should eq(0)
      iface.subint_config[0].frequency.should eq(868_000_000_i64)
    end
  end

  describe "#should_ingress_limit?" do
    it "returns false" do
      iface = RNS::RNodeMultiInterface.new("TestMulti", "/dev/ttyUSB0")
      iface.should_ingress_limit?.should be_false
    end
  end

  describe "#to_s" do
    it "formats as RNodeMultiInterface[name]" do
      iface = RNS::RNodeMultiInterface.new("TestMulti", "/dev/ttyUSB0")
      iface.to_s.should eq("RNodeMultiInterface[TestMulti]")
    end
  end

  describe "#validate_firmware" do
    it "accepts valid firmware version" do
      iface = RNS::RNodeMultiInterface.new("TestMulti", "/dev/ttyUSB0")
      iface.maj_version = 1
      iface.min_version = 74
      iface.validate_firmware
      iface.firmware_ok.should be_true
    end

    it "accepts newer firmware version" do
      iface = RNS::RNodeMultiInterface.new("TestMulti", "/dev/ttyUSB0")
      iface.maj_version = 2
      iface.min_version = 0
      iface.validate_firmware
      iface.firmware_ok.should be_true
    end
  end

  describe "#received_announce / #sent_announce" do
    it "tracks announce timestamps when from spawned" do
      iface = RNS::RNodeMultiInterface.new("TestMulti", "/dev/ttyUSB0")
      iface.received_announce(from_spawned: true)
      iface.sent_announce(from_spawned: true)
      # Should not raise; deques should have entries
    end

    it "does not track when not from spawned" do
      iface = RNS::RNodeMultiInterface.new("TestMulti", "/dev/ttyUSB0")
      iface.received_announce(from_spawned: false)
      iface.sent_announce(from_spawned: false)
    end
  end
end

describe RNS::RNodeSubInterface do
  describe "constants" do
    it "defines frequency ranges" do
      RNS::RNodeSubInterface::LOW_FREQ_MIN.should eq(137_000_000_i64)
      RNS::RNodeSubInterface::LOW_FREQ_MAX.should eq(1_000_000_000_i64)
      RNS::RNodeSubInterface::HIGH_FREQ_MIN.should eq(2_200_000_000_i64)
      RNS::RNodeSubInterface::HIGH_FREQ_MAX.should eq(2_600_000_000_i64)
    end

    it "defines RSSI offset" do
      RNS::RNodeSubInterface::RSSI_OFFSET.should eq(157)
    end

    it "defines quality SNR parameters" do
      RNS::RNodeSubInterface::Q_SNR_MIN_BASE.should eq(-9)
      RNS::RNodeSubInterface::Q_SNR_MAX.should eq(6)
      RNS::RNodeSubInterface::Q_SNR_STEP.should eq(2)
    end
  end

  describe "#initialize with skip_configure" do
    it "creates a subinterface and registers with parent" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      sub = RNS::RNodeSubInterface.new("Sub0", parent, 0, "SX127X", skip_configure: true)
      sub.name.should eq("Sub0")
      sub.index.should eq(0)
      sub.interface_type.should eq("SX127X")
      sub.rnode_parent.should eq(parent)
      parent.subinterfaces[0].should eq(sub)
    end
  end

  describe "#to_s" do
    it "formats as ParentName[SubName]" do
      parent = RNS::RNodeMultiInterface.new("RNode", "/dev/ttyUSB0")
      sub = RNS::RNodeSubInterface.new("Radio0", parent, 0, "SX127X", skip_configure: true)
      sub.to_s.should eq("RNode[Radio0]")
    end
  end

  describe "#update_bitrate" do
    it "calculates bitrate from radio parameters" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      sub = RNS::RNodeSubInterface.new("Sub0", parent, 0, "SX127X", skip_configure: true)
      sub.r_sf = 7
      sub.r_cr = 5
      sub.r_bandwidth = 125_000_i64
      sub.update_bitrate
      sub.bitrate.should be > 0
      sub.bitrate_kbps.should be > 0.0
    end

    it "handles missing radio parameters gracefully" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      sub = RNS::RNodeSubInterface.new("Sub0", parent, 0, "SX127X", skip_configure: true)
      sub.r_sf = nil
      sub.update_bitrate
      # Should not raise
    end
  end

  describe "#process_incoming" do
    it "updates receive byte counter and clears stats" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      sub = RNS::RNodeSubInterface.new("Sub0", parent, 0, "SX127X", skip_configure: true)
      sub.r_stat_rssi = -80
      sub.r_stat_snr = 5.0

      data = Bytes[0x01, 0x02, 0x03]
      sub.process_incoming(data)

      sub.rxb.should eq(3)
      sub.r_stat_rssi.should be_nil
      sub.r_stat_snr.should be_nil
    end
  end

  describe "#queue and #process_queue" do
    it "queues data and processes it" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      sub = RNS::RNodeSubInterface.new("Sub0", parent, 0, "SX127X", skip_configure: true)
      sub.interface_ready = false

      data = Bytes[0x01, 0x02, 0x03]
      sub.queue(data)
      sub.packet_queue.size.should eq(1)

      sub.process_queue
      sub.interface_ready.should be_true
      sub.packet_queue.size.should eq(0)
    end

    it "sets interface_ready when queue is empty" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      sub = RNS::RNodeSubInterface.new("Sub0", parent, 0, "SX127X", skip_configure: true)
      sub.interface_ready = false

      sub.process_queue
      sub.interface_ready.should be_true
    end
  end

  describe "radio parameter validation" do
    it "rejects invalid frequency for SX127X" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      expect_raises(ArgumentError) do
        RNS::RNodeSubInterface.new(
          name: "BadFreq",
          parent_interface: parent,
          index: 0,
          interface_type: "SX127X",
          frequency: 50_000_000_i64, # Too low
          bandwidth: 125_000_i64,
          txpower: 17,
          sf: 7,
          cr: 5,
        )
      end
    end

    it "rejects invalid frequency for SX128X" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      expect_raises(ArgumentError) do
        RNS::RNodeSubInterface.new(
          name: "BadFreq",
          parent_interface: parent,
          index: 0,
          interface_type: "SX128X",
          frequency: 1_000_000_000_i64, # Too low for 2.4GHz
          bandwidth: 125_000_i64,
          txpower: 17,
          sf: 7,
          cr: 5,
        )
      end
    end

    it "rejects invalid TX power" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      expect_raises(ArgumentError) do
        RNS::RNodeSubInterface.new(
          name: "BadTX",
          parent_interface: parent,
          index: 0,
          interface_type: "SX127X",
          frequency: 868_000_000_i64,
          bandwidth: 125_000_i64,
          txpower: 50, # Too high
          sf: 7,
          cr: 5,
        )
      end
    end

    it "rejects invalid bandwidth" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      expect_raises(ArgumentError) do
        RNS::RNodeSubInterface.new(
          name: "BadBW",
          parent_interface: parent,
          index: 0,
          interface_type: "SX127X",
          frequency: 868_000_000_i64,
          bandwidth: 100_i64, # Too low
          txpower: 17,
          sf: 7,
          cr: 5,
        )
      end
    end

    it "rejects invalid spreading factor" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      expect_raises(ArgumentError) do
        RNS::RNodeSubInterface.new(
          name: "BadSF",
          parent_interface: parent,
          index: 0,
          interface_type: "SX127X",
          frequency: 868_000_000_i64,
          bandwidth: 125_000_i64,
          txpower: 17,
          sf: 15, # Too high
          cr: 5,
        )
      end
    end

    it "rejects invalid coding rate" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      expect_raises(ArgumentError) do
        RNS::RNodeSubInterface.new(
          name: "BadCR",
          parent_interface: parent,
          index: 0,
          interface_type: "SX127X",
          frequency: 868_000_000_i64,
          bandwidth: 125_000_i64,
          txpower: 17,
          sf: 7,
          cr: 10, # Too high
        )
      end
    end

    it "rejects invalid short-term airtime limit" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      expect_raises(ArgumentError) do
        RNS::RNodeSubInterface.new(
          name: "BadSTAL",
          parent_interface: parent,
          index: 0,
          interface_type: "SX127X",
          frequency: 868_000_000_i64,
          bandwidth: 125_000_i64,
          txpower: 17,
          sf: 7,
          cr: 5,
          st_alock: 150.0, # Too high
        )
      end
    end

    it "rejects invalid long-term airtime limit" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      expect_raises(ArgumentError) do
        RNS::RNodeSubInterface.new(
          name: "BadLTAL",
          parent_interface: parent,
          index: 0,
          interface_type: "SX127X",
          frequency: 868_000_000_i64,
          bandwidth: 125_000_i64,
          txpower: 17,
          sf: 7,
          cr: 5,
          lt_alock: -5.0, # Negative
        )
      end
    end

    it "rejects unknown interface type" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      expect_raises(ArgumentError) do
        RNS::RNodeSubInterface.new(
          name: "BadType",
          parent_interface: parent,
          index: 0,
          interface_type: "UNKNOWN",
          frequency: 868_000_000_i64,
          bandwidth: 125_000_i64,
          txpower: 17,
          sf: 7,
          cr: 5,
        )
      end
    end
  end

  describe "#validate_radio_state" do
    it "returns true when radio parameters match" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      sub = RNS::RNodeSubInterface.new("Sub0", parent, 0, "SX127X", skip_configure: true)
      sub.frequency = 868_000_000_i64
      sub.bandwidth = 125_000_i64
      sub.txpower = 17
      sub.sf = 7
      sub.state = RNS::RNodeMultiKISS::RADIO_STATE_ON

      sub.r_frequency = 868_000_050_i64 # Within 100Hz tolerance
      sub.r_bandwidth = 125_000_i64
      sub.r_txpower = 17
      sub.r_sf = 7
      sub.r_state = RNS::RNodeMultiKISS::RADIO_STATE_ON

      sub.validate_radio_state.should be_true
    end

    it "returns false on frequency mismatch beyond tolerance" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      sub = RNS::RNodeSubInterface.new("Sub0", parent, 0, "SX127X", skip_configure: true)
      sub.frequency = 868_000_000_i64
      sub.r_frequency = 868_001_000_i64 # > 100Hz difference

      sub.validate_radio_state.should be_false
    end
  end

  describe "multiplexing logic" do
    it "allows multiple subinterfaces on different vports" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      sub0 = RNS::RNodeSubInterface.new("Sub0", parent, 0, "SX127X", skip_configure: true)
      sub1 = RNS::RNodeSubInterface.new("Sub1", parent, 1, "SX126X", skip_configure: true)

      parent.subinterfaces[0].should eq(sub0)
      parent.subinterfaces[1].should eq(sub1)
      parent.subinterfaces[2].should be_nil
    end

    it "process_queue iterates all subinterfaces" do
      parent = RNS::RNodeMultiInterface.new("Parent", "/dev/ttyUSB0")
      sub0 = RNS::RNodeSubInterface.new("Sub0", parent, 0, "SX127X", skip_configure: true)
      sub1 = RNS::RNodeSubInterface.new("Sub1", parent, 1, "SX126X", skip_configure: true)
      sub0.interface_ready = false
      sub1.interface_ready = false

      parent.process_queue

      sub0.interface_ready.should be_true
      sub1.interface_ready.should be_true
    end
  end
end
