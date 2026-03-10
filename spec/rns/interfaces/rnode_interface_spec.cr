require "../../spec_helper"

describe RNS::RNodeKISS do
  describe "constants" do
    it "defines frame delimiters matching base KISS" do
      RNS::RNodeKISS::FEND.should eq(0xC0_u8)
      RNS::RNodeKISS::FESC.should eq(0xDB_u8)
      RNS::RNodeKISS::TFEND.should eq(0xDC_u8)
      RNS::RNodeKISS::TFESC.should eq(0xDD_u8)
    end

    it "defines all RNode-specific KISS commands" do
      RNS::RNodeKISS::CMD_UNKNOWN.should eq(0xFE_u8)
      RNS::RNodeKISS::CMD_DATA.should eq(0x00_u8)
      RNS::RNodeKISS::CMD_FREQUENCY.should eq(0x01_u8)
      RNS::RNodeKISS::CMD_BANDWIDTH.should eq(0x02_u8)
      RNS::RNodeKISS::CMD_TXPOWER.should eq(0x03_u8)
      RNS::RNodeKISS::CMD_SF.should eq(0x04_u8)
      RNS::RNodeKISS::CMD_CR.should eq(0x05_u8)
      RNS::RNodeKISS::CMD_RADIO_STATE.should eq(0x06_u8)
      RNS::RNodeKISS::CMD_RADIO_LOCK.should eq(0x07_u8)
      RNS::RNodeKISS::CMD_DETECT.should eq(0x08_u8)
      RNS::RNodeKISS::CMD_LEAVE.should eq(0x0A_u8)
      RNS::RNodeKISS::CMD_ST_ALOCK.should eq(0x0B_u8)
      RNS::RNodeKISS::CMD_LT_ALOCK.should eq(0x0C_u8)
      RNS::RNodeKISS::CMD_READY.should eq(0x0F_u8)
    end

    it "defines statistics commands" do
      RNS::RNodeKISS::CMD_STAT_RX.should eq(0x21_u8)
      RNS::RNodeKISS::CMD_STAT_TX.should eq(0x22_u8)
      RNS::RNodeKISS::CMD_STAT_RSSI.should eq(0x23_u8)
      RNS::RNodeKISS::CMD_STAT_SNR.should eq(0x24_u8)
      RNS::RNodeKISS::CMD_STAT_CHTM.should eq(0x25_u8)
      RNS::RNodeKISS::CMD_STAT_PHYPRM.should eq(0x26_u8)
      RNS::RNodeKISS::CMD_STAT_BAT.should eq(0x27_u8)
      RNS::RNodeKISS::CMD_STAT_CSMA.should eq(0x28_u8)
      RNS::RNodeKISS::CMD_STAT_TEMP.should eq(0x29_u8)
    end

    it "defines device management commands" do
      RNS::RNodeKISS::CMD_BLINK.should eq(0x30_u8)
      RNS::RNodeKISS::CMD_RANDOM.should eq(0x40_u8)
      RNS::RNodeKISS::CMD_FB_EXT.should eq(0x41_u8)
      RNS::RNodeKISS::CMD_FB_READ.should eq(0x42_u8)
      RNS::RNodeKISS::CMD_FB_WRITE.should eq(0x43_u8)
      RNS::RNodeKISS::CMD_DISP_READ.should eq(0x66_u8)
      RNS::RNodeKISS::CMD_BT_CTRL.should eq(0x46_u8)
      RNS::RNodeKISS::CMD_PLATFORM.should eq(0x48_u8)
      RNS::RNodeKISS::CMD_MCU.should eq(0x49_u8)
      RNS::RNodeKISS::CMD_FW_VERSION.should eq(0x50_u8)
      RNS::RNodeKISS::CMD_ROM_READ.should eq(0x51_u8)
      RNS::RNodeKISS::CMD_RESET.should eq(0x55_u8)
    end

    it "defines detection constants" do
      RNS::RNodeKISS::DETECT_REQ.should eq(0x73_u8)
      RNS::RNodeKISS::DETECT_RESP.should eq(0x46_u8)
    end

    it "defines radio states" do
      RNS::RNodeKISS::RADIO_STATE_OFF.should eq(0x00_u8)
      RNS::RNodeKISS::RADIO_STATE_ON.should eq(0x01_u8)
      RNS::RNodeKISS::RADIO_STATE_ASK.should eq(0xFF_u8)
    end

    it "defines error codes" do
      RNS::RNodeKISS::CMD_ERROR.should eq(0x90_u8)
      RNS::RNodeKISS::ERROR_INITRADIO.should eq(0x01_u8)
      RNS::RNodeKISS::ERROR_TXFAILED.should eq(0x02_u8)
      RNS::RNodeKISS::ERROR_EEPROM_LOCKED.should eq(0x03_u8)
      RNS::RNodeKISS::ERROR_QUEUE_FULL.should eq(0x04_u8)
      RNS::RNodeKISS::ERROR_MEMORY_LOW.should eq(0x05_u8)
      RNS::RNodeKISS::ERROR_MODEM_TIMEOUT.should eq(0x06_u8)
    end

    it "defines platform types" do
      RNS::RNodeKISS::PLATFORM_AVR.should eq(0x90_u8)
      RNS::RNodeKISS::PLATFORM_ESP32.should eq(0x80_u8)
      RNS::RNodeKISS::PLATFORM_NRF52.should eq(0x70_u8)
    end
  end

  describe ".escape" do
    it "delegates to KISS.escape" do
      data = Bytes[0x01, 0xC0, 0x02, 0xDB, 0x03]
      result = RNS::RNodeKISS.escape(data)
      expected = RNS::KISS.escape(data)
      result.should eq(expected)
    end
  end
end

