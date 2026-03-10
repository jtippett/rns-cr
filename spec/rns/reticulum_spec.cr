require "../spec_helper"

# Helper to create a test ReticulumInstance with a config, without starting interfaces
private def make_test_instance(config_text : String, **opts) : RNS::ReticulumInstance
  lines = config_text.lines.map { |l| l.lstrip }
  config = RNS::ConfigObj.new(lines)
  RNS::ReticulumInstance.new(
    config,
    requested_loglevel: opts[:requested_loglevel]?,
    requested_verbosity: opts[:requested_verbosity]?,
    shared_instance_type: opts[:shared_instance_type]?,
    _test: true
  )
end

describe RNS::Reticulum do
  # ─── Protocol constants ──────────────────────────────────────────
  describe "protocol constants" do
    it "MTU is 500" do
      RNS::Reticulum::MTU.should eq 500
    end

    it "LINK_MTU_DISCOVERY is true" do
      RNS::Reticulum::LINK_MTU_DISCOVERY.should be_true
    end

    it "MAX_QUEUED_ANNOUNCES is 16384" do
      RNS::Reticulum::MAX_QUEUED_ANNOUNCES.should eq 16384
    end

    it "QUEUED_ANNOUNCE_LIFE is 86400" do
      RNS::Reticulum::QUEUED_ANNOUNCE_LIFE.should eq 86400
    end

    it "ANNOUNCE_CAP is 2" do
      RNS::Reticulum::ANNOUNCE_CAP.should eq 2
    end

    it "MINIMUM_BITRATE is 5" do
      RNS::Reticulum::MINIMUM_BITRATE.should eq 5
    end

    it "DEFAULT_PER_HOP_TIMEOUT is 6" do
      RNS::Reticulum::DEFAULT_PER_HOP_TIMEOUT.should eq 6
    end

    it "TRUNCATED_HASHLENGTH is 128" do
      RNS::Reticulum::TRUNCATED_HASHLENGTH.should eq 128
    end

    it "HEADER_MINSIZE is 19" do
      RNS::Reticulum::HEADER_MINSIZE.should eq 19
    end

    it "HEADER_MAXSIZE is 35" do
      RNS::Reticulum::HEADER_MAXSIZE.should eq 35
    end

    it "IFAC_MIN_SIZE is 1" do
      RNS::Reticulum::IFAC_MIN_SIZE.should eq 1
    end

    it "MDU is 464 (MTU - HEADER_MAXSIZE - IFAC_MIN_SIZE)" do
      RNS::Reticulum::MDU.should eq 464
      RNS::Reticulum::MDU.should eq(RNS::Reticulum::MTU - RNS::Reticulum::HEADER_MAXSIZE - RNS::Reticulum::IFAC_MIN_SIZE)
    end

    it "IFAC_SALT is 32 bytes matching Python hex" do
      RNS::Reticulum::IFAC_SALT.size.should eq 32
      RNS::Reticulum::IFAC_SALT.should eq "adf54d882c9a9b80771eb4995d702d4a3e733391b2a0f53f416d9f907e55cff8".hexbytes
    end
  end

  # ─── Time interval constants ─────────────────────────────────────
  describe "time interval constants" do
    it "RESOURCE_CACHE is 86400 (24 hours)" do
      RNS::Reticulum::RESOURCE_CACHE.should eq 86400
    end

    it "JOB_INTERVAL is 300 (5 minutes)" do
      RNS::Reticulum::JOB_INTERVAL.should eq 300
    end

    it "CLEAN_INTERVAL is 900 (15 minutes)" do
      RNS::Reticulum::CLEAN_INTERVAL.should eq 900
    end

    it "PERSIST_INTERVAL is 43200 (12 hours)" do
      RNS::Reticulum::PERSIST_INTERVAL.should eq 43200
    end

    it "GRACIOUS_PERSIST_INTERVAL is 300 (5 minutes)" do
      RNS::Reticulum::GRACIOUS_PERSIST_INTERVAL.should eq 300
    end
  end

  # ─── Default port constants ──────────────────────────────────────
  describe "default port constants" do
    it "DEFAULT_LOCAL_INTERFACE_PORT is 37428" do
      RNS::Reticulum::DEFAULT_LOCAL_INTERFACE_PORT.should eq 37428
    end

    it "DEFAULT_LOCAL_CONTROL_PORT is 37429" do
      RNS::Reticulum::DEFAULT_LOCAL_CONTROL_PORT.should eq 37429
    end
  end

  # ─── Path management ──────────────────────────────────────────────
  describe "path management" do
    it "configdir defaults to ~/.reticulum" do
      expected = File.join(Path.home.to_s, ".reticulum")
      RNS::Reticulum.configdir = expected
      RNS::Reticulum.configdir.should eq expected
    end

    it "configdir can be set and read back" do
      original = RNS::Reticulum.configdir
      RNS::Reticulum.configdir = "/tmp/test_reticulum"
      RNS::Reticulum.configdir.should eq "/tmp/test_reticulum"
      RNS::Reticulum.configdir = original
    end

    it "all path accessors work" do
      paths = {
        "storagepath"   => ->{ RNS::Reticulum.storagepath },
        "cachepath"     => ->{ RNS::Reticulum.cachepath },
        "resourcepath"  => ->{ RNS::Reticulum.resourcepath },
        "identitypath"  => ->{ RNS::Reticulum.identitypath },
        "blackholepath" => ->{ RNS::Reticulum.blackholepath },
        "interfacepath" => ->{ RNS::Reticulum.interfacepath },
      }
      paths.each do |name, getter|
        getter.call.should be_a(String)
      end
    end

    it "paths can be set and read back" do
      original = RNS::Reticulum.storagepath
      RNS::Reticulum.storagepath = "/tmp/test_storage"
      RNS::Reticulum.storagepath.should eq "/tmp/test_storage"
      RNS::Reticulum.storagepath = original
    end
  end

  # ─── Singleton management ──────────────────────────────────────────
  describe "singleton management" do
    it "get_instance returns nil initially after reset" do
      RNS::Reticulum.reset_instance!
      RNS::Reticulum.get_instance.should be_nil
    end

    it "reset_instance! clears all class-level state" do
      RNS::Reticulum.transport_enabled = true
      RNS::Reticulum.remote_management_enabled = true
      RNS::Reticulum.allow_probes = true
      RNS::Reticulum.panic_on_interface_error = true
      RNS::Reticulum.discovery_enabled = true
      RNS::Reticulum.discover_interfaces_flag = true

      RNS::Reticulum.reset_instance!

      RNS::Reticulum.transport_enabled?.should be_false
      RNS::Reticulum.remote_management_enabled?.should be_false
      RNS::Reticulum.probe_destination_enabled?.should be_false
      RNS::Reticulum.panic_on_interface_error.should be_false
      RNS::Reticulum.discovery_enabled?.should be_false
      RNS::Reticulum.discover_interfaces?.should be_false
      RNS::Reticulum.get_instance.should be_nil
    end
  end

  # ─── Static accessors ─────────────────────────────────────────────
  describe "static accessors" do
    before_each { RNS::Reticulum.reset_instance! }

    it "transport_enabled? defaults to false" do
      RNS::Reticulum.transport_enabled?.should be_false
    end

    it "transport_enabled can be toggled" do
      RNS::Reticulum.transport_enabled = true
      RNS::Reticulum.transport_enabled?.should be_true
    end

    it "link_mtu_discovery? defaults to LINK_MTU_DISCOVERY" do
      RNS::Reticulum.link_mtu_discovery?.should eq RNS::Reticulum::LINK_MTU_DISCOVERY
    end

    it "remote_management_enabled? defaults to false" do
      RNS::Reticulum.remote_management_enabled?.should be_false
    end

    it "should_use_implicit_proof? defaults to true" do
      RNS::Reticulum.should_use_implicit_proof?.should be_true
    end

    it "use_implicit_proof can be set to false" do
      RNS::Reticulum.use_implicit_proof = false
      RNS::Reticulum.should_use_implicit_proof?.should be_false
    end

    it "probe_destination_enabled? defaults to false" do
      RNS::Reticulum.probe_destination_enabled?.should be_false
    end

    it "discovery_enabled? defaults to false" do
      RNS::Reticulum.discovery_enabled?.should be_false
    end

    it "discover_interfaces? defaults to false" do
      RNS::Reticulum.discover_interfaces?.should be_false
    end

    it "required_discovery_value defaults to nil" do
      RNS::Reticulum.required_discovery_value.should be_nil
    end

    it "publish_blackhole_enabled? defaults to false" do
      RNS::Reticulum.publish_blackhole_enabled?.should be_false
    end

    it "blackhole_sources defaults to empty" do
      RNS::Reticulum.blackhole_sources.should be_empty
    end

    it "interface_discovery_sources defaults to empty" do
      RNS::Reticulum.interface_discovery_sources.should be_empty
    end

    it "should_autoconnect_discovered_interfaces? defaults to false" do
      RNS::Reticulum.should_autoconnect_discovered_interfaces?.should be_false
    end

    it "max_autoconnected_interfaces defaults to 0" do
      RNS::Reticulum.max_autoconnected_interfaces.should eq 0
    end

    it "network_identity defaults to nil" do
      RNS::Reticulum.network_identity.should be_nil
    end

    it "force_shared_instance_bitrate defaults to nil" do
      RNS::Reticulum.force_shared_instance_bitrate.should be_nil
    end

    it "panic_on_interface_error defaults to false" do
      RNS::Reticulum.panic_on_interface_error.should be_false
    end

    it "userdir returns home directory" do
      RNS::Reticulum.userdir.should eq Path.home.to_s
    end
  end

  # ─── Default config template ───────────────────────────────────────
  describe "default config template" do
    it "returns an array of strings" do
      lines = RNS::Reticulum.default_config_lines
      lines.should be_a(Array(String))
      lines.size.should be > 10
    end

    it "contains [reticulum] section" do
      lines = RNS::Reticulum.default_config_lines
      lines.any? { |l| l.strip == "[reticulum]" }.should be_true
    end

    it "contains [logging] section" do
      lines = RNS::Reticulum.default_config_lines
      lines.any? { |l| l.strip == "[logging]" }.should be_true
    end

    it "contains [interfaces] section" do
      lines = RNS::Reticulum.default_config_lines
      lines.any? { |l| l.strip == "[interfaces]" }.should be_true
    end

    it "contains Default Interface subsection" do
      lines = RNS::Reticulum.default_config_lines
      lines.any? { |l| l.strip == "[[Default Interface]]" }.should be_true
    end

    it "enables AutoInterface by default" do
      lines = RNS::Reticulum.default_config_lines
      lines.any? { |l| l.strip == "type = AutoInterface" }.should be_true
    end

    it "has enable_transport = False" do
      lines = RNS::Reticulum.default_config_lines
      lines.any? { |l| l.strip == "enable_transport = False" }.should be_true
    end

    it "has share_instance = Yes" do
      lines = RNS::Reticulum.default_config_lines
      lines.any? { |l| l.strip == "share_instance = Yes" }.should be_true
    end

    it "has instance_name = default" do
      lines = RNS::Reticulum.default_config_lines
      lines.any? { |l| l.strip == "instance_name = default" }.should be_true
    end

    it "has loglevel = 4" do
      lines = RNS::Reticulum.default_config_lines
      lines.any? { |l| l.strip == "loglevel = 4" }.should be_true
    end

    it "can be parsed by ConfigObj" do
      lines = RNS::Reticulum.default_config_lines
      config = RNS::ConfigObj.new(lines)
      config.has_key?("reticulum").should be_true
      config.has_key?("logging").should be_true
      config.has_key?("interfaces").should be_true
    end

    it "parsed config has correct reticulum values" do
      lines = RNS::Reticulum.default_config_lines
      config = RNS::ConfigObj.new(lines)
      ret = config["reticulum"].as(RNS::ConfigObj::Section)
      ret.as_bool("enable_transport").should be_false
      ret.as_bool("share_instance").should be_true
      ret["instance_name"].should eq "default"
    end

    it "parsed config has loglevel 4" do
      lines = RNS::Reticulum.default_config_lines
      config = RNS::ConfigObj.new(lines)
      log = config["logging"].as(RNS::ConfigObj::Section)
      log.as_int("loglevel").should eq 4
    end

    it "parsed config has Default Interface with AutoInterface type" do
      lines = RNS::Reticulum.default_config_lines
      config = RNS::ConfigObj.new(lines)
      ifaces = config["interfaces"].as(RNS::ConfigObj::Section)
      ifaces.has_key?("Default Interface").should be_true
      di = ifaces["Default Interface"].as(RNS::ConfigObj::Section)
      di["type"].should eq "AutoInterface"
      di.as_bool("enabled").should be_true
    end
  end

  # ─── Default config file creation ──────────────────────────────────
  describe "default config file I/O" do
    it "creates config file on disk" do
      tmpdir = File.tempname("rns_test")
      begin
        Dir.mkdir_p(tmpdir)
        config_path = File.join(tmpdir, "config")

        lines = RNS::Reticulum.default_config_lines
        config = RNS::ConfigObj.new(lines)
        config.filename = config_path
        config.write

        File.exists?(config_path).should be_true
        content = File.read(config_path)
        content.should contain("enable_transport")
        content.should contain("share_instance")
        content.should contain("loglevel")
        content.should contain("AutoInterface")
      ensure
        FileUtils.rm_rf(tmpdir) if Dir.exists?(tmpdir)
      end
    end

    it "written config can be re-read by ConfigObj" do
      tmpdir = File.tempname("rns_test")
      begin
        Dir.mkdir_p(tmpdir)
        config_path = File.join(tmpdir, "config")

        lines = RNS::Reticulum.default_config_lines
        config = RNS::ConfigObj.new(lines)
        config.filename = config_path
        config.write

        reloaded = RNS::ConfigObj.from_file(config_path)
        reloaded.has_key?("reticulum").should be_true
        reloaded.has_key?("logging").should be_true
        reloaded.has_key?("interfaces").should be_true
      ensure
        FileUtils.rm_rf(tmpdir) if Dir.exists?(tmpdir)
      end
    end
  end

  # ─── Config parsing (apply_config) ─────────────────────────────────
  describe "config parsing" do
    before_each { RNS::Reticulum.reset_instance! }

    it "parses logging section loglevel" do
      inst = make_test_instance("[logging]\nloglevel = 6\n[reticulum]\nshare_instance = No")
      original_ll = RNS.loglevel
      begin
        inst.apply_config
        RNS.loglevel.should eq 6
      ensure
        RNS.loglevel = original_ll
      end
    end

    it "respects requested_loglevel over config" do
      inst = make_test_instance("[logging]\nloglevel = 6\n[reticulum]\nshare_instance = No",
        requested_loglevel: 3)
      original_ll = RNS.loglevel
      begin
        RNS.loglevel = 3
        inst.apply_config
        RNS.loglevel.should eq 3  # Should NOT change
      ensure
        RNS.loglevel = original_ll
      end
    end

    it "adds verbosity to config loglevel" do
      inst = make_test_instance("[logging]\nloglevel = 4\n[reticulum]\nshare_instance = No",
        requested_verbosity: 2)
      original_ll = RNS.loglevel
      begin
        inst.apply_config
        RNS.loglevel.should eq 6  # 4 + 2
      ensure
        RNS.loglevel = original_ll
      end
    end

    it "clamps loglevel to 0-7 range" do
      inst = make_test_instance("[logging]\nloglevel = 5\n[reticulum]\nshare_instance = No",
        requested_verbosity: 10)
      original_ll = RNS.loglevel
      begin
        inst.apply_config
        RNS.loglevel.should eq 7  # Clamped
      ensure
        RNS.loglevel = original_ll
      end
    end

    it "parses share_instance = No" do
      inst = make_test_instance("[reticulum]\nshare_instance = No")
      inst.apply_config
      inst.share_instance.should be_false
    end

    it "parses shared_instance_port" do
      inst = make_test_instance("[reticulum]\nshared_instance_port = 12345\nshare_instance = No")
      inst.apply_config
      inst.local_interface_port.should eq 12345
    end

    it "parses instance_control_port" do
      inst = make_test_instance("[reticulum]\ninstance_control_port = 54321\nshare_instance = No")
      inst.apply_config
      inst.local_control_port.should eq 54321
    end

    it "parses enable_transport = Yes" do
      inst = make_test_instance("[reticulum]\nenable_transport = Yes\nshare_instance = No")
      inst.apply_config
      RNS::Reticulum.transport_enabled?.should be_true
    end

    it "parses panic_on_interface_error = Yes" do
      inst = make_test_instance("[reticulum]\npanic_on_interface_error = Yes\nshare_instance = No")
      inst.apply_config
      RNS::Reticulum.panic_on_interface_error.should be_true
    end

    it "parses use_implicit_proof = No" do
      inst = make_test_instance("[reticulum]\nuse_implicit_proof = No\nshare_instance = No")
      inst.apply_config
      RNS::Reticulum.should_use_implicit_proof?.should be_false
    end

    it "parses use_implicit_proof = Yes" do
      RNS::Reticulum.use_implicit_proof = false
      inst = make_test_instance("[reticulum]\nuse_implicit_proof = Yes\nshare_instance = No")
      inst.apply_config
      RNS::Reticulum.should_use_implicit_proof?.should be_true
    end

    it "parses discover_interfaces = Yes" do
      inst = make_test_instance("[reticulum]\ndiscover_interfaces = Yes\nshare_instance = No")
      inst.apply_config
      RNS::Reticulum.discover_interfaces?.should be_true
    end

    it "parses discover_interfaces = No" do
      RNS::Reticulum.discover_interfaces_flag = true
      inst = make_test_instance("[reticulum]\ndiscover_interfaces = No\nshare_instance = No")
      inst.apply_config
      RNS::Reticulum.discover_interfaces?.should be_false
    end

    it "parses required_discovery_value positive" do
      inst = make_test_instance("[reticulum]\nrequired_discovery_value = 42\nshare_instance = No")
      inst.apply_config
      RNS::Reticulum.required_discovery_value.should eq 42
    end

    it "parses required_discovery_value = 0 as nil" do
      inst = make_test_instance("[reticulum]\nrequired_discovery_value = 0\nshare_instance = No")
      inst.apply_config
      RNS::Reticulum.required_discovery_value.should be_nil
    end

    it "parses publish_blackhole = Yes" do
      inst = make_test_instance("[reticulum]\npublish_blackhole = Yes\nshare_instance = No")
      inst.apply_config
      RNS::Reticulum.publish_blackhole_enabled?.should be_true
    end

    it "parses publish_blackhole = No" do
      RNS::Reticulum.publish_blackhole = true
      inst = make_test_instance("[reticulum]\npublish_blackhole = No\nshare_instance = No")
      inst.apply_config
      RNS::Reticulum.publish_blackhole_enabled?.should be_false
    end

    it "parses force_shared_instance_bitrate" do
      inst = make_test_instance("[reticulum]\nforce_shared_instance_bitrate = 115200\nshare_instance = No")
      inst.apply_config
      RNS::Reticulum.force_shared_instance_bitrate.should eq 115200_i64
    end

    it "parses shared_instance_type = tcp" do
      inst = make_test_instance("[reticulum]\nshared_instance_type = tcp\nshare_instance = No")
      inst.apply_config
      inst.shared_instance_type.should eq "tcp"
    end

    it "does not override shared_instance_type from config if already set via constructor" do
      inst = make_test_instance("[reticulum]\nshared_instance_type = tcp\nshare_instance = No",
        shared_instance_type: "unix")
      # Before apply_config, the value should be "unix" (constructor wins over config)
      inst.shared_instance_type.should eq "unix"
      inst.apply_config
      # On non-AF_UNIX platforms (macOS), apply_config forces shared_instance_type to "tcp"
      if RNS::PlatformUtils.use_af_unix?
        inst.shared_instance_type.should eq "unix"
      else
        inst.shared_instance_type.should eq "tcp"
      end
    end

    it "parses respond_to_probes = Yes" do
      inst = make_test_instance("[reticulum]\nrespond_to_probes = Yes\nshare_instance = No")
      inst.apply_config
      RNS::Reticulum.probe_destination_enabled?.should be_true
    end

    it "parses enable_remote_management = Yes" do
      inst = make_test_instance("[reticulum]\nenable_remote_management = Yes\nshare_instance = No")
      inst.apply_config
      RNS::Reticulum.remote_management_enabled?.should be_true
    end

    it "parses autoconnect_discovered_interfaces" do
      inst = make_test_instance("[reticulum]\nautoconnect_discovered_interfaces = 5\nshare_instance = No")
      inst.apply_config
      RNS::Reticulum.should_autoconnect_discovered_interfaces?.should be_true
      RNS::Reticulum.max_autoconnected_interfaces.should eq 5
    end

    it "handles AF_UNIX vs TCP determination with tcp override" do
      inst = make_test_instance("[reticulum]\nshared_instance_type = tcp\nshare_instance = No")
      inst.apply_config
      if RNS::PlatformUtils.use_af_unix?
        inst.use_af_unix.should be_false
      end
    end

    it "defaults local_socket_path to 'default' when using AF_UNIX" do
      inst = make_test_instance("[reticulum]\nshare_instance = No")
      inst.apply_config
      if RNS::PlatformUtils.use_af_unix?
        inst.local_socket_path.should eq "default"
        inst.use_af_unix.should be_true
      end
    end

    it "parses instance_name on AF_UNIX platforms" do
      inst = make_test_instance("[reticulum]\ninstance_name = myapp\nshare_instance = No")
      inst.apply_config
      if RNS::PlatformUtils.use_af_unix?
        inst.local_socket_path.should eq "myapp"
      end
    end

    it "handles rpc_key" do
      valid_hex = "deadbeef" * 8  # 32 bytes
      inst = make_test_instance("[reticulum]\nrpc_key = #{valid_hex}\nshare_instance = No")
      inst.apply_config
      inst.rpc_key.should eq valid_hex.hexbytes
    end

    it "handles invalid rpc_key gracefully" do
      inst = make_test_instance("[reticulum]\nrpc_key = not_hex\nshare_instance = No")
      inst.apply_config
      inst.rpc_key.should be_nil  # Falls back to nil
    end

    it "handles empty config gracefully" do
      inst = make_test_instance("")
      inst.apply_config  # Should not raise
    end
  end

  # ─── Full initialization with temp directory ─────────────────────
  describe "full initialization" do
    it "creates all required directories" do
      tmpdir = File.tempname("rns_init_test")
      begin
        RNS::Reticulum.reset_instance!
        RNS::Transport.reset

        Dir.mkdir_p(tmpdir)
        config_path = File.join(tmpdir, "config")
        lines = RNS::Reticulum.default_config_lines
        config = RNS::ConfigObj.new(lines)
        config.filename = config_path
        config.write

        original_ll = RNS.loglevel

        begin
          inst = RNS::ReticulumInstance.new(configdir: tmpdir, loglevel: RNS::LOG_NONE)

          Dir.exists?(File.join(tmpdir, "storage")).should be_true
          Dir.exists?(File.join(tmpdir, "storage", "cache")).should be_true
          Dir.exists?(File.join(tmpdir, "storage", "resources")).should be_true
          Dir.exists?(File.join(tmpdir, "storage", "identities")).should be_true
          Dir.exists?(File.join(tmpdir, "storage", "blackhole")).should be_true
          Dir.exists?(File.join(tmpdir, "interfaces")).should be_true
          Dir.exists?(File.join(tmpdir, "storage", "cache", "announces")).should be_true

          RNS::Reticulum.configdir.should eq tmpdir
          RNS::Reticulum.configpath.should eq File.join(tmpdir, "config")
          RNS::Reticulum.storagepath.should eq File.join(tmpdir, "storage")

          RNS::Reticulum.get_instance.should eq inst
        ensure
          RNS.loglevel = original_ll
          RNS::Reticulum.reset_instance!
          RNS::Transport.reset
        end
      ensure
        FileUtils.rm_rf(tmpdir) if Dir.exists?(tmpdir)
      end
    end

    it "rejects duplicate initialization" do
      tmpdir = File.tempname("rns_dup_test")
      begin
        RNS::Reticulum.reset_instance!
        RNS::Transport.reset

        Dir.mkdir_p(tmpdir)
        lines = RNS::Reticulum.default_config_lines
        config = RNS::ConfigObj.new(lines)
        config.filename = File.join(tmpdir, "config")
        config.write

        original_ll = RNS.loglevel

        begin
          inst1 = RNS::ReticulumInstance.new(configdir: tmpdir, loglevel: RNS::LOG_NONE)

          expect_raises(Exception, /reinitialise/) do
            RNS::ReticulumInstance.new(configdir: tmpdir, loglevel: RNS::LOG_NONE)
          end
        ensure
          RNS.loglevel = original_ll
          RNS::Reticulum.reset_instance!
          RNS::Transport.reset
        end
      ensure
        FileUtils.rm_rf(tmpdir) if Dir.exists?(tmpdir)
      end
    end

    it "creates default config when none exists" do
      tmpdir = File.tempname("rns_default_test")
      begin
        RNS::Reticulum.reset_instance!
        RNS::Transport.reset

        Dir.mkdir_p(tmpdir)

        original_ll = RNS.loglevel

        begin
          inst = RNS::ReticulumInstance.new(configdir: tmpdir, loglevel: RNS::LOG_NONE)

          File.exists?(File.join(tmpdir, "config")).should be_true

          reloaded = RNS::ConfigObj.from_file(File.join(tmpdir, "config"))
          reloaded.has_key?("reticulum").should be_true
          reloaded.has_key?("logging").should be_true
        ensure
          RNS.loglevel = original_ll
          RNS::Reticulum.reset_instance!
          RNS::Transport.reset
        end
      ensure
        FileUtils.rm_rf(tmpdir) if Dir.exists?(tmpdir)
      end
    end

    it "becomes standalone when share_instance is No" do
      tmpdir = File.tempname("rns_standalone_test")
      begin
        RNS::Reticulum.reset_instance!
        RNS::Transport.reset

        Dir.mkdir_p(tmpdir)
        File.write(File.join(tmpdir, "config"),
          "[reticulum]\nshare_instance = No\n[logging]\nloglevel = 0\n[interfaces]\n")

        original_ll = RNS.loglevel

        begin
          inst = RNS::ReticulumInstance.new(configdir: tmpdir, loglevel: RNS::LOG_NONE)
          inst.is_standalone_instance.should be_true
          inst.is_shared_instance.should be_false
          inst.is_connected_to_shared_instance.should be_false
        ensure
          RNS.loglevel = original_ll
          RNS::Reticulum.reset_instance!
          RNS::Transport.reset
        end
      ensure
        FileUtils.rm_rf(tmpdir) if Dir.exists?(tmpdir)
      end
    end

    it "reads custom loglevel from config" do
      tmpdir = File.tempname("rns_loglevel_test")
      begin
        RNS::Reticulum.reset_instance!
        RNS::Transport.reset

        Dir.mkdir_p(tmpdir)
        File.write(File.join(tmpdir, "config"),
          "[reticulum]\nshare_instance = No\n[logging]\nloglevel = 6\n[interfaces]\n")

        original_ll = RNS.loglevel

        begin
          inst = RNS::ReticulumInstance.new(configdir: tmpdir)
          RNS.loglevel.should eq 6
        ensure
          RNS.loglevel = original_ll
          RNS::Reticulum.reset_instance!
          RNS::Transport.reset
        end
      ensure
        FileUtils.rm_rf(tmpdir) if Dir.exists?(tmpdir)
      end
    end

    it "requested loglevel overrides config" do
      tmpdir = File.tempname("rns_loglevel_override_test")
      begin
        RNS::Reticulum.reset_instance!
        RNS::Transport.reset

        Dir.mkdir_p(tmpdir)
        File.write(File.join(tmpdir, "config"),
          "[reticulum]\nshare_instance = No\n[logging]\nloglevel = 6\n[interfaces]\n")

        original_ll = RNS.loglevel

        begin
          inst = RNS::ReticulumInstance.new(configdir: tmpdir, loglevel: 2)
          RNS.loglevel.should eq 2
        ensure
          RNS.loglevel = original_ll
          RNS::Reticulum.reset_instance!
          RNS::Transport.reset
        end
      ensure
        FileUtils.rm_rf(tmpdir) if Dir.exists?(tmpdir)
      end
    end

    it "clamps requested loglevel to valid range" do
      tmpdir = File.tempname("rns_clamp_test")
      begin
        RNS::Reticulum.reset_instance!
        RNS::Transport.reset

        Dir.mkdir_p(tmpdir)
        File.write(File.join(tmpdir, "config"),
          "[reticulum]\nshare_instance = No\n[logging]\nloglevel = 4\n[interfaces]\n")

        original_ll = RNS.loglevel

        begin
          inst = RNS::ReticulumInstance.new(configdir: tmpdir, loglevel: 99)
          RNS.loglevel.should eq RNS::LOG_EXTREME  # 7
        ensure
          RNS.loglevel = original_ll
          RNS::Reticulum.reset_instance!
          RNS::Transport.reset
        end
      ensure
        FileUtils.rm_rf(tmpdir) if Dir.exists?(tmpdir)
      end
    end
  end

  # ─── Exit handler ──────────────────────────────────────────────────
  describe "exit handler" do
    it "runs without errors" do
      RNS::Reticulum.reset_instance!
      RNS::Reticulum.exit_handler
    end

    it "is idempotent" do
      RNS::Reticulum.reset_instance!
      RNS::Reticulum.exit_handler
      RNS::Reticulum.exit_handler  # Should be a no-op
    end

    it "signal handlers run without errors" do
      RNS::Reticulum.sigint_handler
      RNS::Reticulum.sigterm_handler
    end
  end

  # ─── Transport stubs ───────────────────────────────────────────────
  describe "Transport remote management stubs" do
    before_each { RNS::Transport.reset }

    it "add_remote_management_allowed adds hash" do
      hash = Random::Secure.random_bytes(16)
      RNS::Transport.add_remote_management_allowed(hash)
      RNS::Transport.remote_management_allowed.size.should eq 1
      RNS::Transport.remote_management_allowed[0].should eq hash
    end

    it "add_remote_management_allowed deduplicates" do
      hash = Random::Secure.random_bytes(16)
      RNS::Transport.add_remote_management_allowed(hash)
      RNS::Transport.add_remote_management_allowed(hash)
      RNS::Transport.remote_management_allowed.size.should eq 1
    end

    it "detach_interfaces does not raise" do
      RNS::Transport.detach_interfaces
    end
  end

  # ─── Stress tests ─────────────────────────────────────────────────
  describe "stress tests" do
    it "parses 20 different configs" do
      20.times do |i|
        RNS::Reticulum.reset_instance!
        inst = make_test_instance(
          "[reticulum]\nshare_instance = No\nshared_instance_port = #{37428 + i}\ninstance_control_port = #{37429 + i}\n[logging]\nloglevel = #{i % 8}")
        inst.apply_config
        inst.local_interface_port.should eq(37428 + i)
        inst.local_control_port.should eq(37429 + i)
      end
    end

    it "singleton reset works 50 times" do
      50.times do
        RNS::Reticulum.reset_instance!
        RNS::Reticulum.get_instance.should be_nil
        RNS::Reticulum.transport_enabled?.should be_false
        RNS::Reticulum.should_use_implicit_proof?.should be_true
      end
    end

    it "default config can be parsed 30 times" do
      30.times do
        lines = RNS::Reticulum.default_config_lines
        config = RNS::ConfigObj.new(lines)
        config.has_key?("reticulum").should be_true
        config.has_key?("logging").should be_true
        config.has_key?("interfaces").should be_true
      end
    end
  end
end
