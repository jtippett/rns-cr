module RNS
  module Management
    class StateCollector
      @node_identity_hash : Bytes
      @config_path : String?
      @start_time : Float64

      def initialize(*, @node_identity_hash : Bytes, @config_path : String?)
        @start_time = Time.utc.to_unix_f
      end

      # Snapshot all runtime state into a NodeStateReport.
      def collect_state : NodeStateReport
        report = NodeStateReport.new
        report.node_identity_hash = @node_identity_hash
        report.uptime = Time.utc.to_unix_f - @start_time
        report.timestamp = Time.utc.to_unix_f
        report.config_hash = compute_current_config_hash
        report.interfaces = collect_interfaces
        report.announce_table = collect_announce_table
        report.path_table = collect_path_table
        report.active_links = collect_active_links
        report
      end

      private def compute_current_config_hash : Bytes
        if path = @config_path
          if File.exists?(path)
            return ConfigEngine.compute_config_hash(File.read(path))
          end
        end
        Bytes.new(32, 0_u8)
      end

      private def collect_interfaces : Array(InterfaceEntry)
        Transport.interface_objects.compact_map do |iface|
          # Skip LocalClientInterface (shared instance connections, not data-plane)
          next if iface.is_a?(LocalClientInterface)

          entry = InterfaceEntry.new
          entry.name = iface.name
          entry.type = iface.class.name.split("::").last
          entry.mode = iface.mode
          entry.online = iface.online
          entry.bitrate = iface.bitrate
          entry.mtu = iface.mtu.to_u16
          entry.rxb = iface.rxb.to_u64
          entry.txb = iface.txb.to_u64

          # Collect peer hashes for interfaces with spawned peers
          if spawned = iface.spawned_interfaces
            entry.peers = spawned.compact_map { |s| s.get_hash rescue nil }
          end

          entry.ifac_configured = !iface.ifac_key.nil?
          entry.ifac_netname = iface.ifac_netname
          entry.announce_queue_size = iface.announce_queue.size.to_u32
          entry
        end
      end

      private def collect_announce_table : Array(AnnounceTableEntry)
        Transport.announce_table.map do |dest_hex, announce_entry|
          entry = AnnounceTableEntry.new
          entry.dest_hash = announce_entry.packet.destination_hash || Bytes.empty
          entry.hops = announce_entry.hops.to_u8
          # Find receiving interface name from hash
          if ri_hash = announce_entry.received_from
            ri = Transport.interface_objects.find { |i| i.get_hash == ri_hash }
            entry.interface_name = ri.try(&.name) || "unknown"
          else
            entry.interface_name = "unknown"
          end
          entry.timestamp = announce_entry.timestamp
          entry.expires = announce_entry.timestamp + announce_entry.retransmit_timeout
          entry
        end
      end

      private def collect_path_table : Array(PathTableEntry)
        Transport.path_table.map do |dest_hex, path_entry|
          entry = PathTableEntry.new
          entry.dest_hash = dest_hex.hexbytes rescue Bytes.empty
          entry.next_hop = path_entry.next_hop
          entry.hops = path_entry.hops.to_u8
          if ri_hash = path_entry.receiving_interface
            ri = Transport.interface_objects.find { |i| i.get_hash == ri_hash }
            entry.interface_name = ri.try(&.name) || "unknown"
          else
            entry.interface_name = "unknown"
          end
          entry.expires = path_entry.expires
          entry
        end
      end

      private def collect_active_links : Array(ActiveLinkEntry)
        Transport.active_links.compact_map do |link_like|
          entry = ActiveLinkEntry.new
          entry.dest_hash = link_like.destination_hash
          entry.status = link_like.status
          if link_like.is_a?(Link)
            entry.rtt = link_like.rtt
            entry.established_at = link_like.activated_at
          end
          entry
        end
      end
    end
  end
end
