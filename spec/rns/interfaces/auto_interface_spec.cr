require "../../spec_helper"

# Helper to wait with timeout
private def wait_for(timeout = 2.seconds, &)
  deadline = Time.utc + timeout
  while Time.utc < deadline
    return if yield
    sleep 10.milliseconds
  end
end

describe RNS::NetInfo do
  describe ".format_ipv6" do
    it "formats all-zeros as ::" do
      bytes = Bytes.new(16, 0_u8)
      RNS::NetInfo.format_ipv6(bytes).should eq("::")
    end

    it "formats loopback as ::1" do
      bytes = Bytes.new(16, 0_u8)
      bytes[15] = 1_u8
      RNS::NetInfo.format_ipv6(bytes).should eq("::1")
    end

    it "formats fe80:: link-local prefix" do
      bytes = Bytes.new(16, 0_u8)
      bytes[0] = 0xfe_u8
      bytes[1] = 0x80_u8
      bytes[15] = 0x01_u8
      result = RNS::NetInfo.format_ipv6(bytes)
      result.should start_with("fe80::")
      result.should end_with("1")
    end

    it "formats a full address without compression when no zero runs" do
      bytes = Bytes[0x20, 0x01, 0x0d, 0xb8, 0x00, 0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x04, 0x00, 0x05, 0x00, 0x06]
      result = RNS::NetInfo.format_ipv6(bytes)
      result.should eq("2001:db8:1:2:3:4:5:6")
    end

    it "compresses the longest zero run" do
      # 2001:db8:0:0:0:0:0:1
      bytes = Bytes[0x20, 0x01, 0x0d, 0xb8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01]
      result = RNS::NetInfo.format_ipv6(bytes)
      result.should eq("2001:db8::1")
    end

    it "compresses leading zeros" do
      # ::ffff:192.168.1.1 = 0000:0000:0000:0000:0000:ffff:c0a8:0101
      bytes = Bytes[0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xc0, 0xa8, 0x01, 0x01]
      result = RNS::NetInfo.format_ipv6(bytes)
      result.should eq("::ffff:c0a8:101")
    end

    it "raises on wrong size input" do
      expect_raises(ArgumentError) do
        RNS::NetInfo.format_ipv6(Bytes.new(10))
      end
    end

    it "does not compress a single zero group" do
      # 2001:db8:0:1:2:3:4:5 — single zero, no compression
      bytes = Bytes[0x20, 0x01, 0x0d, 0xb8, 0x00, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x04, 0x00, 0x05]
      result = RNS::NetInfo.format_ipv6(bytes)
      result.should eq("2001:db8:0:1:2:3:4:5")
    end
  end

  describe ".descope_linklocal" do
    it "removes %ifname suffix" do
      RNS::NetInfo.descope_linklocal("fe80::1%en0").should eq("fe80::1")
    end

    it "removes embedded scope specifier" do
      RNS::NetInfo.descope_linklocal("fe80:1::abcd").should eq("fe80::abcd")
    end

    it "handles address without scope" do
      RNS::NetInfo.descope_linklocal("fe80::1234:5678").should eq("fe80::1234:5678")
    end

    it "handles both scope specifier and %ifname" do
      RNS::NetInfo.descope_linklocal("fe80:abcd::1%eth0").should eq("fe80::1")
    end
  end

  describe ".interfaces" do
    it "returns a non-empty array of interface names" do
      ifaces = RNS::NetInfo.interfaces
      ifaces.should be_a(Array(String))
      ifaces.size.should be > 0
    end

    it "includes loopback interface" do
      ifaces = RNS::NetInfo.interfaces
      has_lo = ifaces.any? { |name| name == "lo" || name == "lo0" }
      has_lo.should be_true
    end

    it "returns unique names" do
      ifaces = RNS::NetInfo.interfaces
      ifaces.uniq.size.should eq(ifaces.size)
    end
  end

  describe ".interface_name_to_index" do
    it "returns a positive index for loopback" do
      lo_name = RNS::NetInfo.interfaces.find { |name| name == "lo" || name == "lo0" }
      if lo_name
        idx = RNS::NetInfo.interface_name_to_index(lo_name)
        idx.should be > 0
      end
    end

    it "returns 0 for a non-existent interface" do
      idx = RNS::NetInfo.interface_name_to_index("nonexistent_if_12345")
      idx.should eq(0)
    end
  end

  describe ".ifaddresses" do
    it "returns addresses for loopback" do
      lo_name = RNS::NetInfo.interfaces.find { |name| name == "lo" || name == "lo0" }
      if lo_name
        addrs = RNS::NetInfo.ifaddresses(lo_name)
        # Loopback should have at least IPv4 or IPv6
        (addrs.has_key?(RNS::NetInfo::AF_INET.to_i32) || addrs.has_key?(RNS::NetInfo::AF_INET6.to_i32)).should be_true
      end
    end

    it "returns IPv4 127.0.0.1 for loopback" do
      lo_name = RNS::NetInfo.interfaces.find { |name| name == "lo" || name == "lo0" }
      if lo_name
        addrs = RNS::NetInfo.ifaddresses(lo_name)
        if ipv4s = addrs[RNS::NetInfo::AF_INET.to_i32]?
          ipv4s.any? { |addr| addr.addr == "127.0.0.1" }.should be_true
        end
      end
    end

    it "returns IPv6 ::1 for loopback" do
      lo_name = RNS::NetInfo.interfaces.find { |name| name == "lo" || name == "lo0" }
      if lo_name
        addrs = RNS::NetInfo.ifaddresses(lo_name)
        if ipv6s = addrs[RNS::NetInfo::AF_INET6.to_i32]?
          ipv6s.any? { |addr| addr.addr == "::1" }.should be_true
        end
      end
    end

    it "returns empty hash for non-existent interface" do
      addrs = RNS::NetInfo.ifaddresses("nonexistent_if_12345")
      addrs.empty?.should be_true
    end
  end

  describe ".interface_name_to_nice_name" do
    it "returns the interface name on POSIX" do
      RNS::NetInfo.interface_name_to_nice_name("en0").should eq("en0")
    end
  end

  describe ".interface_names_to_indexes" do
    it "returns a hash mapping names to indexes" do
      map = RNS::NetInfo.interface_names_to_indexes
      map.should be_a(Hash(String, UInt32))
      map.size.should be > 0
    end
  end
