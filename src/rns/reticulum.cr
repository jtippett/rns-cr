module RNS
  # Main system module for the Reticulum Network Stack.
  #
  # Holds protocol constants, path configuration, and class-level state
  # for transport, identity, and interface management. Provides the
  # singleton accessor for `ReticulumInstance`, signal handlers for
  # graceful shutdown, and the default configuration template.
  module Reticulum
    # ─── Protocol constants ──────────────────────────────────────────
    # Core protocol limits: MTU, announce queue depth, header sizes,
    # and the derived Maximum Data Unit (MDU) available to payloads.
    MTU                = 500
    LINK_MTU_DISCOVERY = true

    MAX_QUEUED_ANNOUNCES = 16384
    QUEUED_ANNOUNCE_LIFE = 60 * 60 * 24 # 86400

    ANNOUNCE_CAP    = 2 # percentage
    MINIMUM_BITRATE = 5 # bits per second

    DEFAULT_PER_HOP_TIMEOUT = 6

    TRUNCATED_HASHLENGTH = 128 # bits

    HEADER_MINSIZE = 2 + 1 + (TRUNCATED_HASHLENGTH // 8) * 1 # 19
    HEADER_MAXSIZE = 2 + 1 + (TRUNCATED_HASHLENGTH // 8) * 2 # 35
    IFAC_MIN_SIZE  = 1

    MDU = MTU - HEADER_MAXSIZE - IFAC_MIN_SIZE # 464

    # IFAC (Interface Authentication Code) salt — must match Python exactly
    IFAC_SALT = "adf54d882c9a9b80771eb4995d702d4a3e733391b2a0f53f416d9f907e55cff8".hexbytes

    # ─── Time interval constants ─────────────────────────────────────
    # Intervals (in seconds) for background cache cleaning, data
    # persistence, and resource expiration.
    RESOURCE_CACHE            = 24 * 60 * 60 # 86400
    JOB_INTERVAL              = 5 * 60       # 300
    CLEAN_INTERVAL            = 15 * 60      # 900
    PERSIST_INTERVAL          = 60 * 60 * 12 # 43200
    GRACIOUS_PERSIST_INTERVAL = 60 * 5       # 300

    # ─── Default ports ───────────────────────────────────────────────
    DEFAULT_LOCAL_INTERFACE_PORT = 37428
    DEFAULT_LOCAL_CONTROL_PORT   = 37429

    # ─── Class-level mutable state ───────────────────────────────────
    @@panic_on_interface_error : Bool = false
    @@instance : ReticulumInstance? = nil
    @@interface_detach_ran : Bool = false
    @@exit_handler_ran : Bool = false

    # Paths
    @@userdir : String = Path.home.to_s
    @@configdir : String = File.join(Path.home.to_s, ".reticulum")
    @@configpath : String = File.join(@@configdir, "config")
    @@storagepath : String = File.join(@@configdir, "storage")
    @@cachepath : String = File.join(@@configdir, "storage", "cache")
    @@resourcepath : String = File.join(@@configdir, "storage", "resources")
    @@identitypath : String = File.join(@@configdir, "storage", "identities")
    @@blackholepath : String = File.join(@@configdir, "storage", "blackhole")
    @@interfacepath : String = File.join(@@configdir, "interfaces")

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
    def self.panic_on_interface_error
      @@panic_on_interface_error
    end

    def self.panic_on_interface_error=(v)
      @@panic_on_interface_error = v
    end

    def self.userdir
      @@userdir
    end

    def self.configdir
      @@configdir
    end

    def self.configdir=(v)
      @@configdir = v
    end

    def self.configpath
      @@configpath
    end

    def self.configpath=(v)
      @@configpath = v
    end

    def self.storagepath
      @@storagepath
    end

    def self.storagepath=(v)
      @@storagepath = v
    end

    def self.cachepath
      @@cachepath
    end

    def self.cachepath=(v)
      @@cachepath = v
    end

    def self.resourcepath
      @@resourcepath
    end

    def self.resourcepath=(v)
      @@resourcepath = v
    end

    def self.identitypath
      @@identitypath
    end

    def self.identitypath=(v)
      @@identitypath = v
    end

    def self.blackholepath
      @@blackholepath
    end

    def self.blackholepath=(v)
      @@blackholepath = v
    end

    def self.interfacepath
      @@interfacepath
    end

    def self.interfacepath=(v)
      @@interfacepath = v
    end

    def self.transport_enabled?
      @@transport_enabled
    end

    def self.transport_enabled=(v)
      @@transport_enabled = v
    end

    def self.link_mtu_discovery?
      @@link_mtu_discovery
    end

    def self.link_mtu_discovery=(v)
      @@link_mtu_discovery = v
    end

    def self.remote_management_enabled?
      @@remote_management_enabled
    end

    def self.remote_management_enabled=(v)
      @@remote_management_enabled = v
    end

    def self.should_use_implicit_proof?
      @@use_implicit_proof
    end

    def self.use_implicit_proof=(v)
      @@use_implicit_proof = v
    end

    def self.probe_destination_enabled?
      @@allow_probes
    end

    def self.allow_probes=(v)
      @@allow_probes = v
    end

    def self.discovery_enabled?
      @@discovery_enabled
    end

    def self.discovery_enabled=(v)
      @@discovery_enabled = v
    end

    def self.discover_interfaces?
      @@discover_interfaces
    end

    def self.discover_interfaces_flag=(v)
      @@discover_interfaces = v
    end

    def self.required_discovery_value
      @@required_discovery_value
    end

    def self.required_discovery_value=(v)
      @@required_discovery_value = v
    end

    def self.publish_blackhole_enabled?
      @@publish_blackhole
    end

    def self.publish_blackhole=(v)
      @@publish_blackhole = v
    end

    def self.blackhole_sources
      @@blackhole_sources
    end

    def self.interface_discovery_sources
      @@interface_sources
    end

    def self.network_identity
      @@network_identity
    end

    def self.network_identity=(v)
      @@network_identity = v
    end

    def self.force_shared_instance_bitrate
      @@force_shared_instance_bitrate
    end

    def self.force_shared_instance_bitrate=(v)
      @@force_shared_instance_bitrate = v
    end

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

    # Performs graceful shutdown: detaches interfaces, flushes transport
    # state, persists identity data, and silences logging. Safe to call
    # multiple times; only the first invocation has effect.
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

    # INI-style default configuration written when no config file exists.
    # Matches the Python reference implementation byte-for-byte.
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
    property bootstrap_configs : Array(Hash(String, String)) = [] of Hash(String, String)

    # ─── Management (Reticule) ──────────────────────────────────────
    getter management_enabled : Bool = false
    getter reticule_dest_hash : Bytes? = nil
    getter management_node_id : Bytes? = nil
    getter management_report_interval : Float64 = 30.0
    getter management_heartbeat_interval : Float64 = 10.0
    getter management : Management::Manager? = nil
    property bootstrap_interface_name : String? = nil

    def initialize(
      configdir : String? = nil,
      loglevel : Int32? = nil,
      logdest : (Int32 | Proc(String, Nil))? = nil,
      verbosity : Int32? = nil,
      require_shared_instance : Bool = false,
      shared_instance_type : String? = nil,
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

      # Bring up system interfaces from config
      if @is_shared_instance || @is_standalone_instance
        start_system_interfaces
      end

      # Start management link if management is enabled and we have a dest hash
      if @management_enabled && @reticule_dest_hash
        @management.try(&.connect)
      end

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
      Signal::INT.trap do
        Reticulum.sigint_handler
        RNS.exit(0)
      end
      Signal::TERM.trap do
        Reticulum.sigterm_handler
        RNS.exit(0)
      end

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
                  unless Reticulum.blackhole_sources.any? { |hash| hash == source_hash }
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
                  unless Reticulum.interface_discovery_sources.any? { |hash| hash == source_hash }
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

      # [management] section
      if cfg.has_key?("management")
        mgmt_section = cfg["management"]
        if mgmt_section.is_a?(ConfigObj::Section)
          if mgmt_section.has_key?("enabled") && mgmt_section.as_bool("enabled")
            @management_enabled = true
            if mgmt_section.has_key?("reticule_dest_hash")
              begin
                @reticule_dest_hash = mgmt_section["reticule_dest_hash"].as(String).hexbytes
              rescue
                RNS.log("Invalid reticule_dest_hash in [management] config", RNS::LOG_ERROR)
                @reticule_dest_hash = nil
              end
            end
            if mgmt_section.has_key?("node_id")
              begin
                @management_node_id = mgmt_section["node_id"].as(String).hexbytes
              rescue
                RNS.log("Invalid node_id in [management] config", RNS::LOG_ERROR)
                @management_node_id = nil
              end
            end
            if mgmt_section.has_key?("report_interval")
              @management_report_interval = mgmt_section.as_int("report_interval").to_f64
            end
            if mgmt_section.has_key?("heartbeat_interval")
              @management_heartbeat_interval = mgmt_section.as_int("heartbeat_interval").to_f64
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

      # Create Management::Manager if [management] enabled = yes
      if @management_enabled
        mgmt_id_path = Reticulum.identitypath + "/management"
        if File.exists?(mgmt_id_path)
          identity = Identity.from_file(mgmt_id_path)
          if identity.nil?
            RNS.log("Could not load management identity from #{mgmt_id_path}, creating new", RNS::LOG_WARNING)
            identity = Identity.new(create_keys: true)
            identity.to_file(mgmt_id_path)
          end
        else
          RNS.log("No saved management identity found, creating new", RNS::LOG_INFO)
          identity = Identity.new(create_keys: true)
          identity.to_file(mgmt_id_path)
        end
        @management = Management::Manager.new(
          identity: identity,
          reticulum_instance: self,
          config_path: Reticulum.configpath,
          reticule_dest_hash: @reticule_dest_hash,
          node_id: @management_node_id,
          report_interval: @management_report_interval,
          heartbeat_interval: @management_heartbeat_interval,
          bootstrap_interface_name: @bootstrap_interface_name,
        )
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
            wire_transport_inbound_callback(interface)
            Transport.register_interface(interface)
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

            wire_transport_inbound_callback(client)
            Transport.register_interface(client)
            @is_shared_instance = false
            @is_standalone_instance = false
            @is_connected_to_shared_instance = true
            client.is_connected_to_shared_instance = true
            Reticulum.transport_enabled = false
            Reticulum.remote_management_enabled = false
            Reticulum.allow_probes = false
            RNS.log("Connected to locally available Reticulum instance via: #{client}", RNS::LOG_DEBUG)
          rescue ex
            RNS.log("Local shared instance appears to be running, but it could not be connected", RNS::LOG_ERROR)
            RNS.log("The contained exception was: #{ex.message}", RNS::LOG_ERROR)
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

    # ─── System interface instantiation from config ────────────────────
    def start_system_interfaces
      cfg = @config
      return unless cfg

      if cfg.has_key?("interfaces")
        interfaces_section = cfg["interfaces"]
        if interfaces_section.is_a?(ConfigObj::Section)
          RNS.log("Bringing up system interfaces...", RNS::LOG_VERBOSE)
          interface_names = [] of String

          interfaces_section.sections.each do |name|
            if interface_names.includes?(name)
              RNS.log("The interface name \"#{name}\" was already used. Check your configuration file for errors!", RNS::LOG_ERROR)
              RNS.panic
              next
            end
            interface_names << name

            section = interfaces_section[name]
            if section.is_a?(ConfigObj::Section)
              synthesize_interface(section, name, instance_init: true)
            end
          end

          RNS.log("System interfaces are ready", RNS::LOG_VERBOSE)
        end
      end
    end

    protected def synthesize_interface(config : ConfigObj::Section, name : String, instance_init : Bool = false)
      # Parse interface mode
      interface_mode = Interface::MODE_FULL

      if config.has_key?("interface_mode")
        mode_str = config["interface_mode"].as(String).downcase
        interface_mode = parse_interface_mode(mode_str)
      elsif config.has_key?("mode")
        mode_str = config["mode"].as(String).downcase
        interface_mode = parse_interface_mode(mode_str)
      end

      # Parse IFAC settings
      ifac_size : Int32? = nil
      if config.has_key?("ifac_size")
        val = config.as_int("ifac_size")
        ifac_size = val // 8 if val >= Reticulum::IFAC_MIN_SIZE * 8
      end

      ifac_netname : String? = nil
      if config.has_key?("networkname")
        v = config["networkname"].as(String)
        ifac_netname = v unless v.empty?
      end
      if config.has_key?("network_name")
        v = config["network_name"].as(String)
        ifac_netname = v unless v.empty?
      end

      ifac_netkey : String? = nil
      if config.has_key?("passphrase")
        v = config["passphrase"].as(String)
        ifac_netkey = v unless v.empty?
      end
      if config.has_key?("pass_phrase")
        v = config["pass_phrase"].as(String)
        ifac_netkey = v unless v.empty?
      end

      # Parse ingress control settings
      ingress_control = true
      ingress_control = config.as_bool("ingress_control") if config.has_key?("ingress_control")
      ic_max_held_announces : Int32? = nil
      ic_max_held_announces = config.as_int("ic_max_held_announces") if config.has_key?("ic_max_held_announces")
      ic_burst_hold : Float64? = nil
      ic_burst_hold = config.as_float("ic_burst_hold") if config.has_key?("ic_burst_hold")
      ic_burst_freq_new : Float64? = nil
      ic_burst_freq_new = config.as_float("ic_burst_freq_new") if config.has_key?("ic_burst_freq_new")
      ic_burst_freq : Float64? = nil
      ic_burst_freq = config.as_float("ic_burst_freq") if config.has_key?("ic_burst_freq")
      ic_new_time : Float64? = nil
      ic_new_time = config.as_float("ic_new_time") if config.has_key?("ic_new_time")
      ic_burst_penalty : Float64? = nil
      ic_burst_penalty = config.as_float("ic_burst_penalty") if config.has_key?("ic_burst_penalty")
      ic_held_release_interval : Float64? = nil
      ic_held_release_interval = config.as_float("ic_held_release_interval") if config.has_key?("ic_held_release_interval")

      # Parse bitrate and announce rate settings
      configured_bitrate : Int32? = nil
      if config.has_key?("bitrate")
        val = config.as_int("bitrate")
        configured_bitrate = val if val >= Reticulum::MINIMUM_BITRATE
      end

      announce_rate_target : Int32? = nil
      if config.has_key?("announce_rate_target")
        val = config.as_int("announce_rate_target")
        announce_rate_target = val if val > 0
      end

      announce_rate_grace : Int32? = nil
      if config.has_key?("announce_rate_grace")
        val = config.as_int("announce_rate_grace")
        announce_rate_grace = val if val >= 0
      end

      announce_rate_penalty : Int32? = nil
      if config.has_key?("announce_rate_penalty")
        val = config.as_int("announce_rate_penalty")
        announce_rate_penalty = val if val >= 0
      end

      announce_rate_grace = 0 if announce_rate_target && announce_rate_grace.nil?
      announce_rate_penalty = 0 if announce_rate_target && announce_rate_penalty.nil?

      announce_cap = Reticulum::ANNOUNCE_CAP / 100.0
      if config.has_key?("announce_cap")
        val = config.as_float("announce_cap")
        announce_cap = val / 100.0 if val > 0 && val <= 100
      end

      bootstrap_only = false
      bootstrap_only = config.as_bool("bootstrap_only") if config.has_key?("bootstrap_only")

      ignore_config_warnings = false
      ignore_config_warnings = config.as_bool("ignore_config_warnings") if config.has_key?("ignore_config_warnings")

      # Parse discovery settings
      discoverable = false
      discovery_announce_interval : Int32? = nil
      discovery_stamp_value : Int32? = nil
      discovery_name : String? = nil
      discovery_encrypt = false
      reachable_on : String? = nil
      publish_ifac = false
      latitude : Float64? = nil
      longitude : Float64? = nil
      height : Float64? = nil
      discovery_frequency : Int32? = nil
      discovery_bandwidth : Int32? = nil
      discovery_modulation : Int32? = nil

      if config.has_key?("discoverable")
        discoverable = config.as_bool("discoverable")
        if discoverable
          Reticulum.discovery_enabled = true
          if config.has_key?("announce_interval")
            discovery_announce_interval = config.as_int("announce_interval") * 60
            discovery_announce_interval = 5 * 60 if discovery_announce_interval < 5 * 60
          end

          discovery_announce_interval = 6 * 60 * 60 if discovery_announce_interval.nil?
          discovery_stamp_value = config.as_int("discovery_stamp_value") if config.has_key?("discovery_stamp_value")
          discovery_name = config["discovery_name"].as(String) if config.has_key?("discovery_name")
          discovery_encrypt = config.as_bool("discovery_encrypt") if config.has_key?("discovery_encrypt")
          reachable_on = config["reachable_on"].as(String) if config.has_key?("reachable_on")
          publish_ifac = config.as_bool("publish_ifac") if config.has_key?("publish_ifac")
          latitude = config.as_float("latitude") if config.has_key?("latitude")
          longitude = config.as_float("longitude") if config.has_key?("longitude")
          height = config.as_float("height") if config.has_key?("height")
          discovery_frequency = config.as_int("discovery_frequency") if config.has_key?("discovery_frequency")
          discovery_bandwidth = config.as_int("discovery_bandwidth") if config.has_key?("discovery_bandwidth")
          discovery_modulation = config.as_int("discovery_modulation") if config.has_key?("discovery_modulation")

          interface_type = config.has_key?("type") ? config["type"].as(String) : ""
          unless interface_mode == Interface::MODE_GATEWAY || interface_mode == Interface::MODE_ACCESS_POINT
            unless ignore_config_warnings
              if interface_type == "RNodeInterface" || interface_type == "RNodeMultiInterface"
                interface_mode = Interface::MODE_ACCESS_POINT
                RNS.log("Discovery enabled on interface #{name} without gateway or AP mode. Auto-configured to AP mode.", RNS::LOG_NOTICE)
              else
                interface_mode = Interface::MODE_GATEWAY
                RNS.log("Discovery enabled on interface #{name} without gateway or AP mode. Auto-configured to gateway mode.", RNS::LOG_NOTICE)
              end
            end
          end
        end
      end

      begin
        interface : Interface? = nil
        enabled = false
        if config.has_key?("interface_enabled")
          enabled = config.as_bool("interface_enabled")
        elsif config.has_key?("enabled")
          enabled = config.as_bool("enabled")
        end

        if enabled
          # Build interface config hash
          interface_config = config.to_string_hash
          interface_config["name"] = name
          interface_config["selected_interface_mode"] = interface_mode.to_s
          interface_config["configured_bitrate"] = configured_bitrate.to_s if configured_bitrate

          interface_type = config.has_key?("type") ? config["type"].as(String) : ""

          case interface_type
          when "AutoInterface"
            interface = AutoInterface.new(interface_config)
          when "BackboneInterface", "BackboneClientInterface"
            # Normalize config aliases
            if config.has_key?("port")
              port_val = config["port"].as(String)
              interface_config["listen_port"] = port_val
              interface_config["target_port"] = port_val
            end
            if config.has_key?("remote")
              interface_config["target_host"] = config["remote"].as(String)
            end
            if config.has_key?("listen_on")
              interface_config["listen_ip"] = config["listen_on"].as(String)
            end

            if interface_type == "BackboneInterface"
              if interface_config.has_key?("target_host")
                interface = BackboneClientInterface.new(interface_config)
              else
                interface = BackboneInterface.new(interface_config)
              end
            else
              interface = BackboneClientInterface.new(interface_config)
            end
          when "UDPInterface"
            interface = UDPInterface.new(interface_config)
          when "TCPServerInterface"
            interface = TCPServerInterface.new(interface_config)
          when "TCPClientInterface"
            interface = TCPClientInterface.new(interface_config)
          when "I2PInterface"
            interface_config["storagepath"] = Reticulum.storagepath
            interface_config["ifac_netname"] = ifac_netname.to_s if ifac_netname
            interface_config["ifac_netkey"] = ifac_netkey.to_s if ifac_netkey
            interface_config["ifac_size"] = ifac_size.to_s if ifac_size
            interface = I2PInterface.new(interface_config)
          when "SerialInterface"
            interface = SerialInterface.new(interface_config)
          when "PipeInterface"
            interface = PipeInterface.new(interface_config)
          when "KISSInterface"
            interface = KISSInterface.new(interface_config)
          when "AX25KISSInterface"
            interface = AX25KISSInterface.new(interface_config)
          when "RNodeInterface"
            interface = RNodeInterface.new(interface_config)
          when "RNodeMultiInterface"
            iface = RNodeMultiInterface.new(interface_config)
            interface = iface
          when "WeaveInterface"
            interface = WeaveInterface.new(interface_config)
          end

          if iface = interface
            interface_post_init(iface,
              interface_mode: interface_mode,
              announce_cap: announce_cap,
              bootstrap_only: bootstrap_only,
              configured_bitrate: configured_bitrate,
              ifac_size: ifac_size,
              ifac_netname: ifac_netname,
              ifac_netkey: ifac_netkey,
              ingress_control: ingress_control,
              ic_max_held_announces: ic_max_held_announces,
              ic_burst_hold: ic_burst_hold,
              ic_burst_freq_new: ic_burst_freq_new,
              ic_burst_freq: ic_burst_freq,
              ic_new_time: ic_new_time,
              ic_burst_penalty: ic_burst_penalty,
              ic_held_release_interval: ic_held_release_interval,
              announce_rate_target: announce_rate_target,
              announce_rate_grace: announce_rate_grace,
              announce_rate_penalty: announce_rate_penalty,
              discoverable: discoverable,
              discovery_announce_interval: discovery_announce_interval,
              discovery_publish_ifac: publish_ifac,
              reachable_on: reachable_on,
              discovery_name: discovery_name,
              discovery_encrypt: discovery_encrypt,
              discovery_stamp_value: discovery_stamp_value,
              discovery_latitude: latitude,
              discovery_longitude: longitude,
              discovery_height: height,
              discovery_frequency: discovery_frequency,
              discovery_bandwidth: discovery_bandwidth,
              discovery_modulation: discovery_modulation,
              outgoing: config.has_key?("outgoing") ? config.as_bool("outgoing") : true,
            )

            # RNodeMultiInterface needs start() called after post_init
            if interface_type == "RNodeMultiInterface" && iface.responds_to?(:start)
              iface.as(RNodeMultiInterface).start
            end
          end

          if bootstrap_only && instance_init && interface_config
            @bootstrap_configs << interface_config
          end

          if interface.nil?
            # Try loading as external interface (not supported in Crystal port)
            RNS.log("Unknown interface type \"#{interface_type}\" for interface \"#{name}\"", RNS::LOG_ERROR)
          end
        else
          RNS.log("Skipping disabled interface \"#{name}\"", RNS::LOG_DEBUG)
        end
      rescue ex
        RNS.log("The interface \"#{name}\" could not be created. Check your configuration file for errors!", RNS::LOG_ERROR)
        RNS.log("The contained exception was: #{ex.message}", RNS::LOG_ERROR)
        RNS.panic
      end
    end

    protected def interface_post_init(interface : Interface, *,
                                      interface_mode : UInt8,
                                      announce_cap : Float64,
                                      bootstrap_only : Bool,
                                      configured_bitrate : Int32?,
                                      ifac_size : Int32?,
                                      ifac_netname : String?,
                                      ifac_netkey : String?,
                                      ingress_control : Bool,
                                      ic_max_held_announces : Int32?,
                                      ic_burst_hold : Float64?,
                                      ic_burst_freq_new : Float64?,
                                      ic_burst_freq : Float64?,
                                      ic_new_time : Float64?,
                                      ic_burst_penalty : Float64?,
                                      ic_held_release_interval : Float64?,
                                      announce_rate_target : Int32?,
                                      announce_rate_grace : Int32?,
                                      announce_rate_penalty : Int32?,
                                      discoverable : Bool,
                                      discovery_announce_interval : Int32?,
                                      discovery_publish_ifac : Bool,
                                      reachable_on : String?,
                                      discovery_name : String?,
                                      discovery_encrypt : Bool,
                                      discovery_stamp_value : Int32?,
                                      discovery_latitude : Float64?,
                                      discovery_longitude : Float64?,
                                      discovery_height : Float64?,
                                      discovery_frequency : Int32?,
                                      discovery_bandwidth : Int32?,
                                      discovery_modulation : Int32?,
                                      outgoing : Bool)
      # Set direction
      if interface.responds_to?(:dir_out=)
        interface.dir_out = outgoing
      end

      interface.mode = interface_mode
      interface.announce_cap = announce_cap
      interface.bootstrap_only = bootstrap_only
      interface.bitrate = configured_bitrate.to_i64 if configured_bitrate
      interface.optimise_mtu

      if is = ifac_size
        interface.ifac_size = is
      else
        # Use the interface's own DEFAULT_IFAC_SIZE
        interface.ifac_size = get_default_ifac_size(interface)
      end

      # Discovery properties
      interface.discoverable = discoverable
      interface.discovery_announce_interval = discovery_announce_interval
      interface.discovery_publish_ifac = discovery_publish_ifac
      interface.reachable_on = reachable_on
      interface.discovery_name = discovery_name
      interface.discovery_encrypt = discovery_encrypt
      interface.discovery_stamp_value = discovery_stamp_value
      interface.discovery_latitude = discovery_latitude
      interface.discovery_longitude = discovery_longitude
      interface.discovery_height = discovery_height
      interface.discovery_frequency = discovery_frequency
      interface.discovery_bandwidth = discovery_bandwidth
      interface.discovery_modulation = discovery_modulation

      # Announce rate limiting
      interface.announce_rate_target = announce_rate_target
      interface.announce_rate_grace = announce_rate_grace
      interface.announce_rate_penalty = announce_rate_penalty

      # Ingress control
      interface.ingress_control = ingress_control
      interface.ic_max_held_announces = ic_max_held_announces if ic_max_held_announces
      interface.ic_burst_hold = ic_burst_hold.to_i32 if ic_burst_hold
      interface.ic_burst_freq_new = ic_burst_freq_new if ic_burst_freq_new
      interface.ic_burst_freq = ic_burst_freq if ic_burst_freq
      interface.ic_new_time = ic_new_time.to_i32 if ic_new_time
      interface.ic_burst_penalty = ic_burst_penalty.to_i32 if ic_burst_penalty
      interface.ic_held_release_interval = ic_held_release_interval.to_i32 if ic_held_release_interval

      # IFAC (Interface Authentication Code)
      interface.ifac_netname = ifac_netname
      interface.ifac_netkey = ifac_netkey

      if ifac_netname || ifac_netkey
        ifac_origin = IO::Memory.new

        if nn = ifac_netname
          ifac_origin.write(Identity.full_hash(nn.encode("UTF-8")))
        end

        if nk = ifac_netkey
          ifac_origin.write(Identity.full_hash(nk.encode("UTF-8")))
        end

        ifac_origin_hash = Identity.full_hash(ifac_origin.to_slice)
        interface.ifac_key = RNS::Cryptography.hkdf(
          length: 64,
          derive_from: ifac_origin_hash,
          salt: @ifac_salt,
          context: nil
        )

        if ik = interface.ifac_key
          interface.ifac_identity = Identity.from_bytes(ik)
          if ii = interface.ifac_identity
            interface.ifac_signature = ii.sign(Identity.full_hash(ik))
          end
        end
      end

      # Wire inbound callback so received data reaches Transport.inbound
      wire_transport_inbound_callback(interface)

      Transport.register_interface(interface)
      interface.final_init
    end

    # Get the default IFAC size for a given interface type
    private def get_default_ifac_size(interface : Interface) : Int32
      case interface
      when AutoInterface           then 16
      when BackboneInterface       then 16
      when BackboneClientInterface then 16
      when TCPServerInterface      then 16
      when TCPClientInterface      then 16
      when UDPInterface            then 16
      when I2PInterface            then 16
      when WeaveInterface          then 16
      when RNodeInterface          then 8
      when RNodeMultiInterface     then 8
      when SerialInterface         then 8
      when KISSInterface           then 8
      when AX25KISSInterface       then 8
      when PipeInterface           then 8
      else                              8
      end
    end

    private def parse_interface_mode(mode_str : String) : UInt8
      case mode_str
      when "full"
        Interface::MODE_FULL
      when "access_point", "accesspoint", "ap"
        Interface::MODE_ACCESS_POINT
      when "pointtopoint", "ptp"
        Interface::MODE_POINT_TO_POINT
      when "roaming"
        Interface::MODE_ROAMING
      when "boundary"
        Interface::MODE_BOUNDARY
      when "gateway", "gw"
        Interface::MODE_GATEWAY
      else
        Interface::MODE_FULL
      end
    end

    # Public API to add an interface programmatically (matching Python's _add_interface)
    def add_interface(interface : Interface, *,
                      mode : UInt8? = nil,
                      configured_bitrate : Int32? = nil,
                      ifac_size : Int32? = nil,
                      ifac_netname : String? = nil,
                      ifac_netkey : String? = nil,
                      announce_cap : Float64? = nil,
                      announce_rate_target : Int32? = nil,
                      announce_rate_grace : Int32? = nil,
                      announce_rate_penalty : Int32? = nil,
                      bootstrap_only : Bool = false)
      return if @is_connected_to_shared_instance

      actual_mode = mode || Interface::MODE_FULL
      interface.mode = actual_mode
      if interface.responds_to?(:dir_out=)
        interface.dir_out = true
      end

      interface.bitrate = configured_bitrate.to_i64 if configured_bitrate
      interface.bootstrap_only = true if bootstrap_only
      interface.optimise_mtu

      interface.ifac_size = ifac_size || 8
      interface.announce_cap = announce_cap || (Reticulum::ANNOUNCE_CAP / 100.0)
      interface.announce_rate_target = announce_rate_target
      interface.announce_rate_grace = announce_rate_grace
      interface.announce_rate_penalty = announce_rate_penalty

      interface.ifac_netname = ifac_netname
      interface.ifac_netkey = ifac_netkey

      if ifac_netname || ifac_netkey
        ifac_origin = IO::Memory.new

        if nn = ifac_netname
          ifac_origin.write(Identity.full_hash(nn.encode("UTF-8")))
        end

        if nk = ifac_netkey
          ifac_origin.write(Identity.full_hash(nk.encode("UTF-8")))
        end

        ifac_origin_hash = Identity.full_hash(ifac_origin.to_slice)
        interface.ifac_key = RNS::Cryptography.hkdf(
          length: 64,
          derive_from: ifac_origin_hash,
          salt: @ifac_salt,
          context: nil
        )

        if ik = interface.ifac_key
          interface.ifac_identity = Identity.from_bytes(ik)
          if ii = interface.ifac_identity
            interface.ifac_signature = ii.sign(Identity.full_hash(ik))
          end
        end
      end

      # Wire inbound callback so received data reaches Transport.inbound
      wire_transport_inbound_callback(interface)

      Transport.register_interface(interface)
      interface.final_init
    end

    private def wire_transport_inbound_callback(interface : Interface) : Nil
      case interface
      when AutoInterface
        interface.owner_inbound = Transport::INBOUND_DISPATCH
      when AutoInterfacePeer
        interface.inbound_callback = Transport::INBOUND_DISPATCH
      else
        interface.inbound_callback = Transport::INBOUND_DISPATCH
      end
      nil
    end

    # Removes a previously added interface. Deregisters from Transport,
    # detaches, and tears down the interface.
    def remove_interface(interface : Interface)
      Transport.deregister_interface(interface)
      interface.detach
      interface.teardown
    end

    # Remove an interface by name. Returns false if not found or protected.
    def remove_interface(name : String) : Bool
      interface = Transport.interface_objects.find { |i| i.name == name }
      return false unless interface
      return false if interface.management_protected
      Transport.deregister_interface(interface)
      interface.detach
      interface.teardown
      true
    end

    # Replace an interface (teardown + re-add from config section).
    def replace_interface(name : String, new_config : ConfigObj::Section) : Interface?
      existing = Transport.interface_objects.find { |i| i.name == name }
      if existing
        return nil if existing.management_protected
        remove_interface(name)
      end
      synthesize_interface(new_config, name)
      Transport.interface_objects.find { |i| i.name == name }
    end

    # Update IFAC credentials on a running interface without teardown.
    def update_interface_ifac(name : String, *,
                              network_name : String?, passphrase : String?,
                              ifac_size : UInt8?) : Bool
      interface = Transport.interface_objects.find { |i| i.name == name }
      return false unless interface
      interface.ifac_netname = network_name
      interface.ifac_netkey = passphrase
      interface.ifac_size = (ifac_size || 16_u8).to_i32
      interface.recompute_ifac_identity
      true
    end

    # Check if data should be persisted (used by other modules)
    def should_persist_data? : Bool
      Time.utc.to_unix_f > @last_data_persist + Reticulum::GRACIOUS_PERSIST_INTERVAL
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
