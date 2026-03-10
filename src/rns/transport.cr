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

    # ─── Core state (class-level variables) ────────────────────────
    @@interfaces = [] of Bytes         # Interface hashes (actual interface objects managed elsewhere)
    @@destinations = [] of Destination
    @@pending_links = [] of Bytes      # Link IDs (actual Link objects when Link is implemented)
    @@active_links = [] of Bytes       # Link IDs
    @@packet_hashlist = Set(String).new
    @@packet_hashlist_prev = Set(String).new
    @@receipts = [] of PacketReceipt

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
    @@pending_local_path_requests = Hash(String, Float64).new

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
    @@owner : Nil = nil  # Will be Reticulum instance when implemented

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
      @@saving_path_table = false
      @@saving_packet_hashlist = false
      @@saving_tunnel_table = false
    end

    # Alias for backward compat with existing specs
    def self.clear_destinations
      @@destinations.clear
    end
  end
end