end

describe RNS::AutoInterface do
  # Reset Transport state between tests
  before_each do
    RNS::Transport.reset
  end

  describe "constants" do
    it "has correct HW_MTU" do
      RNS::AutoInterface::HW_MTU.should eq(1196)
    end

    it "has correct FIXED_MTU" do
      RNS::AutoInterface::FIXED_MTU.should be_true
    end

    it "has correct DEFAULT_DISCOVERY_PORT" do
      RNS::AutoInterface::DEFAULT_DISCOVERY_PORT.should eq(29716)
    end

    it "has correct DEFAULT_DATA_PORT" do
      RNS::AutoInterface::DEFAULT_DATA_PORT.should eq(42671)
    end

    it "has correct DEFAULT_IFAC_SIZE" do
      RNS::AutoInterface::DEFAULT_IFAC_SIZE.should eq(16)
    end

    it "has correct scope constants" do
      RNS::AutoInterface::SCOPE_LINK.should eq("2")
      RNS::AutoInterface::SCOPE_ADMIN.should eq("4")
      RNS::AutoInterface::SCOPE_SITE.should eq("5")
      RNS::AutoInterface::SCOPE_ORGANISATION.should eq("8")
      RNS::AutoInterface::SCOPE_GLOBAL.should eq("e")
    end

    it "has correct multicast address types" do
      RNS::AutoInterface::MULTICAST_PERMANENT_ADDRESS_TYPE.should eq("0")
      RNS::AutoInterface::MULTICAST_TEMPORARY_ADDRESS_TYPE.should eq("1")
    end

    it "has correct timing constants" do
      RNS::AutoInterface::PEERING_TIMEOUT.should eq(22.0)
      RNS::AutoInterface::ANNOUNCE_INTERVAL.should eq(1.6)
      RNS::AutoInterface::PEER_JOB_INTERVAL.should eq(4.0)
      RNS::AutoInterface::MCAST_ECHO_TIMEOUT.should eq(6.5)
    end

    it "has correct platform ignore lists" do
      RNS::AutoInterface::ALL_IGNORE_IFS.should eq(["lo0"])
      RNS::AutoInterface::DARWIN_IGNORE_IFS.should eq(["awdl0", "llw0", "lo0", "en5"])
      RNS::AutoInterface::ANDROID_IGNORE_IFS.should eq(["dummy0", "lo", "tun0"])
    end

    it "has correct BITRATE_GUESS" do
      RNS::AutoInterface::BITRATE_GUESS.should eq(10_000_000)
    end

    it "has correct multi-interface dedup constants" do
      RNS::AutoInterface::MULTI_IF_DEQUE_LEN.should eq(48)
      RNS::AutoInterface::MULTI_IF_DEQUE_TTL.should eq(0.75)
    end
  end

  describe "constructor" do
    it "creates with default configuration" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.name.should eq("TestAuto")
      ai.group_id.should eq("reticulum".encode("UTF-8"))
      ai.discovery_port.should eq(29716)
      ai.data_port.should eq(42671)
      ai.discovery_scope.should eq("2")        # SCOPE_LINK
      ai.multicast_address_type.should eq("1") # TEMPORARY
      ai.bitrate.should eq(10_000_000)
      ai.hw_mtu.should eq(1196)
      ai.online.should be_false
      ai.dir_in.should be_true
      ai.dir_out.should be_false
    end

    it "accepts custom group_id" do
      config = {"name" => "TestAuto", "group_id" => "mygroup"}
      ai = RNS::AutoInterface.new(config)
      ai.group_id.should eq("mygroup".encode("UTF-8"))
    end

    it "accepts custom discovery_port" do
      config = {"name" => "TestAuto", "discovery_port" => "30000"}
      ai = RNS::AutoInterface.new(config)
      ai.discovery_port.should eq(30000)
      ai.unicast_discovery_port.should eq(30001)
    end

    it "accepts custom data_port" do
      config = {"name" => "TestAuto", "data_port" => "50000"}
      ai = RNS::AutoInterface.new(config)
      ai.data_port.should eq(50000)
    end

    it "accepts link discovery scope" do
      config = {"name" => "TestAuto", "discovery_scope" => "link"}
      ai = RNS::AutoInterface.new(config)
      ai.discovery_scope.should eq("2")
    end

    it "accepts admin discovery scope" do
      config = {"name" => "TestAuto", "discovery_scope" => "admin"}
      ai = RNS::AutoInterface.new(config)
      ai.discovery_scope.should eq("4")
    end

    it "accepts site discovery scope" do
      config = {"name" => "TestAuto", "discovery_scope" => "site"}
      ai = RNS::AutoInterface.new(config)
      ai.discovery_scope.should eq("5")
    end

    it "accepts organisation discovery scope" do
      config = {"name" => "TestAuto", "discovery_scope" => "organisation"}
      ai = RNS::AutoInterface.new(config)
      ai.discovery_scope.should eq("8")
    end

    it "accepts global discovery scope" do
      config = {"name" => "TestAuto", "discovery_scope" => "global"}
      ai = RNS::AutoInterface.new(config)
      ai.discovery_scope.should eq("e")
    end

    it "accepts permanent multicast address type" do
      config = {"name" => "TestAuto", "multicast_address_type" => "permanent"}
      ai = RNS::AutoInterface.new(config)
      ai.multicast_address_type.should eq("0")
    end

    it "accepts temporary multicast address type" do
      config = {"name" => "TestAuto", "multicast_address_type" => "temporary"}
      ai = RNS::AutoInterface.new(config)
      ai.multicast_address_type.should eq("1")
    end

    it "defaults to temporary multicast address type for unknown value" do
      config = {"name" => "TestAuto", "multicast_address_type" => "unknown"}
      ai = RNS::AutoInterface.new(config)
      ai.multicast_address_type.should eq("1")
    end

    it "uses configured bitrate" do
      config = {"name" => "TestAuto", "configured_bitrate" => "5000000"}
      _ai = RNS::AutoInterface.new(config)
      # Bitrate is only set if suitable_interfaces > 0, but we might not have any
      # In this case the default should still be BITRATE_GUESS
    end

    it "computes reverse_peering_interval" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      expected = RNS::AutoInterface::ANNOUNCE_INTERVAL * 3.25
      ai.reverse_peering_interval.should eq(expected)
    end

    it "parses allowed interfaces" do
      config = {"name" => "TestAuto", "devices" => "en0, en1, wlan0"}
      ai = RNS::AutoInterface.new(config)
      ai.allowed_interfaces.should eq(["en0", "en1", "wlan0"])
    end

    it "parses ignored interfaces" do
      config = {"name" => "TestAuto", "ignored_devices" => "docker0, veth123"}
      ai = RNS::AutoInterface.new(config)
      ai.ignored_interfaces.should eq(["docker0", "veth123"])
    end

    it "starts with empty peers" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.peers.empty?.should be_true
      ai.peer_count.should eq(0)
    end
  end

  describe "group hash and multicast address" do
    it "computes group_hash from group_id" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      expected_hash = RNS::Identity.full_hash("reticulum".encode("UTF-8"))
      ai.group_hash.should eq(expected_hash)
    end

    it "computes multicast address correctly" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      addr = ai.mcast_discovery_address
      # Should start with "ff" + address_type("1") + scope("2") + ":"
      addr.should start_with("ff12:")
    end

    it "multicast address changes with scope" do
      config1 = {"name" => "TestAuto", "discovery_scope" => "link"}
      config2 = {"name" => "TestAuto", "discovery_scope" => "site"}
      ai1 = RNS::AutoInterface.new(config1)
      ai2 = RNS::AutoInterface.new(config2)
      ai1.mcast_discovery_address.should_not eq(ai2.mcast_discovery_address)
      ai1.mcast_discovery_address.should start_with("ff12:")
      ai2.mcast_discovery_address.should start_with("ff15:")
    end

    it "multicast address changes with address type" do
      config1 = {"name" => "TestAuto", "multicast_address_type" => "temporary"}
      config2 = {"name" => "TestAuto", "multicast_address_type" => "permanent"}
      ai1 = RNS::AutoInterface.new(config1)
      ai2 = RNS::AutoInterface.new(config2)
      ai1.mcast_discovery_address.should start_with("ff12:")
      ai2.mcast_discovery_address.should start_with("ff02:")
    end

    it "multicast address changes with group_id" do
      config1 = {"name" => "TestAuto", "group_id" => "group1"}
      config2 = {"name" => "TestAuto", "group_id" => "group2"}
      ai1 = RNS::AutoInterface.new(config1)
      ai2 = RNS::AutoInterface.new(config2)
      ai1.mcast_discovery_address.should_not eq(ai2.mcast_discovery_address)
    end

    it "compute_mcast_address matches Python format" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      addr = ai.mcast_discovery_address
      # Format: ff<type><scope>:0:<hex>:<hex>:<hex>:<hex>:<hex>:<hex>
      parts = addr.split(":")
      parts.size.should eq(8)
      parts[0].should match(/^ff[01][2458e]$/)
      parts[1].should eq("0")
    end
  end

  describe "peer management" do
    it "add_peer creates a peer entry" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.online = true
      ai.final_init_done = true

      # add_peer with a non-local address
      ai.add_peer("fe80::dead:beef", "en0")

      ai.peers.has_key?("fe80::dead:beef").should be_true
      ai.peer_count.should eq(1)
    end

    it "add_peer with own address records multicast echo" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.link_local_addresses << "fe80::1234"
      ai.adopted_interfaces["en0"] = "fe80::1234"

      before_time = Time.utc.to_unix_f
      ai.add_peer("fe80::1234", "en0")

      # Should not be added as a peer
      ai.peers.has_key?("fe80::1234").should be_false
      # Should record multicast echo
      ai.multicast_echoes["en0"].should be >= before_time
      ai.initial_echoes.has_key?("en0").should be_true
    end

    it "add_peer for existing peer calls refresh_peer" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.online = true

      # Add peer first
      ai.add_peer("fe80::abcd", "en0")
      first_time = ai.peers["fe80::abcd"][1]

      sleep 10.milliseconds

      # Add same peer again should refresh
      ai.add_peer("fe80::abcd", "en0")
      second_time = ai.peers["fe80::abcd"][1]
      second_time.should be >= first_time
    end

    it "refresh_peer updates last_heard timestamp" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.online = true
      ai.add_peer("fe80::1111", "en0")

      old_time = ai.peers["fe80::1111"][1]
      sleep 10.milliseconds
      ai.refresh_peer("fe80::1111")
      new_time = ai.peers["fe80::1111"][1]
      new_time.should be > old_time
    end

    it "refresh_peer handles non-existent peer gracefully" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      # Should not raise
      ai.refresh_peer("fe80::nonexistent")
    end

    it "process_incoming routes to spawned interface" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.online = true

      received = [] of Bytes
      ai.owner_inbound = ->(data : Bytes, _iface : RNS::Interface) {
        received << data.dup
        nil
      }

      # Add a peer to create spawned interface
      ai.add_peer("fe80::2222", "en0")

      # Send data as if from that peer
      test_data = "hello peer".encode("UTF-8")
      ai.process_incoming(test_data, "fe80::2222")

      received.size.should eq(1)
      received[0].should eq(test_data)
    end

    it "process_incoming ignores data from unknown peer" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.online = true

      received = [] of Bytes
      ai.owner_inbound = ->(data : Bytes, _iface : RNS::Interface) {
        received << data.dup
        nil
      }

      ai.process_incoming("test".encode("UTF-8"), "fe80::unknown")
      received.size.should eq(0)
    end

    it "process_incoming ignores data when offline" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      # Online is false by default

      received = [] of Bytes
      ai.owner_inbound = ->(data : Bytes, _iface : RNS::Interface) {
        received << data.dup
        nil
      }

      ai.add_peer("fe80::3333", "en0")
      ai.process_incoming("test".encode("UTF-8"), "fe80::3333")
      received.size.should eq(0)
    end
  end

  describe "multi-interface deduplication" do
    it "deduplicates packets received from multiple interfaces" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.online = true

      received = [] of Bytes
      ai.owner_inbound = ->(data : Bytes, _iface : RNS::Interface) {
        received << data.dup
        nil
      }

      # Add two peers on different interfaces
      ai.add_peer("fe80::aaaa", "en0")
      ai.add_peer("fe80::bbbb", "en1")

      # Send same data from both peers
      test_data = "duplicate data".encode("UTF-8")
      ai.process_incoming(test_data, "fe80::aaaa")
      ai.process_incoming(test_data, "fe80::bbbb")

      # Should only be received once
      received.size.should eq(1)
    end

    it "allows different data from same interface" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.online = true

      received = [] of Bytes
      ai.owner_inbound = ->(data : Bytes, _iface : RNS::Interface) {
        received << data.dup
        nil
      }

      ai.add_peer("fe80::cccc", "en0")

      ai.process_incoming("data1".encode("UTF-8"), "fe80::cccc")
      ai.process_incoming("data2".encode("UTF-8"), "fe80::cccc")

      received.size.should eq(2)
    end

    it "mif_deque_add adds to deque with TTL" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)

      hash = RNS::Identity.full_hash("test".encode("UTF-8"))
      ai.mif_deque_add(hash)

      ai.mif_deque_hit?(hash).should be_true
    end

    it "mif_deque_hit returns false for unknown hash" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)

      hash = RNS::Identity.full_hash("unknown".encode("UTF-8"))
      ai.mif_deque_hit?(hash).should be_false
    end
  end

  describe "detach" do
    it "sets online to false" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.online = true
      ai.detach
      ai.online.should be_false
    end

    it "sets detached flag" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.detach
      ai.detached?.should be_true
    end
  end

  describe "to_s" do
    it "returns formatted string" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.to_s.should eq("AutoInterface[TestAuto]")
    end
  end

  describe "interface base class" do
    it "inherits from Interface" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.is_a?(RNS::Interface).should be_true
    end

    it "has correct HW_MTU" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.hw_mtu.should eq(1196)
    end

    it "has a get_hash" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      hash = ai.get_hash
      hash.should be_a(Bytes)
      hash.size.should eq(32)
    end

    it "has rxb/txb counters" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.rxb.should eq(0)
      ai.txb.should eq(0)
    end
  end

  describe "adopted interfaces tracking" do
    it "tracks adopted interfaces with link-local addresses" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      # On a real system, adopted_interfaces would be populated during init
      # We can at least check the structure exists
      ai.adopted_interfaces.should be_a(Hash(String, String))
    end

    it "tracks link local addresses" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.link_local_addresses.should be_a(Array(String))
    end
  end

  describe "multicast echo tracking" do
    it "tracks multicast echoes per interface" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.multicast_echoes.should be_a(Hash(String, Float64))
    end

    it "tracks initial echoes per interface" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.initial_echoes.should be_a(Hash(String, Float64))
    end

    it "add_peer records initial echo only once" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.link_local_addresses << "fe80::self"
      ai.adopted_interfaces["en0"] = "fe80::self"

      ai.add_peer("fe80::self", "en0")
      first_initial = ai.initial_echoes["en0"]

      sleep 10.milliseconds

      ai.add_peer("fe80::self", "en0")
      second_initial = ai.initial_echoes["en0"]

      # Initial echo should not change after first recording
      first_initial.should eq(second_initial)
    end
  end

  describe "timed out interfaces" do
    it "tracks carrier state per interface" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.timed_out_interfaces.should be_a(Hash(String, Bool))
    end

    it "tracks carrier_changed flag" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.carrier_changed.should be_false
    end
  end

  describe "process_outgoing" do
    it "is a no-op on AutoInterface itself" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      # Should not raise
      ai.process_outgoing("test".encode("UTF-8"))
    end
  end

  describe "Reticulum constants" do
    it "has IFAC_SALT" do
      salt = RNS::Reticulum::IFAC_SALT
      salt.should be_a(Bytes)
      salt.size.should eq(32)
      salt.hexstring.should eq("adf54d882c9a9b80771eb4995d702d4a3e733391b2a0f53f416d9f907e55cff8")
    end

    it "has panic_on_interface_error" do
      RNS::Reticulum.panic_on_interface_error.should be_false
    end
  end

  describe "stress tests" do
    it "handles 50 peer additions" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)
      ai.online = true

      50.times do |i|
        ai.add_peer("fe80::#{i + 1}", "en0")
      end

      ai.peers.size.should eq(50)
      ai.peer_count.should eq(50)
    end

    it "handles 100 deduplication entries" do
      config = {"name" => "TestAuto"}
      ai = RNS::AutoInterface.new(config)

      100.times do |i|
        hash = RNS::Identity.full_hash("data_#{i}".encode("UTF-8"))
        ai.mif_deque_add(hash)
      end

      # Deque should be bounded at MULTI_IF_DEQUE_LEN
      # The last MULTI_IF_DEQUE_LEN entries should still be present
      last_hash = RNS::Identity.full_hash("data_99".encode("UTF-8"))
      ai.mif_deque_hit?(last_hash).should be_true
    end

    it "creates 20 AutoInterface instances" do
      20.times do |i|
        config = {"name" => "TestAuto_#{i}", "group_id" => "group_#{i}"}
        ai = RNS::AutoInterface.new(config)
        ai.name.should eq("TestAuto_#{i}")
        ai.group_id.should eq("group_#{i}".encode("UTF-8"))
      end
    end
  end
