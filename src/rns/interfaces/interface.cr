# Define O_NOCTTY for platforms where Crystal's LibC doesn't include it (macOS).
{% unless LibC.has_constant?(:O_NOCTTY) %}
  lib LibC
    O_NOCTTY = 0x20000
  end
{% end %}

module RNS
  # HDLC framing helpers used by Serial, TCP, Pipe, and I2P interfaces.
  # Simplified HDLC framing similar to PPP.
  module HDLC
    FLAG     = 0x7E_u8
    ESC      = 0x7D_u8
    ESC_MASK = 0x20_u8

    def self.escape(data : Bytes) : Bytes
      io = IO::Memory.new(data.size)
      data.each do |byte|
        if byte == ESC
          io.write_byte(ESC)
          io.write_byte(ESC ^ ESC_MASK)
        elsif byte == FLAG
          io.write_byte(ESC)
          io.write_byte(FLAG ^ ESC_MASK)
        else
          io.write_byte(byte)
        end
      end
      io.to_slice
    end

    def self.unescape(data : Bytes) : Bytes
      io = IO::Memory.new(data.size)
      i = 0
      while i < data.size
        byte = data[i]
        if byte == ESC && i + 1 < data.size
          i += 1
          next_byte = data[i]
          if next_byte == (FLAG ^ ESC_MASK)
            io.write_byte(FLAG)
          elsif next_byte == (ESC ^ ESC_MASK)
            io.write_byte(ESC)
          else
            io.write_byte(next_byte)
          end
        else
          io.write_byte(byte)
        end
        i += 1
      end
      io.to_slice
    end

    def self.frame(data : Bytes) : Bytes
      io = IO::Memory.new(data.size + 2)
      io.write_byte(FLAG)
      io.write(escape(data))
      io.write_byte(FLAG)
      io.to_slice
    end
  end

  # KISS framing helpers used by TCP (kiss_framing mode), KISS, and AX.25 interfaces.
  module KISS
    FEND            = 0xC0_u8
    FESC            = 0xDB_u8
    TFEND           = 0xDC_u8
    TFESC           = 0xDD_u8
    CMD_DATA        = 0x00_u8
    CMD_TXDELAY     = 0x01_u8
    CMD_P           = 0x02_u8
    CMD_SLOTTIME    = 0x03_u8
    CMD_TXTAIL      = 0x04_u8
    CMD_FULLDUPLEX  = 0x05_u8
    CMD_SETHARDWARE = 0x06_u8
    CMD_READY       = 0x0F_u8
    CMD_UNKNOWN     = 0xFE_u8
    CMD_RETURN      = 0xFF_u8

    def self.escape(data : Bytes) : Bytes
      io = IO::Memory.new(data.size)
      data.each do |byte|
        if byte == FESC
          io.write_byte(FESC)
          io.write_byte(TFESC)
        elsif byte == FEND
          io.write_byte(FESC)
          io.write_byte(TFEND)
        else
          io.write_byte(byte)
        end
      end
      io.to_slice
    end

    def self.unescape(data : Bytes) : Bytes
      io = IO::Memory.new(data.size)
      i = 0
      while i < data.size
        byte = data[i]
        if byte == FESC && i + 1 < data.size
          i += 1
          next_byte = data[i]
          if next_byte == TFEND
            io.write_byte(FEND)
          elsif next_byte == TFESC
            io.write_byte(FESC)
          else
            io.write_byte(next_byte)
          end
        else
          io.write_byte(byte)
        end
        i += 1
      end
      io.to_slice
    end

    def self.frame(data : Bytes) : Bytes
      io = IO::Memory.new(data.size + 4)
      io.write_byte(FEND)
      io.write_byte(CMD_DATA)
      io.write(escape(data))
      io.write_byte(FEND)
      io.to_slice
    end
  end

  # Base interface class for the Reticulum Network Stack.
  # All concrete interfaces (UDP, TCP, Serial, etc.) inherit from this.
  abstract class Interface
    # Direction flags
    IN  = false
    OUT = false
    FWD = false
    RPT = false

    # Interface mode definitions
    MODE_FULL           = 0x01_u8
    MODE_POINT_TO_POINT = 0x02_u8
    MODE_ACCESS_POINT   = 0x03_u8
    MODE_ROAMING        = 0x04_u8
    MODE_BOUNDARY       = 0x05_u8
    MODE_GATEWAY        = 0x06_u8

    # Which interface modes a Transport Node should actively discover paths for
    DISCOVER_PATHS_FOR = [MODE_ACCESS_POINT, MODE_GATEWAY, MODE_ROAMING]

    # How many samples to use for announce frequency calculations
    IA_FREQ_SAMPLES = 6
    OA_FREQ_SAMPLES = 6

    # Maximum amount of ingress limited announces to hold at any given time
    MAX_HELD_ANNOUNCES = 256

    # Spawned interface new time (2 hours)
    IC_NEW_TIME              = 2 * 60 * 60
    IC_BURST_FREQ_NEW        =  3.5
    IC_BURST_FREQ            = 12.0
    IC_BURST_HOLD            = 1 * 60
    IC_BURST_PENALTY         = 5 * 60
    IC_HELD_RELEASE_INTERVAL = 30

    # Announce cap and queued announce life (from Reticulum)
    ANNOUNCE_CAP         = 2
    QUEUED_ANNOUNCE_LIFE = 60 * 60 * 24 # 1 day in seconds

    # MTU configuration flags — subclasses may override
    AUTOCONFIGURE_MTU = false
    FIXED_MTU         = false

    # Properties
    property name : String = ""
    property rxb : Int64 = 0_i64
    property txb : Int64 = 0_i64
    property online : Bool = false
    property bitrate : Int64 = 62500_i64
    property hw_mtu : Int32? = nil
    property mode : UInt8 = MODE_FULL
    property mtu : Int32 = Reticulum::MTU

    # Detach state
    getter? detached : Bool = false

    # Discovery properties
    property supports_discovery : Bool = false
    property discoverable : Bool = false
    property last_discovery_announce : Float64 = 0.0
    property bootstrap_only : Bool = false
    property discovery_announce_interval : Int32? = nil
    property discovery_publish_ifac : Bool = false
    property reachable_on : String? = nil
    property discovery_name : String? = nil
    property discovery_encrypt : Bool = false
    property discovery_stamp_value : Int32? = nil
    property discovery_latitude : Float64? = nil
    property discovery_longitude : Float64? = nil
    property discovery_height : Float64? = nil
    property discovery_frequency : Int32? = nil
    property discovery_bandwidth : Int32? = nil
    property discovery_modulation : Int32? = nil
    property discovery_channel : Int32? = nil

    # Autoconnect properties (set by InterfaceDiscovery)
    property autoconnect_hash : Bytes? = nil
    property autoconnect_source : String? = nil
    property autoconnect_down : Float64? = nil

    # Parent/spawned interface references
    property parent_interface : Interface? = nil
    property spawned_interfaces : Array(Interface)? = nil
    property tunnel_id : Bytes? = nil

    # Ingress control properties
    property ingress_control : Bool = true
    property ic_max_held_announces : Int32 = MAX_HELD_ANNOUNCES
    property ic_burst_hold : Int32 = IC_BURST_HOLD
    property ic_burst_active : Bool = false
    property ic_burst_activated : Float64 = 0.0
    property ic_held_release : Float64 = 0.0
    property ic_burst_freq_new : Float64 = IC_BURST_FREQ_NEW
    property ic_burst_freq : Float64 = IC_BURST_FREQ
    property ic_new_time : Int32 = IC_NEW_TIME
    property ic_burst_penalty : Int32 = IC_BURST_PENALTY
    property ic_held_release_interval : Int32 = IC_HELD_RELEASE_INTERVAL

    # Held announces: destination_hash => raw packet bytes
    property held_announces : Hash(String, HeldAnnounce) = {} of String => HeldAnnounce

    # Announce frequency tracking deques (bounded arrays)
    @ia_freq_deque : Array(Float64) = [] of Float64
    @oa_freq_deque : Array(Float64) = [] of Float64

    # Announce queue and rate limiting
    property announce_queue : Array(AnnounceQueueEntry) = [] of AnnounceQueueEntry
    property announce_cap : Float64 = ANNOUNCE_CAP / 100.0
    property announce_allowed_at : Float64 = 0.0

    # Announce rate limiting (set by Reticulum config)
    property announce_rate_target : Int32? = nil
    property announce_rate_grace : Int32? = nil
    property announce_rate_penalty : Int32? = nil

    # IFAC (Interface Authentication Code) properties
    property ifac_size : Int32 = 0
    property ifac_netname : String? = nil
    property ifac_netkey : String? = nil
    property ifac_key : Bytes? = nil
    property ifac_identity : Identity? = nil
    property ifac_signature : Bytes? = nil

    # Interface creation time
    getter created : Float64

    # A lightweight struct for held announce packets
    record HeldAnnounce,
      raw : Bytes,
      destination_hash : Bytes,
      hops : Int32,
      receiving_interface : Interface?

    # An entry in the announce queue
    record AnnounceQueueEntry,
      raw : Bytes,
      hops : Int32,
      time : Float64

    def initialize
      @created = Time.utc.to_unix_f
    end

    # Compute a hash of this interface based on its string representation
    def get_hash : Bytes
      RNS::Identity.full_hash(to_s.encode("UTF-8"))
    end

    # Determine when an interface should activate ingress limiting.
    # Subclasses may override for different behavior.
    def should_ingress_limit? : Bool
      return false unless @ingress_control

      freq_threshold = age < @ic_new_time ? @ic_burst_freq_new : @ic_burst_freq
      ia_freq = incoming_announce_frequency

      if @ic_burst_active
        if ia_freq < freq_threshold && Time.utc.to_unix_f > @ic_burst_activated + @ic_burst_hold
          @ic_burst_active = false
          @ic_held_release = Time.utc.to_unix_f + @ic_burst_penalty
        end
        true
      else
        if ia_freq > freq_threshold
          @ic_burst_active = true
          @ic_burst_activated = Time.utc.to_unix_f
          true
        else
          false
        end
      end
    end

    # Auto-configure HW_MTU based on bitrate
    def optimise_mtu
      if self.class.autoconfigure_mtu?
        @hw_mtu = case @bitrate
                  when .>= 1_000_000_000 then 524288
                  when .> 750_000_000    then 262144
                  when .> 400_000_000    then 131072
                  when .> 200_000_000    then 65536
                  when .> 100_000_000    then 32768
                  when .> 10_000_000     then 16384
                  when .> 5_000_000      then 8192
                  when .> 2_000_000      then 4096
                  when .> 1_000_000      then 2048
                  when .> 62_500         then 1024
                  else                        nil
                  end
      end
    end

    # Override in subclasses that have auto-configurable MTU
    def self.autoconfigure_mtu? : Bool
      AUTOCONFIGURE_MTU
    end

    # Age of the interface in seconds
    def age : Float64
      Time.utc.to_unix_f - @created
    end

    # Hold an announce packet for later release
    def hold_announce(announce : HeldAnnounce)
      key = announce.destination_hash.hexstring
      if @held_announces.has_key?(key)
        @held_announces[key] = announce
      elsif @held_announces.size < @ic_max_held_announces
        @held_announces[key] = announce
      end
    end

    # Process and release held announces when rate allows
    def process_held_announces
      if !should_ingress_limit? && @held_announces.size > 0 && Time.utc.to_unix_f > @ic_held_release
        freq_threshold = age < @ic_new_time ? @ic_burst_freq_new : @ic_burst_freq
        ia_freq = incoming_announce_frequency

        if ia_freq < freq_threshold
          # Find announce with minimum hops
          selected_key : String? = nil
          min_hops = Transport::PATHFINDER_M
          @held_announces.each do |key, announce|
            if announce.hops < min_hops
              min_hops = announce.hops
              selected_key = key
            end
          end

          if sk = selected_key
            selected = @held_announces[sk]
            @ic_held_release = Time.utc.to_unix_f + @ic_held_release_interval
            @held_announces.delete(sk)
            spawn do
              iface_hash = selected.receiving_interface.try(&.get_hash)
              Transport.inbound(selected.raw, iface_hash)
            end
          end
        end
      end
    rescue ex
      RNS.log("An error occurred while processing held announces for #{self}: #{ex.message}", RNS::LOG_ERROR)
    end

    # Record an incoming announce timestamp
    def received_announce(from_spawned = false)
      @ia_freq_deque << Time.utc.to_unix_f
      if @ia_freq_deque.size > IA_FREQ_SAMPLES
        @ia_freq_deque.shift
      end
      if pi = @parent_interface
        pi.received_announce(from_spawned: true)
      end
    end

    # Record an outgoing announce timestamp
    def sent_announce(from_spawned = false)
      @oa_freq_deque << Time.utc.to_unix_f
      if @oa_freq_deque.size > OA_FREQ_SAMPLES
        @oa_freq_deque.shift
      end
      if pi = @parent_interface
        pi.sent_announce(from_spawned: true)
      end
    end

    # Calculate the incoming announce frequency (announces/second)
    def incoming_announce_frequency : Float64
      return 0.0 unless @ia_freq_deque.size > 1

      dq_len = @ia_freq_deque.size
      delta_sum = 0.0
      (1...dq_len).each do |i|
        delta_sum += @ia_freq_deque[i] - @ia_freq_deque[i - 1]
      end
      delta_sum += Time.utc.to_unix_f - @ia_freq_deque[dq_len - 1]

      return 0.0 if delta_sum == 0.0
      1.0 / (delta_sum / dq_len)
    end

    # Calculate the outgoing announce frequency (announces/second)
    def outgoing_announce_frequency : Float64
      return 0.0 unless @oa_freq_deque.size > 1

      dq_len = @oa_freq_deque.size
      delta_sum = 0.0
      (1...dq_len).each do |i|
        delta_sum += @oa_freq_deque[i] - @oa_freq_deque[i - 1]
      end
      delta_sum += Time.utc.to_unix_f - @oa_freq_deque[dq_len - 1]

      return 0.0 if delta_sum == 0.0
      1.0 / (delta_sum / dq_len)
    end

    # Process the announce queue: send oldest lowest-hop announce, respecting rate cap
    def process_announce_queue
      return if @announce_queue.empty?

      now = Time.utc.to_unix_f

      # Remove stale entries
      @announce_queue.reject! { |a| now > a.time + QUEUED_ANNOUNCE_LIFE }

      return if @announce_queue.empty?

      # Find minimum hops
      min_hops = @announce_queue.min_of(&.hops)
      entries = @announce_queue.select { |e| e.hops == min_hops }
      entries.sort_by!(&.time)
      selected = entries.first

      tx_time = (selected.raw.size * 8).to_f64 / @bitrate
      wait_time = tx_time / @announce_cap
      @announce_allowed_at = now + wait_time

      process_outgoing(selected.raw)
      sent_announce

      @announce_queue.reject! { |a| a.raw == selected.raw && a.time == selected.time }

      unless @announce_queue.empty?
        spawn do
          sleep wait_time.seconds
          process_announce_queue
        end
      end
    rescue ex
      @announce_queue.clear
      RNS.log("Error while processing announce queue on #{self}: #{ex.message}", RNS::LOG_ERROR)
      RNS.log("The announce queue for this interface has been cleared.", RNS::LOG_ERROR)
    end

    # Send data out through the interface. Subclasses must implement this.
    abstract def process_outgoing(data : Bytes)

    # Called after interface configuration is complete
    def final_init
    end

    # Called when the interface is being detached/removed
    def detach
      @detached = true
    end

    # Access the ia/oa frequency deques for testing
    def ia_freq_deque
      @ia_freq_deque
    end

    def oa_freq_deque
      @oa_freq_deque
    end

    def to_s(io : IO)
      io << @name
    end
  end
end
