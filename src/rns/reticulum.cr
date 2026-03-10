module RNS
  module Reticulum
    # ─── Protocol constants ──────────────────────────────────────────
    MTU                = 500
    LINK_MTU_DISCOVERY = true

    MAX_QUEUED_ANNOUNCES = 16384
    QUEUED_ANNOUNCE_LIFE = 60 * 60 * 24  # 86400

    ANNOUNCE_CAP    = 2   # percentage
    MINIMUM_BITRATE = 5   # bits per second

    DEFAULT_PER_HOP_TIMEOUT = 6

    TRUNCATED_HASHLENGTH = 128  # bits

    HEADER_MINSIZE = 2 + 1 + (TRUNCATED_HASHLENGTH // 8) * 1  # 19
    HEADER_MAXSIZE = 2 + 1 + (TRUNCATED_HASHLENGTH // 8) * 2  # 35
    IFAC_MIN_SIZE  = 1

    MDU = MTU - HEADER_MAXSIZE - IFAC_MIN_SIZE  # 464

    # IFAC (Interface Authentication Code) salt — must match Python exactly
    IFAC_SALT = "adf54d882c9a9b80771eb4995d702d4a3e733391b2a0f53f416d9f907e55cff8".hexbytes

    # ─── Time interval constants ─────────────────────────────────────
    RESOURCE_CACHE             = 24 * 60 * 60       # 86400
    JOB_INTERVAL               = 5 * 60             # 300
    CLEAN_INTERVAL             = 15 * 60            # 900
    PERSIST_INTERVAL           = 60 * 60 * 12       # 43200
    GRACIOUS_PERSIST_INTERVAL  = 60 * 5             # 300

    # ─── Default ports ───────────────────────────────────────────────
    DEFAULT_LOCAL_INTERFACE_PORT = 37428
    DEFAULT_LOCAL_CONTROL_PORT  = 37429

    # ─── Class-level mutable state ───────────────────────────────────
    @@panic_on_interface_error : Bool = false
    @@instance : ReticulumInstance? = nil
    @@interface_detach_ran : Bool = false
    @@exit_handler_ran : Bool = false

    # Paths
    @@userdir : String = Path.home.to_s
    @@configdir : String = File.join(Path.home.to_s, ".reticulum")
    @@configpath : String = ""
    @@storagepath : String = ""
    @@cachepath : String = ""
    @@resourcepath : String = ""
    @@identitypath : String = ""
    @@blackholepath : String = ""
    @@interfacepath : String = ""

    # Private class state set by config
    @@network_identity : Identity? = nil
    @@transport_enabled : Bool = false
    @@link_mtu_discovery : Bool = LINK_MTU_DISCOVERY
    @@remote_management_enabled : Bool = false
    @@use_implicit_proof : Bool = true
    @@allow_probes : Bool = false
    @@discovery_enabled : Bool = false
    @@discover_interfaces : Bool = false
    @@autoconnect_discovered_interfaces : Int32 = 0
    @@required_discovery_value : Int32? = nil
    @@publish_blackhole : Bool = false
    @@blackhole_sources : Array(Bytes) = [] of Bytes
    @@interface_sources : Array(Bytes) = [] of Bytes
    @@force_shared_instance_bitrate : Int64? = nil

    # ─── Class-level accessors ───────────────────────────────────────
    def self.panic_on_interface_error; @@panic_on_interface_error; end
    def self.panic_on_interface_error=(v); @@panic_on_interface_error = v; end

    def self.userdir; @@userdir; end
    def self.configdir; @@configdir; end
    def self.configdir=(v); @@configdir = v; end
    def self.configpath; @@configpath; end
    def self.configpath=(v); @@configpath = v; end
    def self.storagepath; @@storagepath; end
    def self.storagepath=(v); @@storagepath = v; end
    def self.cachepath; @@cachepath; end
    def self.cachepath=(v); @@cachepath = v; end
    def self.resourcepath; @@resourcepath; end
    def self.resourcepath=(v); @@resourcepath = v; end
    def self.identitypath; @@identitypath; end
    def self.identitypath=(v); @@identitypath = v; end
    def self.blackholepath; @@blackholepath; end
    def self.blackholepath=(v); @@blackholepath = v; end
    def self.interfacepath; @@interfacepath; end
    def self.interfacepath=(v); @@interfacepath = v; end

    def self.transport_enabled?; @@transport_enabled; end
    def self.transport_enabled=(v); @@transport_enabled = v; end
    def self.link_mtu_discovery?; @@link_mtu_discovery; end
    def self.link_mtu_discovery=(v); @@link_mtu_discovery = v; end
    def self.remote_management_enabled?; @@remote_management_enabled; end
    def self.remote_management_enabled=(v); @@remote_management_enabled = v; end
    def self.should_use_implicit_proof?; @@use_implicit_proof; end
    def self.use_implicit_proof=(v); @@use_implicit_proof = v; end
    def self.probe_destination_enabled?; @@allow_probes; end
    def self.allow_probes=(v); @@allow_probes = v; end
    def self.discovery_enabled?; @@discovery_enabled; end
    def self.discovery_enabled=(v); @@discovery_enabled = v; end
    def self.discover_interfaces?; @@discover_interfaces; end
    def self.discover_interfaces_flag=(v); @@discover_interfaces = v; end
    def self.required_discovery_value; @@required_discovery_value; end
    def self.required_discovery_value=(v); @@required_discovery_value = v; end
    def self.publish_blackhole_enabled?; @@publish_blackhole; end
    def self.publish_blackhole=(v); @@publish_blackhole = v; end
    def self.blackhole_sources; @@blackhole_sources; end
    def self.interface_discovery_sources; @@interface_sources; end
    def self.network_identity; @@network_identity; end
    def self.network_identity=(v); @@network_identity = v; end
    def self.force_shared_instance_bitrate; @@force_shared_instance_bitrate; end
    def self.force_shared_instance_bitrate=(v); @@force_shared_instance_bitrate = v; end

    def self.should_autoconnect_discovered_interfaces?
      @@autoconnect_discovered_interfaces > 0
    end

    def self.max_autoconnected_interfaces
      @@autoconnect_discovered_interfaces
    end

    def self.autoconnect_discovered_interfaces=(v)
      @@autoconnect_discovered_interfaces = v
    end

    # ─── Singleton access ────────────────────────────────────────────
    def self.get_instance : ReticulumInstance?
      @@instance
    end

    # Set instance (called from ReticulumInstance constructor)
    protected def self.class_set_instance(inst : ReticulumInstance)
      @@instance = inst
    end

    # Reset singleton for testing
    def self.reset_instance!
      @@instance = nil
      @@interface_detach_ran = false
      @@exit_handler_ran = false
      @@transport_enabled = false
      @@link_mtu_discovery = LINK_MTU_DISCOVERY
      @@remote_management_enabled = false
      @@use_implicit_proof = true
      @@allow_probes = false
      @@discovery_enabled = false
      @@discover_interfaces = false
      @@autoconnect_discovered_interfaces = 0
      @@required_discovery_value = nil
      @@publish_blackhole = false
      @@blackhole_sources = [] of Bytes
      @@interface_sources = [] of Bytes
      @@network_identity = nil
      @@force_shared_instance_bitrate = nil
      @@panic_on_interface_error = false
    end

    # ─── Exit handler ────────────────────────────────────────────────
    def self.exit_handler
      unless @@exit_handler_ran
        @@exit_handler_ran = true
        unless @@interface_detach_ran
          Transport.detach_interfaces
        end
        Transport.exit_handler
        Identity.exit_handler(@@storagepath)
        RNS.loglevel = -1
      end
    end

    def self.sigint_handler
      Transport.detach_interfaces
      @@interface_detach_ran = true
    end

    def self.sigterm_handler
      Transport.detach_interfaces
      @@interface_detach_ran = true
    end

    # ─── Default config template (matches Python exactly) ────────────
    DEFAULT_RNS_CONFIG = <<-'CONFIG'
    # This is the default Reticulum config file.
    # You should probably edit it to include any additional,
    # interfaces and settings you might need.

    # Only the most basic options are included in this default
    # configuration. To see a more verbose, and much longer,
    # configuration example, you can run the command:
    # rnsd --exampleconfig


    [reticulum]

    # If you enable Transport, your system will route traffic
    # for other peers, pass announces and serve path requests.
    # This should only be done for systems that are suited to
    # act as transport nodes, ie. if they are stationary and
    # always-on. This directive is optional and can be removed
    # for brevity.

    enable_transport = False


    # By default, the first program to launch the Reticulum
    # Network Stack will create a shared instance, that other
    # programs can communicate with. Only the shared instance
    # opens all the configured interfaces directly, and other
    # local programs communicate with the shared instance over
    # a local socket. This is completely transparent to the
    # user, and should generally be turned on. This directive
    # is optional and can be removed for brevity.

    share_instance = Yes


    # If you want to run multiple *different* shared instances
    # on the same system, you will need to specify different
    # instance names for each. On platforms supporting domain
    # sockets, this can be done with the instance_name option:

    instance_name = default


    # Some platforms don't support domain sockets, and if that
    # is the case, you can isolate different instances by
    # specifying a unique set of ports for each:

    # shared_instance_port = 37428
    # instance_control_port = 37429


    # If you want to explicitly use TCP for shared instance
    # communication, instead of domain sockets, this is also
    # possible, by using the following option:

    # shared_instance_type = tcp


    # You can configure whether Reticulum should discover
    # available interfaces from other Transport Instances over
    # the network. If this option is enabled, Reticulum will
    # collect interface information discovered from the network.

    # discover_interfaces = No


    # You can configure Reticulum to panic and forcibly close
    # if an unrecoverable interface error occurs, such as the
    # hardware device for an interface disappearing. This is
    # an optional directive, and can be left out for brevity.
    # This behaviour is disabled by default.

    # panic_on_interface_error = No


    # If you're connecting to a large external network, you
    # can use one or more external blackhole list to block
    # spammy and excessive announces onto your network. This
    # funtionality is especially useful if you're hosting public
    # entrypoints or gateways. The list source below provides a
    # functional example, but better, more timely maintained
    # lists probably exist in the community.

    # blackhole_sources = 521c87a83afb8f29e4455e77930b973b


    [logging]
    # Valid log levels are 0 through 7:
    #   0: Log only critical information
    #   1: Log errors and lower log levels
    #   2: Log warnings and lower log levels
    #   3: Log notices and lower log levels
    #   4: Log info and lower (this is the default)
    #   5: Verbose logging
    #   6: Debug logging
    #   7: Extreme logging

    loglevel = 4


    # The interfaces section defines the physical and virtual
    # interfaces Reticulum will use to communicate on. This
    # section will contain examples for a variety of interface
    # types. You can modify these or use them as a basis for
    # your own config, or simply remove the unused ones.

    [interfaces]

      # This interface enables communication with other
      # link-local Reticulum nodes over UDP. It does not
      # need any functional IP infrastructure like routers
      # or DHCP servers, but will require that at least link-
      # local IPv6 is enabled in your operating system, which
      # should be enabled by default in almost any OS. See
      # the Reticulum Manual for more configuration options.

      [[Default Interface]]
        type = AutoInterface
        enabled = Yes

    CONFIG

    # Return the default config as an array of lines (matching Python's splitlines())
    def self.default_config_lines : Array(String)
      # Strip the leading indentation from the heredoc
      DEFAULT_RNS_CONFIG.lines.map { |line|
        # Remove exactly 4 spaces of heredoc indentation
        if line.starts_with?("    ")
          line[4..]
        else
          line
        end
      }
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # ReticulumInstance — the actual instantiated Reticulum singleton
  # ═══════════════════════════════════════════════════════════════════
  class ReticulumInstance
    property config : ConfigObj?
    property local_interface_port : Int32
    property local_control_port : Int32
    property local_socket_path : String?
    property share_instance : Bool
    property shared_instance_type : String?
    property rpc_key : Bytes?
    property rpc_type : String
    property use_af_unix : Bool
    property ifac_salt : Bytes

    property is_shared_instance : Bool
    property shared_instance_interface : Interface?
    property is_connected_to_shared_instance : Bool
    property is_standalone_instance : Bool

    property last_data_persist : Float64
    property last_cache_clean : Float64

    property requested_loglevel : Int32?
    property requested_verbosity : Int32?
    property require_shared : Bool

    def initialize(
      configdir : String? = nil,
      loglevel : Int32? = nil,
      logdest : (Int32 | Proc(String, Nil))? = nil,
      verbosity : Int32? = nil,
      require_shared_instance : Bool = false,
      shared_instance_type : String? = nil
    )
      # Singleton guard
      if Reticulum.get_instance
        raise Exception.new("Attempt to reinitialise Reticulum, when it was already running")
      end

      # Resolve configdir
      if configdir
        Reticulum.configdir = configdir
      else
        if Dir.exists?("/etc/reticulum") && File.exists?("/etc/reticulum/config")
          Reticulum.configdir = "/etc/reticulum"
        elsif Dir.exists?(File.join(Reticulum.userdir, ".config", "reticulum")) &&
              File.exists?(File.join(Reticulum.userdir, ".config", "reticulum", "config"))
          Reticulum.configdir = File.join(Reticulum.userdir, ".config", "reticulum")
        else
          Reticulum.configdir = File.join(Reticulum.userdir, ".reticulum")
        end
      end

      # Configure log destination
      case logdest
      when Int32
        if logdest == RNS::LOG_FILE
          RNS.logdest = RNS::LOG_FILE
          RNS.logfile = File.join(Reticulum.configdir, "logfile")
        end
      when Proc(String, Nil)
        RNS.logdest = RNS::LOG_CALLBACK
        RNS.logcall = logdest
      end

      # Set all path class variables
      Reticulum.configpath = File.join(Reticulum.configdir, "config")
      Reticulum.storagepath = File.join(Reticulum.configdir, "storage")
      Reticulum.cachepath = File.join(Reticulum.configdir, "storage", "cache")
      Reticulum.resourcepath = File.join(Reticulum.configdir, "storage", "resources")
      Reticulum.identitypath = File.join(Reticulum.configdir, "storage", "identities")
      Reticulum.blackholepath = File.join(Reticulum.configdir, "storage", "blackhole")
      Reticulum.interfacepath = File.join(Reticulum.configdir, "interfaces")

      # Reset class-level private state
      Reticulum.network_identity = nil
      Reticulum.transport_enabled = false
      Reticulum.link_mtu_discovery = Reticulum::LINK_MTU_DISCOVERY
      Reticulum.remote_management_enabled = false
      Reticulum.use_implicit_proof = true
      Reticulum.allow_probes = false
      Reticulum.discovery_enabled = false
      Reticulum.discover_interfaces_flag = false
      Reticulum.autoconnect_discovered_interfaces = 0
      Reticulum.required_discovery_value = nil
      Reticulum.publish_blackhole = false
      Reticulum.panic_on_interface_error = false

      # Instance variables
      @local_interface_port = Reticulum::DEFAULT_LOCAL_INTERFACE_PORT
      @local_control_port = Reticulum::DEFAULT_LOCAL_CONTROL_PORT
      @local_socket_path = nil
      @share_instance = true
      @shared_instance_type = shared_instance_type
      @rpc_key = nil
      @rpc_type = "AF_INET"
      @use_af_unix = false
      @ifac_salt = Reticulum::IFAC_SALT
      @config = nil

      @requested_loglevel = loglevel
      @requested_verbosity = verbosity
      if ll = @requested_loglevel
        ll = RNS::LOG_EXTREME if ll > RNS::LOG_EXTREME
        ll = RNS::LOG_CRITICAL if ll < RNS::LOG_CRITICAL
        @requested_loglevel = ll
        RNS.loglevel = ll
      end

      @is_shared_instance = false
      @shared_instance_interface = nil
      @require_shared = require_shared_instance
      @is_connected_to_shared_instance = false
      @is_standalone_instance = false
      @last_data_persist = Time.utc.to_unix_f
      @last_cache_clean = 0.0

      # Create directories if they don't exist
      Dir.mkdir_p(Reticulum.storagepath) unless Dir.exists?(Reticulum.storagepath)
      Dir.mkdir_p(Reticulum.cachepath) unless Dir.exists?(Reticulum.cachepath)
      Dir.mkdir_p(Reticulum.resourcepath) unless Dir.exists?(Reticulum.resourcepath)
      Dir.mkdir_p(Reticulum.identitypath) unless Dir.exists?(Reticulum.identitypath)
      Dir.mkdir_p(Reticulum.blackholepath) unless Dir.exists?(Reticulum.blackholepath)
      Dir.mkdir_p(Reticulum.interfacepath) unless Dir.exists?(Reticulum.interfacepath)
      announces_cache = File.join(Reticulum.cachepath, "announces")
      Dir.mkdir_p(announces_cache) unless Dir.exists?(announces_cache)

      # Load or create config
      if File.exists?(Reticulum.configpath)
        begin
          @config = ConfigObj.from_file(Reticulum.configpath)
        rescue ex
          RNS.log("Could not parse the configuration at #{Reticulum.configpath}", RNS::LOG_ERROR)
          RNS.log("Check your configuration file for errors!", RNS::LOG_ERROR)
          RNS.panic
        end
      else
        RNS.log("Could not load config file, creating default configuration file...")
        create_default_config
        RNS.log("Default config file created. Make any necessary changes in #{Reticulum.configdir}/config and restart Reticulum if needed.")
        sleep(1.5.seconds)
      end

      # Apply configuration
      apply_config

      RNS.log("Configuration loaded from #{Reticulum.configpath}", RNS::LOG_VERBOSE)

      # Start local interface
      start_local_interface

      # Start transport (loads known destinations, starts job loop)
      RNS.log("Loading known destinations...", RNS::LOG_VERBOSE)
      Identity.load_known_destinations(Reticulum.storagepath)
      Transport.start(Transport::OwnerRef.new(
        is_connected_to_shared_instance: @is_connected_to_shared_instance,
        storage_path: Reticulum.storagepath,
        cache_path: Reticulum.cachepath,
        transport_enabled: Reticulum.transport_enabled?
      ))

      # Determine RPC address type
      if @use_af_unix
        @rpc_type = "AF_UNIX"
      else
        @rpc_type = "AF_INET"
      end

      # Generate RPC key if not set
      if @rpc_key.nil?
        if prv_key = Transport.identity.try(&.get_private_key)
          @rpc_key = Identity.full_hash(prv_key)
        end
      end

      # Register singleton
      Reticulum.class_set_instance(self)

      # Register signal handlers
      Signal::INT.trap { Reticulum.sigint_handler }
      Signal::TERM.trap { Reticulum.sigterm_handler }

      # Start background jobs
      start_jobs if @is_shared_instance || @is_standalone_instance
    end

    # Test-only constructor: creates instance without starting interfaces or transport
    def initialize(config : ConfigObj, *,
                   requested_loglevel : Int32? = nil,
                   requested_verbosity : Int32? = nil,
                   shared_instance_type : String? = nil,
                   _test : Bool = true)
      @config = config
      @requested_loglevel = requested_loglevel
      @requested_verbosity = requested_verbosity
      @local_interface_port = Reticulum::DEFAULT_LOCAL_INTERFACE_PORT
      @local_control_port = Reticulum::DEFAULT_LOCAL_CONTROL_PORT
      @local_socket_path = nil
      @share_instance = true
      @shared_instance_type = shared_instance_type
      @rpc_key = nil
      @rpc_type = "AF_INET"
      @use_af_unix = false
      @ifac_salt = Reticulum::IFAC_SALT
      @is_shared_instance = false
      @shared_instance_interface = nil
      @is_connected_to_shared_instance = false
      @is_standalone_instance = false
      @last_data_persist = 0.0
      @last_cache_clean = 0.0
      @require_shared = false
    end

    # ─── Config application ──────────────────────────────────────────
    def apply_config
      cfg = @config
      return unless cfg

      # [logging] section
      if cfg.has_key?("logging")
        logging_section = cfg["logging"]
        if logging_section.is_a?(ConfigObj::Section)
          logging_section.scalars.each do |option|
            if option == "loglevel" && @requested_loglevel.nil?
              value = logging_section.as_int(option)
              RNS.loglevel = value
              if rv = @requested_verbosity
                RNS.loglevel = RNS.loglevel + rv
              end
              RNS.loglevel = 0 if RNS.loglevel < 0
              RNS.loglevel = 7 if RNS.loglevel > 7
            end
          end
        end
      end

      # [reticulum] section
      if cfg.has_key?("reticulum")
        ret_section = cfg["reticulum"]
        if ret_section.is_a?(ConfigObj::Section)
          ret_section.scalars.each do |option|
            case option
            when "share_instance"
              @share_instance = ret_section.as_bool(option)

            when "instance_name"
              if RNS::PlatformUtils.use_af_unix?
                @local_socket_path = ret_section[option].as(String)
              end

            when "shared_instance_type"
              if @shared_instance_type.nil?
                val = ret_section[option].as(String).downcase
                if val == "tcp" || val == "unix"
                  @shared_instance_type = val
                end
              end

            when "shared_instance_port"
              @local_interface_port = ret_section.as_int(option)

            when "instance_control_port"
              @local_control_port = ret_section.as_int(option)

            when "rpc_key"
              begin
                @rpc_key = ret_section[option].as(String).hexbytes
              rescue
                RNS.log("Invalid shared instance RPC key specified, falling back to default key", RNS::LOG_ERROR)
                @rpc_key = nil
              end

            when "enable_transport"
              if ret_section.as_bool(option)
                Reticulum.transport_enabled = true
              end

            when "network_identity"
              if Reticulum.network_identity.nil?
                path = ret_section[option].as(String)
                identitypath = File.expand_path(path)
                begin
                  network_identity : Identity? = nil
                  if !File.exists?(identitypath)
                    network_identity = Identity.new
                    network_identity.to_file(identitypath)
                    RNS.log("Network identity generated and persisted to #{identitypath}", RNS::LOG_VERBOSE)
                  else
                    network_identity = Identity.from_file(identitypath)
                    RNS.log("Network identity loaded from #{identitypath}", RNS::LOG_VERBOSE)
                  end
                  if ni = network_identity
                    Reticulum.network_identity = ni
                  else
                    raise Exception.new("Network identity initialisation failed")
                  end
                rescue ex
                  raise Exception.new("Could not set network identity from #{path}: #{ex.message}")
                end
              end

            when "link_mtu_discovery"
              if ret_section.as_bool(option)
                Reticulum.link_mtu_discovery = true
              end

            when "enable_remote_management"
              if ret_section.as_bool(option)
                Reticulum.remote_management_enabled = true
              end

            when "remote_management_allowed"
              v = ret_section.as_list(option)
              dest_len = (Reticulum::TRUNCATED_HASHLENGTH // 8) * 2
              v.each do |hexhash|
                if hexhash.size != dest_len
                  raise Exception.new("Identity hash length for remote management ACL #{hexhash} is invalid, must be #{dest_len} hexadecimal characters (#{dest_len // 2} bytes).")
                end
                begin
                  allowed_hash = hexhash.hexbytes
                  Transport.add_remote_management_allowed(allowed_hash)
                rescue
                  raise Exception.new("Invalid identity hash for remote management ACL: #{hexhash}")
                end
              end

            when "respond_to_probes"
              if ret_section.as_bool(option)
                Reticulum.allow_probes = true
              end

            when "force_shared_instance_bitrate"
              Reticulum.force_shared_instance_bitrate = ret_section.as_int(option).to_i64

            when "panic_on_interface_error"
              if ret_section.as_bool(option)
                Reticulum.panic_on_interface_error = true
              end

            when "use_implicit_proof"
              Reticulum.use_implicit_proof = ret_section.as_bool(option)

            when "discover_interfaces"
              Reticulum.discover_interfaces_flag = ret_section.as_bool(option)

            when "required_discovery_value"
              v = ret_section.as_int(option)
              Reticulum.required_discovery_value = v > 0 ? v : nil

            when "publish_blackhole"
              Reticulum.publish_blackhole = ret_section.as_bool(option)

            when "blackhole_sources"
              v = ret_section.as_list(option)
              dest_len = (Reticulum::TRUNCATED_HASHLENGTH // 8) * 2
              v.each do |hexhash|
                if hexhash.size != dest_len
                  raise Exception.new("Identity hash length for blackhole source #{hexhash} is invalid, must be #{dest_len} hexadecimal characters (#{dest_len // 2} bytes).")
                end
                begin
                  source_hash = hexhash.hexbytes
                  unless Reticulum.blackhole_sources.any? { |h| h == source_hash }
                    Reticulum.blackhole_sources << source_hash
                  end
                rescue
                  raise Exception.new("Invalid identity hash for remote blackhole source: #{hexhash}")
                end
              end

            when "interface_discovery_sources"
              v = ret_section.as_list(option)
              dest_len = (Reticulum::TRUNCATED_HASHLENGTH // 8) * 2
              v.each do |hexhash|
                if hexhash.size != dest_len
                  raise Exception.new("Identity hash length for interface discovery source #{hexhash} is invalid, must be #{dest_len} hexadecimal characters (#{dest_len // 2} bytes).")
                end
                begin
                  source_hash = hexhash.hexbytes
                  unless Reticulum.interface_discovery_sources.any? { |h| h == source_hash }
                    Reticulum.interface_discovery_sources << source_hash
                  end
                rescue
                  raise Exception.new("Invalid identity hash for interface discovery source: #{hexhash}")
                end
              end

            when "autoconnect_discovered_interfaces"
              v = ret_section.as_int(option)
              Reticulum.autoconnect_discovered_interfaces = v if v > 0
            end
          end
        end
      end

      # Determine AF_UNIX vs TCP
      if RNS::PlatformUtils.use_af_unix?
        if @shared_instance_type == "tcp"
          @use_af_unix = false
        else
          @use_af_unix = true
        end
      else
        @shared_instance_type = "tcp"
        @use_af_unix = false
      end

      if @local_socket_path.nil? && @use_af_unix
        @local_socket_path = "default"
      end
    end

    # ─── Start local interface (shared instance / client / standalone) ──
    protected def start_local_interface
      if @share_instance
        begin
          # Try to be the shared instance (server)
          interface = if @use_af_unix && (sp = @local_socket_path)
            LocalServerInterface.new(socket_path: sp)
          else
            LocalServerInterface.new(bindport: @local_interface_port)
          end
          interface.dir_out = true

          if fsib = Reticulum.force_shared_instance_bitrate
            interface.bitrate = fsib
            interface.force_bitrate = true
            RNS.log("Forcing shared instance bitrate of #{RNS.prettyspeed(fsib.to_f64)}", RNS::LOG_WARNING)
            interface.optimise_mtu
          end

          if @require_shared
            interface.detach
            @is_shared_instance = true
            RNS.log("Existing shared instance required, but this instance started as shared instance. Aborting startup.", RNS::LOG_VERBOSE)
          else
            Transport.register_interface(interface.get_hash)
            @shared_instance_interface = interface
            @is_shared_instance = true
            RNS.log("Started shared instance interface: #{interface}", RNS::LOG_DEBUG)
          end
        rescue ex
          begin
            # Try to connect as a client
            client = if @use_af_unix && (sp = @local_socket_path)
              LocalClientInterface.new(socket_path: sp)
            else
              LocalClientInterface.new(target_port: @local_interface_port)
            end
            client.name = "Local shared instance"
            client.dir_out = true

            if fsib = Reticulum.force_shared_instance_bitrate
              client.bitrate = fsib.to_i64
              client.force_bitrate = true
              RNS.log("Forcing shared instance bitrate of #{RNS.prettyspeed(fsib.to_f64)}", RNS::LOG_WARNING)
              client.optimise_mtu
            end

            Transport.register_interface(client.get_hash)
            @is_shared_instance = false
            @is_standalone_instance = false
            @is_connected_to_shared_instance = true
            client.is_connected_to_shared_instance = true
            Reticulum.transport_enabled = false
            Reticulum.remote_management_enabled = false
            Reticulum.allow_probes = false
            RNS.log("Connected to locally available Reticulum instance via: #{client}", RNS::LOG_DEBUG)
          rescue ex2
            RNS.log("Local shared instance appears to be running, but it could not be connected", RNS::LOG_ERROR)
            RNS.log("The contained exception was: #{ex2.message}", RNS::LOG_ERROR)
            @is_shared_instance = false
            @is_standalone_instance = true
            @is_connected_to_shared_instance = false
          end
        end

        if @is_shared_instance && @require_shared
          raise Exception.new("No shared instance available, but application that started Reticulum required it")
        end
      else
        @is_shared_instance = false
        @is_standalone_instance = true
        @is_connected_to_shared_instance = false
      end
    end

    # ─── Background jobs ─────────────────────────────────────────────
    protected def start_jobs
      spawn do
        Identity.try_clean_ratchets
        loop do
          now = Time.utc.to_unix_f
          if now > @last_cache_clean + Reticulum::CLEAN_INTERVAL
            clean_caches
            @last_cache_clean = Time.utc.to_unix_f
          end
          if now > @last_data_persist + Reticulum::PERSIST_INTERVAL
            persist_data
          end
          sleep(Reticulum::JOB_INTERVAL.seconds)
        end
      end
    end

    protected def persist_data
      Transport.persist_data(Reticulum.storagepath)
      Identity.persist_data(Reticulum.storagepath)
      @last_data_persist = Time.utc.to_unix_f
    end

    protected def clean_caches
      RNS.log("Cleaning resource and packet caches...", RNS::LOG_EXTREME)
      now = Time.utc.to_unix_f

      # Clean resource caches
      if Dir.exists?(Reticulum.resourcepath)
        Dir.each_child(Reticulum.resourcepath) do |filename|
          begin
            expected_len = (Identity::HASHLENGTH // 8) * 2
            if filename.size == expected_len
              filepath = File.join(Reticulum.resourcepath, filename)
              mtime = File.info(filepath).modification_time.to_unix_f
              age = now - mtime
              if age > Reticulum::RESOURCE_CACHE
                File.delete(filepath)
              end
            end
          rescue ex
            RNS.log("Error while cleaning resources cache, the contained exception was: #{ex.message}", RNS::LOG_ERROR)
          end
        end
      end

      # Clean packet caches
      if Dir.exists?(Reticulum.cachepath)
        Dir.each_child(Reticulum.cachepath) do |filename|
          begin
            expected_len = (Identity::HASHLENGTH // 8) * 2
            if filename.size == expected_len
              filepath = File.join(Reticulum.cachepath, filename)
              mtime = File.info(filepath).modification_time.to_unix_f
              age = now - mtime
              if age > Transport::DESTINATION_TIMEOUT
                File.delete(filepath)
              end
            end
          rescue ex
            RNS.log("Error while cleaning packet cache, the contained exception was: #{ex.message}", RNS::LOG_ERROR)
          end
        end
      end
    end

    # ─── Default config creation ─────────────────────────────────────
    protected def create_default_config
      lines = Reticulum.default_config_lines
      @config = ConfigObj.new(lines)
      if cfg = @config
        cfg.filename = Reticulum.configpath
        Dir.mkdir_p(Reticulum.configdir) unless Dir.exists?(Reticulum.configdir)
        cfg.write
      end
    end
  end
end
