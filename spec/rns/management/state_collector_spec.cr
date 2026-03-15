require "../../spec_helper"

class CollectorTestInterface < RNS::Interface
  IN  = true
  OUT = true

  def initialize(name : String = "CollectorTest")
    super()
    @name = name
    @online = true
    @bitrate = 115200_i64
    @rxb = 1000_i64
    @txb = 2000_i64
  end

  def process_outgoing(data : Bytes)
  end
end

describe RNS::Management::StateCollector do
  describe "#collect_state" do
    it "captures interface stats into NodeStateReport" do
      iface = CollectorTestInterface.new("test-iface")
      iface.ifac_netname = "test-net"
      iface.ifac_netkey = "test-key"
      iface.ifac_size = 16
      iface.recompute_ifac_identity
      RNS::Transport.register_interface(iface)

      node_hash = Bytes.new(16, 0x42_u8)
      collector = RNS::Management::StateCollector.new(
        node_identity_hash: node_hash,
        config_path: nil
      )

      report = collector.collect_state

      report.node_identity_hash.should eq(node_hash)
      report.uptime.should be >= 0.0
      report.timestamp.should be > 0.0
      report.interfaces.size.should be >= 1

      test_entry = report.interfaces.find { |i| i.name == "test-iface" }
      test_entry.should_not be_nil
      entry = test_entry.not_nil!
      entry.online.should be_true
      entry.bitrate.should eq(115200_i64)
      entry.rxb.should eq(1000_u64)
      entry.txb.should eq(2000_u64)
      entry.ifac_configured.should be_true
      entry.ifac_netname.should eq("test-net")
    end

    it "captures announce table entries" do
      node_hash = Bytes.new(16, 0x42_u8)
      collector = RNS::Management::StateCollector.new(
        node_identity_hash: node_hash,
        config_path: nil
      )

      report = collector.collect_state
      # Announce table may be empty in test, but should not error
      report.announce_table.should be_a(Array(RNS::Management::AnnounceTableEntry))
    end

    it "captures path table entries" do
      node_hash = Bytes.new(16, 0x42_u8)
      collector = RNS::Management::StateCollector.new(
        node_identity_hash: node_hash,
        config_path: nil
      )

      report = collector.collect_state
      report.path_table.should be_a(Array(RNS::Management::PathTableEntry))
    end

    it "captures active links" do
      node_hash = Bytes.new(16, 0x42_u8)
      collector = RNS::Management::StateCollector.new(
        node_identity_hash: node_hash,
        config_path: nil
      )

      report = collector.collect_state
      report.active_links.should be_a(Array(RNS::Management::ActiveLinkEntry))
    end
  end
end
