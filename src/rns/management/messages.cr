require "msgpack"

module RNS
  module Management
    # Convenience alias for the msgpack-compatible hash type
    private alias MPHash = Hash(MessagePack::Type, MessagePack::Type)

    # ── Supporting data structures ──────────────────────────────────

    class InterfaceEntry
      property name : String = ""
      property type : String = ""
      property mode : UInt8 = 0_u8
      property online : Bool = false
      property bitrate : Int64 = 0_i64
      property mtu : UInt16 = 0_u16
      property rxb : UInt64 = 0_u64
      property txb : UInt64 = 0_u64
      property peers : Array(Bytes) = [] of Bytes
      property ifac_configured : Bool = false
      property ifac_netname : String? = nil
      property announce_queue_size : UInt32 = 0_u32

      def to_msgpack_hash : MPHash
        h = MPHash.new
        h["name"] = @name
        h["type"] = @type
        h["mode"] = @mode.to_u8
        h["online"] = @online
        h["bitrate"] = @bitrate.to_i64
        h["mtu"] = @mtu.to_u16
        h["rxb"] = @rxb.to_u64
        h["txb"] = @txb.to_u64
        h["peers"] = @peers.map { |p| p.as(MessagePack::Type) }
        h["ifac_configured"] = @ifac_configured
        h["ifac_netname"] = @ifac_netname.as(MessagePack::Type)
        h["announce_queue_size"] = @announce_queue_size.to_u32
        h
      end

      def self.from_msgpack_hash(h : Hash) : InterfaceEntry
        e = InterfaceEntry.new
        e.name = h["name"].as(String)
        e.type = h["type"].as(String)
        e.mode = h["mode"].as(Int).to_u8
        e.online = h["online"].as(Bool)
        e.bitrate = h["bitrate"].as(Int).to_i64
        e.mtu = h["mtu"].as(Int).to_u16
        e.rxb = h["rxb"].as(Int).to_u64
        e.txb = h["txb"].as(Int).to_u64
        e.peers = (h["peers"].as(Array)).map { |p| p.as(Bytes) }
        e.ifac_configured = h["ifac_configured"].as(Bool)
        raw_netname = h["ifac_netname"]?
        e.ifac_netname = raw_netname.is_a?(String) ? raw_netname : nil
        e.announce_queue_size = h["announce_queue_size"].as(Int).to_u32
        e
      end
    end

    class AnnounceTableEntry
      property dest_hash : Bytes = Bytes.empty
      property hops : UInt8 = 0_u8
      property interface_name : String = ""
      property timestamp : Float64 = 0.0
      property expires : Float64 = 0.0

      def to_msgpack_hash : MPHash
        h = MPHash.new
        h["dest_hash"] = @dest_hash
        h["hops"] = @hops.to_u8
        h["interface_name"] = @interface_name
        h["timestamp"] = @timestamp
        h["expires"] = @expires
        h
      end

      def self.from_msgpack_hash(h : Hash) : AnnounceTableEntry
        e = AnnounceTableEntry.new
        e.dest_hash = h["dest_hash"].as(Bytes)
        e.hops = h["hops"].as(Int).to_u8
        e.interface_name = h["interface_name"].as(String)
        e.timestamp = h["timestamp"].as(Float64)
        e.expires = h["expires"].as(Float64)
        e
      end
    end

    class PathTableEntry
      property dest_hash : Bytes = Bytes.empty
      property next_hop : Bytes = Bytes.empty
      property hops : UInt8 = 0_u8
      property interface_name : String = ""
      property expires : Float64 = 0.0

      def to_msgpack_hash : MPHash
        h = MPHash.new
        h["dest_hash"] = @dest_hash
        h["next_hop"] = @next_hop
        h["hops"] = @hops.to_u8
        h["interface_name"] = @interface_name
        h["expires"] = @expires
        h
      end

      def self.from_msgpack_hash(h : Hash) : PathTableEntry
        e = PathTableEntry.new
        e.dest_hash = h["dest_hash"].as(Bytes)
        e.next_hop = h["next_hop"].as(Bytes)
        e.hops = h["hops"].as(Int).to_u8
        e.interface_name = h["interface_name"].as(String)
        e.expires = h["expires"].as(Float64)
        e
      end
    end

    class ActiveLinkEntry
      property dest_hash : Bytes = Bytes.empty
      property status : UInt8 = 0_u8
      property rtt : Float64? = nil
      property established_at : Float64? = nil

      def to_msgpack_hash : MPHash
        h = MPHash.new
        h["dest_hash"] = @dest_hash
        h["status"] = @status.to_u8
        h["rtt"] = @rtt.as(MessagePack::Type)
        h["established_at"] = @established_at.as(MessagePack::Type)
        h
      end

      def self.from_msgpack_hash(h : Hash) : ActiveLinkEntry
        e = ActiveLinkEntry.new
        e.dest_hash = h["dest_hash"].as(Bytes)
        e.status = h["status"].as(Int).to_u8
        raw_rtt = h["rtt"]?
        e.rtt = raw_rtt.is_a?(Float64) ? raw_rtt : nil
        raw_est = h["established_at"]?
        e.established_at = raw_est.is_a?(Float64) ? raw_est : nil
        e
      end
    end

    # ── Management Protocol Messages ───────────────────────────────

    # 1. NodeStateReport (node -> Reticule)
    class NodeStateReport < MessageBase
      class_getter msgtype : UInt16 = 0x0100_u16

      property node_identity_hash : Bytes = Bytes.empty
      property uptime : Float64 = 0.0
      property config_hash : Bytes = Bytes.empty
      property timestamp : Float64 = 0.0
      property interfaces : Array(InterfaceEntry) = [] of InterfaceEntry
      property announce_table : Array(AnnounceTableEntry) = [] of AnnounceTableEntry
      property path_table : Array(PathTableEntry) = [] of PathTableEntry
      property active_links : Array(ActiveLinkEntry) = [] of ActiveLinkEntry

      def pack : Bytes
        h = MPHash.new
        h["node_identity_hash"] = @node_identity_hash
        h["uptime"] = @uptime
        h["config_hash"] = @config_hash
        h["timestamp"] = @timestamp
        h["interfaces"] = @interfaces.map { |i| i.to_msgpack_hash.as(MessagePack::Type) }
        h["announce_table"] = @announce_table.map { |a| a.to_msgpack_hash.as(MessagePack::Type) }
        h["path_table"] = @path_table.map { |p| p.to_msgpack_hash.as(MessagePack::Type) }
        h["active_links"] = @active_links.map { |l| l.to_msgpack_hash.as(MessagePack::Type) }
        h.to_msgpack
      end

      def unpack(raw : Bytes)
        pull = MessagePack::IOUnpacker.new(IO::Memory.new(raw))
        h = pull.read.as(Hash)
        @node_identity_hash = h["node_identity_hash"].as(Bytes)
        @uptime = h["uptime"].as(Float64)
        @config_hash = h["config_hash"].as(Bytes)
        @timestamp = h["timestamp"].as(Float64)
        @interfaces = h["interfaces"].as(Array).map { |i| InterfaceEntry.from_msgpack_hash(i.as(Hash)) }
        @announce_table = h["announce_table"].as(Array).map { |a| AnnounceTableEntry.from_msgpack_hash(a.as(Hash)) }
        @path_table = h["path_table"].as(Array).map { |p| PathTableEntry.from_msgpack_hash(p.as(Hash)) }
        @active_links = h["active_links"].as(Array).map { |l| ActiveLinkEntry.from_msgpack_hash(l.as(Hash)) }
      end
    end

    # 2. ConfigPush (Reticule -> node)
    class ConfigPush < MessageBase
      class_getter msgtype : UInt16 = 0x0101_u16

      property push_id : Bytes = Bytes.empty
      property strategy : UInt8 = 0_u8
      property config_sections : Hash(String, Hash(String, String)) = {} of String => Hash(String, String)
      property expected_hash : Bytes = Bytes.empty

      def pack : Bytes
        h = MPHash.new
        h["push_id"] = @push_id
        h["strategy"] = @strategy.to_u8
        sections = MPHash.new
        @config_sections.each do |section_name, kvs|
          inner = MPHash.new
          kvs.each { |k, v| inner[k.as(MessagePack::Type)] = v.as(MessagePack::Type) }
          sections[section_name.as(MessagePack::Type)] = inner.as(MessagePack::Type)
        end
        h["config_sections"] = sections.as(MessagePack::Type)
        h["expected_hash"] = @expected_hash
        h.to_msgpack
      end

      def unpack(raw : Bytes)
        pull = MessagePack::IOUnpacker.new(IO::Memory.new(raw))
        h = pull.read.as(Hash)
        @push_id = h["push_id"].as(Bytes)
        @strategy = h["strategy"].as(Int).to_u8
        raw_sections = h["config_sections"].as(Hash)
        @config_sections = {} of String => Hash(String, String)
        raw_sections.each do |section_name, kvs|
          inner = {} of String => String
          kvs.as(Hash).each { |k, v| inner[k.as(String)] = v.as(String) }
          @config_sections[section_name.as(String)] = inner
        end
        @expected_hash = h["expected_hash"].as(Bytes)
      end
    end

    # 3. ConfigAck (node -> Reticule)
    class ConfigAck < MessageBase
      class_getter msgtype : UInt16 = 0x0102_u16

      STATUS_APPLIED                 = 0_u8
      STATUS_APPLIED_PENDING_RESTART = 1_u8
      STATUS_VALIDATION_FAILED       = 2_u8
      STATUS_APPLY_FAILED            = 3_u8

      property push_id : Bytes = Bytes.empty
      property status : UInt8 = 0_u8
      property config_hash : Bytes = Bytes.empty
      property error_message : String? = nil

      def pack : Bytes
        h = MPHash.new
        h["push_id"] = @push_id
        h["status"] = @status.to_u8
        h["config_hash"] = @config_hash
        h["error_message"] = @error_message.as(MessagePack::Type)
        h.to_msgpack
      end

      def unpack(raw : Bytes)
        pull = MessagePack::IOUnpacker.new(IO::Memory.new(raw))
        h = pull.read.as(Hash)
        @push_id = h["push_id"].as(Bytes)
        @status = h["status"].as(Int).to_u8
        @config_hash = h["config_hash"].as(Bytes)
        raw_err = h["error_message"]?
        @error_message = raw_err.is_a?(String) ? raw_err : nil
      end
    end

    # 4. Heartbeat (bidirectional)
    class Heartbeat < MessageBase
      class_getter msgtype : UInt16 = 0x0103_u16

      property timestamp : Float64 = 0.0
      property sequence : UInt32 = 0_u32

      def pack : Bytes
        h = MPHash.new
        h["timestamp"] = @timestamp
        h["sequence"] = @sequence.to_u32
        h.to_msgpack
      end

      def unpack(raw : Bytes)
        pull = MessagePack::IOUnpacker.new(IO::Memory.new(raw))
        h = pull.read.as(Hash)
        @timestamp = h["timestamp"].as(Float64)
        @sequence = h["sequence"].as(Int).to_u32
      end
    end

    # 5. JoinRequest (node -> Reticule)
    class JoinRequest < MessageBase
      class_getter msgtype : UInt16 = 0x0110_u16

      property token_secret : Bytes = Bytes.empty
      property identity_pubkey : Bytes = Bytes.empty
      property hostname : String = ""
      property platform : String = ""
      property daemon_version : String = ""

      def pack : Bytes
        h = MPHash.new
        h["token_secret"] = @token_secret
        h["identity_pubkey"] = @identity_pubkey
        h["hostname"] = @hostname
        h["platform"] = @platform
        h["daemon_version"] = @daemon_version
        h.to_msgpack
      end

      def unpack(raw : Bytes)
        pull = MessagePack::IOUnpacker.new(IO::Memory.new(raw))
        h = pull.read.as(Hash)
        @token_secret = h["token_secret"].as(Bytes)
        @identity_pubkey = h["identity_pubkey"].as(Bytes)
        @hostname = h["hostname"].as(String)
        @platform = h["platform"].as(String)
        @daemon_version = h["daemon_version"].as(String)
      end
    end

    # 6. JoinResponse (Reticule -> node)
    class JoinResponse < MessageBase
      class_getter msgtype : UInt16 = 0x0111_u16

      property accepted : Bool = false
      property node_id : Bytes? = nil
      property config_sections : Hash(String, Hash(String, String))? = nil
      property reject_reason : String? = nil

      def pack : Bytes
        h = MPHash.new
        h["accepted"] = @accepted
        h["node_id"] = @node_id.as(MessagePack::Type)
        if cs = @config_sections
          sections = MPHash.new
          cs.each do |section_name, kvs|
            inner = MPHash.new
            kvs.each { |k, v| inner[k.as(MessagePack::Type)] = v.as(MessagePack::Type) }
            sections[section_name.as(MessagePack::Type)] = inner.as(MessagePack::Type)
          end
          h["config_sections"] = sections.as(MessagePack::Type)
        else
          h["config_sections"] = nil
        end
        h["reject_reason"] = @reject_reason.as(MessagePack::Type)
        h.to_msgpack
      end

      def unpack(raw : Bytes)
        pull = MessagePack::IOUnpacker.new(IO::Memory.new(raw))
        h = pull.read.as(Hash)
        @accepted = h["accepted"].as(Bool)
        raw_node_id = h["node_id"]?
        @node_id = raw_node_id.is_a?(Bytes) ? raw_node_id : nil
        raw_sections = h["config_sections"]?
        if raw_sections.is_a?(Hash)
          @config_sections = {} of String => Hash(String, String)
          raw_sections.each do |section_name, kvs|
            inner = {} of String => String
            kvs.as(Hash).each { |k, v| inner[k.as(String)] = v.as(String) }
            @config_sections.not_nil![section_name.as(String)] = inner
          end
        else
          @config_sections = nil
        end
        raw_reason = h["reject_reason"]?
        @reject_reason = raw_reason.is_a?(String) ? raw_reason : nil
      end
    end
  end
end