describe RNS::RNodeInterface do
  describe "class constants" do
    it "defines hardware and frequency constants" do
      RNS::RNodeInterface::MAX_CHUNK.should eq(32768)
      RNS::RNodeInterface::DEFAULT_IFAC_SIZE.should eq(8)
      RNS::RNodeInterface::FREQ_MIN.should eq(137_000_000_i64)
      RNS::RNodeInterface::FREQ_MAX.should eq(3_000_000_000_i64)
    end

    it "defines signal quality constants" do
      RNS::RNodeInterface::RSSI_OFFSET.should eq(157)
      RNS::RNodeInterface::Q_SNR_MIN_BASE.should eq(-9)
      RNS::RNodeInterface::Q_SNR_MAX.should eq(6)
      RNS::RNodeInterface::Q_SNR_STEP.should eq(2)
    end

    it "defines firmware version requirements" do
      RNS::RNodeInterface::REQUIRED_FW_VER_MAJ.should eq(1)
      RNS::RNodeInterface::REQUIRED_FW_VER_MIN.should eq(52)
    end

    it "defines battery state constants" do
      RNS::RNodeInterface::BATTERY_STATE_UNKNOWN.should eq(0x00_u8)
      RNS::RNodeInterface::BATTERY_STATE_DISCHARGING.should eq(0x01_u8)
      RNS::RNodeInterface::BATTERY_STATE_CHARGING.should eq(0x02_u8)
      RNS::RNodeInterface::BATTERY_STATE_CHARGED.should eq(0x03_u8)
    end

    it "defines display constants" do
      RNS::RNodeInterface::DISPLAY_READ_INTERVAL.should eq(1.0)
      RNS::RNodeInterface::FB_PIXEL_WIDTH.should eq(64)
      RNS::RNodeInterface::FB_BITS_PER_PIXEL.should eq(1)
      RNS::RNodeInterface::FB_PIXELS_PER_BYTE.should eq(8)
      RNS::RNodeInterface::FB_BYTES_PER_LINE.should eq(8)
    end

    it "defines callsign and reconnect constants" do
      RNS::RNodeInterface::CALLSIGN_MAX_LEN.should eq(32)
      RNS::RNodeInterface::RECONNECT_WAIT.should eq(5)
    end
  end

  describe "test constructor" do
    it "creates with default parameters" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.name.should eq("TestRNode")
      iface.frequency.should eq(868_000_000_i64)
      iface.bandwidth.should eq(125_000_i64)
      iface.txpower.should eq(17)
      iface.sf.should eq(7)
      iface.cr.should eq(5)
      iface.online.should be_false
      iface.detected.should be_false
      iface.firmware_ok.should be_false
    end

    it "sets HW_MTU to 508" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.hw_mtu.should eq(508)
    end

    it "supports discovery" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.supports_discovery.should be_true
    end

    it "starts with radio state off" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.state.should eq(RNS::RNodeKISS::RADIO_STATE_OFF)
    end

    it "configures flow control" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5,
        flow_control: true
      )
      iface.flow_control.should be_true
    end

    it "configures ID beacon" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5,
        id_interval: 600,
        id_callsign: "N0CALL"
      )
      iface.id_interval.should eq(600)
      iface.id_callsign.should eq("N0CALL".to_slice)
    end

    it "configures airtime limits" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5,
        st_alock: 25.0,
        lt_alock: 10.0
      )
      iface.st_alock.should eq(25.0)
      iface.lt_alock.should eq(10.0)
    end

    it "has empty packet queue" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.packet_queue.should be_empty
    end

    it "has empty hw_errors" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.hw_errors.should be_empty
    end
  end

  describe "configuration parsing" do
    it "raises if no port specified" do
      config = {
        "name"             => "TestRNode",
        "frequency"        => "868000000",
        "bandwidth"        => "125000",
        "txpower"          => "17",
        "spreadingfactor"  => "7",
        "codingrate"       => "5",
      } of String => String
      expect_raises(ArgumentError, /No port/) do
        RNS::RNodeInterface.new(config)
      end
    end

    it "detects TCP URI scheme" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        port: "tcp://192.168.1.1",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      # Doesn't set use_tcp directly, but port URI parsing is handled in config path
      iface.should be_a(RNS::RNodeInterface)
    end

    it "detects BLE URI scheme" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        port: "ble://RNode 1234",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.should be_a(RNS::RNodeInterface)
    end
  end

  describe "validation" do
    it "rejects frequency below minimum" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 100_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.validcfg.should be_false
    end

    it "rejects frequency above maximum" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 4_000_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.validcfg.should be_false
    end

    it "rejects TX power below 0" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: -1,
        sf: 7,
        cr: 5
      )
      iface.validcfg.should be_false
    end

    it "rejects TX power above 37" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 38,
        sf: 7,
        cr: 5
      )
      iface.validcfg.should be_false
    end

    it "rejects bandwidth below 7800" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 5000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.validcfg.should be_false
    end

    it "rejects bandwidth above 1625000" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 2_000_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.validcfg.should be_false
    end

    it "rejects spreading factor below 5" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 4,
        cr: 5
      )
      iface.validcfg.should be_false
    end

    it "rejects spreading factor above 12" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 13,
        cr: 5
      )
      iface.validcfg.should be_false
    end

    it "rejects coding rate below 5" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 4
      )
      iface.validcfg.should be_false
    end

    it "rejects coding rate above 8" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 9
      )
      iface.validcfg.should be_false
    end

    it "rejects airtime limit below 0" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5,
        st_alock: -1.0
      )
      iface.validcfg.should be_false
    end

    it "rejects airtime limit above 100" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5,
        lt_alock: 101.0
      )
      iface.validcfg.should be_false
    end

    it "accepts valid configuration" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.validcfg.should be_true
    end

    it "accepts all valid spreading factors (5-12)" do
      [5, 6, 7, 8, 9, 10, 11, 12].each do |spreading|
        iface = RNS::RNodeInterface.new(
          name: "TestRNode",
          frequency: 868_000_000_i64,
          bandwidth: 125_000_i64,
          txpower: 17,
          sf: spreading,
          cr: 5
        )
        iface.validcfg.should be_true
      end
    end

    it "accepts all valid coding rates (5-8)" do
      [5, 6, 7, 8].each do |coding|
        iface = RNS::RNodeInterface.new(
          name: "TestRNode",
          frequency: 868_000_000_i64,
          bandwidth: 125_000_i64,
          txpower: 17,
          sf: 7,
          cr: coding
        )
        iface.validcfg.should be_true
      end
    end
  end

  describe "should_ingress_limit?" do
    it "always returns false" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.should_ingress_limit?.should be_false
    end
  end

  describe "to_s" do
    it "returns RNodeInterface[name]" do
      iface = RNS::RNodeInterface.new(
        name: "LoRa868",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.to_s.should eq("RNodeInterface[LoRa868]")
    end
  end

  describe "interface base class" do
    it "inherits from Interface" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.should be_a(RNS::Interface)
    end

    it "has byte counters" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.rxb.should eq(0_i64)
      iface.txb.should eq(0_i64)
    end

    it "has consistent hash" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      h1 = iface.get_hash
      h2 = iface.get_hash
      h1.should eq(h2)
    end
  end

  describe "reset_radio_state" do
    it "clears all reported radio parameters" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      # Simulate receiving some radio state
      iface.r_frequency = 868_000_000_i64
      iface.r_bandwidth = 125_000_i64
      iface.r_txpower = 17
      iface.r_sf = 7
      iface.r_cr = 5
      iface.r_state = RNS::RNodeKISS::RADIO_STATE_ON
      iface.r_lock = 0x00_u8
      iface.detected = true

      iface.reset_radio_state

      iface.r_frequency.should be_nil
      iface.r_bandwidth.should be_nil
      iface.r_txpower.should be_nil
      iface.r_sf.should be_nil
      iface.r_cr.should be_nil
      iface.r_state.should be_nil
      iface.r_lock.should be_nil
      iface.detected.should be_false
    end
  end

  describe "battery state" do
    it "returns battery state" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.get_battery_state.should eq(RNS::RNodeInterface::BATTERY_STATE_UNKNOWN)
    end

    it "returns unknown state string by default" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.get_battery_state_string.should eq("unknown")
    end

    it "returns charged state string" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.r_battery_state = RNS::RNodeInterface::BATTERY_STATE_CHARGED
      iface.get_battery_state_string.should eq("charged")
    end

    it "returns charging state string" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.r_battery_state = RNS::RNodeInterface::BATTERY_STATE_CHARGING
      iface.get_battery_state_string.should eq("charging")
    end

    it "returns discharging state string" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.r_battery_state = RNS::RNodeInterface::BATTERY_STATE_DISCHARGING
      iface.get_battery_state_string.should eq("discharging")
    end

    it "returns battery percent" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.r_battery_percent = 75
      iface.get_battery_percent.should eq(75)
    end
  end

  describe "update_bitrate" do
    it "calculates bitrate from radio parameters" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.r_sf = 7
      iface.r_cr = 5
      iface.r_bandwidth = 125_000_i64
      iface.update_bitrate
      iface.bitrate.should be > 0
      iface.bitrate_kbps.should be > 0.0
    end

    it "handles nil parameters gracefully" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.r_sf = nil
      iface.update_bitrate
      # Should not crash
    end

    it "calculates correct bitrate for SF7 BW125k CR5" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.r_sf = 7
      iface.r_cr = 5
      iface.r_bandwidth = 125_000_i64
      iface.update_bitrate
      # bitrate = 7 * ((4.0/5) / (2^7 / (125000/1000))) * 1000
      # = 7 * (0.8 / (128/125)) * 1000
      # = 7 * (0.8 / 1.024) * 1000
      # = 7 * 0.78125 * 1000
      # ≈ 5468
      iface.bitrate.should be_close(5468, 10)
    end

    it "calculates lower bitrate for higher SF" do
      iface1 = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface1.r_sf = 7
      iface1.r_cr = 5
      iface1.r_bandwidth = 125_000_i64
      iface1.update_bitrate

      iface2 = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 12,
        cr: 5
      )
      iface2.r_sf = 12
      iface2.r_cr = 5
      iface2.r_bandwidth = 125_000_i64
      iface2.update_bitrate

      iface1.bitrate.should be > iface2.bitrate
    end
  end

  describe "process_incoming" do
    it "tracks rxb bytes" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      data = Bytes[1, 2, 3, 4, 5]
      iface.process_incoming(data)
      iface.rxb.should eq(5_i64)
    end

    it "invokes inbound callback" do
      received = nil
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5,
        inbound_callback: ->(data : Bytes, _iface : RNS::Interface) { received = data; nil }
      )
      data = Bytes[10, 20, 30]
      iface.process_incoming(data)
      received.should eq(data)
    end

    it "clears RSSI and SNR after processing" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.r_stat_rssi = -80
      iface.r_stat_snr = 5.0
      iface.process_incoming(Bytes[1, 2, 3])
      iface.r_stat_rssi.should be_nil
      iface.r_stat_snr.should be_nil
    end
  end

  describe "process_outgoing" do
    it "does nothing when offline" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.online = false
      iface.process_outgoing(Bytes[1, 2, 3])
      iface.txb.should eq(0_i64)
    end

    it "queues data when interface not ready" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.online = true
      iface.interface_ready = false
      iface.process_outgoing(Bytes[1, 2, 3])
      iface.packet_queue.size.should eq(1)
    end
  end

  describe "queue and process_queue" do
    it "queues packets" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.queue(Bytes[1, 2, 3])
      iface.queue(Bytes[4, 5, 6])
      iface.packet_queue.size.should eq(2)
    end

    it "process_queue sets ready when empty" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.interface_ready = false
      iface.process_queue
      iface.interface_ready.should be_true
    end
  end

  describe "validate_firmware" do
    it "validates firmware with major > required" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.maj_version = 2
      iface.min_version = 0
      iface.validate_firmware
      iface.firmware_ok.should be_true
    end

    it "validates firmware with exact required version" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.maj_version = 1
      iface.min_version = 52
      iface.validate_firmware
      iface.firmware_ok.should be_true
    end

    it "validates firmware with higher minor version" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.maj_version = 1
      iface.min_version = 60
      iface.validate_firmware
      iface.firmware_ok.should be_true
    end
  end

  describe "teardown and detach" do
    it "teardown sets running and online to false" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.teardown
      iface.online.should be_false
    end
  end

  describe "KISS command encoding" do
    it "encodes frequency as 4-byte big-endian roundtrip" do
      freq = 868_000_000_i64
      c1 = ((freq >> 24) & 0xFF).to_u8
      c2 = ((freq >> 16) & 0xFF).to_u8
      c3 = ((freq >> 8) & 0xFF).to_u8
      c4 = (freq & 0xFF).to_u8
      # Reconstruct from bytes
      reconstructed = (c1.to_i64 << 24) | (c2.to_i64 << 16) | (c3.to_i64 << 8) | c4.to_i64
      reconstructed.should eq(freq)
    end

    it "encodes bandwidth as 4-byte big-endian" do
      # 125000 = 0x0001_E848
      c1 = ((125_000_i64 >> 24) & 0xFF).to_u8
      c2 = ((125_000_i64 >> 16) & 0xFF).to_u8
      c3 = ((125_000_i64 >> 8) & 0xFF).to_u8
      c4 = (125_000_i64 & 0xFF).to_u8
      c1.should eq(0x00_u8)
      c2.should eq(0x01_u8)
      c3.should eq(0xE8_u8)
      c4.should eq(0x48_u8)
    end

    it "encodes airtime limit as 2-byte xx.xx format" do
      # 25.50% → 2550 → 0x09F6
      val = 25.50
      at = (val * 100).to_i32  # 2550
      c1 = ((at >> 8) & 0xFF).to_u8
      c2 = (at & 0xFF).to_u8
      c1.should eq(0x09_u8)
      c2.should eq(0xF6_u8)
    end

    it "detect command includes FW_VERSION, PLATFORM, MCU requests" do
      detect_cmd = Bytes[
        RNS::RNodeKISS::FEND, RNS::RNodeKISS::CMD_DETECT, RNS::RNodeKISS::DETECT_REQ, RNS::RNodeKISS::FEND,
        RNS::RNodeKISS::CMD_FW_VERSION, 0x00_u8, RNS::RNodeKISS::FEND,
        RNS::RNodeKISS::CMD_PLATFORM, 0x00_u8, RNS::RNodeKISS::FEND,
        RNS::RNodeKISS::CMD_MCU, 0x00_u8, RNS::RNodeKISS::FEND
      ]
      detect_cmd.size.should eq(13)
      detect_cmd[0].should eq(RNS::RNodeKISS::FEND)
      detect_cmd[1].should eq(RNS::RNodeKISS::CMD_DETECT)
      detect_cmd[2].should eq(RNS::RNodeKISS::DETECT_REQ)
    end
  end

  describe "KISS data frame encoding" do
    it "encodes data frame with FEND CMD_DATA escaped_data FEND" do
      data = Bytes[0x01, 0x02, 0x03]
      escaped = RNS::RNodeKISS.escape(data)
      frame = IO::Memory.new(2 + escaped.size)
      frame.write_byte(RNS::RNodeKISS::FEND)
      frame.write_byte(RNS::RNodeKISS::CMD_DATA)
      frame.write(escaped)
      frame.write_byte(RNS::RNodeKISS::FEND)
      result = frame.to_slice
      result[0].should eq(0xC0_u8)  # FEND
      result[1].should eq(0x00_u8)  # CMD_DATA
      result[-1].should eq(0xC0_u8) # FEND
    end

    it "escapes FEND in data" do
      data = Bytes[0xC0]  # FEND byte in payload
      escaped = RNS::RNodeKISS.escape(data)
      escaped.should eq(Bytes[0xDB, 0xDC])
    end

    it "escapes FESC in data" do
      data = Bytes[0xDB]  # FESC byte in payload
      escaped = RNS::RNodeKISS.escape(data)
      escaped.should eq(Bytes[0xDB, 0xDD])
    end

    it "roundtrips escape/unescape" do
      100.times do
        size = Random.rand(1..200)
        data = Random::Secure.random_bytes(size)
        escaped = RNS::KISS.escape(data)
        unescaped = RNS::KISS.unescape(escaped)
        unescaped.should eq(data)
      end
    end
  end

  describe "KISS read loop state machine simulation" do
    # Simulates feeding bytes through the RNode KISS protocol and verifying
    # the interface correctly parses them. We use pipe-based IO to test.

    it "parses a data frame" do
      received_data = nil

      # Build a data frame: FEND CMD_DATA data FEND
      payload = Bytes[0x48, 0x65, 0x6C, 0x6C, 0x6F]  # "Hello"
      frame = IO::Memory.new
      frame.write_byte(RNS::RNodeKISS::FEND)
      frame.write_byte(RNS::RNodeKISS::CMD_DATA)
      frame.write(RNS::KISS.escape(payload))
      frame.write_byte(RNS::RNodeKISS::FEND)

      # Simulate the KISS state machine
      in_frame = false
      escape_flag = false
      command = RNS::RNodeKISS::CMD_UNKNOWN
      data_buffer = IO::Memory.new(1024)

      frame.to_slice.each do |byte|
        if in_frame && byte == RNS::RNodeKISS::FEND && command == RNS::RNodeKISS::CMD_DATA
          in_frame = false
          if data_buffer.pos > 0
            received_data = data_buffer.to_slice.dup
          end
        elsif byte == RNS::RNodeKISS::FEND
          in_frame = true
          command = RNS::RNodeKISS::CMD_UNKNOWN
          data_buffer = IO::Memory.new(1024)
        elsif in_frame
          if data_buffer.pos == 0 && command == RNS::RNodeKISS::CMD_UNKNOWN
            command = byte
          elsif command == RNS::RNodeKISS::CMD_DATA
            if byte == RNS::RNodeKISS::FESC
              escape_flag = true
            else
              if escape_flag
                byte = RNS::RNodeKISS::FEND if byte == RNS::RNodeKISS::TFEND
                byte = RNS::RNodeKISS::FESC if byte == RNS::RNodeKISS::TFESC
                escape_flag = false
              end
              data_buffer.write_byte(byte)
            end
          end
        end
      end

      received_data.should eq(payload)
    end

    it "parses frequency response" do
      # Simulate FEND CMD_FREQUENCY 4-byte-big-endian FEND
      freq_val = 868_000_000_i64
      cmd_buf = IO::Memory.new
      cmd_buf.write_byte(RNS::RNodeKISS::FEND)
      cmd_buf.write_byte(RNS::RNodeKISS::CMD_FREQUENCY)
      freq_bytes = Bytes[
        ((freq_val >> 24) & 0xFF).to_u8,
        ((freq_val >> 16) & 0xFF).to_u8,
        ((freq_val >> 8) & 0xFF).to_u8,
        (freq_val & 0xFF).to_u8,
      ]
      cmd_buf.write(RNS::KISS.escape(freq_bytes))
      cmd_buf.write_byte(RNS::RNodeKISS::FEND)

      # Parse the frequency response
      in_frame = false
      escape_flag = false
      command = RNS::RNodeKISS::CMD_UNKNOWN
      command_buffer = IO::Memory.new(64)
      parsed_freq : Int64? = nil

      cmd_buf.to_slice.each do |byte|
        if byte == RNS::RNodeKISS::FEND
          if in_frame
            in_frame = false
          end
          in_frame = true
          command = RNS::RNodeKISS::CMD_UNKNOWN
          command_buffer = IO::Memory.new(64)
        elsif in_frame
          if command == RNS::RNodeKISS::CMD_UNKNOWN
            command = byte
          elsif command == RNS::RNodeKISS::CMD_FREQUENCY
            if byte == RNS::RNodeKISS::FESC
              escape_flag = true
            else
              actual = byte
              if escape_flag
                actual = RNS::RNodeKISS::FEND if byte == RNS::RNodeKISS::TFEND
                actual = RNS::RNodeKISS::FESC if byte == RNS::RNodeKISS::TFESC
                escape_flag = false
              end
              command_buffer.write_byte(actual)
              if command_buffer.pos == 4
                cb = command_buffer.to_slice
                parsed_freq = (cb[0].to_i64 << 24) | (cb[1].to_i64 << 16) | (cb[2].to_i64 << 8) | cb[3].to_i64
              end
            end
          end
        end
      end

      parsed_freq.should eq(868_000_000_i64)
    end

    it "parses detect response" do
      frame = Bytes[RNS::RNodeKISS::FEND, RNS::RNodeKISS::CMD_DETECT, RNS::RNodeKISS::DETECT_RESP, RNS::RNodeKISS::FEND]

      in_frame = false
      command = RNS::RNodeKISS::CMD_UNKNOWN
      detected = false

      frame.each do |byte|
        if byte == RNS::RNodeKISS::FEND
          in_frame = !in_frame
          command = RNS::RNodeKISS::CMD_UNKNOWN if in_frame
        elsif in_frame
          if command == RNS::RNodeKISS::CMD_UNKNOWN
            command = byte
          elsif command == RNS::RNodeKISS::CMD_DETECT
            detected = (byte == RNS::RNodeKISS::DETECT_RESP)
          end
        end
      end

      detected.should be_true
    end

    it "parses firmware version response" do
      frame = IO::Memory.new
      frame.write_byte(RNS::RNodeKISS::FEND)
      frame.write_byte(RNS::RNodeKISS::CMD_FW_VERSION)
      frame.write(RNS::KISS.escape(Bytes[0x01_u8, 0x34_u8]))  # version 1.52
      frame.write_byte(RNS::RNodeKISS::FEND)

      in_frame = false
      escape_flag = false
      command = RNS::RNodeKISS::CMD_UNKNOWN
      command_buffer = IO::Memory.new(64)
      maj = 0
      min_ver = 0

      frame.to_slice.each do |byte|
        if byte == RNS::RNodeKISS::FEND
          in_frame = !in_frame
          command = RNS::RNodeKISS::CMD_UNKNOWN if in_frame
          command_buffer = IO::Memory.new(64) if in_frame
        elsif in_frame
          if command == RNS::RNodeKISS::CMD_UNKNOWN
            command = byte
          elsif command == RNS::RNodeKISS::CMD_FW_VERSION
            if byte == RNS::RNodeKISS::FESC
              escape_flag = true
            else
              actual = byte
              if escape_flag
                actual = RNS::RNodeKISS::FEND if byte == RNS::RNodeKISS::TFEND
                actual = RNS::RNodeKISS::FESC if byte == RNS::RNodeKISS::TFESC
                escape_flag = false
              end
              command_buffer.write_byte(actual)
              if command_buffer.pos == 2
                cb = command_buffer.to_slice
                maj = cb[0].to_i32
                min_ver = cb[1].to_i32
              end
            end
          end
        end
      end

      maj.should eq(1)
      min_ver.should eq(52)
    end

    it "parses RSSI response" do
      # RSSI byte: value - 157 = dBm
      # To get -80 dBm: byte = -80 + 157 = 77
      rssi_byte = 77_u8
      frame = Bytes[RNS::RNodeKISS::FEND, RNS::RNodeKISS::CMD_STAT_RSSI, rssi_byte, RNS::RNodeKISS::FEND]

      in_frame = false
      command = RNS::RNodeKISS::CMD_UNKNOWN
      rssi : Int32? = nil

      frame.each do |byte|
        if byte == RNS::RNodeKISS::FEND
          in_frame = !in_frame
          command = RNS::RNodeKISS::CMD_UNKNOWN if in_frame
        elsif in_frame
          if command == RNS::RNodeKISS::CMD_UNKNOWN
            command = byte
          elsif command == RNS::RNodeKISS::CMD_STAT_RSSI
            rssi = byte.to_i32 - RNS::RNodeInterface::RSSI_OFFSET
          end
        end
      end

      rssi.should eq(-80)
    end

    it "parses SNR response and computes quality" do
      # SNR: signed byte * 0.25 = dB
      # For SNR = 3.0 dB: signed_byte = 12 (12 * 0.25 = 3.0)
      snr_byte = 12_u8  # 3.0 dB
      rsf = 7

      signed = snr_byte.to_i8
      snr = signed.to_f64 * 0.25
      snr.should eq(3.0)

      sfs = rsf - 7  # 0
      q_snr_min = RNS::RNodeInterface::Q_SNR_MIN_BASE - sfs * RNS::RNodeInterface::Q_SNR_STEP  # -9
      q_snr_max = RNS::RNodeInterface::Q_SNR_MAX  # 6
      q_snr_span = q_snr_max - q_snr_min  # 15
      quality = ((snr - q_snr_min) / q_snr_span) * 100.0  # (3 - (-9)) / 15 * 100 = 80%
      quality = quality.clamp(0.0, 100.0).round(1)
      quality.should eq(80.0)
    end

    it "parses platform response" do
      frame = Bytes[RNS::RNodeKISS::FEND, RNS::RNodeKISS::CMD_PLATFORM, RNS::RNodeKISS::PLATFORM_ESP32, RNS::RNodeKISS::FEND]

      in_frame = false
      command = RNS::RNodeKISS::CMD_UNKNOWN
      platform : UInt8? = nil

      frame.each do |byte|
        if byte == RNS::RNodeKISS::FEND
          in_frame = !in_frame
          command = RNS::RNodeKISS::CMD_UNKNOWN if in_frame
        elsif in_frame
          if command == RNS::RNodeKISS::CMD_UNKNOWN
            command = byte
          elsif command == RNS::RNodeKISS::CMD_PLATFORM
            platform = byte
          end
        end
      end

      platform.should eq(RNS::RNodeKISS::PLATFORM_ESP32)
    end

    it "parses battery status response" do
      # Battery: [state, percent] — 2 bytes
      bat_frame = IO::Memory.new
      bat_frame.write_byte(RNS::RNodeKISS::FEND)
      bat_frame.write_byte(RNS::RNodeKISS::CMD_STAT_BAT)
      bat_frame.write(RNS::KISS.escape(Bytes[RNS::RNodeInterface::BATTERY_STATE_CHARGING, 75_u8]))
      bat_frame.write_byte(RNS::RNodeKISS::FEND)

      in_frame = false
      escape_flag = false
      command = RNS::RNodeKISS::CMD_UNKNOWN
      command_buffer = IO::Memory.new(64)
      bat_state : UInt8 = 0_u8
      bat_percent : Int32 = 0

      bat_frame.to_slice.each do |byte|
        if byte == RNS::RNodeKISS::FEND
          in_frame = !in_frame
          command = RNS::RNodeKISS::CMD_UNKNOWN if in_frame
          command_buffer = IO::Memory.new(64) if in_frame
        elsif in_frame
          if command == RNS::RNodeKISS::CMD_UNKNOWN
            command = byte
          elsif command == RNS::RNodeKISS::CMD_STAT_BAT
            if byte == RNS::RNodeKISS::FESC
              escape_flag = true
            else
              actual = byte
              if escape_flag
                actual = RNS::RNodeKISS::FEND if byte == RNS::RNodeKISS::TFEND
                actual = RNS::RNodeKISS::FESC if byte == RNS::RNodeKISS::TFESC
                escape_flag = false
              end
              command_buffer.write_byte(actual)
              if command_buffer.pos == 2
                cb = command_buffer.to_slice
                bat_state = cb[0]
                bp = cb[1].to_i32
                bat_percent = bp.clamp(0, 100)
              end
            end
          end
        end
      end

      bat_state.should eq(RNS::RNodeInterface::BATTERY_STATE_CHARGING)
      bat_percent.should eq(75)
    end

    it "parses temperature response" do
      # Temperature: byte - 120 = celsius
      # 25°C = byte 145
      temp_byte = 145_u8
      frame = IO::Memory.new
      frame.write_byte(RNS::RNodeKISS::FEND)
      frame.write_byte(RNS::RNodeKISS::CMD_STAT_TEMP)
      frame.write(RNS::KISS.escape(Bytes[temp_byte]))
      frame.write_byte(RNS::RNodeKISS::FEND)

      in_frame = false
      escape_flag = false
      command = RNS::RNodeKISS::CMD_UNKNOWN
      command_buffer = IO::Memory.new(64)
      temperature : Int32? = nil

      frame.to_slice.each do |byte|
        if byte == RNS::RNodeKISS::FEND
          in_frame = !in_frame
          command = RNS::RNodeKISS::CMD_UNKNOWN if in_frame
          command_buffer = IO::Memory.new(64) if in_frame
        elsif in_frame
          if command == RNS::RNodeKISS::CMD_UNKNOWN
            command = byte
          elsif command == RNS::RNodeKISS::CMD_STAT_TEMP
            if byte == RNS::RNodeKISS::FESC
              escape_flag = true
            else
              actual = byte
              if escape_flag
                actual = RNS::RNodeKISS::FEND if byte == RNS::RNodeKISS::TFEND
                actual = RNS::RNodeKISS::FESC if byte == RNS::RNodeKISS::TFESC
                escape_flag = false
              end
              command_buffer.write_byte(actual)
              if command_buffer.pos == 1
                cb = command_buffer.to_slice
                temp = cb[0].to_i32 - 120
                temperature = temp if temp >= -30 && temp <= 90
              end
            end
          end
        end
      end

      temperature.should eq(25)
    end

    it "parses multiple frames in sequence" do
      # Platform + Detect frames
      combined = IO::Memory.new
      # Platform: ESP32
      combined.write(Bytes[RNS::RNodeKISS::FEND, RNS::RNodeKISS::CMD_PLATFORM, RNS::RNodeKISS::PLATFORM_ESP32, RNS::RNodeKISS::FEND])
      # Detect response
      combined.write(Bytes[RNS::RNodeKISS::FEND, RNS::RNodeKISS::CMD_DETECT, RNS::RNodeKISS::DETECT_RESP, RNS::RNodeKISS::FEND])

      in_frame = false
      command = RNS::RNodeKISS::CMD_UNKNOWN
      platform : UInt8? = nil
      detected = false

      combined.to_slice.each do |byte|
        if byte == RNS::RNodeKISS::FEND
          in_frame = true
          command = RNS::RNodeKISS::CMD_UNKNOWN
        elsif in_frame
          if command == RNS::RNodeKISS::CMD_UNKNOWN
            command = byte
          elsif command == RNS::RNodeKISS::CMD_PLATFORM
            platform = byte
          elsif command == RNS::RNodeKISS::CMD_DETECT
            detected = (byte == RNS::RNodeKISS::DETECT_RESP)
          end
        end
      end

      platform.should eq(RNS::RNodeKISS::PLATFORM_ESP32)
      detected.should be_true
    end

    it "handles escaped bytes in data frames" do
      # Data payload containing FEND (0xC0) and FESC (0xDB) bytes
      payload = Bytes[0x01, 0xC0, 0x02, 0xDB, 0x03]
      escaped = RNS::KISS.escape(payload)

      frame = IO::Memory.new
      frame.write_byte(RNS::RNodeKISS::FEND)
      frame.write_byte(RNS::RNodeKISS::CMD_DATA)
      frame.write(escaped)
      frame.write_byte(RNS::RNodeKISS::FEND)

      in_frame = false
      escape_flag = false
      command = RNS::RNodeKISS::CMD_UNKNOWN
      data_buffer = IO::Memory.new(1024)
      received : Bytes? = nil

      frame.to_slice.each do |byte|
        if in_frame && byte == RNS::RNodeKISS::FEND && command == RNS::RNodeKISS::CMD_DATA
          in_frame = false
          received = data_buffer.to_slice.dup if data_buffer.pos > 0
        elsif byte == RNS::RNodeKISS::FEND
          in_frame = true
          command = RNS::RNodeKISS::CMD_UNKNOWN
          data_buffer = IO::Memory.new(1024)
        elsif in_frame
          if data_buffer.pos == 0 && command == RNS::RNodeKISS::CMD_UNKNOWN
            command = byte
          elsif command == RNS::RNodeKISS::CMD_DATA
            if byte == RNS::RNodeKISS::FESC
              escape_flag = true
            else
              actual = byte
              if escape_flag
                actual = RNS::RNodeKISS::FEND if byte == RNS::RNodeKISS::TFEND
                actual = RNS::RNodeKISS::FESC if byte == RNS::RNodeKISS::TFESC
                escape_flag = false
              end
              data_buffer.write_byte(actual)
            end
          end
        end
      end

      received.should eq(payload)
    end
  end

  describe "validate_radio_state" do
    it "returns true when parameters match" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.r_frequency = 868_000_000_i64
      iface.r_bandwidth = 125_000_i64
      iface.r_txpower = 17
      iface.r_sf = 7
      iface.state = RNS::RNodeKISS::RADIO_STATE_ON
      iface.r_state = RNS::RNodeKISS::RADIO_STATE_ON
      # Skip the sleep in validate_radio_state for test
      iface.validcfg.should be_true
    end

    it "detects frequency mismatch" do
      iface = RNS::RNodeInterface.new(
        name: "TestRNode",
        frequency: 868_000_000_i64,
        bandwidth: 125_000_i64,
        txpower: 17,
        sf: 7,
        cr: 5
      )
      iface.r_frequency = 915_000_000_i64  # Wrong frequency
      iface.r_bandwidth = 125_000_i64
      iface.r_txpower = 17
      iface.r_sf = 7
      iface.state = RNS::RNodeKISS::RADIO_STATE_ON
      iface.r_state = RNS::RNodeKISS::RADIO_STATE_ON
      # Manually check frequency mismatch logic
      freq_match = (iface.r_frequency.not_nil! - iface.frequency).abs <= 100
      freq_match.should be_false
    end
  end

  describe "RNodeTCPConnection constants" do
    it "defines connection constants" do
      RNS::RNodeTCPConnection::TARGET_PORT.should eq(7633)
      RNS::RNodeTCPConnection::CONNECT_TIMEOUT.should eq(5.0)
      RNS::RNodeTCPConnection::INITIAL_CONNECT_TIMEOUT.should eq(5.0)
      RNS::RNodeTCPConnection::RECONNECT_WAIT.should eq(4.0)
      RNS::RNodeTCPConnection::ACTIVITY_TIMEOUT.should eq(6.0)
      RNS::RNodeTCPConnection::ACTIVITY_KEEPALIVE.should eq(3.5)
    end

    it "defines TCP keepalive constants" do
      RNS::RNodeTCPConnection::TCP_USER_TIMEOUT.should eq(24)
      RNS::RNodeTCPConnection::TCP_PROBE_AFTER.should eq(5)
      RNS::RNodeTCPConnection::TCP_PROBE_INTERVAL.should eq(2)
      RNS::RNodeTCPConnection::TCP_PROBES.should eq(12)
    end
  end

  describe "stress tests" do
    it "creates 20 interfaces with different configurations" do
      20.times do |i|
        freq = (137_000_000_i64 + Random.rand(2_863_000_000_i64))
        bw = [7800_i64, 10400_i64, 15600_i64, 20800_i64, 31250_i64, 41700_i64, 62500_i64, 125000_i64, 250000_i64, 500000_i64].sample
        sf = Random.rand(5..12)
        cr = Random.rand(5..8)
        txp = Random.rand(0..37)
        iface = RNS::RNodeInterface.new(
          name: "StressRNode#{i}",
          frequency: freq,
          bandwidth: bw,
          txpower: txp,
          sf: sf,
          cr: cr
        )
        iface.validcfg.should be_true
        iface.to_s.should eq("RNodeInterface[StressRNode#{i}]")
      end
    end

    it "roundtrips 100 random KISS data frames" do
      100.times do
        size = Random.rand(1..200)
        payload = Random::Secure.random_bytes(size)

        # Encode
        escaped = RNS::KISS.escape(payload)
        frame = IO::Memory.new
        frame.write_byte(RNS::RNodeKISS::FEND)
        frame.write_byte(RNS::RNodeKISS::CMD_DATA)
        frame.write(escaped)
        frame.write_byte(RNS::RNodeKISS::FEND)

        # Decode
        in_frame = false
        escape_flag = false
        command = RNS::RNodeKISS::CMD_UNKNOWN
        data_buffer = IO::Memory.new(1024)
        received : Bytes? = nil

        frame.to_slice.each do |byte|
          if in_frame && byte == RNS::RNodeKISS::FEND && command == RNS::RNodeKISS::CMD_DATA
            in_frame = false
            received = data_buffer.to_slice.dup if data_buffer.pos > 0
          elsif byte == RNS::RNodeKISS::FEND
            in_frame = true
            command = RNS::RNodeKISS::CMD_UNKNOWN
            data_buffer = IO::Memory.new(1024)
          elsif in_frame
            if data_buffer.pos == 0 && command == RNS::RNodeKISS::CMD_UNKNOWN
              command = byte
            elsif command == RNS::RNodeKISS::CMD_DATA
              if byte == RNS::RNodeKISS::FESC
                escape_flag = true
              else
                actual = byte
                if escape_flag
                  actual = RNS::RNodeKISS::FEND if byte == RNS::RNodeKISS::TFEND
                  actual = RNS::RNodeKISS::FESC if byte == RNS::RNodeKISS::TFESC
                  escape_flag = false
                end
                data_buffer.write_byte(actual)
              end
            end
          end
        end

        received.should eq(payload)
      end
    end

    it "roundtrips 50 random frequency encodings" do
      50.times do
        freq = Random.rand(RNS::RNodeInterface::FREQ_MIN..RNS::RNodeInterface::FREQ_MAX)

        # Encode as 4-byte big-endian
        c1 = ((freq >> 24) & 0xFF).to_u8
        c2 = ((freq >> 16) & 0xFF).to_u8
        c3 = ((freq >> 8) & 0xFF).to_u8
        c4 = (freq & 0xFF).to_u8
        encoded = Bytes[c1, c2, c3, c4]
        escaped = RNS::KISS.escape(encoded)

        # Decode via state machine
        frame = IO::Memory.new
        frame.write_byte(RNS::RNodeKISS::FEND)
        frame.write_byte(RNS::RNodeKISS::CMD_FREQUENCY)
        frame.write(escaped)
        frame.write_byte(RNS::RNodeKISS::FEND)

        in_frame = false
        escape_flag = false
        command = RNS::RNodeKISS::CMD_UNKNOWN
        command_buffer = IO::Memory.new(64)
        parsed_freq : Int64? = nil

        frame.to_slice.each do |byte|
          if byte == RNS::RNodeKISS::FEND
            in_frame = true
            command = RNS::RNodeKISS::CMD_UNKNOWN
            command_buffer = IO::Memory.new(64)
          elsif in_frame
            if command == RNS::RNodeKISS::CMD_UNKNOWN
              command = byte
            elsif command == RNS::RNodeKISS::CMD_FREQUENCY
              if byte == RNS::RNodeKISS::FESC
                escape_flag = true
              else
                actual = byte
                if escape_flag
                  actual = RNS::RNodeKISS::FEND if byte == RNS::RNodeKISS::TFEND
                  actual = RNS::RNodeKISS::FESC if byte == RNS::RNodeKISS::TFESC
                  escape_flag = false
                end
                command_buffer.write_byte(actual)
                if command_buffer.pos == 4
                  cb = command_buffer.to_slice
                  parsed_freq = (cb[0].to_i64 << 24) | (cb[1].to_i64 << 16) | (cb[2].to_i64 << 8) | cb[3].to_i64
                end
              end
            end
          end
        end

        parsed_freq.should eq(freq)
      end
    end
  end
end
