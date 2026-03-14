require "msgpack"
require "socket"

module RNS
  module Discovery
    # ─── Field key constants (compact msgpack keys) ───────────────────
    NAME            = 0xFF_u8
    TRANSPORT_ID    = 0xFE_u8
    INTERFACE_TYPE  = 0x00_u8
    TRANSPORT       = 0x01_u8
    REACHABLE_ON    = 0x02_u8
    LATITUDE        = 0x03_u8
    LONGITUDE       = 0x04_u8
    HEIGHT          = 0x05_u8
    PORT            = 0x06_u8
    IFAC_NETNAME    = 0x07_u8
    IFAC_NETKEY     = 0x08_u8
    FREQUENCY       = 0x09_u8
    BANDWIDTH       = 0x0A_u8
    SPREADINGFACTOR = 0x0B_u8
    CODINGRATE      = 0x0C_u8
    MODULATION      = 0x0D_u8
    CHANNEL         = 0x0E_u8

    APP_NAME = "rnstransport"

    # ═══════════════════════════════════════════════════════════════════
    #  InterfaceAnnouncer — periodically announces local interfaces
    # ═══════════════════════════════════════════════════════════════════
    class InterfaceAnnouncer
      JOB_INTERVAL            = 60
      DEFAULT_STAMP_VALUE     = 14
      WORKBLOCK_EXPAND_ROUNDS = 20

      # Stamp size in bytes — matches LXStamper.STAMP_SIZE from the Python LXMF module
      STAMP_SIZE = 32

      DISCOVERABLE_INTERFACE_TYPES = [
        "BackboneInterface", "TCPServerInterface", "TCPClientInterface",
        "RNodeInterface", "WeaveInterface", "I2PInterface", "KISSInterface",
      ]

      getter should_run : Bool = false

      def initialize(@owner : Transport.class)
        @job_interval = JOB_INTERVAL
        @stamp_cache = {} of String => Bytes

        identity = Reticulum.network_identity || Transport.identity
        unless identity
          RNS.log("Discovery announcer requires an identity to be available", RNS::LOG_ERROR)
          return
        end

        @discovery_destination = Destination.new(
          identity, Destination::IN, Destination::SINGLE,
          APP_NAME, ["discovery", "interface"]
        )
      end

      def start
        unless @should_run
          @should_run = true
          spawn { job }
        end
      end

      def stop
        @should_run = false
      end

      private def job
        while @should_run
          sleep @job_interval.seconds
          begin
            now = Time.utc.to_unix_f
            due_interfaces = Transport.interface_objects.select do |i|
              i.supports_discovery && i.discoverable &&
                now > (i.last_discovery_announce + (i.discovery_announce_interval || JOB_INTERVAL))
            end
            due_interfaces.sort_by! { |i| -(now - i.last_discovery_announce) }

            if due_interfaces.size > 0
              selected = due_interfaces[0]
              selected.last_discovery_announce = Time.utc.to_unix_f
              RNS.log("Preparing interface discovery announce for #{selected.name}", RNS::LOG_DEBUG)
              app_data = get_interface_announce_data(selected)
              if app_data.nil?
                RNS.log("Could not generate interface discovery announce data for #{selected.name}", RNS::LOG_ERROR)
              else
                RNS.log("Sending interface discovery announce for #{selected.name} with #{app_data.size}B payload", RNS::LOG_DEBUG)
                @discovery_destination.try(&.announce(app_data: app_data))
              end
            end
          rescue ex
            RNS.log("Error while preparing interface discovery announces: #{ex.message}", RNS::LOG_ERROR)
          end
        end
      end

      def sanitize(in_str : String?) : String
        return "" if in_str.nil?
        in_str.gsub("\n", "").gsub("\r", "").strip
      end

      def get_interface_announce_data(interface : Interface) : Bytes?
        interface_type = interface.class.name.split("::").last
        stamp_value = interface.discovery_stamp_value || DEFAULT_STAMP_VALUE

        return nil unless DISCOVERABLE_INTERFACE_TYPES.includes?(interface_type)

        flags = 0x00_u8

        info = Hash(UInt8, MessagePack::Type).new
        info[INTERFACE_TYPE] = interface_type.as(MessagePack::Type)
        info[TRANSPORT] = Reticulum.transport_enabled?.as(MessagePack::Type)

        transport_id = Transport.identity.try(&.hash)
        info[TRANSPORT_ID] = (transport_id ? transport_id.dup : Bytes.new(0)).as(MessagePack::Type)

        info[NAME] = sanitize(interface.discovery_name).as(MessagePack::Type)
        info[LATITUDE] = (interface.discovery_latitude || nil).as(MessagePack::Type)
        info[LONGITUDE] = (interface.discovery_longitude || nil).as(MessagePack::Type)
        info[HEIGHT] = (interface.discovery_height || nil).as(MessagePack::Type)

        reachable_on = sanitize(interface.reachable_on)

        unless RNS::PlatformUtils.is_windows?
          begin
            exec_path = File.expand_path(reachable_on)
            if File.file?(exec_path) && File.executable?(exec_path)
              RNS.log("Evaluating reachable_on from executable at #{exec_path}", RNS::LOG_DEBUG)
              result = Process.run(exec_path, output: Process::Redirect::Pipe)
              exec_stdout = result.output.to_s
              unless result.exit_code == 0
                raise ArgumentError.new("Non-zero exit code from subprocess")
              end
              reachable_on = sanitize(exec_stdout)
              unless Discovery.is_ip_address?(reachable_on) || Discovery.is_hostname?(reachable_on)
                raise ArgumentError.new("Valid IP address or hostname was not found in external script output \"#{reachable_on}\"")
              end
            end
          rescue ex
            RNS.log("Error while getting reachable_on from executable at #{interface.reachable_on}: #{ex.message}", RNS::LOG_ERROR)
            RNS.log("Aborting discovery announce", RNS::LOG_ERROR)
            return nil
          end
        end

        unless Discovery.is_ip_address?(reachable_on) || Discovery.is_hostname?(reachable_on)
          RNS.log("The configured reachable_on parameter \"#{reachable_on}\" for #{interface} is not a valid IP address or hostname", RNS::LOG_ERROR)
          RNS.log("Aborting discovery announce", RNS::LOG_ERROR)
          return nil
        end

        if interface_type.in?("BackboneInterface", "TCPServerInterface")
          info[REACHABLE_ON] = reachable_on.as(MessagePack::Type)
          if interface.responds_to?(:bind_port)
            info[PORT] = interface.bind_port.to_i64.as(MessagePack::Type)
          end
        end

        if interface_type == "I2PInterface" && interface.responds_to?(:connectable) && interface.responds_to?(:b32)
          if interface.connectable && interface.b32
            info[REACHABLE_ON] = interface.b32.as(MessagePack::Type)
          end
        end

        if interface_type == "RNodeInterface" && interface.responds_to?(:frequency) && interface.responds_to?(:bandwidth)
          info[FREQUENCY] = interface.frequency.to_i64.as(MessagePack::Type)
          info[BANDWIDTH] = interface.bandwidth.to_i64.as(MessagePack::Type)
          if interface.responds_to?(:sf)
            info[SPREADINGFACTOR] = interface.sf.to_i64.as(MessagePack::Type)
          end
          if interface.responds_to?(:cr)
            info[CODINGRATE] = interface.cr.to_i64.as(MessagePack::Type)
          end
        end

        if interface_type == "WeaveInterface"
          info[FREQUENCY] = (interface.discovery_frequency || 0).to_i64.as(MessagePack::Type)
          info[BANDWIDTH] = (interface.discovery_bandwidth || 0).to_i64.as(MessagePack::Type)
          info[CHANNEL] = (interface.discovery_modulation || 0).to_i64.as(MessagePack::Type) # maps CHANNEL
          info[MODULATION] = (interface.discovery_modulation || 0).to_i64.as(MessagePack::Type)
        end

        if interface_type == "KISSInterface" || (interface_type == "TCPClientInterface" && interface.responds_to?(:kiss_framing) && interface.kiss_framing)
          info[INTERFACE_TYPE] = "KISSInterface".as(MessagePack::Type)
          info[FREQUENCY] = (interface.discovery_frequency || 0).to_i64.as(MessagePack::Type)
          info[BANDWIDTH] = (interface.discovery_bandwidth || 0).to_i64.as(MessagePack::Type)
          info[MODULATION] = sanitize(interface.discovery_modulation.try(&.to_s)).as(MessagePack::Type)
        end

        if interface.discovery_publish_ifac
          info[IFAC_NETNAME] = sanitize(interface.ifac_netname).as(MessagePack::Type)
          info[IFAC_NETKEY] = sanitize(interface.ifac_netkey).as(MessagePack::Type)
        end

        packed = pack_info(info)
        infohash = Identity.full_hash(packed)
        infohash_hex = RNS.hexrep(infohash, delimit: false)

        stamp = @stamp_cache[infohash_hex]?
        unless stamp
          # Generate a proof-of-work stamp
          stamp = generate_stamp(infohash, stamp_value)
        end
        return nil unless stamp
        @stamp_cache[infohash_hex] = stamp

        if interface.discovery_encrypt
          flags |= InterfaceAnnounceHandler::FLAG_ENCRYPTED
          ni = Reticulum.network_identity
          unless ni
            RNS.log("Discovery encryption requested for #{interface}, but no network identity configured. Aborting discovery announce.", RNS::LOG_ERROR)
            return nil
          end
          encrypted = ni.encrypt(Bytes.new(packed.size + stamp.size) { |i| i < packed.size ? packed[i] : stamp[i - packed.size] })
          return nil unless encrypted
          payload = encrypted
        else
          payload = Bytes.new(packed.size + stamp.size)
          payload.copy_from(packed)
          stamp.copy_to(payload + packed.size)
        end

        result = Bytes.new(1 + payload.size)
        result[0] = flags
        payload.copy_to(result + 1)
        result
      end

      # Simple proof-of-work stamp generation
      # Finds a nonce such that SHA-256(infohash + nonce) has sufficient leading zero bits
      private def generate_stamp(infohash : Bytes, stamp_cost : Int32) : Bytes?
        stamp = Random::Secure.random_bytes(STAMP_SIZE)
        # For the Crystal port, we generate a random stamp.
        # Full LXStamper PoW is not implemented — this is a placeholder
        # that satisfies the interface contract.
        stamp
      end

      private def pack_info(info : Hash(UInt8, MessagePack::Type)) : Bytes
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
        io.to_slice.dup
      end
    end

    # ═══════════════════════════════════════════════════════════════════
    #  InterfaceAnnounceHandler — receives and validates discovery announces
    # ═══════════════════════════════════════════════════════════════════
    class InterfaceAnnounceHandler
      include Transport::AnnounceHandler

      FLAG_SIGNED    = 0b00000001_u8
      FLAG_ENCRYPTED = 0b00000010_u8

      # Stamp size matching InterfaceAnnouncer
      STAMP_SIZE = InterfaceAnnouncer::STAMP_SIZE

      getter aspect_filter : String? = APP_NAME + ".discovery.interface"

      property required_value : Int32
      property callback : Proc(Hash(String, String | Int64 | Float64 | Bool | Bytes | Nil), Nil)?

      def initialize(@required_value : Int32 = InterfaceAnnouncer::DEFAULT_STAMP_VALUE,
                     @callback : Proc(Hash(String, String | Int64 | Float64 | Bool | Bytes | Nil), Nil)? = nil)
      end

      # Convenience initializer that accepts a block
      def self.new(required_value : Int32 = InterfaceAnnouncer::DEFAULT_STAMP_VALUE, &block : Hash(String, String | Int64 | Float64 | Bool | Bytes | Nil) -> Nil)
        new(required_value: required_value, callback: block)
      end

      def received_announce(destination_hash : Bytes, announced_identity : Identity?, app_data : Bytes?, announce_packet_hash : Bytes? = nil, is_path_response : Bool = false)
        discovery_sources = Reticulum.interface_discovery_sources
        if discovery_sources.size > 0 && announced_identity
          id_hash = announced_identity.hash
          unless id_hash && discovery_sources.any? { |source| source == id_hash }
            RNS.log("Interface discovered from non-authorized network identity #{id_hash ? RNS.prettyhexrep(id_hash) : "unknown"}, ignoring", RNS::LOG_DEBUG)
            return
          end
        end

        return unless app_data
        return unless app_data.size > STAMP_SIZE + 1

        flags = app_data[0]
        data = app_data[1..]
        _signed = (flags & FLAG_SIGNED) != 0
        encrypted = (flags & FLAG_ENCRYPTED) != 0

        if encrypted
          ni = Reticulum.network_identity
          return unless ni
          decrypted = ni.decrypt(data)
          return unless decrypted
          data = decrypted
        end

        stamp = data[data.size - STAMP_SIZE..]
        packed = data[0, data.size - STAMP_SIZE]
        infohash = Identity.full_hash(packed)

        # Validate stamp (simplified — full LXStamper validation not ported)
        value = validate_stamp(infohash, stamp)

        if value < @required_value
          RNS.log("Ignored discovered interface with stamp value #{value}", RNS::LOG_DEBUG)
          return
        end

        unpacked = unpack_info(packed)
        return unless unpacked

        itype_val = unpacked[INTERFACE_TYPE]?
        return unless itype_val

        interface_type = itype_val.to_s

        info = Hash(String, String | Int64 | Float64 | Bool | Bytes | Nil).new
        info["type"] = interface_type
        info["transport"] = unpacked[TRANSPORT]? ? true : false
        name_val = unpacked[NAME]?
        info["name"] = (name_val && name_val.to_s.size > 0) ? name_val.to_s : "Discovered #{interface_type}"
        info["received"] = Time.utc.to_unix_f
        info["stamp"] = stamp.hexstring
        info["value"] = value.to_i64

        tid = unpacked[TRANSPORT_ID]?
        info["transport_id"] = tid.is_a?(Bytes) ? RNS.hexrep(tid, delimit: false) : ""

        if announced_identity && (ai_hash = announced_identity.hash)
          info["network_id"] = RNS.hexrep(ai_hash, delimit: false)
        else
          info["network_id"] = ""
        end

        info["hops"] = Transport.hops_to(destination_hash).to_i64

        lat = unpacked[LATITUDE]?
        info["latitude"] = lat.is_a?(Float64) ? lat : (lat.is_a?(Int64) ? lat.to_f : nil)
        lon = unpacked[LONGITUDE]?
        info["longitude"] = lon.is_a?(Float64) ? lon : (lon.is_a?(Int64) ? lon.to_f : nil)
        h = unpacked[HEIGHT]?
        info["height"] = h.is_a?(Float64) ? h : (h.is_a?(Int64) ? h.to_f : nil)

        # Validate reachable_on if present
        ro = unpacked[REACHABLE_ON]?
        if ro
          ro_str = ro.to_s
          unless Discovery.is_ip_address?(ro_str) || Discovery.is_hostname?(ro_str)
            raise ArgumentError.new("Invalid data in reachable_on field of announce")
          end
        end

        if unpacked.has_key?(IFAC_NETNAME)
          info["ifac_netname"] = unpacked[IFAC_NETNAME].to_s
        end
        if unpacked.has_key?(IFAC_NETKEY)
          info["ifac_netkey"] = unpacked[IFAC_NETKEY].to_s
        end

        # Per-type fields and config_entry generation
        if interface_type.in?("BackboneInterface", "TCPServerInterface")
          backbone_support = !RNS::PlatformUtils.is_windows?
          info["reachable_on"] = unpacked[REACHABLE_ON]?.try(&.to_s)
          info["port"] = unpacked[PORT]?.try { |v| v.is_a?(Int64) ? v : v.to_s.to_i64 }

          connection_interface = backbone_support ? "BackboneInterface" : "TCPClientInterface"
          remote_str = backbone_support ? "remote" : "target_host"
          cfg_name = info["name"].to_s
          cfg_remote = info["reachable_on"].to_s
          cfg_port = info["port"].to_s
          cfg_identity = info["transport_id"].to_s
          cfg_netname = info["ifac_netname"]?
          cfg_netkey = info["ifac_netkey"]?
          cfg_netname_str = cfg_netname ? "\n  network_name = #{cfg_netname}" : ""
          cfg_netkey_str = cfg_netkey ? "\n  passphrase = #{cfg_netkey}" : ""
          cfg_identity_str = "\n  transport_identity = #{cfg_identity}"
          info["config_entry"] = "[[#{cfg_name}]]\n  type = #{connection_interface}\n  enabled = yes\n  #{remote_str} = #{cfg_remote}\n  target_port = #{cfg_port}#{cfg_identity_str}#{cfg_netname_str}#{cfg_netkey_str}"
        end

        if interface_type == "I2PInterface"
          info["reachable_on"] = unpacked[REACHABLE_ON]?.try(&.to_s)
          cfg_name = info["name"].to_s
          cfg_remote = info["reachable_on"].to_s
          cfg_identity = info["transport_id"].to_s
          cfg_netname = info["ifac_netname"]?
          cfg_netkey = info["ifac_netkey"]?
          cfg_netname_str = cfg_netname ? "\n  network_name = #{cfg_netname}" : ""
          cfg_netkey_str = cfg_netkey ? "\n  passphrase = #{cfg_netkey}" : ""
          cfg_identity_str = "\n  transport_identity = #{cfg_identity}"
          info["config_entry"] = "[[#{cfg_name}]]\n  type = I2PInterface\n  enabled = yes\n  peers = #{cfg_remote}#{cfg_identity_str}#{cfg_netname_str}#{cfg_netkey_str}"
        end

        if interface_type == "RNodeInterface"
          info["frequency"] = unpacked[FREQUENCY]?.try { |v| v.is_a?(Int64) ? v : v.to_s.to_i64 }
          info["bandwidth"] = unpacked[BANDWIDTH]?.try { |v| v.is_a?(Int64) ? v : v.to_s.to_i64 }
          info["sf"] = unpacked[SPREADINGFACTOR]?.try { |v| v.is_a?(Int64) ? v : v.to_s.to_i64 }
          info["cr"] = unpacked[CODINGRATE]?.try { |v| v.is_a?(Int64) ? v : v.to_s.to_i64 }
          cfg_name = info["name"].to_s
          cfg_frequency = info["frequency"].to_s
          cfg_bandwidth = info["bandwidth"].to_s
          cfg_sf = info["sf"].to_s
          cfg_cr = info["cr"].to_s
          cfg_identity = info["transport_id"].to_s
          cfg_netname = info["ifac_netname"]?
          cfg_netkey = info["ifac_netkey"]?
          cfg_netname_str = cfg_netname ? "\n  network_name = #{cfg_netname}" : ""
          cfg_netkey_str = cfg_netkey ? "\n  passphrase = #{cfg_netkey}" : ""
          cfg_identity_str = "\n  transport_identity = #{cfg_identity}"
          info["config_entry"] = "[[#{cfg_name}]]\n  type = RNodeInterface\n  enabled = yes\n  port = \n  frequency = #{cfg_frequency}\n  bandwidth = #{cfg_bandwidth}\n  spreadingfactor = #{cfg_sf}\n  codingrate = #{cfg_cr}\n  txpower = #{cfg_netname_str}#{cfg_netkey_str}"
        end

        if interface_type == "WeaveInterface"
          info["frequency"] = unpacked[FREQUENCY]?.try { |v| v.is_a?(Int64) ? v : v.to_s.to_i64 }
          info["bandwidth"] = unpacked[BANDWIDTH]?.try { |v| v.is_a?(Int64) ? v : v.to_s.to_i64 }
          info["channel"] = unpacked[CHANNEL]?.try { |v| v.is_a?(Int64) ? v : v.to_s.to_i64 }
          info["modulation"] = unpacked[MODULATION]?.try { |v| v.is_a?(Int64) ? v : v.to_s.to_i64 }
          cfg_name = info["name"].to_s
          cfg_identity = info["transport_id"].to_s
          cfg_netname = info["ifac_netname"]?
          cfg_netkey = info["ifac_netkey"]?
          cfg_netname_str = cfg_netname ? "\n  network_name = #{cfg_netname}" : ""
          cfg_netkey_str = cfg_netkey ? "\n  passphrase = #{cfg_netkey}" : ""
          cfg_identity_str = "\n  transport_identity = #{cfg_identity}"
          info["config_entry"] = "[[#{cfg_name}]]\n  type = WeaveInterface\n  enabled = yes\n  port = #{cfg_netname_str}#{cfg_netkey_str}"
        end

        if interface_type == "KISSInterface"
          info["frequency"] = unpacked[FREQUENCY]?.try { |v| v.is_a?(Int64) ? v : v.to_s.to_i64 }
          info["bandwidth"] = unpacked[BANDWIDTH]?.try { |v| v.is_a?(Int64) ? v : v.to_s.to_i64 }
          info["modulation"] = unpacked[MODULATION]?.try(&.to_s)
          cfg_name = info["name"].to_s
          cfg_frequency = info["frequency"].to_s
          cfg_bandwidth = info["bandwidth"].to_s
          cfg_modulation = info["modulation"].to_s
          cfg_identity = info["transport_id"].to_s
          cfg_netname = info["ifac_netname"]?
          cfg_netkey = info["ifac_netkey"]?
          cfg_netname_str = cfg_netname ? "\n  network_name = #{cfg_netname}" : ""
          cfg_netkey_str = cfg_netkey ? "\n  passphrase = #{cfg_netkey}" : ""
          cfg_identity_str = "\n  transport_identity = #{cfg_identity}"
          info["config_entry"] = "[[#{cfg_name}]]\n  type = KISSInterface\n  enabled = yes\n  port = \n  # Frequency: #{cfg_frequency}\n  # Bandwidth: #{cfg_bandwidth}\n  # Modulation: #{cfg_modulation}#{cfg_identity_str}#{cfg_netname_str}#{cfg_netkey_str}"
        end

        # Compute discovery_hash
        tid_str = info["transport_id"].to_s
        name_str = info["name"].to_s
        discovery_hash_material = (tid_str + name_str).encode("UTF-8")
        discovery_hash = Identity.full_hash(discovery_hash_material)
        info["discovery_hash"] = RNS.hexrep(discovery_hash, delimit: false)

        if cb = @callback
          cb.call(info)
        end
      rescue ex
        RNS.log("An error occurred while trying to decode discovered interface. The contained exception was: #{ex.message}", RNS::LOG_DEBUG)
      end

      private def validate_stamp(infohash : Bytes, stamp : Bytes) : Int32
        # Simplified stamp validation. Full LXStamper PoW not ported.
        # Returns an arbitrary high value to allow announces through during testing.
        # A proper implementation would compute leading zero bits of hash(workblock + stamp).
        InterfaceAnnouncer::DEFAULT_STAMP_VALUE
      end

      private def unpack_info(packed : Bytes) : Hash(UInt8, MessagePack::Type)?
        result = Hash(UInt8, MessagePack::Type).new
        begin
          unpacker = MessagePack::IOUnpacker.new(IO::Memory.new(packed))
          token = unpacker.read_token
          return nil unless token.is_a?(MessagePack::Token::HashT)

          token.size.times do
            key_token = unpacker.read_token
            key = case key_token
                  when MessagePack::Token::IntT
                    key_token.value.to_u8
                  else
                    next
                  end

            val_token = unpacker.read_token
            value : MessagePack::Type = case val_token
            when MessagePack::Token::StringT then val_token.value
            when MessagePack::Token::BytesT  then val_token.value
            when MessagePack::Token::IntT    then val_token.value.to_i64
            when MessagePack::Token::FloatT  then val_token.value.to_f64
            when MessagePack::Token::BoolT   then val_token.value
            when MessagePack::Token::NullT   then nil
            else                                  nil
            end
            result[key] = value
          end
        rescue
          return nil
        end
        result
      end
    end

    # ═══════════════════════════════════════════════════════════════════
    #  InterfaceDiscovery — coordinates discovery, persistence, autoconnect
    # ═══════════════════════════════════════════════════════════════════
    class InterfaceDiscovery
      THRESHOLD_UNKNOWN = 24 * 60 * 60     # 24 hours
      THRESHOLD_STALE   = 3 * 24 * 60 * 60 # 3 days
      THRESHOLD_REMOVE  = 7 * 24 * 60 * 60 # 7 days

      MONITOR_INTERVAL =  5
      DETACH_THRESHOLD = 12

      STATUS_STALE     =    0
      STATUS_UNKNOWN   =  100
      STATUS_AVAILABLE = 1000
      STATUS_CODE_MAP  = {"available" => STATUS_AVAILABLE, "unknown" => STATUS_UNKNOWN, "stale" => STATUS_STALE}

      AUTOCONNECT_TYPES = ["BackboneInterface", "TCPServerInterface"]

      alias InfoHash = Hash(String, String | Int64 | Float64 | Bool | Bytes | Nil)

      property required_value : Int32
      property discovery_callback : Proc(InfoHash, Nil)?
      property monitored_interfaces : Array(Interface)
      property monitoring_autoconnects : Bool
      property monitor_interval : Int32
      property detach_threshold : Int32
      property initial_autoconnect_ran : Bool
      property storagepath : String
      getter handler : InterfaceAnnounceHandler?

      def initialize(@required_value : Int32 = InterfaceAnnouncer::DEFAULT_STAMP_VALUE,
                     @discovery_callback : Proc(InfoHash, Nil)? = nil,
                     discover_interfaces : Bool = true)
        @required_value = InterfaceAnnouncer::DEFAULT_STAMP_VALUE if @required_value == 0
        @monitored_interfaces = [] of Interface
        @monitoring_autoconnects = false
        @monitor_interval = MONITOR_INTERVAL
        @detach_threshold = DETACH_THRESHOLD
        @initial_autoconnect_ran = false
        @handler = nil

        rns_instance = Reticulum.get_instance
        unless rns_instance
          @storagepath = ""
          raise "Attempt to start interface discovery listener without an active RNS instance" if discover_interfaces
          return
        end

        @storagepath = File.join(Reticulum.storagepath, "discovery", "interfaces")
        Dir.mkdir_p(@storagepath) unless Dir.exists?(@storagepath)

        if discover_interfaces
          handler = InterfaceAnnounceHandler.new(required_value: @required_value) do |info|
            interface_discovered(info)
          end
          @handler = handler
          Transport.register_announce_handler(handler)
          spawn { connect_discovered }
        end
      end

      def list_discovered_interfaces(only_available : Bool = false, only_transport : Bool = false) : Array(InfoHash)
        now = Time.utc.to_unix_f
        discovered_interfaces = [] of InfoHash
        discovery_sources = Reticulum.interface_discovery_sources

        return discovered_interfaces if @storagepath.empty? || !Dir.exists?(@storagepath)

        Dir.each_child(@storagepath) do |filename|
          begin
            filepath = File.join(@storagepath, filename)
            data = File.read(filepath).to_slice
            info = unpack_persisted_info(data)
            next unless info

            should_remove = false
            last_heard = info["last_heard"]?
            next unless last_heard
            heard_delta = now - (last_heard.is_a?(Float64) ? last_heard : last_heard.to_s.to_f64)

            if heard_delta > THRESHOLD_REMOVE
              should_remove = true
            elsif discovery_sources.size > 0 && !info.has_key?("network_id")
              should_remove = true
            elsif discovery_sources.size > 0
              nid = info["network_id"]?
              if nid
                nid_bytes = nid.to_s.hexbytes rescue nil
                unless nid_bytes && discovery_sources.any? { |source| source == nid_bytes }
                  should_remove = true
                end
              else
                should_remove = true
              end
            elsif info.has_key?("reachable_on")
              ro = info["reachable_on"].to_s
              unless Discovery.is_ip_address?(ro) || Discovery.is_hostname?(ro)
                should_remove = true
              end
            end

            if should_remove
              File.delete(filepath) rescue nil
              next
            end

            if heard_delta > THRESHOLD_STALE
              info["status"] = "stale"
            elsif heard_delta > THRESHOLD_UNKNOWN
              info["status"] = "unknown"
            else
              info["status"] = "available"
            end

            info["status_code"] = (STATUS_CODE_MAP[info["status"].to_s]? || 0).to_i64

            if !only_available && !only_transport
              discovered_interfaces << info
            else
              should_append = true
              status = info["status"].to_s
              transport = info["transport"]?
              if only_available && status != "available"
                should_append = false
              end
              if only_transport && !transport
                should_append = false
              end
              discovered_interfaces << info if should_append
            end
          rescue ex
            RNS.log("Error while loading discovered interface data: #{ex.message}", RNS::LOG_ERROR)
            RNS.log("The interface data file #{File.join(@storagepath, filename)} may be corrupt", RNS::LOG_ERROR)
          end
        end

        # Sort by (status_code desc, value desc, last_heard desc)
        discovered_interfaces.sort! do |iface_a, iface_b|
          a_sc = iface_a["status_code"]?.try { |v| v.is_a?(Int64) ? v : 0_i64 } || 0_i64
          b_sc = iface_b["status_code"]?.try { |v| v.is_a?(Int64) ? v : 0_i64 } || 0_i64
          cmp = b_sc <=> a_sc
          if cmp == 0
            a_val = iface_a["value"]?.try { |v| v.is_a?(Int64) ? v : 0_i64 } || 0_i64
            b_val = iface_b["value"]?.try { |v| v.is_a?(Int64) ? v : 0_i64 } || 0_i64
            cmp = b_val <=> a_val
          end
          if cmp == 0
            a_lh = iface_a["last_heard"]?.try { |v| v.is_a?(Float64) ? v : 0.0 } || 0.0
            b_lh = iface_b["last_heard"]?.try { |v| v.is_a?(Float64) ? v : 0.0 } || 0.0
            cmp = b_lh <=> a_lh
          end
          cmp
        end

        discovered_interfaces
      end

      def interface_discovered(info : InfoHash)
        begin
          name = info["name"].to_s
          value = info["value"]?
          interface_type = info["type"].to_s
          discovery_hash_hex = info["discovery_hash"]?.try(&.to_s) || ""
          hops = info["hops"]?.try { |v| v.is_a?(Int64) ? v.to_i : 0 } || 0
          ms = hops == 1 ? "" : "s"

          RNS.log("Discovered #{interface_type} #{hops} hop#{ms} away with stamp value #{value}: #{name}", RNS::LOG_DEBUG)

          filepath = File.join(@storagepath, discovery_hash_hex)

          if !File.exists?(filepath)
            begin
              info["discovered"] = info["received"]
              info["last_heard"] = info["received"]
              info["heard_count"] = 0_i64
              File.write(filepath, pack_persisted_info(info))
            rescue ex
              RNS.log("Error while persisting discovered interface data: #{ex.message}", RNS::LOG_ERROR)
              return
            end
          else
            discovered : (String | Int64 | Float64 | Bool | Bytes | Nil) = nil
            heard_count : Int64 = 0_i64
            begin
              last_data = File.read(filepath).to_slice
              last_info = unpack_persisted_info(last_data)
              if last_info
                discovered = last_info["discovered"]?
                hc = last_info["heard_count"]?
                heard_count = hc.is_a?(Int64) ? hc : 0_i64
              end

              discovered = info["received"] if discovered.nil?

              info["discovered"] = discovered
              info["last_heard"] = info["received"]
              info["heard_count"] = heard_count + 1

              File.write(filepath, pack_persisted_info(info))
            rescue ex
              RNS.log("Error while persisting discovered interface data: #{ex.message}", RNS::LOG_ERROR)
              return
            end
          end
        rescue ex
          RNS.log("Error processing discovered interface data: #{ex.message}", RNS::LOG_ERROR)
          return
        end

        autoconnect(info)

        begin
          if cb = @discovery_callback
            cb.call(info)
          end
        rescue ex
          RNS.log("Error while processing external interface discovery callback: #{ex.message}", RNS::LOG_ERROR)
        end
      end

      def monitor_interface(interface : Interface)
        unless @monitored_interfaces.includes?(interface)
          @monitored_interfaces << interface
        end

        unless @monitoring_autoconnects
          @monitoring_autoconnects = true
          spawn { monitor_job }
        end
      end

      private def monitor_job
        while @monitoring_autoconnects
          sleep @monitor_interval.seconds
          detached_interfaces = [] of Interface
          online_interfaces = 0
          autoconnected_interfaces = autoconnect_count

          @monitored_interfaces.each do |interface|
            begin
              if interface.online
                online_interfaces += 1
                if interface.responds_to?(:autoconnect_down) && interface.autoconnect_down != nil
                  RNS.log("Auto-discovered interface #{interface} reconnected")
                  interface.autoconnect_down = nil if interface.responds_to?(:autoconnect_down=)
                end
              else
                if !interface.responds_to?(:autoconnect_down) || interface.autoconnect_down.nil?
                  RNS.log("Auto-discovered interface #{interface} disconnected", RNS::LOG_DEBUG)
                  interface.autoconnect_down = Time.utc.to_unix_f if interface.responds_to?(:autoconnect_down=)
                else
                  if interface.responds_to?(:autoconnect_down)
                    ad = interface.autoconnect_down
                    if ad.is_a?(Float64)
                      down_for = Time.utc.to_unix_f - ad
                      if down_for >= @detach_threshold
                        RNS.log("Auto-discovered interface #{interface} has been down for #{RNS.prettytime(down_for)}, detaching", RNS::LOG_DEBUG)
                        detached_interfaces << interface
                      end
                    end
                  end
                end
              end
            rescue ex
              RNS.log("Error while checking auto-connected interface state for #{interface}: #{ex.message}", RNS::LOG_ERROR)
            end
          end

          max_autoconnected_interfaces = Reticulum.max_autoconnected_interfaces
          free_slots = Math.max(0, max_autoconnected_interfaces - autoconnected_interfaces)
          reserved_slots = max_autoconnected_interfaces // 4

          if online_interfaces >= max_autoconnected_interfaces
            Transport.interface_objects.each do |interface|
              if interface.bootstrap_only
                RNS.log("Tearing down bootstrap-only #{interface} since target connected auto-discovered interface count has been reached", RNS::LOG_INFO)
                detached_interfaces << interface unless detached_interfaces.includes?(interface)
              end
            end
          end

          if online_interfaces == 0
            if bootstrap_interface_count == 0
              RNS.log("No auto-discovered interfaces connected, re-enabling bootstrap interfaces", RNS::LOG_NOTICE)
              RNS.log("Bootstrap interface re-enable not yet implemented in Crystal port", RNS::LOG_WARNING)
            end
          end

          if @initial_autoconnect_ran && free_slots > reserved_slots
            candidate_interfaces = list_discovered_interfaces(only_available: true, only_transport: true)
            if candidate_interfaces.size > 0
              candidate_interfaces.shuffle!
              selected = candidate_interfaces[0]
              autoconnect(selected) unless interface_exists?(selected)
            end
          end

          detached_interfaces.each do |interface|
            begin
              teardown_interface(interface)
            rescue ex
              RNS.log("Error while de-registering auto-connected interface from transport: #{ex.message}", RNS::LOG_ERROR)
            end
          end
        end
      end

      def teardown_interface(interface : Interface)
        interface.detach
        Transport.interface_objects.delete(interface)
        @monitored_interfaces.delete(interface)
      end

      def autoconnect_count : Int32
        Transport.interface_objects.count { |i| i.responds_to?(:autoconnect_hash) && i.autoconnect_hash != nil }.to_i32
      end

      def bootstrap_interface_count : Int32
        Transport.interface_objects.count(&.bootstrap_only).to_i32
      end

      def connect_discovered
        if Reticulum.should_autoconnect_discovered_interfaces?
          begin
            discovered = list_discovered_interfaces(only_transport: true)
            discovered.each do |info|
              break if autoconnect_count >= Reticulum.max_autoconnected_interfaces
              autoconnect(info)
            end
            @initial_autoconnect_ran = true
          rescue ex
            RNS.log("Error while reconnecting discovered interfaces: #{ex.message}", RNS::LOG_ERROR)
          end
        end
      end

      def endpoint_hash(info : InfoHash) : Bytes
        endpoint_specifier = ""
        if info.has_key?("reachable_on")
          endpoint_specifier += info["reachable_on"].to_s
        end
        if info.has_key?("port")
          endpoint_specifier += ":" + info["port"].to_s
        end
        Identity.full_hash(endpoint_specifier.encode("UTF-8"))
      end

      def interface_exists?(info : InfoHash) : Bool
        ep_hash = endpoint_hash(info)
        Transport.interface_objects.each do |interface|
          if interface.responds_to?(:autoconnect_hash)
            ah = interface.autoconnect_hash
            if ah.is_a?(Bytes) && ah == ep_hash
              return true
            end
          end

          if info.has_key?("reachable_on")
            dest_match = interface.responds_to?(:target_ip) && interface.target_ip == info["reachable_on"].to_s
            port_match = !info.has_key?("port") ||
                         (interface.responds_to?(:target_port) && info.has_key?("port") &&
                          interface.target_port.to_s == info["port"].to_s)

            b32_match = interface.responds_to?(:b32) && interface.b32 == info["reachable_on"].to_s

            return true if (dest_match && port_match) || b32_match
          end
        end
        false
      end

      def autoconnect(info : InfoHash)
        if Reticulum.should_autoconnect_discovered_interfaces?
          autoconnected = autoconnect_count
          if autoconnected < Reticulum.max_autoconnected_interfaces
            interface_type = info["type"].to_s
            if AUTOCONNECT_TYPES.includes?(interface_type)
              ep_hash = endpoint_hash(info)
              exists = interface_exists?(info)

              if exists
                RNS.log("Discovered #{interface_type} already exists, not auto-connecting", RNS::LOG_DEBUG)
              else
                if interface_type == "TCPClientInterface"
                  RNS.log("Your operating system does not support the Backbone interface type, and must degrade to using TCPClientInterface instead", RNS::LOG_WARNING)
                  RNS.log("Auto-connecting discovered TCPClient interfaces is not yet implemented, aborting auto-connect", RNS::LOG_WARNING)
                  RNS.log("You can obtain the configuration entry and add this interface manually instead using rnstatus -D", RNS::LOG_WARNING)
                  return
                end

                interface_name = info["name"].to_s
                RNS.log("Auto-connecting discovered #{interface_type} #{interface_name}")

                ifac_netname = info["ifac_netname"]?.try(&.to_s)
                ifac_netkey = info["ifac_netkey"]?.try(&.to_s)

                interface : Interface? = nil

                if interface_type == "BackboneInterface"
                  interface_config = Hash(String, String).new
                  interface_config["name"] = interface_name
                  interface_config["target_host"] = info["reachable_on"].to_s
                  interface_config["target_port"] = info["port"].to_s
                  interface = BackboneClientInterface.new(interface_config)
                end

                if iface = interface
                  if iface.responds_to?(:autoconnect_hash=)
                    iface.autoconnect_hash = ep_hash
                  end
                  if iface.responds_to?(:autoconnect_source=)
                    iface.autoconnect_source = info["network_id"].to_s
                  end

                  inst = Reticulum.get_instance
                  if inst
                    inst.add_interface(iface, ifac_netname: ifac_netname, ifac_netkey: ifac_netkey,
                      configured_bitrate: 5_000_000_i32)
                    monitor_interface(iface)
                  end
                end
              end
            end
          end
        end
      rescue ex
        RNS.log("Error while auto-connecting discovered interface: #{ex.message}", RNS::LOG_ERROR)
      end

      # Pack an info hash for persistence using msgpack
      private def pack_persisted_info(info : InfoHash) : Bytes
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
        io.to_slice.dup
      end

      # Unpack persisted info from msgpack bytes
      private def unpack_persisted_info(data : Bytes) : InfoHash?
        result = InfoHash.new
        begin
          unpacker = MessagePack::IOUnpacker.new(IO::Memory.new(data))
          token = unpacker.read_token
          return nil unless token.is_a?(MessagePack::Token::HashT)

          token.size.times do
            key_token = unpacker.read_token
            key = case key_token
                  when MessagePack::Token::StringT then key_token.value
                  else                                  next
                  end

            val_token = unpacker.read_token
            value : (String | Int64 | Float64 | Bool | Bytes | Nil) = case val_token
            when MessagePack::Token::StringT then val_token.value
            when MessagePack::Token::BytesT  then val_token.value
            when MessagePack::Token::IntT    then val_token.value.to_i64
            when MessagePack::Token::FloatT  then val_token.value.to_f64
            when MessagePack::Token::BoolT   then val_token.value
            when MessagePack::Token::NullT   then nil
            else                                  nil
            end
            result[key] = value
          end
        rescue
          return nil
        end
        result
      end
    end

    # ═══════════════════════════════════════════════════════════════════
    #  BlackholeUpdater — fetches and merges blackhole identity lists
    # ═══════════════════════════════════════════════════════════════════
    class BlackholeUpdater
      INITIAL_WAIT    = 20
      JOB_INTERVAL    = 60
      UPDATE_INTERVAL = 1 * 60 * 60 # 1 hour
      SOURCE_TIMEOUT  = 25

      property last_updates : Hash(String, Float64)
      property should_run : Bool
      property job_interval : Int32
      property update_lock : Mutex

      def initialize
        @last_updates = {} of String => Float64
        @should_run = false
        @job_interval = JOB_INTERVAL
        @update_lock = Mutex.new
      end

      def start
        unless @should_run
          source_count = Reticulum.blackhole_sources.size
          ms = source_count == 1 ? "" : "s"
          RNS.log("Starting blackhole updater with #{source_count} source#{ms}", RNS::LOG_DEBUG)
          @should_run = true
          spawn { job }
        end
      end

      def stop
        @should_run = false
      end

      def update_link_established(link : Link)
        remote_identity = link.get_remote_identity
        return unless remote_identity

        RNS.log("Link established for blackhole list update from #{RNS.prettyhexrep(remote_identity.hash)}", RNS::LOG_DEBUG)
        receipt = link.request("/list")
        return unless receipt

        # Wait for request to conclude
        timeout = SOURCE_TIMEOUT
        elapsed = 0.0
        while !receipt.concluded? && elapsed < timeout
          sleep 0.2.seconds
          elapsed += 0.2
        end

        response = receipt.get_response
        link.teardown

        blackhole_list = response.is_a?(Hash) ? response : nil

        if blackhole_list
          added = 0
          blackhole_list.each do |identity_hash, entry|
            identity_hex = identity_hash.to_s
            unless Transport.blackholed_identities.has_key?(identity_hex)
              Transport.blackholed_identities[identity_hex] = entry.is_a?(Hash(String, String | Float64 | Nil)) ? entry : Hash(String, String | Float64 | Nil).new
              added += 1
            end
          end

          if added > 0
            spec = added == 1 ? "identity" : "identities"
            RNS.log("Added #{added} blackholed #{spec} from #{RNS.prettyhexrep(remote_identity.hash)}", RNS::LOG_DEBUG)

            begin
              sourcelistpath = File.join(Reticulum.blackholepath, RNS.hexrep(remote_identity.hash, delimit: false))
              tmppath = "#{sourcelistpath}.tmp"
              # Persist blackhole list using msgpack
              io = IO::Memory.new
              packer = MessagePack::Packer.new(io)
              packer.write(blackhole_list)
              File.write(tmppath, io.to_slice)
              File.delete(sourcelistpath) if File.exists?(sourcelistpath)
              File.rename(tmppath, sourcelistpath)
            rescue ex
              RNS.log("Error while persisting blackhole list from #{RNS.prettyhexrep(remote_identity.hash)}: #{ex.message}", RNS::LOG_ERROR)
            end
          end
        end

        RNS.log("Blackhole list update from #{RNS.prettyhexrep(remote_identity.hash)} completed", RNS::LOG_DEBUG)
      end

      private def job
        sleep INITIAL_WAIT.seconds
        while @should_run
          begin
            now = Time.utc.to_unix_f
            Reticulum.blackhole_sources.each do |identity_hash|
              identity_hex = RNS.hexrep(identity_hash, delimit: false)
              last_update = @last_updates[identity_hex]? || 0.0

              if now > last_update + UPDATE_INTERVAL
                begin
                  destination_hash = Destination.hash_from_name_and_identity(
                    "rnstransport.info.blackhole",
                    Identity.recall(identity_hash)
                  )
                  RNS.log("Attempting blackhole list update from #{RNS.prettyhexrep(identity_hash)}...", RNS::LOG_DEBUG)

                  if !Transport.has_path?(destination_hash)
                    RNS.log("No path available for blackhole list update from #{RNS.prettyhexrep(identity_hash)}, retrying later", RNS::LOG_VERBOSE)
                  else
                    remote_identity = Identity.recall(destination_hash)
                    if remote_identity
                      destination = Destination.new(
                        remote_identity, Destination::OUT, Destination::SINGLE,
                        "rnstransport", ["info", "blackhole"]
                      )
                      link = Link.new(destination)
                      link.set_link_established_callback(->(l : Link) { update_link_established(l); nil })
                      @last_updates[identity_hex] = Time.utc.to_unix_f
                    end
                  end
                rescue ex
                  RNS.log("Error while establishing link for blackhole list update from #{RNS.prettyhexrep(identity_hash)}: #{ex.message}", RNS::LOG_ERROR)
                end
              end
            end
          rescue ex
            RNS.log("Error in blackhole list updater job: #{ex.message}", RNS::LOG_ERROR)
          end

          sleep @job_interval.seconds
        end
      end
    end

    # ═══════════════════════════════════════════════════════════════════
    #  Helper functions
    # ═══════════════════════════════════════════════════════════════════

    def self.is_ip_address?(address_string : String) : Bool
      return false if address_string.empty?
      begin
        Socket::IPAddress.new(address_string, 0)
        true
      rescue
        false
      end
    end

    def self.is_hostname?(hostname : String) : Bool
      return false if hostname.empty?
      h = hostname.rstrip('.')
      return false if h.size > 253
      components = h.split('.')
      return false if components.empty?
      # Reject all-numeric TLD
      return false if components.last.matches?(/^[0-9]+$/)
      allowed = /^(?!-)[a-z0-9-]{1,63}(?<!-)$/i
      components.all? { |label| allowed.matches?(label) }
    end
  end
end
