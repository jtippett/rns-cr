require "openssl"

module RNS
  module Management
    module ConfigEngine
      enum ReloadType
        Hot       # Update property in-place
        Targeted  # Teardown/recreate specific interface
        Restart   # Full daemon restart required
      end

      enum ChangeType
        Added
        Removed
        Modified
      end

      record ConfigChange,
        section : String,
        change_type : ChangeType,
        reload_type : ReloadType,
        changed_keys : Array(String) = [] of String

      # Keys that can be changed without interface teardown
      HOT_RELOAD_KEYS = Set{
        "networkname", "network_name", "passphrase", "pass_phrase",
        "ifac_size",
        "announce_rate_target", "announce_rate_grace", "announce_rate_penalty",
        "interface_mode", "mode",
        "bitrate",
        "ingress_control", "ic_max_held_announces", "ic_burst_hold",
        "ic_burst_freq_new", "ic_burst_freq", "ic_new_time",
        "ic_burst_penalty", "ic_held_release_interval",
        "discoverable", "announce_interval",
      }

      # Keys whose changes require interface teardown and recreation
      TARGETED_KEYS = Set{
        "target_host", "target_port", "listen_ip", "listen_port",
        "bind_ip", "bind_port", "port", "type",
        "devices", "group_id",
      }

      # Section names that require full restart
      RESTART_SECTIONS = Set{"reticulum"}

      def self.validate_config_sections(
        sections : Hash(String, Hash(String, String)),
        protected_interface : String? = nil
      ) : NamedTuple(valid: Bool, errors: Array(String))
        errors = [] of String

        sections.each do |section_name, kvs|
          # Protected interface check
          if section_name == protected_interface
            errors << "Cannot modify management-protected interface '#{section_name}'"
            next
          end

          # Validate ifac_size
          if size_str = kvs["ifac_size"]?
            size = size_str.to_i rescue -1
            if size < 1 || size > 64
              errors << "#{section_name}: ifac_size must be between 1 and 64 (got #{size_str})"
            end
          end

          # Validate announce_rate_target
          if art_str = kvs["announce_rate_target"]?
            art = art_str.to_i rescue 0
            if art <= 0
              errors << "#{section_name}: announce_rate_target must be > 0 (got #{art_str})"
            end
          end

          # Validate mode
          if mode_str = kvs["mode"]? || kvs["interface_mode"]?
            valid_modes = Set{"full", "gateway", "ap", "roaming", "boundary", "point_to_point"}
            unless valid_modes.includes?(mode_str.downcase)
              errors << "#{section_name}: invalid mode '#{mode_str}'"
            end
          end

          # Validate port values
          {"target_port", "listen_port", "port"}.each do |key|
            if port_str = kvs[key]?
              port = port_str.to_i rescue -1
              if port < 1 || port > 65535
                errors << "#{section_name}: #{key} must be between 1 and 65535 (got #{port_str})"
              end
            end
          end

          # Validate interface type
          if type_str = kvs["type"]?
            valid_types = Set{
              "AutoInterface", "TCPClientInterface", "TCPServerInterface",
              "UDPInterface", "SerialInterface", "RNodeInterface",
              "PipeInterface", "KISSInterface", "I2PInterface",
              "BackboneInterface", "BackboneClientInterface", "WeaveInterface",
            }
            unless valid_types.includes?(type_str)
              errors << "#{section_name}: unknown interface type '#{type_str}'"
            end
          end

          # Validate IFAC credentials are non-empty if provided
          {"networkname", "network_name"}.each do |key|
            if val = kvs[key]?
              if val.strip.empty?
                errors << "#{section_name}: #{key} must be non-empty if provided"
              end
            end
          end
          {"passphrase", "pass_phrase"}.each do |key|
            if val = kvs[key]?
              if val.strip.empty?
                errors << "#{section_name}: #{key} must be non-empty if provided"
              end
            end
          end
        end

        {valid: errors.empty?, errors: errors}
      end

      def self.diff_config(
        old_sections : Hash(String, Hash(String, String)),
        new_sections : Hash(String, Hash(String, String))
      ) : Array(ConfigChange)
        changes = [] of ConfigChange

        # Detect removed sections
        old_sections.each_key do |name|
          unless new_sections.has_key?(name)
            changes << ConfigChange.new(
              section: name,
              change_type: ChangeType::Removed,
              reload_type: ReloadType::Targeted
            )
          end
        end

        # Detect added sections
        new_sections.each_key do |name|
          unless old_sections.has_key?(name)
            reload = RESTART_SECTIONS.includes?(name) ? ReloadType::Restart : ReloadType::Targeted
            changes << ConfigChange.new(
              section: name,
              change_type: ChangeType::Added,
              reload_type: reload
            )
          end
        end

        # Detect modified sections
        new_sections.each do |name, new_kvs|
          old_kvs = old_sections[name]?
          next unless old_kvs

          changed_keys = [] of String
          all_keys = (old_kvs.keys + new_kvs.keys).uniq

          all_keys.each do |key|
            old_val = old_kvs[key]?
            new_val = new_kvs[key]?
            if old_val != new_val
              changed_keys << key
            end
          end

          next if changed_keys.empty?

          # Determine reload type: worst case wins
          reload = ReloadType::Hot
          if RESTART_SECTIONS.includes?(name)
            reload = ReloadType::Restart
          elsif changed_keys.any? { |k| TARGETED_KEYS.includes?(k) }
            reload = ReloadType::Targeted
          end

          changes << ConfigChange.new(
            section: name,
            change_type: ChangeType::Modified,
            reload_type: reload,
            changed_keys: changed_keys
          )
        end

        changes
      end

      def self.compute_config_hash(content : String) : Bytes
        digest = OpenSSL::Digest.new("SHA256")
        digest.update(content)
        digest.final.dup
      end
    end
  end
end
