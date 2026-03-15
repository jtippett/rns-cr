require "../../spec_helper"

describe RNS::Management do
  describe RNS::Management::NodeStateReport do
    it "has MSGTYPE 0x0100" do
      RNS::Management::NodeStateReport.msgtype.should eq(0x0100_u16)
    end

    it "round-trips through pack/unpack" do
      msg = RNS::Management::NodeStateReport.new
      msg.node_identity_hash = Bytes.new(16, 0xAB_u8)
      msg.uptime = 3600.0
      msg.config_hash = Bytes.new(32, 0xCD_u8)
      msg.timestamp = Time.utc.to_unix_f

      iface_entry = RNS::Management::InterfaceEntry.new
      iface_entry.name = "AutoInterface"
      iface_entry.type = "AutoInterface"
      iface_entry.mode = RNS::Interface::MODE_FULL
      iface_entry.online = true
      iface_entry.bitrate = 10_000_000_i64
      iface_entry.mtu = 500_u16
      iface_entry.rxb = 1024_u64
      iface_entry.txb = 2048_u64
      iface_entry.peers = [Bytes.new(16, 0x01_u8)]
      iface_entry.ifac_configured = true
      iface_entry.ifac_netname = "office"
      iface_entry.announce_queue_size = 5_u32
      msg.interfaces = [iface_entry]

      announce_entry = RNS::Management::AnnounceTableEntry.new
      announce_entry.dest_hash = Bytes.new(16, 0x11_u8)
      announce_entry.hops = 3_u8
      announce_entry.interface_name = "AutoInterface"
      announce_entry.timestamp = Time.utc.to_unix_f
      announce_entry.expires = Time.utc.to_unix_f + 3600.0
      msg.announce_table = [announce_entry]

      msg.path_table = [] of RNS::Management::PathTableEntry
      msg.active_links = [] of RNS::Management::ActiveLinkEntry

      raw = msg.pack
      msg2 = RNS::Management::NodeStateReport.new
      msg2.unpack(raw)

      msg2.node_identity_hash.should eq(msg.node_identity_hash)
      msg2.uptime.should eq(msg.uptime)
      msg2.config_hash.should eq(msg.config_hash)
      msg2.interfaces.size.should eq(1)
      msg2.interfaces[0].name.should eq("AutoInterface")
      msg2.interfaces[0].online.should be_true
      msg2.interfaces[0].peers.size.should eq(1)
      msg2.announce_table.size.should eq(1)
      msg2.announce_table[0].hops.should eq(3_u8)
    end
  end

  describe RNS::Management::ConfigPush do
    it "has MSGTYPE 0x0101" do
      RNS::Management::ConfigPush.msgtype.should eq(0x0101_u16)
    end

    it "round-trips through pack/unpack" do
      msg = RNS::Management::ConfigPush.new
      msg.push_id = Bytes.new(16, 0xFF_u8)
      msg.strategy = 0_u8 # full replace
      msg.config_sections = {
        "interfaces" => {"type" => "AutoInterface", "enabled" => "yes"},
        "reticulum"  => {"enable_transport" => "yes"},
      }
      msg.expected_hash = Bytes.new(32, 0xEE_u8)

      raw = msg.pack
      msg2 = RNS::Management::ConfigPush.new
      msg2.unpack(raw)

      msg2.push_id.should eq(msg.push_id)
      msg2.strategy.should eq(0_u8)
      msg2.config_sections["interfaces"]["type"].should eq("AutoInterface")
      msg2.expected_hash.should eq(msg.expected_hash)
    end
  end

  describe RNS::Management::ConfigAck do
    it "has MSGTYPE 0x0102" do
      RNS::Management::ConfigAck.msgtype.should eq(0x0102_u16)
    end

    it "round-trips through pack/unpack" do
      msg = RNS::Management::ConfigAck.new
      msg.push_id = Bytes.new(16, 0xAA_u8)
      msg.status = 0_u8 # applied
      msg.config_hash = Bytes.new(32, 0xBB_u8)
      msg.error_message = nil

      raw = msg.pack
      msg2 = RNS::Management::ConfigAck.new
      msg2.unpack(raw)

      msg2.push_id.should eq(msg.push_id)
      msg2.status.should eq(0_u8)
      msg2.config_hash.should eq(msg.config_hash)
      msg2.error_message.should be_nil
    end

    it "round-trips with error_message" do
      msg = RNS::Management::ConfigAck.new
      msg.push_id = Bytes.new(16, 0xAA_u8)
      msg.status = 2_u8 # validation_failed
      msg.config_hash = Bytes.new(32, 0xBB_u8)
      msg.error_message = "Unknown interface type"

      raw = msg.pack
      msg2 = RNS::Management::ConfigAck.new
      msg2.unpack(raw)

      msg2.status.should eq(2_u8)
      msg2.error_message.should eq("Unknown interface type")
    end
  end

  describe RNS::Management::Heartbeat do
    it "has MSGTYPE 0x0103" do
      RNS::Management::Heartbeat.msgtype.should eq(0x0103_u16)
    end

    it "round-trips through pack/unpack" do
      msg = RNS::Management::Heartbeat.new
      msg.timestamp = Time.utc.to_unix_f
      msg.sequence = 42_u32

      raw = msg.pack
      msg2 = RNS::Management::Heartbeat.new
      msg2.unpack(raw)

      msg2.timestamp.should eq(msg.timestamp)
      msg2.sequence.should eq(42_u32)
    end
  end

  describe RNS::Management::JoinRequest do
    it "has MSGTYPE 0x0110" do
      RNS::Management::JoinRequest.msgtype.should eq(0x0110_u16)
    end

    it "round-trips through pack/unpack" do
      msg = RNS::Management::JoinRequest.new
      msg.token_secret = Bytes.new(32, 0x77_u8)
      msg.identity_pubkey = Bytes.new(64, 0x88_u8)
      msg.hostname = "james-workstation"
      msg.platform = "darwin-arm64"
      msg.daemon_version = "0.1.0"

      raw = msg.pack
      msg2 = RNS::Management::JoinRequest.new
      msg2.unpack(raw)

      msg2.token_secret.should eq(msg.token_secret)
      msg2.identity_pubkey.should eq(msg.identity_pubkey)
      msg2.hostname.should eq("james-workstation")
      msg2.platform.should eq("darwin-arm64")
      msg2.daemon_version.should eq("0.1.0")
    end
  end

  describe RNS::Management::JoinResponse do
    it "has MSGTYPE 0x0111" do
      RNS::Management::JoinResponse.msgtype.should eq(0x0111_u16)
    end

    it "round-trips accepted response" do
      msg = RNS::Management::JoinResponse.new
      msg.accepted = true
      msg.node_id = Bytes.new(16, 0x99_u8)
      msg.config_sections = {
        "reticulum" => {"enable_transport" => "yes"},
      }
      msg.reject_reason = nil

      raw = msg.pack
      msg2 = RNS::Management::JoinResponse.new
      msg2.unpack(raw)

      msg2.accepted.should be_true
      msg2.node_id.should eq(msg.node_id)
      msg2.config_sections.should_not be_nil
      msg2.config_sections.not_nil!["reticulum"]["enable_transport"].should eq("yes")
      msg2.reject_reason.should be_nil
    end

    it "round-trips rejected response" do
      msg = RNS::Management::JoinResponse.new
      msg.accepted = false
      msg.node_id = nil
      msg.config_sections = nil
      msg.reject_reason = "token_expired"

      raw = msg.pack
      msg2 = RNS::Management::JoinResponse.new
      msg2.unpack(raw)

      msg2.accepted.should be_false
      msg2.reject_reason.should eq("token_expired")
    end
  end
end
