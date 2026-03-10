module RNS
  module Transport
    # ─── Transport type constants ──────────────────────────────────
    BROADCAST = 0x00_u8
    TRANSPORT = 0x01_u8
    RELAY     = 0x02_u8
    TUNNEL    = 0x03_u8
    TYPES     = [BROADCAST, TRANSPORT, RELAY, TUNNEL]

    # ─── Reachability constants ────────────────────────────────────
    REACHABILITY_UNREACHABLE = 0x00_u8
    REACHABILITY_DIRECT      = 0x01_u8
    REACHABILITY_TRANSPORT   = 0x02_u8

    # ─── App name ──────────────────────────────────────────────────
    APP_NAME = "rnstransport"

    # ─── Pathfinder constants ──────────────────────────────────────
    PATHFINDER_M  = 128       # Max hops
    PATHFINDER_R  =   1       # Retransmit retries
    PATHFINDER_G  =   5       # Retry grace period (seconds)
    PATHFINDER_RW =   0.5     # Random window for announce rebroadcast
    PATHFINDER_E  = 60*60*24*7 # Path expiration: 1 week (604800s)

    AP_PATH_TIME      = 60*60*24 # Access Point path expiration: 1 day
    ROAMING_PATH_TIME = 60*60*6  # Roaming path expiration: 6 hours

    LOCAL_REBROADCASTS_MAX = 2 # How many local rebroadcasts of an announce is allowed

    # ─── Path request constants ────────────────────────────────────
    PATH_REQUEST_TIMEOUT = 15    # Default timeout for client path requests (seconds)
    PATH_REQUEST_GRACE   =  0.4  # Grace time before path announcement
    PATH_REQUEST_RG      =  1.5  # Extra grace for roaming-mode interfaces
    PATH_REQUEST_MI      = 20    # Minimum interval for automated path requests (seconds)

    # ─── State constants ───────────────────────────────────────────
    STATE_UNKNOWN      = 0x00_u8
    STATE_UNRESPONSIVE = 0x01_u8
    STATE_RESPONSIVE   = 0x02_u8

    # ─── Timeout and limit constants ───────────────────────────────
    # LINK_TIMEOUT is set after Link is defined; use class method for now
    REVERSE_TIMEOUT     = 8 * 60         # 480 seconds (8 minutes)
    DESTINATION_TIMEOUT = 60*60*24*7     # 1 week
    MAX_RECEIPTS        = 1024
    MAX_RATE_TIMESTAMPS = 16
    PERSIST_RANDOM_BLOBS = 32
    MAX_RANDOM_BLOBS     = 64
    LOCAL_CLIENT_CACHE_MAXSIZE = 512

    # ─── Job interval constants ────────────────────────────────────
    JOB_INTERVAL              = 0.250
    LINKS_CHECK_INTERVAL      = 1.0
    RECEIPTS_CHECK_INTERVAL   = 1.0
    ANNOUNCES_CHECK_INTERVAL  = 1.0
    PENDING_PRS_CHECK_INTERVAL = 30.0
    CACHE_CLEAN_INTERVAL      = 5 * 60   # 300 seconds
    TABLES_CULL_INTERVAL      = 5.0
    INTERFACE_JOBS_INTERVAL   = 5.0
    MGMT_ANNOUNCE_INTERVAL    = 2 * 60 * 60 # 7200 seconds
    BLACKHOLE_CHECK_INTERVAL  = 60

    HASHLIST_MAXSIZE = 1_000_000
    MAX_PR_TAGS      = 32_000

    # ─── Path table entry indices ──────────────────────────────────
    IDX_PT_TIMESTAMP = 0
    IDX_PT_NEXT_HOP  = 1
    IDX_PT_HOPS      = 2
    IDX_PT_EXPIRES   = 3
    IDX_PT_RANDBLOBS = 4
    IDX_PT_RVCD_IF   = 5
    IDX_PT_PACKET    = 6

    # ─── Reverse table entry indices ───────────────────────────────
    IDX_RT_RCVD_IF   = 0
    IDX_RT_OUTB_IF   = 1
    IDX_RT_TIMESTAMP = 2

    # ─── Announce table entry indices ──────────────────────────────
    IDX_AT_TIMESTAMP = 0
    IDX_AT_RTRNS_TMO = 1
    IDX_AT_RETRIES   = 2
    IDX_AT_RCVD_IF   = 3
    IDX_AT_HOPS      = 4
    IDX_AT_PACKET    = 5
    IDX_AT_LCL_RBRD  = 6
    IDX_AT_BLCK_RBRD = 7
    IDX_AT_ATTCHD_IF = 8

    # ─── Link table entry indices ──────────────────────────────────
    IDX_LT_TIMESTAMP = 0
    IDX_LT_NH_TRID   = 1
    IDX_LT_NH_IF     = 2
    IDX_LT_REM_HOPS  = 3
    IDX_LT_RCVD_IF   = 4
    IDX_LT_HOPS      = 5
    IDX_LT_DSTHASH   = 6
    IDX_LT_VALIDATED = 7
    IDX_LT_PROOF_TMO = 8

    # ─── Tunnel table entry indices ────────────────────────────────
    IDX_TT_TUNNEL_ID = 0
    IDX_TT_IF        = 1
    IDX_TT_PATHS     = 2
    IDX_TT_EXPIRES   = 3

    # ─── Path table entry type ─────────────────────────────────────
    # Each path table entry is stored as a named tuple for clarity.
    # Python uses: [timestamp, next_hop, hops, expires, random_blobs, receiving_interface, packet_hash]
    record PathEntry,
      timestamp : Float64,
      next_hop : Bytes,
      hops : Int32,
      expires : Float64,
      random_blobs : Array(Bytes),
      receiving_interface : Bytes?,   # Interface hash (Bytes) — actual interface resolved at runtime
      packet_hash : Bytes

    # ─── Announce table entry type ─────────────────────────────────
    record AnnounceEntry,
      timestamp : Float64,
      retransmit_timeout : Float64,
      retries : Int32,
      received_from : Bytes,
      hops : Int32,
      packet : Packet,
      local_rebroadcasts : Int32,
      block_rebroadcasts : Bool,
      attached_interface : Bytes?   # Interface hash

    # ─── Reverse table entry type ──────────────────────────────────
    record ReverseEntry,
      received_on : Bytes?,   # Interface hash
      outbound : Bytes?,      # Interface hash
      timestamp : Float64

    # ─── Link table entry type ─────────────────────────────────────
    record LinkEntry,
      timestamp : Float64,
      next_hop_transport_id : Bytes,
      next_hop_interface : Bytes?,  # Interface hash
      remaining_hops : Int32,
      received_on : Bytes?,         # Interface hash
      taken_hops : Int32,
      destination_hash : Bytes,
      validated : Bool,
      proof_timeout : Float64

    # ─── Tunnel table entry type ───────────────────────────────────
    record TunnelEntry,
      tunnel_id : Bytes,
      interface : Bytes?,             # Interface hash
      paths : Hash(String, PathEntry),  # destination_hash hex -> PathEntry
      expires : Float64

    # ─── Announce rate entry type ──────────────────────────────────
    record AnnounceRateEntry,
      last : Float64,
      rate_violations : Int32,
      blocked_until : Float64,
      timestamps : Array(Float64)

    # Link timeout derived from Link stale time
    LINK_TIMEOUT = (LinkLike::STALE_TIME * 1.25)

    # ─── Core state (class-level variables) ────────────────────────
    @@interfaces = [] of Bytes         # Interface hashes (actual interface objects managed elsewhere)
    @@destinations = [] of Destination
    @@pending_links = [] of LinkLike
    @@active_links = [] of LinkLike
    @@packet_hashlist = Set(String).new
    @@packet_hashlist_prev = Set(String).new
    @@receipts = [] of PacketReceipt

    # ─── Transmit log (for testing — records [interface_hash, raw] pairs) ──
    @@transmit_log = [] of {Bytes, Bytes}

    # ─── Tables ────────────────────────────────────────────────────
    @@announce_table = Hash(String, AnnounceEntry).new        # dest_hash hex -> entry
    @@path_table = Hash(String, PathEntry).new                # dest_hash hex -> entry
    @@reverse_table = Hash(String, ReverseEntry).new          # truncated_packet_hash hex -> entry
    @@link_table = Hash(String, LinkEntry).new                # link_id hex -> entry
    @@held_announces = Hash(String, AnnounceEntry).new        # dest_hash hex -> entry
    @@tunnels = Hash(String, TunnelEntry).new                 # tunnel_id hex -> entry
    @@announce_rate_table = Hash(String, AnnounceRateEntry).new # dest_hash hex -> entry
    @@path_requests = Hash(String, Float64).new               # dest_hash hex -> timestamp
    @@path_states = Hash(String, UInt8).new                   # dest_hash hex -> STATE_*
    @@blackholed_identities = Hash(String, Hash(String, String | Float64 | Nil)).new

    @@announce_handlers = [] of AnnounceHandler

    @@discovery_path_requests = Hash(String, Hash(String, String | Bytes | Float64 | Nil)).new
    @@discovery_pr_tags = [] of Bytes

    # ─── Control destinations ──────────────────────────────────────
    @@control_destinations = [] of Destination
    @@control_hashes = [] of Bytes

    # ─── Local client state ────────────────────────────────────────
    @@local_client_interfaces = [] of Bytes
    @@pending_local_path_requests = Hash(String, Bytes?).new
    @@transport_enabled = false
    @@is_connected_to_shared_instance = false

    # ─── Timing state ──────────────────────────────────────────────
    @@start_time : Float64? = nil
    @@jobs_locked = false
    @@jobs_running = false
    @@links_last_checked = 0.0
    @@receipts_last_checked = 0.0
    @@announces_last_checked = 0.0
    @@pending_prs_last_checked = 0.0
    @@cache_last_cleaned = 0.0
    @@tables_last_culled = 0.0
    @@interface_last_jobs = 0.0
    @@last_mgmt_announce = 0.0
    @@blackhole_last_checked = 0.0

    # ─── Locking ───────────────────────────────────────────────────
    @@inbound_announce_lock = Mutex.new

    # ─── Traffic counters ──────────────────────────────────────────
    @@traffic_rxb : Int64 = 0_i64
    @@traffic_txb : Int64 = 0_i64
    @@speed_rx : Int64 = 0_i64
    @@speed_tx : Int64 = 0_i64

    # ─── Identity ──────────────────────────────────────────────────
    @@identity : Identity? = nil

    # Owner is a lightweight record holding the Reticulum instance properties
    # that Transport needs. This avoids a circular dependency on the full
    # Reticulum class which hasn't been implemented yet.
    record OwnerRef,
      is_connected_to_shared_instance : Bool = false,
      storage_path : String = "",
      cache_path : String = "",
      transport_enabled : Bool = false

    @@owner : OwnerRef? = nil

    # Job loop fiber reference
    @@job_fiber : Fiber? = nil
    @@job_loop_running = false

    # ─── Save operation guards ─────────────────────────────────────
    @@saving_path_table = false
    @@saving_packet_hashlist = false
    @@saving_tunnel_table = false

    # ─── Announce handler interface ────────────────────────────────
    module AnnounceHandler
      abstract def aspect_filter : String?
      abstract def received_announce(destination_hash : Bytes, announced_identity : Identity?, app_data : Bytes?, announce_packet_hash : Bytes?)
    end

    # ════════════════════════════════════════════════════════════════
    #  Accessors
    # ════════════════════════════════════════════════════════════════

    def self.destinations
      @@destinations
    end

    def self.interfaces
      @@interfaces
    end

    def self.pending_links
      @@pending_links
    end

    def self.active_links
      @@active_links
    end

    def self.packet_hashlist
      @@packet_hashlist
    end

    def self.receipts
      @@receipts
    end

    def self.announce_table
      @@announce_table
    end

    def self.path_table
      @@path_table
    end

    def self.reverse_table
      @@reverse_table
    end

    def self.link_table
      @@link_table
    end

    def self.held_announces
      @@held_announces
    end

    def self.tunnels
      @@tunnels
    end

    def self.announce_rate_table
      @@announce_rate_table
    end

    def self.path_requests
      @@path_requests
    end

    def self.path_states
      @@path_states
    end

    def self.announce_handlers
      @@announce_handlers
    end

    def self.identity
      @@identity
    end

    def self.identity=(value : Identity?)
      @@identity = value
    end

    def self.owner
      @@owner
    end

    def self.owner=(value : OwnerRef?)
      @@owner = value
    end

    def self.job_loop_running?
      @@job_loop_running
    end

    def self.jobs_locked
      @@jobs_locked
    end

    def self.jobs_locked=(value : Bool)
      @@jobs_locked = value
    end

    def self.jobs_running
      @@jobs_running
    end

    def self.jobs_running=(value : Bool)
      @@jobs_running = value
    end

    def self.start_time
      @@start_time
    end

    def self.tables_last_culled
      @@tables_last_culled
    end

    def self.tables_last_culled=(value : Float64)
      @@tables_last_culled = value
    end

    def self.inbound_announce_lock
      @@inbound_announce_lock
    end

    def self.traffic_rxb
      @@traffic_rxb
    end

    def self.traffic_txb
      @@traffic_txb
    end

    def self.speed_rx
      @@speed_rx
    end

    def self.speed_tx
      @@speed_tx
    end

    def self.discovery_path_requests
      @@discovery_path_requests
    end

    def self.discovery_pr_tags
      @@discovery_pr_tags
    end

    def self.control_destinations
      @@control_destinations
    end

    def self.control_hashes
      @@control_hashes
    end

    def self.local_client_interfaces
      @@local_client_interfaces
    end

    def self.blackholed_identities
      @@blackholed_identities
    end

    def self.transmit_log
      @@transmit_log
    end

    def self.transport_enabled?
      @@transport_enabled
    end

    def self.transport_enabled=(value : Bool)
      @@transport_enabled = value
    end

    def self.is_connected_to_shared_instance?
      @@is_connected_to_shared_instance
    end

    def self.is_connected_to_shared_instance=(value : Bool)
      @@is_connected_to_shared_instance = value
    end

    def self.blackhole_last_checked
      @@blackhole_last_checked
    end

    def self.blackhole_last_checked=(value : Float64)
      @@blackhole_last_checked = value
    end

    def self.packet_hashlist_prev
      @@packet_hashlist_prev
    end

    def self.pending_local_path_requests
      @@pending_local_path_requests
    end

    # ════════════════════════════════════════════════════════════════
    #  Registration
    # ════════════════════════════════════════════════════════════════

    def self.register_destination(destination : Destination)
      destination.mtu = Reticulum::MTU

      if destination.direction == Destination::IN
        @@destinations.each do |registered|
          if destination.hash == registered.hash
            raise KeyError.new("Attempt to register an already registered destination.")
          end
        end
      end

      @@destinations << destination
    end

    def self.deregister_destination(destination : Destination)
      @@destinations.delete(destination)
    end

    def self.register_announce_handler(handler : AnnounceHandler)
      @@announce_handlers << handler
    end

    def self.deregister_announce_handler(handler : AnnounceHandler)
      @@announce_handlers.reject! { |h| h == handler }
    end

    # ════════════════════════════════════════════════════════════════
    #  Reset (for testing)
    # ════════════════════════════════════════════════════════════════

    def self.reset
      @@interfaces.clear
      @@destinations.clear
      @@pending_links.clear
      @@active_links.clear
      @@packet_hashlist.clear
      @@packet_hashlist_prev.clear
      @@receipts.clear
      @@announce_table.clear
      @@path_table.clear
      @@reverse_table.clear
      @@link_table.clear
      @@held_announces.clear
      @@tunnels.clear
      @@announce_rate_table.clear
      @@path_requests.clear
      @@path_states.clear
      @@blackholed_identities.clear
      @@announce_handlers.clear
      @@discovery_path_requests.clear
      @@discovery_pr_tags.clear
      @@control_destinations.clear
      @@control_hashes.clear
      @@local_client_interfaces.clear
      @@pending_local_path_requests.clear
      @@transmit_log.clear
      @@start_time = nil
      @@jobs_locked = false
      @@jobs_running = false
      @@links_last_checked = 0.0
      @@receipts_last_checked = 0.0
      @@announces_last_checked = 0.0
      @@pending_prs_last_checked = 0.0
      @@cache_last_cleaned = 0.0
      @@tables_last_culled = 0.0
      @@interface_last_jobs = 0.0
      @@last_mgmt_announce = 0.0
      @@blackhole_last_checked = 0.0
      @@traffic_rxb = 0_i64
      @@traffic_txb = 0_i64
      @@speed_rx = 0_i64
      @@speed_tx = 0_i64
      @@identity = nil
      @@owner = nil
      @@job_loop_running = false
      @@job_fiber = nil
      @@saving_path_table = false
      @@saving_packet_hashlist = false
      @@saving_tunnel_table = false
      @@transport_enabled = false
      @@is_connected_to_shared_instance = false
    end

    # Alias for backward compat with existing specs
    def self.clear_destinations
      @@destinations.clear
    end

    # ════════════════════════════════════════════════════════════════
    #  Link Management
    # ════════════════════════════════════════════════════════════════

    # Registers a link. Initiator links go to pending_links,
    # responder links go directly to active_links.
    def self.register_link(link : LinkLike)
      RNS.log("Registering link #{link.link_id.hexstring}", RNS::LOG_EXTREME)
      if link.initiator?
        @@pending_links << link
      else
        @@active_links << link
      end
    end

    # Activates a link by moving it from pending to active.
    # The link must be in pending_links and have ACTIVE status.
    def self.activate_link(link : LinkLike)
      RNS.log("Activating link #{link.link_id.hexstring}", RNS::LOG_EXTREME)
      if @@pending_links.includes?(link)
        if link.status != LinkLike::ACTIVE
          raise IO::Error.new("Invalid link state for link activation: #{link.status}")
        end
        @@pending_links.delete(link)
        @@active_links << link
      else
        RNS.log("Attempted to activate a link that was not in the pending table", RNS::LOG_ERROR)
      end
    end

    # Finds an active link matching the given destination hash (link_id).
    def self.find_link_for_destination(destination_hash : Bytes) : LinkLike?
      @@active_links.find { |link| link.link_id == destination_hash }
    end

    # Finds the best active link for a destination hash.
    # Currently returns the first match; future versions may
    # score links by quality metrics.
    def self.find_best_link(destination_hash : Bytes) : LinkLike?
      find_link_for_destination(destination_hash)
    end

    # Checks if a destination hash corresponds to a local client interface.
    def self.is_local_client_interface?(interface_hash : Bytes?) : Bool
      return false unless interface_hash
      @@local_client_interfaces.any? { |lci| lci == interface_hash }
    end

    # Checks if a packet is from a local client.
    def self.from_local_client?(packet : Packet) : Bool
      # Stub: in full implementation checks receiving_interface
      false
    end

    # ════════════════════════════════════════════════════════════════
    #  Transmit
    # ════════════════════════════════════════════════════════════════

    # Transmits raw data on an interface (identified by hash).
    # In the full implementation, this resolves the interface object
    # and handles IFAC masking. For now, records the transmission
    # in the transmit log for testing and verification.
    def self.transmit(interface_hash : Bytes, raw : Bytes)
      @@transmit_log << {interface_hash, raw.dup}
      @@traffic_txb += raw.size.to_i64
    rescue ex
      RNS.log("Error while transmitting: #{ex}", RNS::LOG_ERROR)
    end

    # ════════════════════════════════════════════════════════════════
    #  Outbound Packet Routing
    # ════════════════════════════════════════════════════════════════

    # Main outbound packet routing. Determines how to send a packet
    # based on path table and destination type.
    def self.outbound(packet : Packet) : Bool
      # Wait for jobs to finish
      while @@jobs_running
        sleep(500.microseconds)
      end

      @@jobs_locked = true
      sent = false

      begin
        # Determine if we should generate a receipt
        generate_receipt = false
        if packet.create_receipt &&
           packet.packet_type == Packet::DATA &&
           packet.destination.try { |d| d.type != Destination::PLAIN } &&
           !(packet.context >= Packet::KEEPALIVE && packet.context <= Packet::LRPROOF) &&
           !(packet.context >= Packet::RESOURCE && packet.context <= Packet::RESOURCE_RCL)
          generate_receipt = true
        end

        dest_hash = packet.destination_hash
        dest_hex = dest_hash.try(&.hexstring)

        # Check if we have a known path for the destination
        if packet.packet_type != Packet::ANNOUNCE &&
           packet.destination.try { |d| d.type != Destination::PLAIN && d.type != Destination::GROUP } &&
           dest_hex && @@path_table.has_key?(dest_hex)

          path_entry = @@path_table[dest_hex]
          outbound_interface = path_entry.receiving_interface

          if outbound_interface
            if path_entry.hops > 1
              # Multi-hop: insert transport headers
              raw = packet.raw
              if raw && packet.header_type == Packet::HEADER_1
                new_flags = (Packet::HEADER_2.to_u8 << 6) | (Transport::TRANSPORT.to_u8 << 4) | (packet.flags & 0x0F_u8)
                io = IO::Memory.new
                io.write_byte(new_flags)
                io.write(raw[1, 1])           # hops byte
                io.write(path_entry.next_hop) # transport ID (next hop)
                io.write(raw[2..])            # rest of packet
                new_raw = io.to_slice.dup

                mark_packet_sent(packet, generate_receipt)
                transmit(outbound_interface, new_raw)

                # Update path timestamp
                @@path_table[dest_hex] = PathEntry.new(
                  timestamp: Time.utc.to_unix_f,
                  next_hop: path_entry.next_hop,
                  hops: path_entry.hops,
                  expires: path_entry.expires,
                  random_blobs: path_entry.random_blobs,
                  receiving_interface: path_entry.receiving_interface,
                  packet_hash: path_entry.packet_hash,
                )
                sent = true
              end

            elsif path_entry.hops == 1 && @@is_connected_to_shared_instance
              # Connected to shared instance and 1 hop away: add transport headers
              raw = packet.raw
              if raw && packet.header_type == Packet::HEADER_1
                new_flags = (Packet::HEADER_2.to_u8 << 6) | (Transport::TRANSPORT.to_u8 << 4) | (packet.flags & 0x0F_u8)
                io = IO::Memory.new
                io.write_byte(new_flags)
                io.write(raw[1, 1])
                io.write(path_entry.next_hop)
                io.write(raw[2..])
                new_raw = io.to_slice.dup

                mark_packet_sent(packet, generate_receipt)
                transmit(outbound_interface, new_raw)

                @@path_table[dest_hex] = PathEntry.new(
                  timestamp: Time.utc.to_unix_f,
                  next_hop: path_entry.next_hop,
                  hops: path_entry.hops,
                  expires: path_entry.expires,
                  random_blobs: path_entry.random_blobs,
                  receiving_interface: path_entry.receiving_interface,
                  packet_hash: path_entry.packet_hash,
                )
                sent = true
              end

            else
              # Directly reachable: transmit as-is
              raw = packet.raw
              if raw
                mark_packet_sent(packet, generate_receipt)
                transmit(outbound_interface, raw)
                sent = true
              end
            end
          end

        else
          # No known path: broadcast on all outgoing interfaces
          stored_hash = false
          raw = packet.raw

          if raw
            @@interfaces.each do |interface_hash|
              should_transmit = true

              # For LINK destinations, check link status
              if packet.destination.try { |d| d.type == Destination::LINK }
                # In full implementation, check link status and attached_interface
                # For now, allow transmission
              end

              # If packet has attached interface, only send on that one
              if packet.attached_interface
                # Attached interface check — when interface objects are available
              end

              if should_transmit
                if !stored_hash
                  ph = packet.packet_hash
                  add_packet_hash(ph) if ph
                  stored_hash = true
                end

                transmit(interface_hash, raw)
                mark_packet_sent(packet, generate_receipt)
                sent = true
              end
            end
          end
        end
      ensure
        @@jobs_locked = false
      end

      sent
    end

    # Helper to mark a packet as sent and optionally create a receipt.
    private def self.mark_packet_sent(packet : Packet, generate_receipt : Bool)
      packet.sent = true
      packet.sent_at = Time.utc.to_unix_f

      if generate_receipt
        packet.receipt = PacketReceipt.new(packet)
        @@receipts << packet.receipt.not_nil!
      end
    end

    # ════════════════════════════════════════════════════════════════
    #  Inbound Packet Processing
    # ════════════════════════════════════════════════════════════════

    # Main inbound packet processing pipeline.
    # Handles IFAC validation, packet unpacking, routing,
    # announce processing, link requests, data delivery, and proofs.
    def self.inbound(raw : Bytes, interface_hash : Bytes? = nil)
      # Minimum size check
      return if raw.size <= 2

      # IFAC validation stub — full implementation when Interface class exists
      # For now, drop packets with IFAC flag set (we don't support IFAC yet)
      if raw[0] & 0x80_u8 == 0x80_u8
        return # IFAC flagged but no IFAC support yet
      end

      # Wait for jobs to finish
      while @@jobs_running
        sleep(500.microseconds)
      end

      return unless @@identity

      @@jobs_locked = true

      begin
        # Unpack the packet
        packet = Packet.new(nil, raw)
        unless packet.unpack
          return
        end

        packet.hops += 1

        # Apply packet filter
        unless packet_filter(packet)
          return
        end

        # Determine if we should remember the hash
        remember_packet_hash = true
        dest_hash = packet.destination_hash
        dest_hex = dest_hash.try(&.hexstring)

        if dest_hex && @@link_table.has_key?(dest_hex)
          remember_packet_hash = false
        end

        if packet.packet_type == Packet::PROOF && packet.context == Packet::LRPROOF
          remember_packet_hash = false
        end

        if remember_packet_hash
          ph = packet.packet_hash
          add_packet_hash(ph) if ph
        end

        # Check conditions for local clients and transport
        from_local = interface_hash && is_local_client_interface?(interface_hash)

        for_local_client = false
        if packet.packet_type != Packet::ANNOUNCE && dest_hex
          if @@path_table.has_key?(dest_hex) && @@path_table[dest_hex].hops == 0
            for_local_client = true
          end
        end

        for_local_client_link = false
        if packet.packet_type != Packet::ANNOUNCE && dest_hex && @@link_table.has_key?(dest_hex)
          link_entry = @@link_table[dest_hex]
          if link_entry.received_on && is_local_client_interface?(link_entry.received_on)
            for_local_client_link = true
          end
          if link_entry.next_hop_interface && is_local_client_interface?(link_entry.next_hop_interface)
            for_local_client_link = true
          end
        end

        proof_for_local_client = false
        if dest_hex && @@reverse_table.has_key?(dest_hex)
          reverse_entry = @@reverse_table[dest_hex]
          if reverse_entry.received_on && is_local_client_interface?(reverse_entry.received_on)
            proof_for_local_client = true
          end
        end

        # Plain broadcast handling
        if dest_hash && !@@control_hashes.any? { |ch| ch == dest_hash }
          if packet.destination_type == Destination::PLAIN && packet.transport_type == Transport::BROADCAST
            if from_local
              # From local client: retransmit on all interfaces except source
              @@interfaces.each do |iface_hash|
                if iface_hash != interface_hash
                  transmit(iface_hash, raw)
                end
              end
            else
              # From network: retransmit to local clients
              @@local_client_interfaces.each do |lci|
                transmit(lci, raw)
              end
            end
          end
        end

        # General transport handling
        if @@transport_enabled || from_local || for_local_client || for_local_client_link
          # Inject transport ID for local clients if needed
          if packet.transport_id.nil? && for_local_client
            packet.transport_id = @@identity.try(&.hash)
          end

          # Transport forwarding for packets addressed to us as next hop
          if packet.transport_id && packet.packet_type != Packet::ANNOUNCE
            our_hash = @@identity.try(&.hash)
            if our_hash && packet.transport_id == our_hash && dest_hex && @@path_table.has_key?(dest_hex)
              path_entry = @@path_table[dest_hex]
              next_hop = path_entry.next_hop
              remaining_hops = path_entry.hops
              outbound_interface = path_entry.receiving_interface

              if outbound_interface
                new_raw = if remaining_hops > 1
                            # Update next hop and retransmit
                            io = IO::Memory.new
                            io.write(raw[0, 1])     # flags
                            io.write_byte(packet.hops) # updated hops
                            io.write(next_hop)         # new next hop
                            truncated_hash_size = Identity::TRUNCATED_HASHLENGTH // 8
                            io.write(raw[(truncated_hash_size + 2)..])
                            io.to_slice.dup
                          elsif remaining_hops == 1
                            # Strip transport headers
                            new_flags = (Packet::HEADER_1.to_u8 << 6) | (Transport::BROADCAST.to_u8 << 4) | (packet.flags & 0x0F_u8)
                            io = IO::Memory.new
                            io.write_byte(new_flags)
                            io.write_byte(packet.hops)
                            truncated_hash_size = Identity::TRUNCATED_HASHLENGTH // 8
                            io.write(raw[(truncated_hash_size + 2)..])
                            io.to_slice.dup
                          else # remaining_hops == 0
                            io = IO::Memory.new
                            io.write(raw[0, 1])
                            io.write_byte(packet.hops)
                            io.write(raw[2..])
                            io.to_slice.dup
                          end

                # For LINKREQUEST: create link table entry
                if packet.packet_type == Packet::LINKREQUEST
                  now = Time.utc.to_unix_f
                  proof_timeout = now + LinkLike::ESTABLISHMENT_TIMEOUT_PER_HOP * Math.max(1, remaining_hops)

                  # Extract link_id from packet (first 32 bytes of data after dest hash)
                  link_id = packet.destination_hash || Bytes.empty

                  @@link_table[link_id.hexstring] = LinkEntry.new(
                    timestamp: now,
                    next_hop_transport_id: next_hop,
                    next_hop_interface: outbound_interface,
                    remaining_hops: remaining_hops,
                    received_on: interface_hash,
                    taken_hops: packet.hops.to_i32,
                    destination_hash: dest_hash || Bytes.empty,
                    validated: false,
                    proof_timeout: proof_timeout,
                  )
                else
                  # For non-LINKREQUEST: create reverse table entry
                  truncated_hash = packet.get_truncated_hash
                  @@reverse_table[truncated_hash.hexstring] = ReverseEntry.new(
                    received_on: interface_hash,
                    outbound: outbound_interface,
                    timestamp: Time.utc.to_unix_f,
                  )
                end

                transmit(outbound_interface, new_raw)

                # Update path timestamp
                @@path_table[dest_hex] = PathEntry.new(
                  timestamp: Time.utc.to_unix_f,
                  next_hop: path_entry.next_hop,
                  hops: path_entry.hops,
                  expires: path_entry.expires,
                  random_blobs: path_entry.random_blobs,
                  receiving_interface: path_entry.receiving_interface,
                  packet_hash: path_entry.packet_hash,
                )
              else
                RNS.log("Got packet in transport, but no known path to final destination #{dest_hex}. Dropping packet.", RNS::LOG_EXTREME)
              end
            end
          end

          # Link transport handling
          if packet.packet_type != Packet::ANNOUNCE &&
             packet.packet_type != Packet::LINKREQUEST &&
             packet.context != Packet::LRPROOF &&
             dest_hex && @@link_table.has_key?(dest_hex)

            link_entry = @@link_table[dest_hex]
            outbound_interface = nil.as(Bytes?)

            if link_entry.next_hop_interface == link_entry.received_on
              # Same interface for both directions
              if packet.hops.to_i32 == link_entry.remaining_hops || packet.hops.to_i32 == link_entry.taken_hops
                outbound_interface = link_entry.next_hop_interface
              end
            else
              # Different interfaces
              if interface_hash == link_entry.next_hop_interface
                if packet.hops.to_i32 == link_entry.remaining_hops
                  outbound_interface = link_entry.received_on
                end
              elsif interface_hash == link_entry.received_on
                if packet.hops.to_i32 == link_entry.taken_hops
                  outbound_interface = link_entry.next_hop_interface
                end
              end
            end

            if outbound_interface
              ph = packet.packet_hash
              add_packet_hash(ph) if ph

              io = IO::Memory.new
              io.write(raw[0, 1])
              io.write_byte(packet.hops)
              io.write(raw[2..])
              new_raw = io.to_slice.dup
              transmit(outbound_interface, new_raw)

              @@link_table[dest_hex] = LinkEntry.new(
                timestamp: Time.utc.to_unix_f,
                next_hop_transport_id: link_entry.next_hop_transport_id,
                next_hop_interface: link_entry.next_hop_interface,
                remaining_hops: link_entry.remaining_hops,
                received_on: link_entry.received_on,
                taken_hops: link_entry.taken_hops,
                destination_hash: link_entry.destination_hash,
                validated: link_entry.validated,
                proof_timeout: link_entry.proof_timeout,
              )
            end
          end
        end

        # Announce handling
        if packet.packet_type == Packet::ANNOUNCE
          inbound_announce(packet)

        # Link request handling for local destinations
        elsif packet.packet_type == Packet::LINKREQUEST
          our_hash = @@identity.try(&.hash)
          if packet.transport_id.nil? || packet.transport_id == our_hash
            @@destinations.each do |destination|
              if destination.hash == dest_hash && destination.type == packet.destination_type
                destination.receive(packet)
              end
            end
          end

        # Data packet handling
        elsif packet.packet_type == Packet::DATA
          if packet.destination_type == Destination::LINK
            # Deliver to active link
            @@active_links.each do |link|
              if link.link_id == dest_hash
                if link.attached_interface == interface_hash || link.attached_interface.nil?
                  # In full implementation: link.receive(packet)
                  break
                end
              end
            end
          else
            # Deliver to local destination
            @@destinations.each do |destination|
              if destination.hash == dest_hash && destination.type == packet.destination_type
                if destination.receive(packet)
                  if destination.proof_strategy == Destination::PROVE_ALL
                    # packet.prove() — will be available when Packet.prove is implemented
                  elsif destination.proof_strategy == Destination::PROVE_APP
                    cb = destination.callbacks.proof_requested
                    if cb
                      begin
                        # cb.call(packet) would trigger proof
                      rescue ex
                        RNS.log("Error while executing proof request callback: #{ex}", RNS::LOG_ERROR)
                      end
                    end
                  end
                end
              end
            end
          end

        # Proof handling
        elsif packet.packet_type == Packet::PROOF
          if packet.context == Packet::LRPROOF
            # Link request proof handling
            if (@@transport_enabled || for_local_client_link || from_local) && dest_hex && @@link_table.has_key?(dest_hex)
              link_entry = @@link_table[dest_hex]
              if packet.hops.to_i32 == link_entry.remaining_hops
                if interface_hash == link_entry.next_hop_interface
                  # Validate signature for transport
                  sig_length = Identity::SIGLENGTH // 8
                  ecpub_half = LinkLike::ECPUBSIZE // 2

                  if packet.data.size == sig_length + ecpub_half || packet.data.size == sig_length + ecpub_half + 2
                    peer_pub_bytes = packet.data[sig_length, ecpub_half]
                    peer_identity = Identity.recall(link_entry.destination_hash)

                    if peer_identity
                      peer_sig_pub_bytes = peer_identity.get_public_key[ecpub_half, ecpub_half]

                      signalling_bytes = Bytes.empty
                      if packet.data.size > sig_length + ecpub_half
                        signalling_bytes = packet.data[(sig_length + ecpub_half)..]
                      end

                      signed_data = Bytes.new(dest_hash.not_nil!.size + peer_pub_bytes.size + peer_sig_pub_bytes.size + signalling_bytes.size)
                      pos = 0
                      dest_hash.not_nil!.copy_to(signed_data + pos); pos += dest_hash.not_nil!.size
                      peer_pub_bytes.copy_to(signed_data + pos); pos += peer_pub_bytes.size
                      peer_sig_pub_bytes.copy_to(signed_data + pos); pos += peer_sig_pub_bytes.size
                      signalling_bytes.copy_to(signed_data + pos) if signalling_bytes.size > 0

                      signature = packet.data[0, sig_length]

                      if peer_identity.validate(signature, signed_data)
                        RNS.log("Link request proof validated for transport", RNS::LOG_EXTREME)
                        # Mark link as validated
                        @@link_table[dest_hex] = LinkEntry.new(
                          timestamp: link_entry.timestamp,
                          next_hop_transport_id: link_entry.next_hop_transport_id,
                          next_hop_interface: link_entry.next_hop_interface,
                          remaining_hops: link_entry.remaining_hops,
                          received_on: link_entry.received_on,
                          taken_hops: link_entry.taken_hops,
                          destination_hash: link_entry.destination_hash,
                          validated: true,
                          proof_timeout: link_entry.proof_timeout,
                        )

                        io = IO::Memory.new
                        io.write(raw[0, 1])
                        io.write_byte(packet.hops)
                        io.write(raw[2..])
                        new_raw = io.to_slice.dup

                        if link_entry.received_on
                          transmit(link_entry.received_on.not_nil!, new_raw)
                        end
                      else
                        RNS.log("Invalid link request proof in transport for link #{dest_hex}, dropping proof.", RNS::LOG_DEBUG)
                      end
                    end
                  end
                end
              end
            else
              # Deliver to pending link
              @@pending_links.each do |link|
                if link.link_id == dest_hash
                  if packet.hops.to_i32 == link.expected_hops || link.expected_hops == PATHFINDER_M
                    ph = packet.packet_hash
                    add_packet_hash(ph) if ph
                    # link.validate_proof(packet) — when Link is implemented
                  end
                end
              end
            end

          elsif packet.context == Packet::RESOURCE_PRF
            # Resource proof: deliver to active link
            @@active_links.each do |link|
              if link.link_id == dest_hash
                # link.receive(packet) — when Link is implemented
              end
            end

          else
            # Regular proof handling
            if packet.data.size == PacketReceipt::EXPL_LENGTH
              proof_hash = packet.data[0, Identity::HASHLENGTH // 8]
            else
              proof_hash = nil
            end

            # Check if proof needs transport via reverse table
            if (@@transport_enabled || from_local || proof_for_local_client) && dest_hex && @@reverse_table.has_key?(dest_hex)
              reverse_entry = @@reverse_table.delete(dest_hex).not_nil!
              if interface_hash == reverse_entry.outbound
                RNS.log("Proof received on correct interface, transporting it", RNS::LOG_EXTREME)
                io = IO::Memory.new
                io.write(raw[0, 1])
                io.write_byte(packet.hops)
                io.write(raw[2..])
                new_raw = io.to_slice.dup
                if reverse_entry.received_on
                  transmit(reverse_entry.received_on.not_nil!, new_raw)
                end
              else
                RNS.log("Proof received on wrong interface, not transporting it.", RNS::LOG_DEBUG)
              end
            end

            # Validate against outstanding receipts
            @@receipts.reject! do |receipt|
              receipt_validated = false
              if proof_hash
                if receipt.hash == proof_hash
                  receipt_validated = receipt.validate_proof_packet(packet)
                end
              else
                receipt_validated = receipt.validate_proof_packet(packet)
              end
              receipt_validated
            end
          end
        end
      ensure
        @@jobs_locked = false
      end
    end

    # ════════════════════════════════════════════════════════════════
    #  Jobs Loop (Periodic Maintenance)
    # ════════════════════════════════════════════════════════════════

    # Runs all periodic maintenance tasks.
    def self.jobs
      outgoing = [] of Packet
      @@jobs_running = true

      begin
        unless @@jobs_locked
          now = Time.utc.to_unix_f

          # Process pending and active link lists
          if now > @@links_last_checked + LINKS_CHECK_INTERVAL
            @@pending_links.reject! { |link| link.status == LinkLike::CLOSED }
            @@active_links.reject! { |link| link.status == LinkLike::CLOSED }
            @@links_last_checked = now
          end

          # Process receipts
          if now > @@receipts_last_checked + RECEIPTS_CHECK_INTERVAL
            # Cull excess receipts
            while @@receipts.size > MAX_RECEIPTS
              culled = @@receipts.shift
              culled.timeout = -1.0
              culled.check_timeout
            end

            @@receipts.each { |receipt| receipt.check_timeout }
            @@receipts.reject! { |receipt| receipt.status != PacketReceipt::SENT }
            @@receipts_last_checked = now
          end

          # Process announce retransmissions
          if now > @@announces_last_checked + ANNOUNCES_CHECK_INTERVAL
            outgoing = process_announce_table
            @@announces_last_checked = now
          end

          # Cull packet hashlist
          if @@packet_hashlist.size > HASHLIST_MAXSIZE // 2
            @@packet_hashlist_prev = @@packet_hashlist.dup
            @@packet_hashlist.clear
          end

          # Cull discovery PR tags
          if @@discovery_pr_tags.size > MAX_PR_TAGS
            start_idx = @@discovery_pr_tags.size - MAX_PR_TAGS
            @@discovery_pr_tags = @@discovery_pr_tags[start_idx..]
          end

          # Cull tables
          if now > @@tables_last_culled + TABLES_CULL_INTERVAL
            cull_tables(now)
            @@tables_last_culled = now
          end

          # Blackhole expiry
          if now > @@blackhole_last_checked + BLACKHOLE_CHECK_INTERVAL
            cull_blackholes(now)
            @@blackhole_last_checked = now
          end
        end
      rescue ex
        RNS.log("An exception occurred while running Transport jobs: #{ex}", RNS::LOG_ERROR)
      end

      @@jobs_running = false

      # Send outgoing packets after releasing jobs lock
      outgoing.each { |packet| packet.send }
    end

    # Cull stale entries from all routing tables.
    private def self.cull_tables(now : Float64)
      # Remove stale path states
      stale_states = [] of String
      @@path_states.each_key do |dest_hex|
        stale_states << dest_hex unless @@path_table.has_key?(dest_hex)
      end
      stale_states.each { |k| @@path_states.delete(k) }
      RNS.log("Removed #{stale_states.size} path state entries", RNS::LOG_EXTREME) if stale_states.size > 0

      # Cull reverse table
      stale_reverse = [] of String
      @@reverse_table.each do |key, entry|
        if now > entry.timestamp + REVERSE_TIMEOUT
          stale_reverse << key
        elsif entry.outbound && !@@interfaces.any? { |i| i == entry.outbound }
          stale_reverse << key
        elsif entry.received_on && !@@interfaces.any? { |i| i == entry.received_on }
          stale_reverse << key
        end
      end
      stale_reverse.each { |k| @@reverse_table.delete(k) }
      RNS.log("Released #{stale_reverse.size} reverse table entries", RNS::LOG_EXTREME) if stale_reverse.size > 0

      # Cull link table
      stale_links = [] of String
      @@link_table.each do |link_id, entry|
        if entry.validated
          if now > entry.timestamp + LINK_TIMEOUT
            stale_links << link_id
          elsif entry.next_hop_interface && !@@interfaces.any? { |i| i == entry.next_hop_interface }
            stale_links << link_id
          elsif entry.received_on && !@@interfaces.any? { |i| i == entry.received_on }
            stale_links << link_id
          end
        else
          if now > entry.proof_timeout
            stale_links << link_id
          end
        end
      end
      stale_links.each { |k| @@link_table.delete(k) }
      RNS.log("Released #{stale_links.size} links", RNS::LOG_EXTREME) if stale_links.size > 0

      # Cull path table
      stale_paths = [] of String
      @@path_table.each do |dest_hex, entry|
        destination_expiry = entry.timestamp + DESTINATION_TIMEOUT.to_f64
        if now > destination_expiry
          stale_paths << dest_hex
        elsif entry.receiving_interface && !@@interfaces.any? { |i| i == entry.receiving_interface }
          stale_paths << dest_hex
        end
      end
      stale_paths.each { |k| @@path_table.delete(k) }
      RNS.log("Removed #{stale_paths.size} paths", RNS::LOG_EXTREME) if stale_paths.size > 0

      # Cull discovery path requests
      stale_dpr = [] of String
      @@discovery_path_requests.each do |dest_hex, entry|
        timeout_val = entry["timeout"]?
        if timeout_val.is_a?(Float64) && now > timeout_val
          stale_dpr << dest_hex
        end
      end
      stale_dpr.each { |k| @@discovery_path_requests.delete(k) }
      RNS.log("Removed #{stale_dpr.size} waiting path requests", RNS::LOG_EXTREME) if stale_dpr.size > 0

      # Cull tunnels
      stale_tunnels = [] of String
      tunnel_paths_removed = 0
      @@tunnels.each do |tunnel_hex, tunnel_entry|
        if now > tunnel_entry.expires
          stale_tunnels << tunnel_hex
        else
          # Check for stale interface
          if tunnel_entry.interface && !@@interfaces.any? { |i| i == tunnel_entry.interface }
            @@tunnels[tunnel_hex] = TunnelEntry.new(
              tunnel_id: tunnel_entry.tunnel_id,
              interface: nil,
              paths: tunnel_entry.paths,
              expires: tunnel_entry.expires,
            )
          end

          # Cull expired tunnel paths
          stale_tp = [] of String
          tunnel_entry.paths.each do |tp_hex, tp_entry|
            if now > tp_entry.timestamp + DESTINATION_TIMEOUT.to_f64
              stale_tp << tp_hex
            end
          end
          stale_tp.each do |tp_hex|
            tunnel_entry.paths.delete(tp_hex)
            tunnel_paths_removed += 1
          end
        end
      end
      stale_tunnels.each { |k| @@tunnels.delete(k) }
      RNS.log("Removed #{stale_tunnels.size} tunnels", RNS::LOG_EXTREME) if stale_tunnels.size > 0
      RNS.log("Removed #{tunnel_paths_removed} tunnel paths", RNS::LOG_EXTREME) if tunnel_paths_removed > 0
    end

    # Remove expired blackhole entries.
    private def self.cull_blackholes(now : Float64)
      stale = [] of String
      @@blackholed_identities.each do |identity_hex, entry|
        until_val = entry["until"]?
        if until_val.is_a?(Float64) && now > until_val
          stale << identity_hex
        end
      end
      stale.each { |k| @@blackholed_identities.delete(k) }
      RNS.log("Removed #{stale.size} blackholed identities", RNS::LOG_VERBOSE) if stale.size > 0
    end

    # ════════════════════════════════════════════════════════════════
    #  Packet Caching
    # ════════════════════════════════════════════════════════════════

    # Determines whether a packet should be cached.
    # Currently returns false — the Python implementation has this
    # disabled with a TODO to rework the caching system.
    def self.should_cache(packet : Packet) : Bool
      false
    end

    # Caches a packet to storage. Packets are stored exactly as they
    # arrived over their interface (hop count not yet incremented).
    # When force_cache is false, should_cache() is consulted.
    def self.cache(packet : Packet, force_cache : Bool = false, packet_type : String? = nil)
      return unless force_cache || should_cache(packet)

      owner_ref = @@owner
      return unless owner_ref

      begin
        ph = packet.get_hash
        packet_hash_str = ph.hexstring

        cache_path = owner_ref.cache_path
        if packet_type == "announce"
          announce_dir = File.join(cache_path, "announces")
          Dir.mkdir_p(announce_dir) unless Dir.exists?(announce_dir)
          filepath = File.join(announce_dir, packet_hash_str)
        else
          filepath = File.join(cache_path, packet_hash_str)
        end

        raw = packet.raw
        return unless raw

        interface_reference : String? = nil
        # When interface objects are available, store interface name here

        data = Array(MessagePack::Type).new
        data << raw.as(MessagePack::Type)
        data << interface_reference.as(MessagePack::Type)
        File.write(filepath, data.to_msgpack)
      rescue ex
        RNS.log("Error writing packet to cache: #{ex}", RNS::LOG_ERROR)
      end
    end

    # Retrieves a cached packet from storage.
    # Returns the packet if found, nil otherwise.
    def self.get_cached_packet(packet_hash : Bytes, packet_type : String? = nil) : Packet?
      owner_ref = @@owner
      return nil unless owner_ref

      begin
        packet_hash_str = packet_hash.hexstring
        cache_path = owner_ref.cache_path

        path = if packet_type == "announce"
                 File.join(cache_path, "announces", packet_hash_str)
               else
                 File.join(cache_path, packet_hash_str)
               end

        return nil unless File.exists?(path)

        data = File.read(path).to_slice
        cached_data = Array(MessagePack::Type).from_msgpack(data)

        raw = cached_data[0].as(Bytes)
        interface_reference = cached_data[1].as?(String)

        packet = Packet.new(nil, raw)

        # Try to match interface reference to a registered interface
        if interface_reference
          @@interfaces.each do |iface_hash|
            # When interface objects are available, match by string representation
          end
        end

        packet
      rescue ex
        RNS.log("Exception occurred while getting cached packet: #{ex}", RNS::LOG_ERROR)
        nil
      end
    end

    # Handles a cache request packet. Retrieves the requested packet
    # from the local cache and replays it to Transport.
    def self.cache_request_packet(packet : Packet) : Bool
      if packet.data.size == Identity::HASHLENGTH // 8
        cached = get_cached_packet(packet.data)
        if cached
          cached_raw = cached.raw
          if cached_raw
            inbound(cached_raw, nil)
            return true
          end
        end
      end
      false
    end

    # Requests a cached packet either from local cache or from the network.
    def self.cache_request(packet_hash : Bytes, destination : Destination)
      cached_packet = get_cached_packet(packet_hash)
      if cached_packet
        cached_raw = cached_packet.raw
        if cached_raw
          inbound(cached_raw, nil)
        end
      else
        request_packet = Packet.new(
          destination,
          packet_hash,
          context: Packet::CACHE_REQUEST,
        )
        request_packet.send
      end
    end

    # Cleans the packet cache by removing stale announce files.
    def self.clean_cache
      owner_ref = @@owner
      return unless owner_ref
      return if owner_ref.is_connected_to_shared_instance

      clean_announce_cache(owner_ref.cache_path)
      @@cache_last_cleaned = Time.utc.to_unix_f
    end

    # ════════════════════════════════════════════════════════════════
    #  Lifecycle: start, jobloop, exit_handler
    # ════════════════════════════════════════════════════════════════

    # Initializes and starts the Transport layer.
    # Creates or loads the transport identity, loads persisted state
    # (packet hashlist, path table, tunnel table), sets up control
    # destinations, and starts the periodic job fiber.
    def self.start(owner_ref : OwnerRef)
      @@owner = owner_ref
      @@jobs_running = true

      # Load or create transport identity
      if @@identity.nil?
        transport_identity_path = File.join(owner_ref.storage_path, "transport_identity")
        if File.exists?(transport_identity_path)
          @@identity = Identity.from_file(transport_identity_path)
        end

        if @@identity.nil?
          RNS.log("No valid Transport Identity in storage, creating...", RNS::LOG_VERBOSE)
          @@identity = Identity.new
          @@identity.try(&.to_file(transport_identity_path))
        else
          RNS.log("Loaded Transport Identity from storage", RNS::LOG_VERBOSE)
        end
      end

      # Load packet hashlist
      unless owner_ref.is_connected_to_shared_instance
        load_packet_hashlist(owner_ref.storage_path)
      end

      # Create control destinations
      begin
        path_request_dest = Destination.new(
          nil,
          Destination::IN,
          Destination::PLAIN,
          APP_NAME,
          ["path", "request"],
        )
        @@control_destinations << path_request_dest
        @@control_hashes << path_request_dest.hash
      rescue ex
        RNS.log("Could not create path request destination: #{ex}", RNS::LOG_ERROR)
      end

      begin
        tunnel_synth_dest = Destination.new(
          nil,
          Destination::IN,
          Destination::PLAIN,
          APP_NAME,
          ["tunnel", "synthesize"],
        )
        @@control_destinations << tunnel_synth_dest
        @@control_hashes << tunnel_synth_dest.hash
      rescue ex
        RNS.log("Could not create tunnel synthesize destination: #{ex}", RNS::LOG_ERROR)
      end

      # Defer cleaning packet cache for 60 seconds
      @@cache_last_cleaned = Time.utc.to_unix_f + 60.0

      # Defer management announces for 15 seconds
      @@last_mgmt_announce = Time.utc.to_unix_f - MGMT_ANNOUNCE_INTERVAL + 15.0

      # Load transport-related data if transport is enabled
      if owner_ref.transport_enabled
        @@transport_enabled = true

        # Load path table
        unless owner_ref.is_connected_to_shared_instance
          loaded = load_path_table(owner_ref.storage_path)
          if loaded >= 0
            specifier = loaded == 1 ? "entry" : "entries"
            RNS.log("Loaded #{loaded} path table #{specifier} from storage", RNS::LOG_VERBOSE)
          end
        end

        # Load tunnel table
        unless owner_ref.is_connected_to_shared_instance
          loaded = load_tunnel_table(owner_ref.storage_path)
          if loaded >= 0
            specifier = loaded == 1 ? "entry" : "entries"
            RNS.log("Loaded #{loaded} tunnel table #{specifier} from storage", RNS::LOG_VERBOSE)
          end
        end

        identity = @@identity
        if identity
          RNS.log("Transport instance #{identity} started", RNS::LOG_VERBOSE)
        end
      end

      @@start_time = Time.utc.to_unix_f
      @@jobs_running = false

      # Start the periodic job fiber
      start_job_loop
    end

    # Starts the periodic job loop fiber.
    def self.start_job_loop
      return if @@job_loop_running

      @@job_loop_running = true
      @@job_fiber = spawn do
        while @@job_loop_running
          jobs
          sleep(JOB_INTERVAL.seconds)
        end
      end
    end

    # Stops the periodic job loop fiber.
    def self.stop_job_loop
      @@job_loop_running = false
    end

    # Exit handler: persists all transport state to disk.
    # Should be called before shutdown.
    def self.exit_handler
      owner_ref = @@owner
      return unless owner_ref
      return if owner_ref.is_connected_to_shared_instance

      stop_job_loop
      persist_data(owner_ref.storage_path)
    end
  end
end
