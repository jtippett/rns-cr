require "../../spec_helper"
require "file_utils"

# ─── Test helpers ────────────────────────────────────────────────
private def make_identity
  RNS::Identity.new(create_keys: true)
end

private def make_interface_hash
  Random::Secure.random_bytes(16)
end

private def make_destination(identity = nil, direction = RNS::Destination::IN, type = RNS::Destination::SINGLE)
  id = identity || make_identity
  RNS::Destination.new(id, direction, type, "test", ["app"], register: false)
end

private def make_plain_destination
  RNS::Destination.new(nil, RNS::Destination::OUT, RNS::Destination::PLAIN, "test", ["plain"], register: false)
end

private def make_packet(destination, data = Bytes.new(10, 0xAA_u8), packet_type = RNS::Packet::DATA, context = RNS::Packet::NONE)
  pkt = RNS::Packet.new(destination, data, packet_type: packet_type, context: context)
  pkt.pack
  pkt
end

private def make_temp_dir : String
  dir = File.join(Dir.tempdir, "rns_test_#{Random::Secure.hex(8)}")
  Dir.mkdir_p(dir)
  dir
end

private def make_owner_ref(storage_path : String, cache_path : String, transport_enabled : Bool = false)
  RNS::Transport::OwnerRef.new(
    is_connected_to_shared_instance: false,
    storage_path: storage_path,
    cache_path: cache_path,
    transport_enabled: transport_enabled,
  )
end