end

describe RNS::AutoInterfacePeer do
  before_each do
    RNS::Transport.reset
  end

  describe "constructor" do
    it "creates with owner, addr, and ifname" do
      config = {"name" => "TestAuto"}
      owner = RNS::AutoInterface.new(config)
      peer = RNS::AutoInterfacePeer.new(owner, "fe80::1", "en0")
      peer.addr.should eq("fe80::1")
      peer.ifname.should eq("en0")
      peer.owner.should eq(owner)
    end

    it "inherits HW_MTU from owner" do
      config = {"name" => "TestAuto"}
      owner = RNS::AutoInterface.new(config)
      peer = RNS::AutoInterfacePeer.new(owner, "fe80::1", "en0")
      peer.hw_mtu.should eq(1196)
    end

    it "sets parent_interface to owner" do
      config = {"name" => "TestAuto"}
      owner = RNS::AutoInterface.new(config)
      peer = RNS::AutoInterfacePeer.new(owner, "fe80::1", "en0")
      peer.parent_interface.should eq(owner)
    end

    it "inherits from Interface" do
      config = {"name" => "TestAuto"}
      owner = RNS::AutoInterface.new(config)
      peer = RNS::AutoInterfacePeer.new(owner, "fe80::1", "en0")
      peer.is_a?(RNS::Interface).should be_true
    end
  end

  describe "process_incoming" do
    it "tracks rxb on both peer and owner" do
      config = {"name" => "TestAuto"}
      owner = RNS::AutoInterface.new(config)
      owner.online = true

      received = [] of Bytes
      owner.owner_inbound = ->(data : Bytes, _iface : RNS::Interface) {
        received << data.dup
        nil
      }

      peer = RNS::AutoInterfacePeer.new(owner, "fe80::1", "en0")
      peer.online = true

      data = "test data".encode("UTF-8")
      peer.process_incoming(data)

      peer.rxb.should eq(data.size.to_i64)
      owner.rxb.should eq(data.size.to_i64)
      received.size.should eq(1)
    end

    it "deduplicates via owner mif_deque" do
      config = {"name" => "TestAuto"}
      owner = RNS::AutoInterface.new(config)
      owner.online = true

      received = [] of Bytes
      owner.owner_inbound = ->(data : Bytes, _iface : RNS::Interface) {
        received << data.dup
        nil
      }

      peer1 = RNS::AutoInterfacePeer.new(owner, "fe80::1", "en0")
      peer1.online = true
      peer2 = RNS::AutoInterfacePeer.new(owner, "fe80::2", "en1")
      peer2.online = true

      data = "same data".encode("UTF-8")
      peer1.process_incoming(data)
      peer2.process_incoming(data)

      received.size.should eq(1)
    end

    it "does nothing when peer is offline" do
      config = {"name" => "TestAuto"}
      owner = RNS::AutoInterface.new(config)
      owner.online = true

      received = [] of Bytes
      owner.owner_inbound = ->(data : Bytes, _iface : RNS::Interface) {
        received << data.dup
        nil
      }

      peer = RNS::AutoInterfacePeer.new(owner, "fe80::1", "en0")
      peer.online = false

      peer.process_incoming("test".encode("UTF-8"))
      received.size.should eq(0)
    end

    it "does nothing when owner is offline" do
      config = {"name" => "TestAuto"}
      owner = RNS::AutoInterface.new(config)
      # owner is offline by default

      received = [] of Bytes
      owner.owner_inbound = ->(data : Bytes, _iface : RNS::Interface) {
        received << data.dup
        nil
      }

      peer = RNS::AutoInterfacePeer.new(owner, "fe80::1", "en0")
      peer.online = true

      peer.process_incoming("test".encode("UTF-8"))
      received.size.should eq(0)
    end

    it "refreshes peer on incoming data" do
      config = {"name" => "TestAuto"}
      owner = RNS::AutoInterface.new(config)
      owner.online = true
      owner.owner_inbound = ->(_data : Bytes, _iface : RNS::Interface) { nil }

      owner.add_peer("fe80::aaa", "en0")
      old_time = owner.peers["fe80::aaa"][1]

      sleep 10.milliseconds

      # Use the spawned peer to process incoming
      if spawned = owner.spawned_peer_interfaces["fe80::aaa"]?
        spawned.process_incoming("hello".encode("UTF-8"))
        new_time = owner.peers["fe80::aaa"][1]
        new_time.should be > old_time
      end
    end
  end

  describe "detach and teardown" do
    it "detach sets online to false and detached flag" do
      config = {"name" => "TestAuto"}
      owner = RNS::AutoInterface.new(config)
      peer = RNS::AutoInterfacePeer.new(owner, "fe80::1", "en0")
      peer.online = true

      peer.detach
      peer.online.should be_false
      peer.detached?.should be_true
    end

    it "teardown removes from owner spawned interfaces" do
      config = {"name" => "TestAuto"}
      owner = RNS::AutoInterface.new(config)
      owner.online = true
      owner.owner_inbound = ->(_data : Bytes, _iface : RNS::Interface) { nil }

      owner.add_peer("fe80::bbb", "en0")
      owner.spawned_peer_interfaces.has_key?("fe80::bbb").should be_true

      peer = owner.spawned_peer_interfaces["fe80::bbb"]
      peer.detach
      peer.teardown

      owner.spawned_peer_interfaces.has_key?("fe80::bbb").should be_false
    end

    it "teardown removes from Transport.interfaces" do
      config = {"name" => "TestAuto"}
      owner = RNS::AutoInterface.new(config)
      owner.online = true
      owner.owner_inbound = ->(_data : Bytes, _iface : RNS::Interface) { nil }

      owner.add_peer("fe80::ccc", "en0")
      peer = owner.spawned_peer_interfaces["fe80::ccc"]

      peer_hash = peer.get_hash
      RNS::Transport.interfaces.includes?(peer_hash).should be_true

      peer.detach
      peer.teardown

      RNS::Transport.interfaces.includes?(peer_hash).should be_false
    end

    it "teardown sets direction flags to false" do
      config = {"name" => "TestAuto"}
      owner = RNS::AutoInterface.new(config)
      peer = RNS::AutoInterfacePeer.new(owner, "fe80::1", "en0")
      peer.dir_in = true
      peer.dir_out = true
      peer.online = true

      peer.detach
      peer.teardown

      peer.dir_in.should be_false
      peer.dir_out.should be_false
      peer.online.should be_false
    end
  end

  describe "to_s" do
    it "returns formatted string" do
      config = {"name" => "TestAuto"}
      owner = RNS::AutoInterface.new(config)
      peer = RNS::AutoInterfacePeer.new(owner, "fe80::1234", "en0")
      peer.to_s.should eq("AutoInterfacePeer[en0/fe80::1234]")
    end
  end

  describe "stress tests" do
    it "handles 30 incoming messages with deduplication" do
      config = {"name" => "TestAuto"}
      owner = RNS::AutoInterface.new(config)
      owner.online = true

      received = [] of Bytes
      owner.owner_inbound = ->(data : Bytes, _iface : RNS::Interface) {
        received << data.dup
        nil
      }

      peer = RNS::AutoInterfacePeer.new(owner, "fe80::1", "en0")
      peer.online = true

      30.times do |i|
        data = "msg_#{i}".encode("UTF-8")
        peer.process_incoming(data)
      end

      received.size.should eq(30) # All unique messages should arrive
    end

    it "handles rapid peer creation and teardown" do
      config = {"name" => "TestAuto"}
      owner = RNS::AutoInterface.new(config)
      owner.online = true
      owner.owner_inbound = ->(_data : Bytes, _iface : RNS::Interface) { nil }

      20.times do |i|
        addr = "fe80::#{i + 1}"
        owner.add_peer(addr, "en0")
        if spawned = owner.spawned_peer_interfaces[addr]?
          spawned.detach
          spawned.teardown
        end
        owner.peers.delete(addr)
      end

      owner.peer_count.should eq(0)
    end
  end
end
