module RNS
  module Management
    class Manager
      enum LinkStatus
        Connected
        Connecting
        Disconnected
      end

      APP_NAME = "reticule"
      ASPECTS  = ["node", "mgmt"]
      DEFAULT_REPORT_INTERVAL    = 30.0   # seconds
      DEFAULT_HEARTBEAT_INTERVAL = 10.0   # seconds
      RECONNECT_INITIAL          =  5.0   # seconds
      RECONNECT_MAX              = 300.0  # seconds

      getter destination : Destination
      getter link_status : LinkStatus = LinkStatus::Disconnected
      getter link_status_since : Float64 = 0.0
      getter state_collector : StateCollector

      @identity : Identity
      @reticulum_instance : ReticulumInstance
      @config_path : String?
      @reticule_dest_hash : Bytes?
      @node_id : Bytes?
      @management_link : Link?
      @report_interval : Float64
      @heartbeat_interval : Float64
      @heartbeat_sequence : UInt32 = 0_u32
      @reconnect_delay : Float64 = RECONNECT_INITIAL
      @periodic_tasks_started : Bool = false
      @bootstrap_interface_name : String?

      def initialize(*, @identity : Identity,
                     @reticulum_instance : ReticulumInstance,
                     @config_path : String?,
                     @reticule_dest_hash : Bytes? = nil,
                     @node_id : Bytes? = nil,
                     @report_interval : Float64 = DEFAULT_REPORT_INTERVAL,
                     @heartbeat_interval : Float64 = DEFAULT_HEARTBEAT_INTERVAL,
                     @bootstrap_interface_name : String? = nil)
        # Create an IN/SINGLE destination so Reticule can establish links to us
        @destination = Destination.new(
          @identity,
          Destination::IN,
          Destination::SINGLE,
          APP_NAME,
          ASPECTS,
        )

        node_hash = @identity.hash || Bytes.new(16)
        @state_collector = StateCollector.new(
          node_identity_hash: node_hash,
          config_path: @config_path,
        )

        @link_status_since = Time.utc.to_unix_f

        # Set up link establishment callback on the destination
        @destination.set_link_established_callback(->(link : Link) {
          on_link_established(link)
          nil
        })
      end

      # Attempt to establish a Link to Reticule's management destination.
      # Called after interfaces are up. Non-blocking -- spawns fibers.
      def connect(reticule_dest_hash : Bytes? = nil)
        target = reticule_dest_hash || @reticule_dest_hash
        return unless target

        @reticule_dest_hash = target
        set_link_status(LinkStatus::Connecting)

        spawn do
          establish_link(target)
        end
      end

      # Handle an incoming ConfigPush message. Returns ConfigAck.
      def handle_config_push(push : ConfigPush) : ConfigAck
        ack = ConfigAck.new
        ack.push_id = push.push_id

        # Validate
        validation = ConfigEngine.validate_config_sections(
          push.config_sections,
          protected_interface: @bootstrap_interface_name,
        )

        unless validation[:valid]
          ack.status = ConfigAck::STATUS_VALIDATION_FAILED
          ack.error_message = validation[:errors].join("; ")
          ack.config_hash = current_config_hash
          return ack
        end

        # Apply config
        begin
          apply_config_push(push)
          ack.status = ConfigAck::STATUS_APPLIED
          ack.config_hash = current_config_hash
        rescue ex
          ack.status = ConfigAck::STATUS_APPLY_FAILED
          ack.error_message = ex.message
          ack.config_hash = current_config_hash
        end

        ack
      end

      # Start periodic reporting and heartbeat fibers.
      def start_periodic_tasks
        return if @periodic_tasks_started
        @periodic_tasks_started = true

        spawn do
          loop do
            sleep @report_interval.seconds
            send_state_report
          rescue ex
            RNS.log("Periodic state report error: #{ex.message}", RNS::LOG_DEBUG)
          end
        end

        spawn do
          loop do
            sleep @heartbeat_interval.seconds
            send_heartbeat
          rescue ex
            RNS.log("Periodic heartbeat error: #{ex.message}", RNS::LOG_DEBUG)
          end
        end
      end

      # Send a state report immediately (for event-driven reports).
      def send_state_report
        link = @management_link
        return unless link && link.status == Link::ACTIVE

        report = @state_collector.collect_state
        channel = link.get_channel
        channel.send(report) if channel.is_ready_to_send?
      end

      # Build and send a JoinRequest over the management link.
      def send_join_request(token : ProvisioningToken) : Nil
        link = @management_link
        return unless link && link.status == Link::ACTIVE

        req = JoinRequest.new
        req.token_secret = token.token_secret
        req.identity_pubkey = @identity.get_public_key
        req.hostname = System.hostname
        req.platform = "crystal-#{Crystal::VERSION}/#{{{flag?(:darwin) ? "darwin" : flag?(:linux) ? "linux" : "unknown"}}}-#{{{flag?(:x86_64) ? "x86_64" : flag?(:aarch64) ? "aarch64" : "unknown"}}}"
        req.daemon_version = RNS::VERSION

        channel = link.get_channel
        channel.send(req)
      end

      def shutdown
        if link = @management_link
          link.teardown if link.status == Link::ACTIVE
        end
        set_link_status(LinkStatus::Disconnected)
      end

      private def set_link_status(status : LinkStatus)
        @link_status = status
        @link_status_since = Time.utc.to_unix_f
      end

      private def on_link_established(link : Link)
        @management_link = link
        set_link_status(LinkStatus::Connected)
        @reconnect_delay = RECONNECT_INITIAL
        register_channel_handlers(link)
        RNS.log("Management link established", RNS::LOG_NOTICE)

        link.callbacks.link_closed = ->(l : Link) {
          set_link_status(LinkStatus::Disconnected)
          RNS.log("Management link closed, will reconnect in #{@reconnect_delay}s", RNS::LOG_WARNING)
          if rdh = @reticule_dest_hash
            schedule_reconnect(rdh)
          end
          nil
        }
      end

      private def establish_link(target_hash : Bytes)
        begin
          # Recall the Reticule identity from known destinations so we can create
          # an outbound destination to link to.
          reticule_identity = Identity.recall(target_hash)
          unless reticule_identity
            RNS.log("Cannot establish management link: Reticule identity not known for #{target_hash.hexstring}", RNS::LOG_WARNING)
            schedule_reconnect(target_hash)
            return
          end

          reticule_dest = Destination.new(
            reticule_identity,
            Destination::OUT,
            Destination::SINGLE,
            APP_NAME,
            ASPECTS,
            register: false,
          )

          link = Link.new(reticule_dest)

          link.callbacks.link_established = ->(l : Link) {
            on_link_established(l)
            nil
          }
        rescue ex
          RNS.log("Failed to establish management link: #{ex.message}", RNS::LOG_ERROR)
          schedule_reconnect(target_hash)
        end
      end

      private def schedule_reconnect(target_hash : Bytes)
        delay = @reconnect_delay
        @reconnect_delay = Math.min(@reconnect_delay * 2, RECONNECT_MAX)

        spawn do
          sleep delay.seconds
          set_link_status(LinkStatus::Connecting)
          establish_link(target_hash)
        end
      end

      private def register_channel_handlers(link : Link)
        channel = link.get_channel
        channel.register_message_type(NodeStateReport)
        channel.register_message_type(ConfigPush)
        channel.register_message_type(ConfigAck)
        channel.register_message_type(Heartbeat)
        channel.register_message_type(JoinRequest)
        channel.register_message_type(JoinResponse)

        channel.add_message_handler(->(msg : MessageBase) {
          case msg
          when ConfigPush
            ack = handle_config_push(msg)
            channel.send(ack)
            true
          when JoinResponse
            handle_join_response(msg)
            true
          when Heartbeat
            # Application-level heartbeat received -- no action needed
            true
          else
            false
          end
        })
      end

      private def handle_join_response(response : JoinResponse)
        if response.accepted
          @node_id = response.node_id
          RNS.log("Join accepted, node_id: #{response.node_id.try(&.hexstring)}", RNS::LOG_NOTICE)

          if sections = response.config_sections
            push = ConfigPush.new
            push.push_id = Bytes.new(16)  # synthetic push
            push.strategy = 0_u8
            push.config_sections = sections
            push.expected_hash = Bytes.new(32)
            handle_config_push(push)
          end

          start_periodic_tasks
        else
          RNS.log("Join rejected: #{response.reject_reason}", RNS::LOG_ERROR)
        end
      end

      private def apply_config_push(push : ConfigPush)
        # Backup current config
        if path = @config_path
          if File.exists?(path)
            File.copy(path, "#{path}.bak")
          end
        end

        # Get current config as sections
        current_sections = current_config_sections

        # Compute diff
        changes = ConfigEngine.diff_config(current_sections, push.config_sections)

        # Apply changes
        begin
          changes.each do |change|
            case change.change_type
            when ConfigEngine::ChangeType::Added
              if change.reload_type == ConfigEngine::ReloadType::Targeted
                apply_new_interface(change.section, push.config_sections[change.section])
              end
            when ConfigEngine::ChangeType::Removed
              @reticulum_instance.remove_interface(change.section)
            when ConfigEngine::ChangeType::Modified
              apply_modification(change, push.config_sections[change.section])
            end
          end

          # Write updated config
          write_config(push.config_sections) if @config_path
        rescue ex
          # Rollback
          if path = @config_path
            bak = "#{path}.bak"
            if File.exists?(bak)
              File.copy(bak, path)
            end
          end
          raise ex
        end
      end

      private def apply_modification(change : ConfigEngine::ConfigChange, new_kvs : Hash(String, String))
        case change.reload_type
        when ConfigEngine::ReloadType::Hot
          apply_hot_reload(change.section, change.changed_keys, new_kvs)
        when ConfigEngine::ReloadType::Targeted
          @reticulum_instance.replace_interface(change.section, build_config_section(change.section, new_kvs))
        when ConfigEngine::ReloadType::Restart
          RNS.log("Config change in '#{change.section}' requires restart", RNS::LOG_WARNING)
        end
      end

      private def apply_hot_reload(name : String, changed_keys : Array(String), kvs : Hash(String, String))
        iface = Transport.interface_objects.find { |i| i.name == name }
        return unless iface

        # IFAC changes
        ifac_keys = Set{"networkname", "network_name", "passphrase", "pass_phrase", "ifac_size"}
        if changed_keys.any? { |k| ifac_keys.includes?(k) }
          nn = kvs["networkname"]? || kvs["network_name"]?
          nk = kvs["passphrase"]? || kvs["pass_phrase"]?
          ifac_size = kvs["ifac_size"]?.try(&.to_u8) || 16_u8
          @reticulum_instance.update_interface_ifac(name,
            network_name: nn, passphrase: nk, ifac_size: ifac_size)
        end

        # Announce rate changes
        if changed_keys.includes?("announce_rate_target")
          iface.announce_rate_target = kvs["announce_rate_target"]?.try(&.to_i32)
        end
        if changed_keys.includes?("announce_rate_grace")
          iface.announce_rate_grace = kvs["announce_rate_grace"]?.try(&.to_i32)
        end
        if changed_keys.includes?("announce_rate_penalty")
          iface.announce_rate_penalty = kvs["announce_rate_penalty"]?.try(&.to_i32)
        end

        # Mode change
        mode_keys = Set{"interface_mode", "mode"}
        if changed_keys.any? { |k| mode_keys.includes?(k) }
          mode_str = kvs["interface_mode"]? || kvs["mode"]?
          if mode_str
            iface.mode = parse_mode(mode_str)
          end
        end

        # Bitrate
        if changed_keys.includes?("bitrate")
          if br = kvs["bitrate"]?
            iface.bitrate = br.to_i64
          end
        end
      end

      private def apply_new_interface(name : String, kvs : Hash(String, String))
        section = build_config_section(name, kvs)
        @reticulum_instance.replace_interface(name, section)
      end

      private def build_config_section(name : String, kvs : Hash(String, String)) : ConfigObj::Section
        section = ConfigObj::Section.new(parent: nil, depth: 2, name: name)
        kvs.each { |k, v| section[k] = v }
        section
      end

      private def current_config_sections : Hash(String, Hash(String, String))
        result = {} of String => Hash(String, String)
        if path = @config_path
          if File.exists?(path)
            config = ConfigObj.from_file(path)
            if config.has_key?("interfaces")
              iface_section = config.section("interfaces")
              iface_section.sections.each do |name|
                sub = iface_section.section(name)
                result[name] = sub.to_string_hash
              end
            end
          end
        end
        result
      end

      private def current_config_hash : Bytes
        if path = @config_path
          if File.exists?(path)
            return ConfigEngine.compute_config_hash(File.read(path))
          end
        end
        Bytes.new(32, 0_u8)
      end

      private def write_config(sections : Hash(String, Hash(String, String)))
        if path = @config_path
          if File.exists?(path)
            config = ConfigObj.from_file(path)
          else
            config = ConfigObj.new
          end

          # Update interface sections
          iface_root = if config.has_key?("interfaces")
                         config.section("interfaces")
                       else
                         config.add_section("interfaces")
                       end

          sections.each do |name, kvs|
            sub = if iface_root.has_key?(name)
                     iface_root.section(name)
                   else
                     iface_root.add_section(name)
                   end
            kvs.each { |k, v| sub[k] = v }
          end

          config.write(path)
        end
      end

      private def send_heartbeat
        link = @management_link
        return unless link && link.status == Link::ACTIVE

        hb = Heartbeat.new
        hb.timestamp = Time.utc.to_unix_f
        hb.sequence = @heartbeat_sequence
        @heartbeat_sequence &+= 1

        channel = link.get_channel
        channel.send(hb) if channel.is_ready_to_send?
      end

      private def parse_mode(mode_str : String) : UInt8
        case mode_str.downcase
        when "full"           then Interface::MODE_FULL
        when "gateway"        then Interface::MODE_GATEWAY
        when "ap"             then Interface::MODE_ACCESS_POINT
        when "roaming"        then Interface::MODE_ROAMING
        when "boundary"       then Interface::MODE_BOUNDARY
        when "point_to_point" then Interface::MODE_POINT_TO_POINT
        else                       Interface::MODE_FULL
        end
      end
    end
  end
end