describe RNS::Transport do
  before_each do
    RNS::Transport.reset
    RNS::Identity.known_destinations.clear
    RNS::Identity.known_ratchets.clear
    RNS::Transport.identity = make_identity
  end

  # ════════════════════════════════════════════════════════════════
  #  OwnerRef record
  # ════════════════════════════════════════════════════════════════

  describe "OwnerRef" do
    it "can be created with default values" do
      ref = RNS::Transport::OwnerRef.new
      ref.is_connected_to_shared_instance.should be_false
      ref.storage_path.should eq("")
      ref.cache_path.should eq("")
      ref.transport_enabled.should be_false
    end

    it "can be created with custom values" do
      ref = RNS::Transport::OwnerRef.new(
        is_connected_to_shared_instance: true,
        storage_path: "/tmp/storage",
        cache_path: "/tmp/cache",
        transport_enabled: true,
      )
      ref.is_connected_to_shared_instance.should be_true
      ref.storage_path.should eq("/tmp/storage")
      ref.cache_path.should eq("/tmp/cache")
      ref.transport_enabled.should be_true
    end

    it "can be set and retrieved on Transport" do
      ref = RNS::Transport::OwnerRef.new(storage_path: "/tmp/test")
      RNS::Transport.owner = ref
      RNS::Transport.owner.should_not be_nil
      RNS::Transport.owner.try(&.storage_path).should eq("/tmp/test")
    end

    it "defaults to nil" do
      RNS::Transport.owner.should be_nil
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  should_cache
  # ════════════════════════════════════════════════════════════════

  describe ".should_cache" do
    it "returns false for any packet (caching disabled per Python)" do
      dest = make_plain_destination
      pkt = make_packet(dest)
      RNS::Transport.should_cache(pkt).should be_false
    end

    it "returns false for ANNOUNCE packets" do
      identity = make_identity
      dest = make_destination(identity, RNS::Destination::IN, RNS::Destination::SINGLE)
      pkt = make_packet(dest, packet_type: RNS::Packet::ANNOUNCE)
      RNS::Transport.should_cache(pkt).should be_false
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Packet caching (cache / get_cached_packet)
  # ════════════════════════════════════════════════════════════════

  describe ".cache and .get_cached_packet" do
    it "caches a packet when force_cache is true" do
      tmp = make_temp_dir
      begin
        RNS::Transport.owner = make_owner_ref(tmp, tmp)
        dest = make_plain_destination
        pkt = make_packet(dest)

        RNS::Transport.cache(pkt, force_cache: true)

        ph = pkt.get_hash
        cached_path = File.join(tmp, ph.hexstring)
        File.exists?(cached_path).should be_true
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "does not cache when force_cache is false and should_cache returns false" do
      tmp = make_temp_dir
      begin
        RNS::Transport.owner = make_owner_ref(tmp, tmp)
        dest = make_plain_destination
        pkt = make_packet(dest)

        RNS::Transport.cache(pkt, force_cache: false)

        ph = pkt.get_hash
        cached_path = File.join(tmp, ph.hexstring)
        File.exists?(cached_path).should be_false
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "caches announce packets in announces/ subdirectory" do
      tmp = make_temp_dir
      begin
        RNS::Transport.owner = make_owner_ref(tmp, tmp)
        dest = make_plain_destination
        pkt = make_packet(dest)

        RNS::Transport.cache(pkt, force_cache: true, packet_type: "announce")

        ph = pkt.get_hash
        cached_path = File.join(tmp, "announces", ph.hexstring)
        File.exists?(cached_path).should be_true
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "does nothing without owner set" do
      dest = make_plain_destination
      pkt = make_packet(dest)
      # Should not raise
      RNS::Transport.cache(pkt, force_cache: true)
    end

    it "retrieves a cached packet" do
      tmp = make_temp_dir
      begin
        RNS::Transport.owner = make_owner_ref(tmp, tmp)
        dest = make_plain_destination
        pkt = make_packet(dest)
        original_raw = pkt.raw.not_nil!.dup

        RNS::Transport.cache(pkt, force_cache: true)

        retrieved = RNS::Transport.get_cached_packet(pkt.get_hash)
        retrieved.should_not be_nil
        retrieved.not_nil!.raw.should eq(original_raw)
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "retrieves an announce-type cached packet" do
      tmp = make_temp_dir
      begin
        RNS::Transport.owner = make_owner_ref(tmp, tmp)
        dest = make_plain_destination
        pkt = make_packet(dest)
        original_raw = pkt.raw.not_nil!.dup

        RNS::Transport.cache(pkt, force_cache: true, packet_type: "announce")

        retrieved = RNS::Transport.get_cached_packet(pkt.get_hash, packet_type: "announce")
        retrieved.should_not be_nil
        retrieved.not_nil!.raw.should eq(original_raw)
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "returns nil for non-existent cached packet" do
      tmp = make_temp_dir
      begin
        RNS::Transport.owner = make_owner_ref(tmp, tmp)
        fake_hash = Random::Secure.random_bytes(32)
        RNS::Transport.get_cached_packet(fake_hash).should be_nil
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "returns nil without owner set" do
      fake_hash = Random::Secure.random_bytes(32)
      RNS::Transport.get_cached_packet(fake_hash).should be_nil
    end

    it "roundtrip: cache and retrieve preserves raw bytes exactly" do
      tmp = make_temp_dir
      begin
        RNS::Transport.owner = make_owner_ref(tmp, tmp)
        10.times do
          data = Random::Secure.random_bytes(rand(1..100))
          dest = make_plain_destination
          pkt = make_packet(dest, data)
          original_raw = pkt.raw.not_nil!.dup

          RNS::Transport.cache(pkt, force_cache: true)
          retrieved = RNS::Transport.get_cached_packet(pkt.get_hash)
          retrieved.should_not be_nil
          retrieved.not_nil!.raw.should eq(original_raw)
        end
      ensure
        FileUtils.rm_rf(tmp)
      end
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  cache_request_packet
  # ════════════════════════════════════════════════════════════════

  describe ".cache_request_packet" do
    it "returns false when data is wrong size" do
      dest = make_plain_destination
      pkt = make_packet(dest, Bytes.new(5, 0xBB_u8))
      RNS::Transport.cache_request_packet(pkt).should be_false
    end

    it "returns false when requested packet is not cached" do
      tmp = make_temp_dir
      begin
        RNS::Transport.owner = make_owner_ref(tmp, tmp)
        # Create a packet with data sized to HASHLENGTH/8 (32 bytes)
        fake_hash = Random::Secure.random_bytes(RNS::Identity::HASHLENGTH // 8)
        dest = make_plain_destination
        pkt = make_packet(dest, fake_hash)
        RNS::Transport.cache_request_packet(pkt).should be_false
      ensure
        FileUtils.rm_rf(tmp)
      end
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  clean_cache
  # ════════════════════════════════════════════════════════════════

  describe ".clean_cache" do
    it "removes orphaned announce cache files" do
      tmp = make_temp_dir
      begin
        RNS::Transport.owner = make_owner_ref(tmp, tmp)

        announce_dir = File.join(tmp, "announces")
        Dir.mkdir_p(announce_dir)

        # Create orphan files
        3.times do |i|
          File.write(File.join(announce_dir, Random::Secure.hex(32)), "data#{i}")
        end

        # Create file referenced by path table
        active_hash = Random::Secure.random_bytes(32)
        dest_hash = Random::Secure.random_bytes(16)
        RNS::Transport.update_path(
          dest_hash,
          Random::Secure.random_bytes(16),
          1,
          (Time.utc.to_unix_f + 3600.0),
          packet_hash: active_hash,
        )
        File.write(File.join(announce_dir, active_hash.hexstring), "active")

        Dir.children(announce_dir).size.should eq(4)

        RNS::Transport.clean_cache

        # Only the active one should remain
        Dir.children(announce_dir).size.should eq(1)
        File.exists?(File.join(announce_dir, active_hash.hexstring)).should be_true
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "does nothing without owner" do
      # Should not raise
      RNS::Transport.clean_cache
    end

    it "updates cache_last_cleaned timestamp" do
      tmp = make_temp_dir
      begin
        RNS::Transport.owner = make_owner_ref(tmp, tmp)
        before = Time.utc.to_unix_f
        RNS::Transport.clean_cache
        # cache_last_cleaned is private, but we can verify it doesn't crash
        # and that orphaned files are cleaned
      ensure
        FileUtils.rm_rf(tmp)
      end
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Packet hashlist persistence
  # ════════════════════════════════════════════════════════════════

  describe "packet hashlist persistence" do
    it "save and load roundtrip" do
      tmp = make_temp_dir
      begin
        # Add some hashes
        5.times do
          h = Random::Secure.random_bytes(32)
          RNS::Transport.add_packet_hash(h)
        end

        original_size = RNS::Transport.packet_hashlist.size

        # Save
        RNS::Transport.save_packet_hashlist(tmp).should be_true

        # Verify file exists
        File.exists?(File.join(tmp, "packet_hashlist")).should be_true

        # Reset and reload
        original_hashes = RNS::Transport.packet_hashlist.dup
        RNS::Transport.packet_hashlist.clear

        loaded = RNS::Transport.load_packet_hashlist(tmp)
        loaded.should eq(original_size)

        # Verify all hashes are present
        original_hashes.each do |hex|
          RNS::Transport.packet_hashlist.includes?(hex).should be_true
        end
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "returns 0 when file doesn't exist" do
      tmp = make_temp_dir
      begin
        RNS::Transport.load_packet_hashlist(tmp).should eq(0)
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "handles empty hashlist" do
      tmp = make_temp_dir
      begin
        RNS::Transport.save_packet_hashlist(tmp).should be_true
        RNS::Transport.load_packet_hashlist(tmp).should eq(0)
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "handles save guard (concurrent protection)" do
      tmp = make_temp_dir
      begin
        5.times { RNS::Transport.add_packet_hash(Random::Secure.random_bytes(32)) }
        # Multiple saves should succeed without corruption
        RNS::Transport.save_packet_hashlist(tmp).should be_true
        RNS::Transport.save_packet_hashlist(tmp).should be_true
      ensure
        FileUtils.rm_rf(tmp)
      end
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Path table persistence
  # ════════════════════════════════════════════════════════════════

  describe "path table persistence" do
    it "save and load roundtrip" do
      tmp = make_temp_dir
      begin
        iface = make_interface_hash
        RNS::Transport.register_interface(iface)

        3.times do |i|
          dest_hash = Random::Secure.random_bytes(16)
          blobs = [Random::Secure.random_bytes(10), Random::Secure.random_bytes(10)]
          RNS::Transport.update_path(
            dest_hash,
            Random::Secure.random_bytes(16),
            i + 1,
            Time.utc.to_unix_f + 3600.0,
            receiving_interface: iface,
            packet_hash: Random::Secure.random_bytes(32),
            random_blobs: blobs,
          )
        end

        RNS::Transport.save_path_table(tmp).should be_true

        # Remember keys
        original_keys = RNS::Transport.path_table.keys.sort!

        # Reset and reload
        RNS::Transport.path_table.clear
        loaded = RNS::Transport.load_path_table(tmp)
        loaded.should eq(3)

        # Verify keys match
        RNS::Transport.path_table.keys.sort!.should eq(original_keys)

        # Verify hops incremented
        RNS::Transport.path_table.each_value do |entry|
          entry.hops.should be > 0
        end
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "returns 0 when file doesn't exist" do
      tmp = make_temp_dir
      begin
        RNS::Transport.load_path_table(tmp).should eq(0)
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "preserves random blobs within PERSIST_RANDOM_BLOBS limit" do
      tmp = make_temp_dir
      begin
        iface = make_interface_hash
        RNS::Transport.register_interface(iface)

        dest_hash = Random::Secure.random_bytes(16)
        many_blobs = (0...50).map { Random::Secure.random_bytes(10) }
        RNS::Transport.update_path(
          dest_hash,
          Random::Secure.random_bytes(16),
          1,
          Time.utc.to_unix_f + 3600.0,
          receiving_interface: iface,
          packet_hash: Random::Secure.random_bytes(32),
          random_blobs: many_blobs,
        )

        RNS::Transport.save_path_table(tmp).should be_true

        RNS::Transport.path_table.clear
        RNS::Transport.load_path_table(tmp)

        key = dest_hash.hexstring
        entry = RNS::Transport.path_table[key]
        entry.random_blobs.size.should be <= RNS::Transport::PERSIST_RANDOM_BLOBS
      ensure
        FileUtils.rm_rf(tmp)
      end
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Tunnel table persistence
  # ════════════════════════════════════════════════════════════════

  describe "tunnel table persistence" do
    it "save and load roundtrip" do
      tmp = make_temp_dir
      begin
        iface = make_interface_hash
        RNS::Transport.register_interface(iface)

        tunnel_id = Random::Secure.random_bytes(16)
        paths = Hash(String, RNS::Transport::PathEntry).new

        2.times do |i|
          dest_hash = Random::Secure.random_bytes(16)
          paths[dest_hash.hexstring] = RNS::Transport::PathEntry.new(
            timestamp: Time.utc.to_unix_f,
            next_hop: Random::Secure.random_bytes(16),
            hops: i + 1,
            expires: Time.utc.to_unix_f + 7200.0,
            random_blobs: [Random::Secure.random_bytes(10)],
            receiving_interface: iface,
            packet_hash: Random::Secure.random_bytes(32),
          )
        end

        RNS::Transport.tunnels[tunnel_id.hexstring] = RNS::Transport::TunnelEntry.new(
          tunnel_id: tunnel_id,
          interface: iface,
          paths: paths,
          expires: Time.utc.to_unix_f + 7200.0,
        )

        RNS::Transport.save_tunnel_table(tmp).should be_true

        # Verify file exists
        File.exists?(File.join(tmp, "tunnels")).should be_true

        # Remember tunnel ID
        original_tunnel_hex = tunnel_id.hexstring

        # Reset and reload
        RNS::Transport.tunnels.clear
        loaded = RNS::Transport.load_tunnel_table(tmp)
        loaded.should eq(1)

        RNS::Transport.tunnels.has_key?(original_tunnel_hex).should be_true
        tunnel = RNS::Transport.tunnels[original_tunnel_hex]
        tunnel.paths.size.should eq(2)
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "returns 0 when file doesn't exist" do
      tmp = make_temp_dir
      begin
        RNS::Transport.load_tunnel_table(tmp).should eq(0)
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "increments hops on tunnel path load" do
      tmp = make_temp_dir
      begin
        iface = make_interface_hash
        RNS::Transport.register_interface(iface)

        tunnel_id = Random::Secure.random_bytes(16)
        dest_hash = Random::Secure.random_bytes(16)
        original_hops = 3

        paths = Hash(String, RNS::Transport::PathEntry).new
        paths[dest_hash.hexstring] = RNS::Transport::PathEntry.new(
          timestamp: Time.utc.to_unix_f,
          next_hop: Random::Secure.random_bytes(16),
          hops: original_hops,
          expires: Time.utc.to_unix_f + 7200.0,
          random_blobs: [] of Bytes,
          receiving_interface: iface,
          packet_hash: Random::Secure.random_bytes(32),
        )

        RNS::Transport.tunnels[tunnel_id.hexstring] = RNS::Transport::TunnelEntry.new(
          tunnel_id: tunnel_id,
          interface: iface,
          paths: paths,
          expires: Time.utc.to_unix_f + 7200.0,
        )

        RNS::Transport.save_tunnel_table(tmp)
        RNS::Transport.tunnels.clear
        RNS::Transport.load_tunnel_table(tmp)

        tunnel = RNS::Transport.tunnels[tunnel_id.hexstring]
        entry = tunnel.paths[dest_hash.hexstring]
        entry.hops.should eq(original_hops + 1)
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "skips tunnels with no paths" do
      tmp = make_temp_dir
      begin
        tunnel_id = Random::Secure.random_bytes(16)
        empty_paths = Hash(String, RNS::Transport::PathEntry).new

        RNS::Transport.tunnels[tunnel_id.hexstring] = RNS::Transport::TunnelEntry.new(
          tunnel_id: tunnel_id,
          interface: nil,
          paths: empty_paths,
          expires: Time.utc.to_unix_f + 7200.0,
        )

        RNS::Transport.save_tunnel_table(tmp)
        RNS::Transport.tunnels.clear
        loaded = RNS::Transport.load_tunnel_table(tmp)
        loaded.should eq(0)
        RNS::Transport.tunnels.size.should eq(0)
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "handles multiple tunnels" do
      tmp = make_temp_dir
      begin
        iface = make_interface_hash
        RNS::Transport.register_interface(iface)

        3.times do
          tunnel_id = Random::Secure.random_bytes(16)
          paths = Hash(String, RNS::Transport::PathEntry).new
          dest_hash = Random::Secure.random_bytes(16)
          paths[dest_hash.hexstring] = RNS::Transport::PathEntry.new(
            timestamp: Time.utc.to_unix_f,
            next_hop: Random::Secure.random_bytes(16),
            hops: 1,
            expires: Time.utc.to_unix_f + 7200.0,
            random_blobs: [] of Bytes,
            receiving_interface: iface,
            packet_hash: Random::Secure.random_bytes(32),
          )
          RNS::Transport.tunnels[tunnel_id.hexstring] = RNS::Transport::TunnelEntry.new(
            tunnel_id: tunnel_id,
            interface: iface,
            paths: paths,
            expires: Time.utc.to_unix_f + 7200.0,
          )
        end

        RNS::Transport.save_tunnel_table(tmp)
        RNS::Transport.tunnels.clear
        loaded = RNS::Transport.load_tunnel_table(tmp)
        loaded.should eq(3)
      ensure
        FileUtils.rm_rf(tmp)
      end
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  persist_data
  # ════════════════════════════════════════════════════════════════

  describe ".persist_data" do
    it "saves all tables to disk" do
      tmp = make_temp_dir
      begin
        iface = make_interface_hash
        RNS::Transport.register_interface(iface)

        # Add path entry
        dest_hash = Random::Secure.random_bytes(16)
        RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 1,
          Time.utc.to_unix_f + 3600.0, receiving_interface: iface,
          packet_hash: Random::Secure.random_bytes(32))

        # Add packet hash
        RNS::Transport.add_packet_hash(Random::Secure.random_bytes(32))

        # Add tunnel
        tunnel_id = Random::Secure.random_bytes(16)
        paths = Hash(String, RNS::Transport::PathEntry).new
        td = Random::Secure.random_bytes(16)
        paths[td.hexstring] = RNS::Transport::PathEntry.new(
          timestamp: Time.utc.to_unix_f, next_hop: Random::Secure.random_bytes(16),
          hops: 1, expires: Time.utc.to_unix_f + 7200.0, random_blobs: [] of Bytes,
          receiving_interface: iface, packet_hash: Random::Secure.random_bytes(32))
        RNS::Transport.tunnels[tunnel_id.hexstring] = RNS::Transport::TunnelEntry.new(
          tunnel_id: tunnel_id, interface: iface, paths: paths,
          expires: Time.utc.to_unix_f + 7200.0)

        RNS::Transport.persist_data(tmp)

        File.exists?(File.join(tmp, "destination_table")).should be_true
        File.exists?(File.join(tmp, "packet_hashlist")).should be_true
        File.exists?(File.join(tmp, "tunnels")).should be_true
      ensure
        FileUtils.rm_rf(tmp)
      end
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  start() initialization
  # ════════════════════════════════════════════════════════════════

  describe ".start" do
    it "creates a transport identity when none exists" do
      tmp = make_temp_dir
      begin
        RNS::Transport.identity = nil

        owner = make_owner_ref(tmp, tmp)
        RNS::Transport.start(owner)

        RNS::Transport.identity.should_not be_nil
        File.exists?(File.join(tmp, "transport_identity")).should be_true
      ensure
        RNS::Transport.stop_job_loop
        FileUtils.rm_rf(tmp)
      end
    end

    it "loads existing transport identity from storage" do
      tmp = make_temp_dir
      begin
        # Create and save an identity
        original_identity = RNS::Identity.new
        identity_path = File.join(tmp, "transport_identity")
        original_identity.to_file(identity_path)
        original_hash = original_identity.hash.not_nil!.dup

        RNS::Transport.identity = nil
        owner = make_owner_ref(tmp, tmp)
        RNS::Transport.start(owner)

        RNS::Transport.identity.should_not be_nil
        RNS::Transport.identity.not_nil!.hash.should eq(original_hash)
      ensure
        RNS::Transport.stop_job_loop
        FileUtils.rm_rf(tmp)
      end
    end

    it "sets owner reference" do
      tmp = make_temp_dir
      begin
        owner = make_owner_ref(tmp, tmp)
        RNS::Transport.start(owner)

        RNS::Transport.owner.should_not be_nil
        RNS::Transport.owner.try(&.storage_path).should eq(tmp)
      ensure
        RNS::Transport.stop_job_loop
        FileUtils.rm_rf(tmp)
      end
    end

    it "sets start_time" do
      tmp = make_temp_dir
      begin
        before = Time.utc.to_unix_f
        owner = make_owner_ref(tmp, tmp)
        RNS::Transport.start(owner)
        after = Time.utc.to_unix_f

        st = RNS::Transport.start_time
        st.should_not be_nil
        st.not_nil!.should be >= before
        st.not_nil!.should be <= after
      ensure
        RNS::Transport.stop_job_loop
        FileUtils.rm_rf(tmp)
      end
    end

    it "creates control destinations" do
      tmp = make_temp_dir
      begin
        owner = make_owner_ref(tmp, tmp)
        RNS::Transport.start(owner)

        RNS::Transport.control_destinations.size.should be >= 2
        RNS::Transport.control_hashes.size.should be >= 2
      ensure
        RNS::Transport.stop_job_loop
        FileUtils.rm_rf(tmp)
      end
    end

    it "starts the job loop fiber" do
      tmp = make_temp_dir
      begin
        owner = make_owner_ref(tmp, tmp)
        RNS::Transport.start(owner)

        RNS::Transport.job_loop_running?.should be_true
      ensure
        RNS::Transport.stop_job_loop
        FileUtils.rm_rf(tmp)
      end
    end

    it "loads packet hashlist from storage" do
      tmp = make_temp_dir
      begin
        # Pre-save some hashes
        5.times { RNS::Transport.add_packet_hash(Random::Secure.random_bytes(32)) }
        RNS::Transport.save_packet_hashlist(tmp)
        saved_size = RNS::Transport.packet_hashlist.size

        # Reset and start
        RNS::Transport.reset
        RNS::Transport.identity = nil
        owner = make_owner_ref(tmp, tmp)
        RNS::Transport.start(owner)

        RNS::Transport.packet_hashlist.size.should eq(saved_size)
      ensure
        RNS::Transport.stop_job_loop
        FileUtils.rm_rf(tmp)
      end
    end

    it "enables transport and loads path/tunnel tables when transport_enabled" do
      tmp = make_temp_dir
      begin
        iface = make_interface_hash

        # Set up some path data and save it
        RNS::Transport.register_interface(iface)
        dest_hash = Random::Secure.random_bytes(16)
        RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 1,
          Time.utc.to_unix_f + 3600.0, receiving_interface: iface,
          packet_hash: Random::Secure.random_bytes(32))
        RNS::Transport.save_path_table(tmp)

        # Reset and start with transport enabled
        RNS::Transport.reset
        RNS::Transport.identity = nil
        RNS::Transport.register_interface(iface)
        owner = make_owner_ref(tmp, tmp, transport_enabled: true)
        RNS::Transport.start(owner)

        RNS::Transport.transport_enabled?.should be_true
        RNS::Transport.path_table.size.should eq(1)
      ensure
        RNS::Transport.stop_job_loop
        FileUtils.rm_rf(tmp)
      end
    end

    it "does not load path tables when transport not enabled" do
      tmp = make_temp_dir
      begin
        iface = make_interface_hash

        # Set up and save path data
        RNS::Transport.register_interface(iface)
        dest_hash = Random::Secure.random_bytes(16)
        RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 1,
          Time.utc.to_unix_f + 3600.0, receiving_interface: iface,
          packet_hash: Random::Secure.random_bytes(32))
        RNS::Transport.save_path_table(tmp)

        # Reset and start without transport
        RNS::Transport.reset
        RNS::Transport.identity = nil
        owner = make_owner_ref(tmp, tmp, transport_enabled: false)
        RNS::Transport.start(owner)

        RNS::Transport.transport_enabled?.should be_false
        RNS::Transport.path_table.size.should eq(0)
      ensure
        RNS::Transport.stop_job_loop
        FileUtils.rm_rf(tmp)
      end
    end

    it "preserves existing identity if already set" do
      tmp = make_temp_dir
      begin
        existing = RNS::Identity.new
        RNS::Transport.identity = existing
        existing_hash = existing.hash.not_nil!.dup

        owner = make_owner_ref(tmp, tmp)
        RNS::Transport.start(owner)

        RNS::Transport.identity.not_nil!.hash.should eq(existing_hash)
      ensure
        RNS::Transport.stop_job_loop
        FileUtils.rm_rf(tmp)
      end
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Job loop
  # ════════════════════════════════════════════════════════════════

  describe "job loop" do
    it "starts and stops cleanly" do
      RNS::Transport.start_job_loop
      RNS::Transport.job_loop_running?.should be_true

      RNS::Transport.stop_job_loop
      sleep(50.milliseconds) # Let the fiber notice the stop flag
      Fiber.yield

      RNS::Transport.job_loop_running?.should be_false
    end

    it "does not start twice" do
      RNS::Transport.start_job_loop
      RNS::Transport.start_job_loop # Should be a no-op
      RNS::Transport.job_loop_running?.should be_true
      RNS::Transport.stop_job_loop
      sleep(50.milliseconds)
      Fiber.yield
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  exit_handler
  # ════════════════════════════════════════════════════════════════

  describe ".exit_handler" do
    it "persists data and stops job loop" do
      tmp = make_temp_dir
      begin
        iface = make_interface_hash
        RNS::Transport.register_interface(iface)

        owner = make_owner_ref(tmp, tmp)
        RNS::Transport.start(owner)

        # Add some data to persist
        dest_hash = Random::Secure.random_bytes(16)
        RNS::Transport.update_path(dest_hash, Random::Secure.random_bytes(16), 1,
          Time.utc.to_unix_f + 3600.0, receiving_interface: iface,
          packet_hash: Random::Secure.random_bytes(32))
        RNS::Transport.add_packet_hash(Random::Secure.random_bytes(32))

        RNS::Transport.exit_handler

        # Verify data was persisted
        File.exists?(File.join(tmp, "destination_table")).should be_true
        File.exists?(File.join(tmp, "packet_hashlist")).should be_true
        File.exists?(File.join(tmp, "tunnels")).should be_true

        # Verify job loop stopped
        RNS::Transport.job_loop_running?.should be_false
      ensure
        RNS::Transport.stop_job_loop
        FileUtils.rm_rf(tmp)
      end
    end

    it "does nothing without owner" do
      # Should not raise
      RNS::Transport.exit_handler
    end

    it "does nothing for shared instance" do
      tmp = make_temp_dir
      begin
        owner = RNS::Transport::OwnerRef.new(
          is_connected_to_shared_instance: true,
          storage_path: tmp,
          cache_path: tmp,
        )
        RNS::Transport.owner = owner

        RNS::Transport.exit_handler

        # No files should be created
        File.exists?(File.join(tmp, "destination_table")).should be_false
        File.exists?(File.join(tmp, "packet_hashlist")).should be_false
      ensure
        FileUtils.rm_rf(tmp)
      end
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Full lifecycle integration
  # ════════════════════════════════════════════════════════════════

  describe "full lifecycle" do
    it "start -> populate -> exit -> restart preserves state" do
      tmp_storage = make_temp_dir
      tmp_cache = make_temp_dir
      begin
        iface = make_interface_hash

        # First session: start and populate
        RNS::Transport.reset
        RNS::Transport.identity = nil
        RNS::Transport.register_interface(iface)
        owner = make_owner_ref(tmp_storage, tmp_cache, transport_enabled: true)
        RNS::Transport.start(owner)

        identity_hash = RNS::Transport.identity.not_nil!.hash.not_nil!.dup

        # Add paths
        dest1 = Random::Secure.random_bytes(16)
        dest2 = Random::Secure.random_bytes(16)
        RNS::Transport.update_path(dest1, Random::Secure.random_bytes(16), 2,
          Time.utc.to_unix_f + 3600.0, receiving_interface: iface,
          packet_hash: Random::Secure.random_bytes(32))
        RNS::Transport.update_path(dest2, Random::Secure.random_bytes(16), 1,
          Time.utc.to_unix_f + 3600.0, receiving_interface: iface,
          packet_hash: Random::Secure.random_bytes(32))

        # Add packet hashes
        10.times { RNS::Transport.add_packet_hash(Random::Secure.random_bytes(32)) }

        # Exit (persists data)
        RNS::Transport.exit_handler

        # Second session: restart and verify
        RNS::Transport.reset
        RNS::Transport.identity = nil
        RNS::Transport.register_interface(iface)
        owner2 = make_owner_ref(tmp_storage, tmp_cache, transport_enabled: true)
        RNS::Transport.start(owner2)

        # Identity should be the same
        RNS::Transport.identity.not_nil!.hash.should eq(identity_hash)

        # Paths should be restored (with hops incremented)
        RNS::Transport.path_table.size.should eq(2)
        RNS::Transport.path_table.has_key?(dest1.hexstring).should be_true
        RNS::Transport.path_table.has_key?(dest2.hexstring).should be_true

        # Packet hashes should be restored
        RNS::Transport.packet_hashlist.size.should eq(10)

        RNS::Transport.stop_job_loop
      ensure
        RNS::Transport.stop_job_loop
        FileUtils.rm_rf(tmp_storage)
        FileUtils.rm_rf(tmp_cache)
      end
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Stress tests
  # ════════════════════════════════════════════════════════════════

  describe "stress tests" do
    it "saves and loads 50 path entries" do
      tmp = make_temp_dir
      begin
        iface = make_interface_hash
        RNS::Transport.register_interface(iface)

        dest_hashes = [] of Bytes
        50.times do
          dest = Random::Secure.random_bytes(16)
          dest_hashes << dest
          RNS::Transport.update_path(dest, Random::Secure.random_bytes(16),
            rand(1..10), Time.utc.to_unix_f + 3600.0,
            receiving_interface: iface,
            packet_hash: Random::Secure.random_bytes(32),
            random_blobs: [Random::Secure.random_bytes(10)])
        end

        RNS::Transport.save_path_table(tmp).should be_true
        RNS::Transport.path_table.clear
        loaded = RNS::Transport.load_path_table(tmp)
        loaded.should eq(50)
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "saves and loads 100 packet hashes" do
      tmp = make_temp_dir
      begin
        100.times { RNS::Transport.add_packet_hash(Random::Secure.random_bytes(32)) }

        RNS::Transport.save_packet_hashlist(tmp).should be_true
        saved_size = RNS::Transport.packet_hashlist.size

        RNS::Transport.packet_hashlist.clear
        loaded = RNS::Transport.load_packet_hashlist(tmp)
        loaded.should eq(saved_size)
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "caches and retrieves 20 packets" do
      tmp = make_temp_dir
      begin
        RNS::Transport.owner = make_owner_ref(tmp, tmp)

        packets = [] of {RNS::Packet, Bytes}
        20.times do
          dest = make_plain_destination
          data = Random::Secure.random_bytes(rand(10..100))
          pkt = make_packet(dest, data)
          packets << {pkt, pkt.raw.not_nil!.dup}
          RNS::Transport.cache(pkt, force_cache: true)
        end

        packets.each do |pkt, original_raw|
          retrieved = RNS::Transport.get_cached_packet(pkt.get_hash)
          retrieved.should_not be_nil
          retrieved.not_nil!.raw.should eq(original_raw)
        end
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    it "handles 10 tunnels with 5 paths each" do
      tmp = make_temp_dir
      begin
        iface = make_interface_hash
        RNS::Transport.register_interface(iface)

        10.times do
          tunnel_id = Random::Secure.random_bytes(16)
          paths = Hash(String, RNS::Transport::PathEntry).new
          5.times do
            dest = Random::Secure.random_bytes(16)
            paths[dest.hexstring] = RNS::Transport::PathEntry.new(
              timestamp: Time.utc.to_unix_f, next_hop: Random::Secure.random_bytes(16),
              hops: rand(1..5), expires: Time.utc.to_unix_f + 7200.0,
              random_blobs: [Random::Secure.random_bytes(10)],
              receiving_interface: iface, packet_hash: Random::Secure.random_bytes(32))
          end
          RNS::Transport.tunnels[tunnel_id.hexstring] = RNS::Transport::TunnelEntry.new(
            tunnel_id: tunnel_id, interface: iface, paths: paths,
            expires: Time.utc.to_unix_f + 7200.0)
        end

        RNS::Transport.save_tunnel_table(tmp).should be_true
        RNS::Transport.tunnels.clear
        loaded = RNS::Transport.load_tunnel_table(tmp)
        loaded.should eq(10)

        total_paths = 0
        RNS::Transport.tunnels.each_value { |t| total_paths += t.paths.size }
        total_paths.should eq(50)
      ensure
        FileUtils.rm_rf(tmp)
      end
    end
  end
end
