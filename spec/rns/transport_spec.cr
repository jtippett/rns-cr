require "../spec_helper"

describe RNS::Transport do
  # Clean up Transport state before each test
  before_each do
    RNS::Transport.reset
  end

  # ════════════════════════════════════════════════════════════════
  #  Constants
  # ════════════════════════════════════════════════════════════════

  describe "transport type constants" do
    it "defines BROADCAST as 0x00" do
      RNS::Transport::BROADCAST.should eq(0x00_u8)
    end

    it "defines TRANSPORT as 0x01" do
      RNS::Transport::TRANSPORT.should eq(0x01_u8)
    end

    it "defines RELAY as 0x02" do
      RNS::Transport::RELAY.should eq(0x02_u8)
    end

    it "defines TUNNEL as 0x03" do
      RNS::Transport::TUNNEL.should eq(0x03_u8)
    end

    it "defines TYPES array" do
      RNS::Transport::TYPES.should eq([0x00_u8, 0x01_u8, 0x02_u8, 0x03_u8])
    end
  end

  describe "reachability constants" do
    it "defines REACHABILITY_UNREACHABLE as 0x00" do
      RNS::Transport::REACHABILITY_UNREACHABLE.should eq(0x00_u8)
    end

    it "defines REACHABILITY_DIRECT as 0x01" do
      RNS::Transport::REACHABILITY_DIRECT.should eq(0x01_u8)
    end

    it "defines REACHABILITY_TRANSPORT as 0x02" do
      RNS::Transport::REACHABILITY_TRANSPORT.should eq(0x02_u8)
    end
  end

  describe "pathfinder constants" do
    it "defines PATHFINDER_M as 128" do
      RNS::Transport::PATHFINDER_M.should eq(128)
    end

    it "defines PATHFINDER_R as 1" do
      RNS::Transport::PATHFINDER_R.should eq(1)
    end

    it "defines PATHFINDER_G as 5" do
      RNS::Transport::PATHFINDER_G.should eq(5)
    end

    it "defines PATHFINDER_RW as 0.5" do
      RNS::Transport::PATHFINDER_RW.should eq(0.5)
    end

    it "defines PATHFINDER_E as one week in seconds" do
      RNS::Transport::PATHFINDER_E.should eq(604800)
    end

    it "defines AP_PATH_TIME as one day" do
      RNS::Transport::AP_PATH_TIME.should eq(86400)
    end

    it "defines ROAMING_PATH_TIME as 6 hours" do
      RNS::Transport::ROAMING_PATH_TIME.should eq(21600)
    end
  end

  describe "path request constants" do
    it "defines PATH_REQUEST_TIMEOUT as 15" do
      RNS::Transport::PATH_REQUEST_TIMEOUT.should eq(15)
    end

    it "defines PATH_REQUEST_GRACE as 0.4" do
      RNS::Transport::PATH_REQUEST_GRACE.should eq(0.4)
    end

    it "defines PATH_REQUEST_RG as 1.5" do
      RNS::Transport::PATH_REQUEST_RG.should eq(1.5)
    end

    it "defines PATH_REQUEST_MI as 20" do
      RNS::Transport::PATH_REQUEST_MI.should eq(20)
    end
  end

  describe "state constants" do
    it "defines STATE_UNKNOWN as 0x00" do
      RNS::Transport::STATE_UNKNOWN.should eq(0x00_u8)
    end

    it "defines STATE_UNRESPONSIVE as 0x01" do
      RNS::Transport::STATE_UNRESPONSIVE.should eq(0x01_u8)
    end

    it "defines STATE_RESPONSIVE as 0x02" do
      RNS::Transport::STATE_RESPONSIVE.should eq(0x02_u8)
    end
  end

  describe "timeout and limit constants" do
    it "defines REVERSE_TIMEOUT as 480 seconds" do
      RNS::Transport::REVERSE_TIMEOUT.should eq(480)
    end

    it "defines DESTINATION_TIMEOUT as one week" do
      RNS::Transport::DESTINATION_TIMEOUT.should eq(604800)
    end

    it "defines MAX_RECEIPTS as 1024" do
      RNS::Transport::MAX_RECEIPTS.should eq(1024)
    end

    it "defines MAX_RATE_TIMESTAMPS as 16" do
      RNS::Transport::MAX_RATE_TIMESTAMPS.should eq(16)
    end

    it "defines PERSIST_RANDOM_BLOBS as 32" do
      RNS::Transport::PERSIST_RANDOM_BLOBS.should eq(32)
    end

    it "defines MAX_RANDOM_BLOBS as 64" do
      RNS::Transport::MAX_RANDOM_BLOBS.should eq(64)
    end

    it "defines LOCAL_CLIENT_CACHE_MAXSIZE as 512" do
      RNS::Transport::LOCAL_CLIENT_CACHE_MAXSIZE.should eq(512)
    end

    it "defines HASHLIST_MAXSIZE as 1_000_000" do
      RNS::Transport::HASHLIST_MAXSIZE.should eq(1_000_000)
    end

    it "defines MAX_PR_TAGS as 32_000" do
      RNS::Transport::MAX_PR_TAGS.should eq(32_000)
    end
  end

  describe "job interval constants" do
    it "defines JOB_INTERVAL as 0.250" do
      RNS::Transport::JOB_INTERVAL.should eq(0.250)
    end

    it "defines LINKS_CHECK_INTERVAL as 1.0" do
      RNS::Transport::LINKS_CHECK_INTERVAL.should eq(1.0)
    end

    it "defines RECEIPTS_CHECK_INTERVAL as 1.0" do
      RNS::Transport::RECEIPTS_CHECK_INTERVAL.should eq(1.0)
    end

    it "defines ANNOUNCES_CHECK_INTERVAL as 1.0" do
      RNS::Transport::ANNOUNCES_CHECK_INTERVAL.should eq(1.0)
    end

    it "defines CACHE_CLEAN_INTERVAL as 300" do
      RNS::Transport::CACHE_CLEAN_INTERVAL.should eq(300)
    end

    it "defines TABLES_CULL_INTERVAL as 5.0" do
      RNS::Transport::TABLES_CULL_INTERVAL.should eq(5.0)
    end
  end

  describe "table index constants" do
    it "defines path table indices" do
      RNS::Transport::IDX_PT_TIMESTAMP.should eq(0)
      RNS::Transport::IDX_PT_NEXT_HOP.should eq(1)
      RNS::Transport::IDX_PT_HOPS.should eq(2)
      RNS::Transport::IDX_PT_EXPIRES.should eq(3)
      RNS::Transport::IDX_PT_RANDBLOBS.should eq(4)
      RNS::Transport::IDX_PT_RVCD_IF.should eq(5)
      RNS::Transport::IDX_PT_PACKET.should eq(6)
    end

    it "defines reverse table indices" do
      RNS::Transport::IDX_RT_RCVD_IF.should eq(0)
      RNS::Transport::IDX_RT_OUTB_IF.should eq(1)
      RNS::Transport::IDX_RT_TIMESTAMP.should eq(2)
    end

    it "defines announce table indices" do
      RNS::Transport::IDX_AT_TIMESTAMP.should eq(0)
      RNS::Transport::IDX_AT_RETRIES.should eq(2)
      RNS::Transport::IDX_AT_HOPS.should eq(4)
      RNS::Transport::IDX_AT_PACKET.should eq(5)
      RNS::Transport::IDX_AT_LCL_RBRD.should eq(6)
      RNS::Transport::IDX_AT_BLCK_RBRD.should eq(7)
      RNS::Transport::IDX_AT_ATTCHD_IF.should eq(8)
    end

    it "defines link table indices" do
      RNS::Transport::IDX_LT_TIMESTAMP.should eq(0)
      RNS::Transport::IDX_LT_NH_TRID.should eq(1)
      RNS::Transport::IDX_LT_DSTHASH.should eq(6)
      RNS::Transport::IDX_LT_VALIDATED.should eq(7)
      RNS::Transport::IDX_LT_PROOF_TMO.should eq(8)
    end

    it "defines tunnel table indices" do
      RNS::Transport::IDX_TT_TUNNEL_ID.should eq(0)
      RNS::Transport::IDX_TT_IF.should eq(1)
      RNS::Transport::IDX_TT_PATHS.should eq(2)
      RNS::Transport::IDX_TT_EXPIRES.should eq(3)
    end
  end

  describe "APP_NAME" do
    it "is rnstransport" do
      RNS::Transport::APP_NAME.should eq("rnstransport")
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Initial State
  # ════════════════════════════════════════════════════════════════

  describe "initial state" do
    it "starts with empty destinations" do
      RNS::Transport.destinations.should be_empty
    end

    it "starts with empty interfaces" do
      RNS::Transport.interfaces.should be_empty
    end

    it "starts with empty path table" do
      RNS::Transport.path_table.should be_empty
    end

    it "starts with empty announce table" do
      RNS::Transport.announce_table.should be_empty
    end

    it "starts with empty reverse table" do
      RNS::Transport.reverse_table.should be_empty
    end

    it "starts with empty link table" do
      RNS::Transport.link_table.should be_empty
    end

    it "starts with empty tunnels" do
      RNS::Transport.tunnels.should be_empty
    end

    it "starts with empty packet hashlist" do
      RNS::Transport.packet_hashlist.should be_empty
    end

    it "starts with empty receipts" do
      RNS::Transport.receipts.should be_empty
    end

    it "starts with jobs not locked" do
      RNS::Transport.jobs_locked.should be_false
    end

    it "starts with jobs not running" do
      RNS::Transport.jobs_running.should be_false
    end

    it "starts with nil identity" do
      RNS::Transport.identity.should be_nil
    end

    it "starts with nil start_time" do
      RNS::Transport.start_time.should be_nil
    end

    it "starts with zero traffic counters" do
      RNS::Transport.traffic_rxb.should eq(0)
      RNS::Transport.traffic_txb.should eq(0)
      RNS::Transport.speed_rx.should eq(0)
      RNS::Transport.speed_tx.should eq(0)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Registration
  # ════════════════════════════════════════════════════════════════

  describe ".register_destination" do
    it "adds a destination to the list" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
      RNS::Transport.register_destination(dest)
      RNS::Transport.destinations.size.should eq(1)
      RNS::Transport.destinations[0].should eq(dest)
    end

    it "sets the destination MTU to Reticulum::MTU" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
      dest.mtu.should eq(0) # default before registration
      RNS::Transport.register_destination(dest)
      dest.mtu.should eq(RNS::Reticulum::MTU)
    end

    it "raises on duplicate IN destination hash" do
      dest1 = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
      RNS::Transport.register_destination(dest1)

      dest2 = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
      expect_raises(KeyError, "already registered") do
        RNS::Transport.register_destination(dest2)
      end
    end

    it "allows OUT destinations with same hash" do
      identity = RNS::Identity.new
      dest_in = RNS::Destination.new(identity, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest_out = RNS::Destination.new(identity, RNS::Destination::OUT, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Transport.register_destination(dest_in)
      RNS::Transport.register_destination(dest_out) # Should not raise
      RNS::Transport.destinations.size.should eq(2)
    end

    it "allows multiple different destinations" do
      dest1 = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "app1", register: false)
      dest2 = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "app2", register: false)
      RNS::Transport.register_destination(dest1)
      RNS::Transport.register_destination(dest2)
      RNS::Transport.destinations.size.should eq(2)
    end
  end

  describe ".deregister_destination" do
    it "removes a destination from the list" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
      RNS::Transport.register_destination(dest)
      RNS::Transport.destinations.size.should eq(1)
      RNS::Transport.deregister_destination(dest)
      RNS::Transport.destinations.should be_empty
    end

    it "does nothing if destination not registered" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
      RNS::Transport.deregister_destination(dest) # Should not raise
      RNS::Transport.destinations.should be_empty
    end
  end

  describe ".register_interface" do
    it "adds an interface hash" do
      iface_hash = Random::Secure.random_bytes(16)
      RNS::Transport.register_interface(iface_hash)
      RNS::Transport.interfaces.size.should eq(1)
      RNS::Transport.interfaces[0].should eq(iface_hash)
    end

    it "allows multiple interfaces" do
      3.times { RNS::Transport.register_interface(Random::Secure.random_bytes(16)) }
      RNS::Transport.interfaces.size.should eq(3)
    end
  end

  describe ".deregister_interface" do
    it "removes an interface hash" do
      iface_hash = Random::Secure.random_bytes(16)
      RNS::Transport.register_interface(iface_hash)
      RNS::Transport.deregister_interface(iface_hash)
      RNS::Transport.interfaces.should be_empty
    end
  end

  describe ".find_interface_from_hash" do
    it "finds a registered interface" do
      iface_hash = Random::Secure.random_bytes(16)
      RNS::Transport.register_interface(iface_hash)
      result = RNS::Transport.find_interface_from_hash(iface_hash)
      result.should_not be_nil
      result.should eq(iface_hash)
    end

    it "returns nil for unknown interface" do
      RNS::Transport.find_interface_from_hash(Random::Secure.random_bytes(16)).should be_nil
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Path Management
  # ════════════════════════════════════════════════════════════════

  describe ".has_path" do
    it "returns false for unknown destination" do
      RNS::Transport.has_path(Random::Secure.random_bytes(16)).should be_false
    end

    it "returns true for known destination" do
      dest_hash = Random::Secure.random_bytes(16)
      next_hop = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, next_hop, 1, Time.utc.to_unix_f + 3600.0)
      RNS::Transport.has_path(dest_hash).should be_true
    end
  end

  describe ".hops_to" do
    it "returns PATHFINDER_M for unknown destination" do
      RNS::Transport.hops_to(Random::Secure.random_bytes(16)).should eq(RNS::Transport::PATHFINDER_M)
    end

    it "returns correct hop count for known destination" do
      dest_hash = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 3, Time.utc.to_unix_f + 3600.0)
      RNS::Transport.hops_to(dest_hash).should eq(3)
    end

    it "returns 0 hops for directly reachable destination" do
      dest_hash = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 0, Time.utc.to_unix_f + 3600.0)
      RNS::Transport.hops_to(dest_hash).should eq(0)
    end
  end

  describe ".next_hop" do
    it "returns nil for unknown destination" do
      RNS::Transport.next_hop(Random::Secure.random_bytes(16)).should be_nil
    end

    it "returns next hop hash for known destination" do
      dest_hash = Random::Secure.random_bytes(16)
      next_hop_hash = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, next_hop_hash, 1, Time.utc.to_unix_f + 3600.0)
      RNS::Transport.next_hop(dest_hash).should eq(next_hop_hash)
    end
  end

  describe ".next_hop_interface" do
    it "returns nil for unknown destination" do
      RNS::Transport.next_hop_interface(Random::Secure.random_bytes(16)).should be_nil
    end

    it "returns interface hash for known destination" do
      dest_hash = Random::Secure.random_bytes(16)
      iface_hash = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 1,
        Time.utc.to_unix_f + 3600.0, receiving_interface: iface_hash)
      RNS::Transport.next_hop_interface(dest_hash).should eq(iface_hash)
    end

    it "returns nil when no interface recorded" do
      dest_hash = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 1, Time.utc.to_unix_f + 3600.0)
      RNS::Transport.next_hop_interface(dest_hash).should be_nil
    end
  end

  describe ".first_hop_timeout" do
    it "returns DEFAULT_PER_HOP_TIMEOUT" do
      RNS::Transport.first_hop_timeout(Random::Secure.random_bytes(16)).should eq(RNS::Reticulum::DEFAULT_PER_HOP_TIMEOUT.to_f64)
    end
  end

  describe ".expire_path" do
    it "returns false for unknown destination" do
      RNS::Transport.expire_path(Random::Secure.random_bytes(16)).should be_false
    end

    it "returns true and sets timestamp to 0 for known destination" do
      dest_hash = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 1, Time.utc.to_unix_f + 3600.0)
      RNS::Transport.expire_path(dest_hash).should be_true

      # Verify timestamp was set to 0
      entry = RNS::Transport.path_table[dest_hash.hexstring]
      entry.timestamp.should eq(0.0)
    end

    it "resets tables_last_culled to trigger culling" do
      dest_hash = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 1, Time.utc.to_unix_f + 3600.0)
      RNS::Transport.tables_last_culled = 100.0
      RNS::Transport.expire_path(dest_hash)
      RNS::Transport.tables_last_culled.should eq(0.0)
    end

    it "preserves other path entry fields" do
      dest_hash = Random::Secure.random_bytes(16)
      next_hop = Random::Secure.random_bytes(16)
      iface = Random::Secure.random_bytes(16)
      pkt_hash = Random::Secure.random_bytes(32)
      blobs = [Random::Secure.random_bytes(10)]

      RNS::Transport.update_path(dest_hash, next_hop, 3, 99999.0,
        receiving_interface: iface, packet_hash: pkt_hash, random_blobs: blobs)

      RNS::Transport.expire_path(dest_hash)

      entry = RNS::Transport.path_table[dest_hash.hexstring]
      entry.next_hop.should eq(next_hop)
      entry.hops.should eq(3)
      entry.expires.should eq(99999.0)
      entry.receiving_interface.should eq(iface)
      entry.packet_hash.should eq(pkt_hash)
      entry.random_blobs.size.should eq(1)
    end
  end

  describe ".mark_path_unresponsive" do
    it "returns false for unknown destination" do
      RNS::Transport.mark_path_unresponsive(Random::Secure.random_bytes(16)).should be_false
    end

    it "marks a known path as unresponsive" do
      dest_hash = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 1, Time.utc.to_unix_f + 3600.0)
      RNS::Transport.mark_path_unresponsive(dest_hash).should be_true
      RNS::Transport.path_is_unresponsive(dest_hash).should be_true
    end
  end

  describe ".mark_path_responsive" do
    it "returns false for unknown destination" do
      RNS::Transport.mark_path_responsive(Random::Secure.random_bytes(16)).should be_false
    end

    it "marks a known path as responsive" do
      dest_hash = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 1, Time.utc.to_unix_f + 3600.0)
      RNS::Transport.mark_path_unresponsive(dest_hash)
      RNS::Transport.mark_path_responsive(dest_hash).should be_true
      RNS::Transport.path_is_unresponsive(dest_hash).should be_false
    end
  end

  describe ".mark_path_unknown_state" do
    it "returns false for unknown destination" do
      RNS::Transport.mark_path_unknown_state(Random::Secure.random_bytes(16)).should be_false
    end

    it "sets state to unknown" do
      dest_hash = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 1, Time.utc.to_unix_f + 3600.0)
      RNS::Transport.mark_path_unresponsive(dest_hash)
      RNS::Transport.mark_path_unknown_state(dest_hash).should be_true
      RNS::Transport.path_is_unresponsive(dest_hash).should be_false
    end
  end

  describe ".path_is_unresponsive" do
    it "returns false for unknown destination" do
      RNS::Transport.path_is_unresponsive(Random::Secure.random_bytes(16)).should be_false
    end

    it "returns false for responsive paths" do
      dest_hash = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 1, Time.utc.to_unix_f + 3600.0)
      RNS::Transport.mark_path_responsive(dest_hash)
      RNS::Transport.path_is_unresponsive(dest_hash).should be_false
    end

    it "returns true for unresponsive paths" do
      dest_hash = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 1, Time.utc.to_unix_f + 3600.0)
      RNS::Transport.mark_path_unresponsive(dest_hash)
      RNS::Transport.path_is_unresponsive(dest_hash).should be_true
    end
  end

  describe ".update_path" do
    it "creates a new path entry" do
      dest_hash = Random::Secure.random_bytes(16)
      next_hop = Random::Secure.random_bytes(16)
      iface = Random::Secure.random_bytes(16)
      pkt_hash = Random::Secure.random_bytes(32)
      blobs = [Random::Secure.random_bytes(10), Random::Secure.random_bytes(10)]

      RNS::Transport.update_path(dest_hash, next_hop, 2, 99999.0,
        receiving_interface: iface, packet_hash: pkt_hash, random_blobs: blobs)

      RNS::Transport.has_path(dest_hash).should be_true
      entry = RNS::Transport.path_table[dest_hash.hexstring]
      entry.next_hop.should eq(next_hop)
      entry.hops.should eq(2)
      entry.expires.should eq(99999.0)
      entry.receiving_interface.should eq(iface)
      entry.packet_hash.should eq(pkt_hash)
      entry.random_blobs.size.should eq(2)
      entry.timestamp.should be_close(Time.utc.to_unix_f, 2.0)
    end

    it "overwrites an existing path entry" do
      dest_hash = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 5, 88888.0)

      new_next_hop = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, new_next_hop, 2, 99999.0)

      entry = RNS::Transport.path_table[dest_hash.hexstring]
      entry.next_hop.should eq(new_next_hop)
      entry.hops.should eq(2)
    end
  end

  describe ".remove_path" do
    it "returns false for unknown destination" do
      RNS::Transport.remove_path(Random::Secure.random_bytes(16)).should be_false
    end

    it "removes a known path" do
      dest_hash = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 1, Time.utc.to_unix_f + 3600.0)
      RNS::Transport.has_path(dest_hash).should be_true
      RNS::Transport.remove_path(dest_hash).should be_true
      RNS::Transport.has_path(dest_hash).should be_false
    end

    it "also removes associated path state" do
      dest_hash = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 1, Time.utc.to_unix_f + 3600.0)
      RNS::Transport.mark_path_unresponsive(dest_hash)
      RNS::Transport.remove_path(dest_hash)
      RNS::Transport.path_is_unresponsive(dest_hash).should be_false
      RNS::Transport.path_states.has_key?(dest_hash.hexstring).should be_false
    end
  end

  describe ".request_path" do
    it "records a path request timestamp" do
      dest_hash = Random::Secure.random_bytes(16)
      RNS::Transport.request_path(dest_hash)
      RNS::Transport.path_requests.has_key?(dest_hash.hexstring).should be_true
      RNS::Transport.path_requests[dest_hash.hexstring].should be_close(Time.utc.to_unix_f, 2.0)
    end

    it "accepts a custom tag" do
      dest_hash = Random::Secure.random_bytes(16)
      tag = Random::Secure.random_bytes(32)
      RNS::Transport.request_path(dest_hash, tag: tag)
      RNS::Transport.path_requests.has_key?(dest_hash.hexstring).should be_true
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Persistence — Path Table
  # ════════════════════════════════════════════════════════════════

  describe ".save_path_table and .load_path_table" do
    it "roundtrip persists path table entries" do
      tmp_dir = File.tempname("rns_transport_test")
      Dir.mkdir_p(tmp_dir)

      begin
        # Create some path entries
        dest1 = Random::Secure.random_bytes(16)
        dest2 = Random::Secure.random_bytes(16)
        next1 = Random::Secure.random_bytes(16)
        next2 = Random::Secure.random_bytes(16)
        iface1 = Random::Secure.random_bytes(16)
        pkt1 = Random::Secure.random_bytes(32)
        pkt2 = Random::Secure.random_bytes(32)
        blob1 = Random::Secure.random_bytes(10)
        blob2 = Random::Secure.random_bytes(10)

        RNS::Transport.update_path(dest1, next1, 2, Time.utc.to_unix_f + 3600.0,
          receiving_interface: iface1, packet_hash: pkt1, random_blobs: [blob1, blob2])
        RNS::Transport.update_path(dest2, next2, 5, Time.utc.to_unix_f + 7200.0,
          packet_hash: pkt2)

        RNS::Transport.save_path_table(tmp_dir).should be_true

        # Clear and reload
        RNS::Transport.reset

        loaded = RNS::Transport.load_path_table(tmp_dir)
        loaded.should eq(2)

        RNS::Transport.has_path(dest1).should be_true
        RNS::Transport.has_path(dest2).should be_true

        entry1 = RNS::Transport.path_table[dest1.hexstring]
        entry1.next_hop.should eq(next1)
        entry1.hops.should eq(3) # hops + 1 on load
        entry1.packet_hash.should eq(pkt1)
        entry1.receiving_interface.should eq(iface1)
        entry1.random_blobs.size.should eq(2)

        entry2 = RNS::Transport.path_table[dest2.hexstring]
        entry2.next_hop.should eq(next2)
        entry2.hops.should eq(6) # hops + 1 on load
      ensure
        FileUtils.rm_rf(tmp_dir) if Dir.exists?(tmp_dir)
      end
    end

    it "returns 0 when no file exists" do
      RNS::Transport.load_path_table("/nonexistent/path").should eq(0)
    end

    it "limits persisted random_blobs to PERSIST_RANDOM_BLOBS" do
      tmp_dir = File.tempname("rns_transport_test")
      Dir.mkdir_p(tmp_dir)

      begin
        dest = Random::Secure.random_bytes(16)
        blobs = (0...50).map { Random::Secure.random_bytes(10) }
        RNS::Transport.update_path(dest, Random::Secure.random_bytes(16), 1,
          Time.utc.to_unix_f + 3600.0, random_blobs: blobs)

        RNS::Transport.save_path_table(tmp_dir)
        RNS::Transport.reset
        RNS::Transport.load_path_table(tmp_dir)

        entry = RNS::Transport.path_table[dest.hexstring]
        entry.random_blobs.size.should eq(RNS::Transport::PERSIST_RANDOM_BLOBS)
      ensure
        FileUtils.rm_rf(tmp_dir) if Dir.exists?(tmp_dir)
      end
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Persistence — Packet Hashlist
  # ════════════════════════════════════════════════════════════════

  describe ".save_packet_hashlist and .load_packet_hashlist" do
    it "roundtrip persists packet hashlist" do
      tmp_dir = File.tempname("rns_transport_test")
      Dir.mkdir_p(tmp_dir)

      begin
        # Add some packet hashes
        hash1 = Random::Secure.random_bytes(32).hexstring
        hash2 = Random::Secure.random_bytes(32).hexstring
        hash3 = Random::Secure.random_bytes(32).hexstring
        RNS::Transport.packet_hashlist << hash1
        RNS::Transport.packet_hashlist << hash2
        RNS::Transport.packet_hashlist << hash3

        RNS::Transport.save_packet_hashlist(tmp_dir).should be_true

        # Clear and reload
        RNS::Transport.reset

        loaded = RNS::Transport.load_packet_hashlist(tmp_dir)
        loaded.should eq(3)
        RNS::Transport.packet_hashlist.includes?(hash1).should be_true
        RNS::Transport.packet_hashlist.includes?(hash2).should be_true
        RNS::Transport.packet_hashlist.includes?(hash3).should be_true
      ensure
        FileUtils.rm_rf(tmp_dir) if Dir.exists?(tmp_dir)
      end
    end

    it "returns 0 when no file exists" do
      RNS::Transport.load_packet_hashlist("/nonexistent/path").should eq(0)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Persistence — Tunnel Table
  # ════════════════════════════════════════════════════════════════

  describe ".save_tunnel_table" do
    it "saves an empty tunnel table" do
      tmp_dir = File.tempname("rns_transport_test")
      Dir.mkdir_p(tmp_dir)

      begin
        RNS::Transport.save_tunnel_table(tmp_dir).should be_true
        File.exists?(File.join(tmp_dir, "tunnels")).should be_true
      ensure
        FileUtils.rm_rf(tmp_dir) if Dir.exists?(tmp_dir)
      end
    end

    it "saves tunnel entries with paths" do
      tmp_dir = File.tempname("rns_transport_test")
      Dir.mkdir_p(tmp_dir)

      begin
        tunnel_id = Random::Secure.random_bytes(32)
        iface = Random::Secure.random_bytes(16)
        dest_hash = Random::Secure.random_bytes(16)
        path_entry = RNS::Transport::PathEntry.new(
          timestamp: Time.utc.to_unix_f,
          next_hop: Random::Secure.random_bytes(16),
          hops: 2,
          expires: Time.utc.to_unix_f + 3600.0,
          random_blobs: [] of Bytes,
          receiving_interface: iface,
          packet_hash: Random::Secure.random_bytes(32),
        )

        paths = Hash(String, RNS::Transport::PathEntry).new
        paths[dest_hash.hexstring] = path_entry

        tunnel = RNS::Transport::TunnelEntry.new(
          tunnel_id: tunnel_id,
          interface: iface,
          paths: paths,
          expires: Time.utc.to_unix_f + 7200.0,
        )
        RNS::Transport.tunnels[tunnel_id.hexstring] = tunnel

        RNS::Transport.save_tunnel_table(tmp_dir).should be_true
      ensure
        FileUtils.rm_rf(tmp_dir) if Dir.exists?(tmp_dir)
      end
    end
  end

  describe ".persist_data" do
    it "saves all tables" do
      tmp_dir = File.tempname("rns_transport_test")
      Dir.mkdir_p(tmp_dir)

      begin
        # Add some data to each table
        dest_hash = Random::Secure.random_bytes(16)
        RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 1, Time.utc.to_unix_f + 3600.0)
        RNS::Transport.packet_hashlist << Random::Secure.random_bytes(32).hexstring

        RNS::Transport.persist_data(tmp_dir)

        File.exists?(File.join(tmp_dir, "destination_table")).should be_true
        File.exists?(File.join(tmp_dir, "packet_hashlist")).should be_true
        File.exists?(File.join(tmp_dir, "tunnels")).should be_true
      ensure
        FileUtils.rm_rf(tmp_dir) if Dir.exists?(tmp_dir)
      end
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Record Types
  # ════════════════════════════════════════════════════════════════

  describe "PathEntry" do
    it "stores all fields correctly" do
      entry = RNS::Transport::PathEntry.new(
        timestamp: 12345.0,
        next_hop: Bytes[1, 2, 3],
        hops: 4,
        expires: 99999.0,
        random_blobs: [Bytes[10, 20, 30]],
        receiving_interface: Bytes[4, 5, 6],
        packet_hash: Bytes[7, 8, 9],
      )
      entry.timestamp.should eq(12345.0)
      entry.next_hop.should eq(Bytes[1, 2, 3])
      entry.hops.should eq(4)
      entry.expires.should eq(99999.0)
      entry.random_blobs.size.should eq(1)
      entry.receiving_interface.should eq(Bytes[4, 5, 6])
      entry.packet_hash.should eq(Bytes[7, 8, 9])
    end
  end

  describe "AnnounceEntry" do
    it "stores all fields correctly" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "test", register: false)
      pkt = RNS::Packet.new(dest, Bytes[1, 2, 3])
      entry = RNS::Transport::AnnounceEntry.new(
        timestamp: 100.0,
        retransmit_timeout: 5.0,
        retries: 0,
        received_from: Bytes[1, 2],
        hops: 3,
        packet: pkt,
        local_rebroadcasts: 0,
        block_rebroadcasts: false,
        attached_interface: nil,
      )
      entry.timestamp.should eq(100.0)
      entry.retries.should eq(0)
      entry.hops.should eq(3)
      entry.block_rebroadcasts.should be_false
    end
  end

  describe "ReverseEntry" do
    it "stores all fields correctly" do
      entry = RNS::Transport::ReverseEntry.new(
        received_on: Bytes[1, 2],
        outbound: Bytes[3, 4],
        timestamp: 500.0,
      )
      entry.received_on.should eq(Bytes[1, 2])
      entry.outbound.should eq(Bytes[3, 4])
      entry.timestamp.should eq(500.0)
    end
  end

  describe "LinkEntry" do
    it "stores all fields correctly" do
      entry = RNS::Transport::LinkEntry.new(
        timestamp: 100.0,
        next_hop_transport_id: Bytes[1],
        next_hop_interface: Bytes[2],
        remaining_hops: 3,
        received_on: Bytes[4],
        taken_hops: 1,
        destination_hash: Bytes[5],
        validated: false,
        proof_timeout: 200.0,
      )
      entry.remaining_hops.should eq(3)
      entry.validated.should be_false
      entry.proof_timeout.should eq(200.0)
    end
  end

  describe "TunnelEntry" do
    it "stores all fields correctly" do
      paths = Hash(String, RNS::Transport::PathEntry).new
      entry = RNS::Transport::TunnelEntry.new(
        tunnel_id: Bytes[1, 2, 3],
        interface: Bytes[4, 5],
        paths: paths,
        expires: 9999.0,
      )
      entry.tunnel_id.should eq(Bytes[1, 2, 3])
      entry.interface.should eq(Bytes[4, 5])
      entry.paths.should be_empty
      entry.expires.should eq(9999.0)
    end
  end

  describe "AnnounceRateEntry" do
    it "stores all fields correctly" do
      entry = RNS::Transport::AnnounceRateEntry.new(
        last: 100.0,
        rate_violations: 2,
        blocked_until: 200.0,
        timestamps: [50.0, 75.0, 100.0],
      )
      entry.last.should eq(100.0)
      entry.rate_violations.should eq(2)
      entry.blocked_until.should eq(200.0)
      entry.timestamps.size.should eq(3)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Reset
  # ════════════════════════════════════════════════════════════════

  describe ".reset" do
    it "clears all state" do
      # Add various state
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
      RNS::Transport.register_destination(dest)
      RNS::Transport.register_interface(Random::Secure.random_bytes(16))
      RNS::Transport.update_path(Random::Secure.random_bytes(16), Random::Secure.random_bytes(16), 1, 9999.0)
      RNS::Transport.packet_hashlist << "abc123"
      RNS::Transport.jobs_locked = true
      RNS::Transport.jobs_running = true

      RNS::Transport.reset

      RNS::Transport.destinations.should be_empty
      RNS::Transport.interfaces.should be_empty
      RNS::Transport.path_table.should be_empty
      RNS::Transport.packet_hashlist.should be_empty
      RNS::Transport.jobs_locked.should be_false
      RNS::Transport.jobs_running.should be_false
      RNS::Transport.identity.should be_nil
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Announce Handler
  # ════════════════════════════════════════════════════════════════

  describe "AnnounceHandler" do
    it "can register and deregister handlers" do
      handler = TestAnnounceHandler.new("test")
      RNS::Transport.register_announce_handler(handler)
      RNS::Transport.announce_handlers.size.should eq(1)
      RNS::Transport.deregister_announce_handler(handler)
      RNS::Transport.announce_handlers.should be_empty
    end

    it "supports multiple handlers" do
      h1 = TestAnnounceHandler.new("filter1")
      h2 = TestAnnounceHandler.new("filter2")
      RNS::Transport.register_announce_handler(h1)
      RNS::Transport.register_announce_handler(h2)
      RNS::Transport.announce_handlers.size.should eq(2)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Stress Tests
  # ════════════════════════════════════════════════════════════════

  describe "stress tests" do
    it "handles 100 path entries" do
      100.times do |i|
        dest_hash = Random::Secure.random_bytes(16)
        next_hop = Random::Secure.random_bytes(16)
        RNS::Transport.update_path(dest_hash, next_hop, i % 10, Time.utc.to_unix_f + 3600.0)
      end
      RNS::Transport.path_table.size.should eq(100)
    end

    it "handles 50 destination registrations" do
      50.times do
        dest = RNS::Destination.new(RNS::Identity.new, RNS::Destination::IN, RNS::Destination::SINGLE, "stressapp", register: false)
        RNS::Transport.register_destination(dest)
      end
      RNS::Transport.destinations.size.should eq(50)
    end

    it "path table persistence roundtrip with many entries" do
      tmp_dir = File.tempname("rns_transport_stress")
      Dir.mkdir_p(tmp_dir)

      begin
        dest_hashes = [] of Bytes
        20.times do
          dest_hash = Random::Secure.random_bytes(16)
          dest_hashes << dest_hash
          blobs = (0...5).map { Random::Secure.random_bytes(10) }
          RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16),
            rand(10), Time.utc.to_unix_f + 3600.0, random_blobs: blobs,
            packet_hash: Random::Secure.random_bytes(32))
        end

        RNS::Transport.save_path_table(tmp_dir)
        RNS::Transport.reset
        loaded = RNS::Transport.load_path_table(tmp_dir)
        loaded.should eq(20)

        dest_hashes.each do |dh|
          RNS::Transport.has_path(dh).should be_true
        end
      ensure
        FileUtils.rm_rf(tmp_dir) if Dir.exists?(tmp_dir)
      end
    end
  end
end

# ─── Test helper ─────────────────────────────────────────────────
require "file_utils"

class TestAnnounceHandler
  include RNS::Transport::AnnounceHandler

  getter aspect_filter : String?
  getter received_announces : Array(Bytes)

  def initialize(@aspect_filter : String?)
    @received_announces = [] of Bytes
  end

  def received_announce(destination_hash : Bytes, announced_identity : RNS::Identity?, app_data : Bytes?, announce_packet_hash : Bytes?)
    @received_announces << destination_hash
  end
end
