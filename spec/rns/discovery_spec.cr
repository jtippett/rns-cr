require "../spec_helper"

describe RNS::Discovery do
  # ─── Constants ──────────────────────────────────────────────────────

  describe "constants" do
    it "defines field key constants matching Python" do
      RNS::Discovery::NAME.should eq(0xFF_u8)
      RNS::Discovery::TRANSPORT_ID.should eq(0xFE_u8)
      RNS::Discovery::INTERFACE_TYPE.should eq(0x00_u8)
      RNS::Discovery::TRANSPORT.should eq(0x01_u8)
      RNS::Discovery::REACHABLE_ON.should eq(0x02_u8)
      RNS::Discovery::LATITUDE.should eq(0x03_u8)
      RNS::Discovery::LONGITUDE.should eq(0x04_u8)
      RNS::Discovery::HEIGHT.should eq(0x05_u8)
      RNS::Discovery::PORT.should eq(0x06_u8)
      RNS::Discovery::IFAC_NETNAME.should eq(0x07_u8)
      RNS::Discovery::IFAC_NETKEY.should eq(0x08_u8)
      RNS::Discovery::FREQUENCY.should eq(0x09_u8)
      RNS::Discovery::BANDWIDTH.should eq(0x0A_u8)
      RNS::Discovery::SPREADINGFACTOR.should eq(0x0B_u8)
      RNS::Discovery::CODINGRATE.should eq(0x0C_u8)
      RNS::Discovery::MODULATION.should eq(0x0D_u8)
      RNS::Discovery::CHANNEL.should eq(0x0E_u8)
    end

    it "defines APP_NAME matching Python" do
      RNS::Discovery::APP_NAME.should eq("rnstransport")
    end
  end

  # ─── Helper functions ───────────────────────────────────────────────

  describe ".is_ip_address?" do
    it "recognizes valid IPv4 addresses" do
      RNS::Discovery.is_ip_address?("192.168.1.1").should be_true
      RNS::Discovery.is_ip_address?("10.0.0.1").should be_true
      RNS::Discovery.is_ip_address?("255.255.255.255").should be_true
      RNS::Discovery.is_ip_address?("0.0.0.0").should be_true
      RNS::Discovery.is_ip_address?("127.0.0.1").should be_true
    end

    it "recognizes valid IPv6 addresses" do
      RNS::Discovery.is_ip_address?("::1").should be_true
      RNS::Discovery.is_ip_address?("fe80::1").should be_true
      RNS::Discovery.is_ip_address?("2001:db8::1").should be_true
    end

    it "rejects invalid IP addresses" do
      RNS::Discovery.is_ip_address?("").should be_false
      RNS::Discovery.is_ip_address?("not-an-ip").should be_false
      RNS::Discovery.is_ip_address?("256.0.0.1").should be_false
      RNS::Discovery.is_ip_address?("example.com").should be_false
    end
  end

  describe ".is_hostname?" do
    it "recognizes valid hostnames" do
      RNS::Discovery.is_hostname?("example.com").should be_true
      RNS::Discovery.is_hostname?("sub.example.com").should be_true
      RNS::Discovery.is_hostname?("my-host.example.org").should be_true
      RNS::Discovery.is_hostname?("a.b.c.d.example.com").should be_true
    end

    it "allows trailing dot" do
      RNS::Discovery.is_hostname?("example.com.").should be_true
    end

    it "rejects empty strings" do
      RNS::Discovery.is_hostname?("").should be_false
    end

    it "rejects all-numeric TLDs" do
      RNS::Discovery.is_hostname?("example.123").should be_false
    end

    it "rejects hostnames exceeding 253 characters" do
      long_hostname = ("a" * 63 + ".") * 4 + "com"
      # This is 63*4 + 4 + 3 = 259 chars, which exceeds 253
      RNS::Discovery.is_hostname?(long_hostname).should be_false
    end

    it "rejects labels starting or ending with hyphens" do
      RNS::Discovery.is_hostname?("-example.com").should be_false
      RNS::Discovery.is_hostname?("example-.com").should be_false
    end

    it "rejects labels exceeding 63 characters" do
      long_label = "a" * 64 + ".com"
      RNS::Discovery.is_hostname?(long_label).should be_false
    end
  end

  # ─── InterfaceAnnouncer ─────────────────────────────────────────────

  describe RNS::Discovery::InterfaceAnnouncer do
    it "has correct constant values" do
      RNS::Discovery::InterfaceAnnouncer::JOB_INTERVAL.should eq(60)
      RNS::Discovery::InterfaceAnnouncer::DEFAULT_STAMP_VALUE.should eq(14)
      RNS::Discovery::InterfaceAnnouncer::WORKBLOCK_EXPAND_ROUNDS.should eq(20)
      RNS::Discovery::InterfaceAnnouncer::STAMP_SIZE.should eq(32)
    end

    it "defines discoverable interface types" do
      types = RNS::Discovery::InterfaceAnnouncer::DISCOVERABLE_INTERFACE_TYPES
      types.should contain("BackboneInterface")
      types.should contain("TCPServerInterface")
      types.should contain("TCPClientInterface")
      types.should contain("RNodeInterface")
      types.should contain("WeaveInterface")
      types.should contain("I2PInterface")
      types.should contain("KISSInterface")
      types.size.should eq(7)
    end

    describe "#sanitize" do
      it "strips newlines and whitespace" do
        # Create a minimal announcer for testing sanitize
        announcer = RNS::Discovery::InterfaceAnnouncer.new(RNS::Transport)
        announcer.sanitize("  hello\nworld\r  ").should eq("helloworld")
      end

      it "handles nil input" do
        announcer = RNS::Discovery::InterfaceAnnouncer.new(RNS::Transport)
        announcer.sanitize(nil).should eq("")
      end

      it "handles empty string" do
        announcer = RNS::Discovery::InterfaceAnnouncer.new(RNS::Transport)
        announcer.sanitize("").should eq("")
      end

      it "handles string with only whitespace" do
        announcer = RNS::Discovery::InterfaceAnnouncer.new(RNS::Transport)
        announcer.sanitize("   \n\r  ").should eq("")
      end
    end
  end

  # ─── InterfaceAnnounceHandler ───────────────────────────────────────

  describe RNS::Discovery::InterfaceAnnounceHandler do
    it "has correct flag constants" do
      RNS::Discovery::InterfaceAnnounceHandler::FLAG_SIGNED.should eq(0b00000001_u8)
      RNS::Discovery::InterfaceAnnounceHandler::FLAG_ENCRYPTED.should eq(0b00000010_u8)
    end

    it "has correct STAMP_SIZE" do
      RNS::Discovery::InterfaceAnnounceHandler::STAMP_SIZE.should eq(32)
    end

    it "has correct aspect_filter" do
      handler = RNS::Discovery::InterfaceAnnounceHandler.new
      handler.aspect_filter.should eq("rnstransport.discovery.interface")
    end

    it "initializes with default required_value" do
      handler = RNS::Discovery::InterfaceAnnounceHandler.new
      handler.required_value.should eq(RNS::Discovery::InterfaceAnnouncer::DEFAULT_STAMP_VALUE)
    end

    it "initializes with custom required_value" do
      handler = RNS::Discovery::InterfaceAnnounceHandler.new(required_value: 20)
      handler.required_value.should eq(20)
    end

    it "implements Transport::AnnounceHandler interface" do
      handler = RNS::Discovery::InterfaceAnnounceHandler.new
      handler.is_a?(RNS::Transport::AnnounceHandler).should be_true
    end

    describe "#received_announce" do
      it "ignores nil app_data" do
        handler = RNS::Discovery::InterfaceAnnounceHandler.new
        callback_called = false
        handler.callback = ->(info : Hash(String, String | Int64 | Float64 | Bool | Bytes | Nil)) { callback_called = true; nil }
        handler.received_announce(Bytes.new(16), nil, nil)
        callback_called.should be_false
      end

      it "ignores app_data shorter than STAMP_SIZE + 1" do
        handler = RNS::Discovery::InterfaceAnnounceHandler.new
        callback_called = false
        handler.callback = ->(info : Hash(String, String | Int64 | Float64 | Bool | Bytes | Nil)) { callback_called = true; nil }
        handler.received_announce(Bytes.new(16), nil, Bytes.new(10))
        callback_called.should be_false
      end

      it "processes valid announce data and calls callback" do
        received_info = nil
        handler = RNS::Discovery::InterfaceAnnounceHandler.new do |info|
          received_info = info
          nil
        end

        # Build a valid announce payload
        io = IO::Memory.new
        packer = MessagePack::Packer.new(io)
        packer.write_hash_start(4)
        packer.write(RNS::Discovery::INTERFACE_TYPE.to_u8)
        packer.write("BackboneInterface")
        packer.write(RNS::Discovery::TRANSPORT.to_u8)
        packer.write(true)
        packer.write(RNS::Discovery::NAME.to_u8)
        packer.write("Test Interface")
        packer.write(RNS::Discovery::TRANSPORT_ID.to_u8)
        packer.write(Bytes.new(16, 0xAB_u8))
        packed = io.to_slice.dup

        # Add a stamp (32 random bytes)
        stamp = Random::Secure.random_bytes(32)
        data_with_stamp = Bytes.new(packed.size + stamp.size)
        packed.copy_to(data_with_stamp)
        stamp.copy_to(data_with_stamp + packed.size)

        # Prepend flags byte (no encryption, no signing)
        app_data = Bytes.new(1 + data_with_stamp.size)
        app_data[0] = 0x00_u8
        data_with_stamp.copy_to(app_data + 1)

        identity = RNS::Identity.new
        handler.received_announce(Bytes.new(16), identity, app_data)

        received_info.should_not be_nil
        if info = received_info
          info["type"].should eq("BackboneInterface")
          info["name"].should eq("Test Interface")
          info["transport"].should eq(true)
          info.has_key?("discovery_hash").should be_true
          info.has_key?("config_entry").should be_true
        end
      end

      it "generates config_entry for BackboneInterface with reachable_on" do
        received_info = nil
        handler = RNS::Discovery::InterfaceAnnounceHandler.new do |info|
          received_info = info
          nil
        end

        io = IO::Memory.new
        packer = MessagePack::Packer.new(io)
        packer.write_hash_start(6)
        packer.write(RNS::Discovery::INTERFACE_TYPE.to_u8)
        packer.write("BackboneInterface")
        packer.write(RNS::Discovery::TRANSPORT.to_u8)
        packer.write(true)
        packer.write(RNS::Discovery::NAME.to_u8)
        packer.write("My Backbone")
        packer.write(RNS::Discovery::TRANSPORT_ID.to_u8)
        packer.write(Bytes.new(16, 0xCD_u8))
        packer.write(RNS::Discovery::REACHABLE_ON.to_u8)
        packer.write("192.168.1.100")
        packer.write(RNS::Discovery::PORT.to_u8)
        packer.write(4242_i64)
        packed = io.to_slice.dup

        stamp = Random::Secure.random_bytes(32)
        data_with_stamp = Bytes.new(packed.size + stamp.size)
        packed.copy_to(data_with_stamp)
        stamp.copy_to(data_with_stamp + packed.size)

        app_data = Bytes.new(1 + data_with_stamp.size)
        app_data[0] = 0x00_u8
        data_with_stamp.copy_to(app_data + 1)

        identity = RNS::Identity.new
        handler.received_announce(Bytes.new(16), identity, app_data)

        received_info.should_not be_nil
        if info = received_info
          config_entry = info["config_entry"].to_s
          config_entry.should contain("BackboneInterface")
          config_entry.should contain("192.168.1.100")
          config_entry.should contain("4242")
          info["reachable_on"].should eq("192.168.1.100")
          info["port"].should eq(4242_i64)
        end
      end

      it "generates config_entry for RNodeInterface with radio params" do
        received_info = nil
        handler = RNS::Discovery::InterfaceAnnounceHandler.new do |info|
          received_info = info
          nil
        end

        io = IO::Memory.new
        packer = MessagePack::Packer.new(io)
        packer.write_hash_start(8)
        packer.write(RNS::Discovery::INTERFACE_TYPE.to_u8)
        packer.write("RNodeInterface")
        packer.write(RNS::Discovery::TRANSPORT.to_u8)
        packer.write(true)
        packer.write(RNS::Discovery::NAME.to_u8)
        packer.write("LoRa Node")
        packer.write(RNS::Discovery::TRANSPORT_ID.to_u8)
        packer.write(Bytes.new(16, 0xEF_u8))
        packer.write(RNS::Discovery::FREQUENCY.to_u8)
        packer.write(868000000_i64)
        packer.write(RNS::Discovery::BANDWIDTH.to_u8)
        packer.write(125000_i64)
        packer.write(RNS::Discovery::SPREADINGFACTOR.to_u8)
        packer.write(7_i64)
        packer.write(RNS::Discovery::CODINGRATE.to_u8)
        packer.write(5_i64)
        packed = io.to_slice.dup

        stamp = Random::Secure.random_bytes(32)
        data_with_stamp = Bytes.new(packed.size + stamp.size)
        packed.copy_to(data_with_stamp)
        stamp.copy_to(data_with_stamp + packed.size)

        app_data = Bytes.new(1 + data_with_stamp.size)
        app_data[0] = 0x00_u8
        data_with_stamp.copy_to(app_data + 1)

        identity = RNS::Identity.new
        handler.received_announce(Bytes.new(16), identity, app_data)

        received_info.should_not be_nil
        if info = received_info
          info["type"].should eq("RNodeInterface")
          info["frequency"].should eq(868000000_i64)
          info["bandwidth"].should eq(125000_i64)
          info["sf"].should eq(7_i64)
          info["cr"].should eq(5_i64)
          config_entry = info["config_entry"].to_s
          config_entry.should contain("RNodeInterface")
          config_entry.should contain("868000000")
          config_entry.should contain("125000")
        end
      end

      it "generates discovery_hash from transport_id and name" do
        received_info = nil
        handler = RNS::Discovery::InterfaceAnnounceHandler.new do |info|
          received_info = info
          nil
        end

        io = IO::Memory.new
        packer = MessagePack::Packer.new(io)
        packer.write_hash_start(4)
        packer.write(RNS::Discovery::INTERFACE_TYPE.to_u8)
        packer.write("BackboneInterface")
        packer.write(RNS::Discovery::TRANSPORT.to_u8)
        packer.write(false)
        packer.write(RNS::Discovery::NAME.to_u8)
        packer.write("TestNode")
        packer.write(RNS::Discovery::TRANSPORT_ID.to_u8)
        packer.write(Bytes.new(16, 0x42_u8))
        packed = io.to_slice.dup

        stamp = Random::Secure.random_bytes(32)
        data_with_stamp = Bytes.new(packed.size + stamp.size)
        packed.copy_to(data_with_stamp)
        stamp.copy_to(data_with_stamp + packed.size)

        app_data = Bytes.new(1 + data_with_stamp.size)
        app_data[0] = 0x00_u8
        data_with_stamp.copy_to(app_data + 1)

        identity = RNS::Identity.new
        handler.received_announce(Bytes.new(16), identity, app_data)

        received_info.should_not be_nil
        if info = received_info
          dh = info["discovery_hash"]
          dh.should_not be_nil
          dh.to_s.size.should be > 0

          # Verify discovery_hash is deterministic: same transport_id + name = same hash
          transport_id_hex = RNS.hexrep(Bytes.new(16, 0x42_u8), delimit: false)
          expected_material = (transport_id_hex + "TestNode").encode("UTF-8")
          expected_hash = RNS::Identity.full_hash(expected_material)
          expected_hex = RNS.hexrep(expected_hash, delimit: false)
          dh.to_s.should eq(expected_hex)
        end
      end
    end
  end

  # ─── InterfaceDiscovery ─────────────────────────────────────────────

  describe RNS::Discovery::InterfaceDiscovery do
    it "has correct threshold constants" do
      RNS::Discovery::InterfaceDiscovery::THRESHOLD_UNKNOWN.should eq(24 * 60 * 60)
      RNS::Discovery::InterfaceDiscovery::THRESHOLD_STALE.should eq(3 * 24 * 60 * 60)
      RNS::Discovery::InterfaceDiscovery::THRESHOLD_REMOVE.should eq(7 * 24 * 60 * 60)
    end

    it "has correct status constants" do
      RNS::Discovery::InterfaceDiscovery::STATUS_STALE.should eq(0)
      RNS::Discovery::InterfaceDiscovery::STATUS_UNKNOWN.should eq(100)
      RNS::Discovery::InterfaceDiscovery::STATUS_AVAILABLE.should eq(1000)
    end

    it "has correct monitor constants" do
      RNS::Discovery::InterfaceDiscovery::MONITOR_INTERVAL.should eq(5)
      RNS::Discovery::InterfaceDiscovery::DETACH_THRESHOLD.should eq(12)
    end

    it "defines autoconnect types" do
      types = RNS::Discovery::InterfaceDiscovery::AUTOCONNECT_TYPES
      types.should contain("BackboneInterface")
      types.should contain("TCPServerInterface")
      types.size.should eq(2)
    end

    it "has correct STATUS_CODE_MAP" do
      map = RNS::Discovery::InterfaceDiscovery::STATUS_CODE_MAP
      map["available"].should eq(1000)
      map["unknown"].should eq(100)
      map["stale"].should eq(0)
    end

    describe "with temporary storage" do
      it "persists and retrieves discovered interface data" do
        # Create a temp directory for testing
        tmpdir = File.tempname("rns_discovery", "")
        Dir.mkdir_p(tmpdir)
        storage = File.join(tmpdir, "discovery", "interfaces")
        Dir.mkdir_p(storage)

        begin
          # Create a discovery instance without starting the listener
          # (we'll test persistence manually)
          discovery = RNS::Discovery::InterfaceDiscovery.new(discover_interfaces: false)
          discovery.storagepath = storage

          # Simulate discovering an interface
          info = RNS::Discovery::InterfaceDiscovery::InfoHash.new
          info["type"] = "BackboneInterface"
          info["transport"] = true
          info["name"] = "Test Interface"
          info["received"] = Time.utc.to_unix_f
          info["stamp"] = "abcd1234"
          info["value"] = 14_i64
          info["transport_id"] = "aabbccdd"
          info["network_id"] = ""
          info["hops"] = 1_i64
          info["latitude"] = nil
          info["longitude"] = nil
          info["height"] = nil
          info["reachable_on"] = "192.168.1.100"
          info["port"] = 4242_i64
          info["config_entry"] = "[[Test Interface]]\n  type = BackboneInterface"

          # Compute discovery_hash
          dh_material = ("aabbccdd" + "Test Interface").encode("UTF-8")
          dh = RNS::Identity.full_hash(dh_material)
          info["discovery_hash"] = RNS.hexrep(dh, delimit: false)

          # Call interface_discovered
          discovery.interface_discovered(info)

          # Verify the file was created
          filepath = File.join(storage, info["discovery_hash"].to_s)
          File.exists?(filepath).should be_true

          # List discovered interfaces
          interfaces = discovery.list_discovered_interfaces
          interfaces.size.should eq(1)
          interfaces[0]["name"].should eq("Test Interface")
          interfaces[0]["type"].should eq("BackboneInterface")
          interfaces[0]["status"].should eq("available")
          interfaces[0]["status_code"].should eq(1000_i64)
        ensure
          # Clean up
          FileUtils.rm_rf(tmpdir) if Dir.exists?(tmpdir)
        end
      end

      it "increments heard_count on subsequent discoveries" do
        tmpdir = File.tempname("rns_discovery", "")
        Dir.mkdir_p(tmpdir)
        storage = File.join(tmpdir, "discovery", "interfaces")
        Dir.mkdir_p(storage)

        begin
          discovery = RNS::Discovery::InterfaceDiscovery.new(discover_interfaces: false)
          discovery.storagepath = storage

          info = RNS::Discovery::InterfaceDiscovery::InfoHash.new
          info["type"] = "BackboneInterface"
          info["transport"] = true
          info["name"] = "Counter Test"
          info["received"] = Time.utc.to_unix_f
          info["stamp"] = "stamp123"
          info["value"] = 14_i64
          info["transport_id"] = "11223344"
          info["network_id"] = ""
          info["hops"] = 2_i64
          info["latitude"] = nil
          info["longitude"] = nil
          info["height"] = nil

          dh_material = ("11223344" + "Counter Test").encode("UTF-8")
          dh = RNS::Identity.full_hash(dh_material)
          info["discovery_hash"] = RNS.hexrep(dh, delimit: false)

          # First discovery
          discovery.interface_discovered(info)

          # Second discovery
          info["received"] = Time.utc.to_unix_f + 1.0
          discovery.interface_discovered(info)

          # Third discovery
          info["received"] = Time.utc.to_unix_f + 2.0
          discovery.interface_discovered(info)

          interfaces = discovery.list_discovered_interfaces
          interfaces.size.should eq(1)
          heard_count = interfaces[0]["heard_count"]
          heard_count.should eq(2_i64) # 0-based: first writes 0, second writes 1, third writes 2
        ensure
          FileUtils.rm_rf(tmpdir) if Dir.exists?(tmpdir)
        end
      end

      it "filters by only_available" do
        tmpdir = File.tempname("rns_discovery", "")
        Dir.mkdir_p(tmpdir)
        storage = File.join(tmpdir, "discovery", "interfaces")
        Dir.mkdir_p(storage)

        begin
          discovery = RNS::Discovery::InterfaceDiscovery.new(discover_interfaces: false)
          discovery.storagepath = storage

          # Create a recent (available) interface
          info_available = RNS::Discovery::InterfaceDiscovery::InfoHash.new
          info_available["type"] = "BackboneInterface"
          info_available["transport"] = true
          info_available["name"] = "Available"
          info_available["received"] = Time.utc.to_unix_f
          info_available["stamp"] = "stamp1"
          info_available["value"] = 14_i64
          info_available["transport_id"] = "aaaa"
          info_available["network_id"] = ""
          info_available["hops"] = 1_i64
          info_available["latitude"] = nil
          info_available["longitude"] = nil
          info_available["height"] = nil
          dh1 = RNS::Identity.full_hash(("aaaa" + "Available").encode("UTF-8"))
          info_available["discovery_hash"] = RNS.hexrep(dh1, delimit: false)

          discovery.interface_discovered(info_available)

          # Create an old (unknown) interface — manually write with old timestamp
          info_old = RNS::Discovery::InterfaceDiscovery::InfoHash.new
          info_old["type"] = "BackboneInterface"
          info_old["transport"] = true
          info_old["name"] = "Old One"
          info_old["received"] = Time.utc.to_unix_f - (25 * 60 * 60) # 25 hours ago
          info_old["stamp"] = "stamp2"
          info_old["value"] = 14_i64
          info_old["transport_id"] = "bbbb"
          info_old["network_id"] = ""
          info_old["hops"] = 3_i64
          info_old["latitude"] = nil
          info_old["longitude"] = nil
          info_old["height"] = nil
          info_old["discovered"] = info_old["received"]
          info_old["last_heard"] = info_old["received"]
          info_old["heard_count"] = 0_i64
          dh2 = RNS::Identity.full_hash(("bbbb" + "Old One").encode("UTF-8"))
          info_old["discovery_hash"] = RNS.hexrep(dh2, delimit: false)

          # Write directly to storage
          filepath = File.join(storage, info_old["discovery_hash"].to_s)
          io = IO::Memory.new
          packer = MessagePack::Packer.new(io)
          packer.write_hash_start(info_old.size)
          info_old.each do |key, value|
            packer.write(key)
            case value
            when Nil     then packer.write(nil)
            when Bool    then packer.write(value)
            when Int64   then packer.write(value)
            when Float64 then packer.write(value)
            when String  then packer.write(value)
            when Bytes   then packer.write(value)
            else              packer.write(value.to_s)
            end
          end
          File.write(filepath, io.to_slice)

          # List all: should have 2
          all = discovery.list_discovered_interfaces
          all.size.should eq(2)

          # List only available: should have 1
          available_only = discovery.list_discovered_interfaces(only_available: true)
          available_only.size.should eq(1)
          available_only[0]["name"].should eq("Available")
        ensure
          FileUtils.rm_rf(tmpdir) if Dir.exists?(tmpdir)
        end
      end

      it "removes entries older than THRESHOLD_REMOVE" do
        tmpdir = File.tempname("rns_discovery", "")
        Dir.mkdir_p(tmpdir)
        storage = File.join(tmpdir, "discovery", "interfaces")
        Dir.mkdir_p(storage)

        begin
          discovery = RNS::Discovery::InterfaceDiscovery.new(discover_interfaces: false)
          discovery.storagepath = storage

          # Create a very old entry (8 days old, beyond THRESHOLD_REMOVE of 7 days)
          info = RNS::Discovery::InterfaceDiscovery::InfoHash.new
          info["type"] = "BackboneInterface"
          info["transport"] = true
          info["name"] = "Ancient"
          info["received"] = Time.utc.to_unix_f - (8 * 24 * 60 * 60)
          info["stamp"] = "stampold"
          info["value"] = 14_i64
          info["transport_id"] = "cccc"
          info["network_id"] = ""
          info["hops"] = 1_i64
          info["latitude"] = nil
          info["longitude"] = nil
          info["height"] = nil
          info["discovered"] = info["received"]
          info["last_heard"] = info["received"]
          info["heard_count"] = 0_i64
          dh = RNS::Identity.full_hash(("cccc" + "Ancient").encode("UTF-8"))
          info["discovery_hash"] = RNS.hexrep(dh, delimit: false)

          filepath = File.join(storage, info["discovery_hash"].to_s)
          io = IO::Memory.new
          packer = MessagePack::Packer.new(io)
          packer.write_hash_start(info.size)
          info.each do |key, value|
            packer.write(key)
            case value
            when Nil     then packer.write(nil)
            when Bool    then packer.write(value)
            when Int64   then packer.write(value)
            when Float64 then packer.write(value)
            when String  then packer.write(value)
            when Bytes   then packer.write(value)
            else              packer.write(value.to_s)
            end
          end
          File.write(filepath, io.to_slice)

          File.exists?(filepath).should be_true

          # Listing should remove the old entry
          interfaces = discovery.list_discovered_interfaces
          interfaces.size.should eq(0)

          # File should be deleted
          File.exists?(filepath).should be_false
        ensure
          FileUtils.rm_rf(tmpdir) if Dir.exists?(tmpdir)
        end
      end

      it "sorts discovered interfaces by status_code, value, last_heard (descending)" do
        tmpdir = File.tempname("rns_discovery", "")
        Dir.mkdir_p(tmpdir)
        storage = File.join(tmpdir, "discovery", "interfaces")
        Dir.mkdir_p(storage)

        begin
          discovery = RNS::Discovery::InterfaceDiscovery.new(discover_interfaces: false)
          discovery.storagepath = storage

          now = Time.utc.to_unix_f

          # Write entries with different ages/values
          [
            {"name" => "Stale", "last_heard" => now - (4 * 24 * 60 * 60), "value" => 14_i64}, # stale
            {"name" => "Fresh", "last_heard" => now - 100.0, "value" => 14_i64},              # available
            {"name" => "Unknown", "last_heard" => now - (25 * 60 * 60), "value" => 20_i64},   # unknown
          ].each_with_index do |entry, idx|
            info = RNS::Discovery::InterfaceDiscovery::InfoHash.new
            info["type"] = "BackboneInterface"
            info["transport"] = true
            info["name"] = entry["name"]
            info["received"] = entry["last_heard"]
            info["stamp"] = "stamp#{idx}"
            info["value"] = entry["value"]
            info["transport_id"] = "id#{idx}"
            info["network_id"] = ""
            info["hops"] = 1_i64
            info["latitude"] = nil
            info["longitude"] = nil
            info["height"] = nil
            info["discovered"] = entry["last_heard"]
            info["last_heard"] = entry["last_heard"]
            info["heard_count"] = 0_i64
            dh = RNS::Identity.full_hash(("id#{idx}" + entry["name"].to_s).encode("UTF-8"))
            info["discovery_hash"] = RNS.hexrep(dh, delimit: false)

            filepath = File.join(storage, info["discovery_hash"].to_s)
            io = IO::Memory.new
            packer = MessagePack::Packer.new(io)
            packer.write_hash_start(info.size)
            info.each do |key, value|
              packer.write(key)
              case value
              when Nil     then packer.write(nil)
              when Bool    then packer.write(value)
              when Int64   then packer.write(value)
              when Float64 then packer.write(value)
              when String  then packer.write(value)
              when Bytes   then packer.write(value)
              else              packer.write(value.to_s)
              end
            end
            File.write(filepath, io.to_slice)
          end

          interfaces = discovery.list_discovered_interfaces
          interfaces.size.should eq(3)

          # Available (status 1000) should be first
          interfaces[0]["name"].should eq("Fresh")
          interfaces[0]["status"].should eq("available")

          # Unknown (status 100) should be second
          interfaces[1]["name"].should eq("Unknown")
          interfaces[1]["status"].should eq("unknown")

          # Stale (status 0) should be last
          interfaces[2]["name"].should eq("Stale")
          interfaces[2]["status"].should eq("stale")
        ensure
          FileUtils.rm_rf(tmpdir) if Dir.exists?(tmpdir)
        end
      end

      it "computes endpoint_hash deterministically" do
        discovery = RNS::Discovery::InterfaceDiscovery.new(discover_interfaces: false)

        info = RNS::Discovery::InterfaceDiscovery::InfoHash.new
        info["reachable_on"] = "192.168.1.1"
        info["port"] = 4242_i64

        hash1 = discovery.endpoint_hash(info)
        hash2 = discovery.endpoint_hash(info)
        hash1.should eq(hash2)

        # Verify it's based on the specifier string
        expected = RNS::Identity.full_hash("192.168.1.1:4242".encode("UTF-8"))
        hash1.should eq(expected)
      end

      it "computes endpoint_hash without port" do
        discovery = RNS::Discovery::InterfaceDiscovery.new(discover_interfaces: false)

        info = RNS::Discovery::InterfaceDiscovery::InfoHash.new
        info["reachable_on"] = "10.0.0.1"

        hash = discovery.endpoint_hash(info)
        expected = RNS::Identity.full_hash("10.0.0.1".encode("UTF-8"))
        hash.should eq(expected)
      end
    end
  end

  # ─── BlackholeUpdater ──────────────────────────────────────────────

  describe RNS::Discovery::BlackholeUpdater do
    it "has correct constants" do
      RNS::Discovery::BlackholeUpdater::INITIAL_WAIT.should eq(20)
      RNS::Discovery::BlackholeUpdater::JOB_INTERVAL.should eq(60)
      RNS::Discovery::BlackholeUpdater::UPDATE_INTERVAL.should eq(3600)
      RNS::Discovery::BlackholeUpdater::SOURCE_TIMEOUT.should eq(25)
    end

    it "initializes with correct defaults" do
      updater = RNS::Discovery::BlackholeUpdater.new
      updater.should_run.should be_false
      updater.job_interval.should eq(60)
      updater.last_updates.should be_empty
    end

    it "can start and stop" do
      updater = RNS::Discovery::BlackholeUpdater.new
      updater.should_run.should be_false
      # Note: start() will spawn a fiber but won't do anything without blackhole_sources
      # We just verify the state management
      updater.stop
      updater.should_run.should be_false
    end
  end

  # ─── Interface base class autoconnect properties ────────────────────

  describe "Interface autoconnect properties" do
    it "has autoconnect_hash property" do
      # Use a concrete interface for testing
      config = {"name" => "test", "listen_ip" => "0.0.0.0", "listen_port" => "0", "forward_ip" => "127.0.0.1", "forward_port" => "0"}
      interface = RNS::UDPInterface.new(config)
      interface.autoconnect_hash.should be_nil
      interface.autoconnect_hash = Bytes.new(32, 0xAA_u8)
      interface.autoconnect_hash.should eq(Bytes.new(32, 0xAA_u8))
    end

    it "has autoconnect_source property" do
      config = {"name" => "test", "listen_ip" => "0.0.0.0", "listen_port" => "0", "forward_ip" => "127.0.0.1", "forward_port" => "0"}
      interface = RNS::UDPInterface.new(config)
      interface.autoconnect_source.should be_nil
      interface.autoconnect_source = "abc123"
      interface.autoconnect_source.should eq("abc123")
    end

    it "has autoconnect_down property" do
      config = {"name" => "test", "listen_ip" => "0.0.0.0", "listen_port" => "0", "forward_ip" => "127.0.0.1", "forward_port" => "0"}
      interface = RNS::UDPInterface.new(config)
      interface.autoconnect_down.should be_nil
      interface.autoconnect_down = Time.utc.to_unix_f
      interface.autoconnect_down.should_not be_nil
    end

    it "has discovery_channel property" do
      config = {"name" => "test", "listen_ip" => "0.0.0.0", "listen_port" => "0", "forward_ip" => "127.0.0.1", "forward_port" => "0"}
      interface = RNS::UDPInterface.new(config)
      interface.discovery_channel.should be_nil
      interface.discovery_channel = 42
      interface.discovery_channel.should eq(42)
    end
  end
end

require "file_utils"
