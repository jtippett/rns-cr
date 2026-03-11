module RNS
  module Rnstatus
    # Parsed command-line arguments for rnstatus
    class Args
      property config : String?
      property verbose : Int32
      property all : Bool
      property announce_stats : Bool
      property link_stats : Bool
      property totals : Bool
      property sort : String?
      property reverse : Bool
      property json : Bool
      property remote : String?
      property identity : String?
      property timeout : Float64
      property discovered : Bool
      property discovered_details : Bool
      property monitor : Bool
      property monitor_interval : Float64
      property filter : String?
      property version : Bool

      def initialize(
        @config = nil,
        @verbose = 0,
        @all = false,
        @announce_stats = false,
        @link_stats = false,
        @totals = false,
        @sort = nil,
        @reverse = false,
        @json = false,
        @remote = nil,
        @identity = nil,
        @timeout = Transport::PATH_REQUEST_TIMEOUT.to_f64,
        @discovered = false,
        @discovered_details = false,
        @monitor = false,
        @monitor_interval = 1.0,
        @filter = nil,
        @version = false,
      )
      end
    end

    # Parse command-line arguments matching Python argparse behavior.
    def self.parse_args(argv : Array(String)) : Args
      args = Args.new
      i = 0
      while i < argv.size
        arg = argv[i]
        case arg
        when "--config"
          i += 1
          args.config = argv[i]? || raise ArgumentError.new("--config requires a path argument")
        when "--version"
          args.version = true
        when "-a", "--all"
          args.all = true
        when "-A", "--announce-stats"
          args.announce_stats = true
        when "-l", "--link-stats"
          args.link_stats = true
        when "-t", "--totals"
          args.totals = true
        when "-s", "--sort"
          i += 1
          args.sort = argv[i]? || raise ArgumentError.new("--sort requires a value")
        when "-r", "--reverse"
          args.reverse = true
        when "-j", "--json"
          args.json = true
        when "-R"
          i += 1
          args.remote = argv[i]? || raise ArgumentError.new("-R requires a hash argument")
        when "-i"
          i += 1
          args.identity = argv[i]? || raise ArgumentError.new("-i requires a path argument")
        when "-w"
          i += 1
          val = argv[i]? || raise ArgumentError.new("-w requires a seconds value")
          args.timeout = val.to_f64
        when "-d", "--discovered"
          args.discovered = true
        when "-D"
          args.discovered_details = true
        when "-m", "--monitor"
          args.monitor = true
        when "-I", "--monitor-interval"
          i += 1
          val = argv[i]? || raise ArgumentError.new("--monitor-interval requires a seconds value")
          args.monitor_interval = val.to_f64
        when /^-[vAaltrjdDm]+$/
          arg[1..].each_char do |char|
            case char
            when 'v' then args.verbose += 1
            when 'A' then args.announce_stats = true
            when 'a' then args.all = true
            when 'l' then args.link_stats = true
            when 't' then args.totals = true
            when 'r' then args.reverse = true
            when 'j' then args.json = true
            when 'd' then args.discovered = true
            when 'D' then args.discovered_details = true
            when 'm' then args.monitor = true
            else
              raise ArgumentError.new("Unknown flag: -#{char}")
            end
          end
        else
          if arg.starts_with?("-")
            raise ArgumentError.new("Unknown argument: #{arg}")
          else
            args.filter = arg
          end
        end
        i += 1
      end
      args
    end

    # Version string matching Python's "rnstatus {version}" format.
    def self.version_string : String
      "rnstatus #{RNS::VERSION}"
    end

    # Format a speed value as a human-readable string with unit suffix.
    # Matches rnstatus.py speed_str() exactly.
    def self.speed_str(num : Float64, suffix : String = "bps") : String
      units = ["", "k", "M", "G", "T", "P", "E", "Z"]
      last_unit = "Y"

      if suffix == "Bps"
        num /= 8.0
        units = ["", "K", "M", "G", "T", "P", "E", "Z"]
        last_unit = "Y"
      end

      units.each do |unit|
        if num.abs < 1000.0
          return "%3.2f %s%s" % [num, unit, suffix]
        end
        num /= 1000.0
      end

      "%.2f %s%s" % [num, last_unit, suffix]
    end

    # Format a byte count with appropriate unit suffix.
    # Matches rnstatus.py size_str() exactly.
    def self.size_str(num : Float64, suffix : String = "B") : String
      units = ["", "K", "M", "G", "T", "P", "E", "Z"]
      last_unit = "Y"

      if suffix == "b"
        num *= 8
        units = ["", "K", "M", "G", "T", "P", "E", "Z"]
        last_unit = "Y"
      end

      units.each do |unit|
        if num.abs < 1000.0
          if unit == ""
            return "%.0f %s%s" % [num, unit, suffix]
          else
            return "%.2f %s%s" % [num, unit, suffix]
          end
        end
        num /= 1000.0
      end

      "%.2f%s%s" % [num, last_unit, suffix]
    end

    # Return a mode string from an interface mode constant.
    def self.mode_str(mode : UInt8) : String
      case mode
      when Interface::MODE_ACCESS_POINT   then "Access Point"
      when Interface::MODE_POINT_TO_POINT then "Point-to-Point"
      when Interface::MODE_ROAMING        then "Roaming"
      when Interface::MODE_BOUNDARY       then "Boundary"
      when Interface::MODE_GATEWAY        then "Gateway"
      else                                     "Full"
      end
    end

    # An interface stats record for displaying status.
    record InterfaceStat,
      name : String,
      short_name : String,
      hash : Bytes,
      type_name : String,
      status : Bool,
      mode : UInt8,
      rxb : Int64,
      txb : Int64,
      rxs : Float64,
      txs : Float64,
      clients : Int32?,
      bitrate : Int64?,
      incoming_announce_frequency : Float64,
      outgoing_announce_frequency : Float64,
      held_announces : Int32,
      announce_queue : Int32?,
      ifac_signature : Bytes?,
      ifac_size : Int32,
      ifac_netname : String?,
      autoconnect_source : String?,
      peers : Int32?

    # A transport stats record for the overall system.
    record TransportStats,
      interfaces : Array(InterfaceStat),
      rxb : Int64,
      txb : Int64,
      rxs : Int64,
      txs : Int64,
      transport_id : Bytes?,
      network_id : Bytes?,
      transport_uptime : Float64?,
      probe_responder : Bytes?

    # Collect interface stats from the running Transport instance.
    # Matches Python Reticulum.get_interface_stats() behavior.
    def self.get_interface_stats : TransportStats
      interfaces = [] of InterfaceStat

      Transport.interface_objects.each do |iface|
        ifstat = InterfaceStat.new(
          name: iface.to_s,
          short_name: iface.name,
          hash: iface.get_hash,
          type_name: iface.class.name.split("::").last,
          status: iface.online,
          mode: iface.mode,
          rxb: iface.rxb,
          txb: iface.txb,
          rxs: 0.0,
          txs: 0.0,
          clients: nil,
          bitrate: iface.bitrate,
          incoming_announce_frequency: iface.incoming_announce_frequency,
          outgoing_announce_frequency: iface.outgoing_announce_frequency,
          held_announces: iface.held_announces.size,
          announce_queue: iface.announce_queue.size,
          ifac_signature: iface.ifac_signature,
          ifac_size: iface.ifac_size,
          ifac_netname: iface.ifac_netname,
          autoconnect_source: iface.autoconnect_source,
          peers: nil,
        )
        interfaces << ifstat
      end

      transport_id = nil.as(Bytes?)
      network_id = nil.as(Bytes?)
      transport_uptime = nil.as(Float64?)
      probe_responder = nil.as(Bytes?)

      if Reticulum.transport_enabled?
        if tid = Transport.identity
          transport_id = tid.hash
        end
        if st = Transport.start_time
          transport_uptime = Time.utc.to_unix_f - st
        end
      end

      TransportStats.new(
        interfaces: interfaces,
        rxb: Transport.traffic_rxb,
        txb: Transport.traffic_txb,
        rxs: Transport.speed_rx,
        txs: Transport.speed_tx,
        transport_id: transport_id,
        network_id: network_id,
        transport_uptime: transport_uptime,
        probe_responder: probe_responder,
      )
    end

    # Sort interfaces by the given criterion.
    def self.sort_interfaces(interfaces : Array(InterfaceStat), sorting : String?, sort_reverse : Bool) : Array(InterfaceStat)
      return interfaces unless sorting
      s = sorting.downcase
      sorted = case s
               when "rate", "bitrate"
                 interfaces.sort_by { |i| i.bitrate || 0_i64 }
               when "rx"
                 interfaces.sort_by(&.rxb)
               when "tx"
                 interfaces.sort_by(&.txb)
               when "rxs"
                 interfaces.sort_by(&.rxs)
               when "txs"
                 interfaces.sort_by(&.txs)
               when "traffic"
                 interfaces.sort_by { |i| i.rxb + i.txb }
               when "announces", "announce"
                 interfaces.sort_by { |i| i.incoming_announce_frequency + i.outgoing_announce_frequency }
               when "arx"
                 interfaces.sort_by(&.incoming_announce_frequency)
               when "atx"
                 interfaces.sort_by(&.outgoing_announce_frequency)
               when "held"
                 interfaces.sort_by(&.held_announces)
               else
                 interfaces
               end
      sort_reverse ? sorted : sorted.reverse
    end

    # Check if an interface name should be hidden by default (not shown unless --all).
    def self.hidden_interface?(name : String) : Bool
      name.starts_with?("LocalInterface[") ||
        name.starts_with?("TCPInterface[Client") ||
        name.starts_with?("BackboneInterface[Client on") ||
        name.starts_with?("AutoInterfacePeer[") ||
        name.starts_with?("WeaveInterfacePeer[")
    end

    # Format the status display for a single interface stat.
    # Returns the formatted string (multiple lines).
    def self.format_interface(ifstat : InterfaceStat, astats : Bool = false) : String
      lines = [] of String

      ss = ifstat.status ? "Up" : "Down"
      modestr = mode_str(ifstat.mode)

      lines << " #{ifstat.name}"

      if src = ifstat.autoconnect_source
        lines << "    Source    : Auto-connect via <#{src}>"
      end

      if nn = ifstat.ifac_netname
        lines << "    Network   : #{nn}"
      end

      lines << "    Status    : #{ss}"

      if c = ifstat.clients
        name = ifstat.name
        if name.starts_with?("Shared Instance[")
          cnum = {c - 1, 0}.max
          spec = cnum == 1 ? " program" : " programs"
          lines << "    Serving   : #{cnum}#{spec}"
        else
          lines << "    Clients   : #{c}"
        end
      end

      unless ifstat.name.starts_with?("Shared Instance[") ||
             ifstat.name.starts_with?("TCPInterface[Client") ||
             ifstat.name.starts_with?("LocalInterface[")
        lines << "    Mode      : #{modestr}"
      end

      if br = ifstat.bitrate
        lines << "    Rate      : #{speed_str(br.to_f64)}"
      end

      if astats
        if aq = ifstat.announce_queue
          if aq > 0
            s = aq == 1 ? "announce" : "announces"
            lines << "    Queued    : #{aq} #{s}"
          end
        end

        if ifstat.held_announces > 0
          s = ifstat.held_announces == 1 ? "announce" : "announces"
          lines << "    Held      : #{ifstat.held_announces} #{s}"
        end

        lines << "    Announces : #{RNS.prettyfrequency(ifstat.outgoing_announce_frequency)}\u2191"
        lines << "                #{RNS.prettyfrequency(ifstat.incoming_announce_frequency)}\u2193"
      end

      if sig = ifstat.ifac_signature
        if sig.size >= 5
          sigstr = "<\u2026#{RNS.hexrep(sig[-5..], delimit: false)}>"
        else
          sigstr = "<\u2026#{RNS.hexrep(sig, delimit: false)}>"
        end
        lines << "    Access    : #{ifstat.ifac_size * 8}-bit IFAC by #{sigstr}"
      end

      if np = ifstat.peers
        lines << "    Peers     : #{np} reachable"
      end

      # Traffic
      rxb_str = "\u2193#{RNS.prettysize(ifstat.rxb.to_f64)}"
      txb_str = "\u2191#{RNS.prettysize(ifstat.txb.to_f64)}"
      strdiff = rxb_str.size - txb_str.size
      if strdiff > 0
        txb_str += " " * strdiff
      elsif strdiff < 0
        rxb_str += " " * (-strdiff)
      end

      rxstat = rxb_str
      txstat = txb_str
      rxstat += "  #{RNS.prettyspeed(ifstat.rxs)}"
      txstat += "  #{RNS.prettyspeed(ifstat.txs)}"

      lines << "    Traffic   : #{txstat}"
      lines << "                #{rxstat}"

      lines.join("\n")
    end

    # Convert an InterfaceStat to a JSON-compatible Hash.
    def self.interface_stat_to_hash(ifstat : InterfaceStat) : Hash(String, String | Int64 | Int32 | Float64 | Bool | Nil)
      h = Hash(String, String | Int64 | Int32 | Float64 | Bool | Nil).new
      h["name"] = ifstat.name
      h["short_name"] = ifstat.short_name
      h["hash"] = ifstat.hash.hexstring
      h["type"] = ifstat.type_name
      h["status"] = ifstat.status
      h["mode"] = ifstat.mode.to_i32
      h["rxb"] = ifstat.rxb
      h["txb"] = ifstat.txb
      h["rxs"] = ifstat.rxs
      h["txs"] = ifstat.txs
      h["clients"] = ifstat.clients
      h["bitrate"] = ifstat.bitrate
      h["incoming_announce_frequency"] = ifstat.incoming_announce_frequency
      h["outgoing_announce_frequency"] = ifstat.outgoing_announce_frequency
      h["held_announces"] = ifstat.held_announces
      h["announce_queue"] = ifstat.announce_queue
      h["ifac_signature"] = ifstat.ifac_signature.try(&.hexstring)
      h["ifac_size"] = ifstat.ifac_size
      h["ifac_netname"] = ifstat.ifac_netname
      h
    end

    # Format stats as JSON string.
    def self.format_json(stats : TransportStats) : String
      parts = [] of String
      stats.interfaces.each do |ifstat|
        h = interface_stat_to_hash(ifstat)
        entries = h.map do |k, v|
          val = case v
                when String then "\"#{v.gsub("\"", "\\\"")}\""
                when nil    then "null"
                when Bool   then v.to_s
                else             v.to_s
                end
          "\"#{k}\":#{val}"
        end
        parts << "{#{entries.join(",")}}"
      end

      tid_str = stats.transport_id.try(&.hexstring) || "null"
      tid_str = "\"#{tid_str}\"" unless tid_str == "null"
      nid_str = stats.network_id.try(&.hexstring) || "null"
      nid_str = "\"#{nid_str}\"" unless nid_str == "null"
      uptime_str = stats.transport_uptime.try(&.to_s) || "null"

      "{\"interfaces\":[#{parts.join(",")}],\"rxb\":#{stats.rxb},\"txb\":#{stats.txb},\"rxs\":#{stats.rxs},\"txs\":#{stats.txs},\"transport_id\":#{tid_str},\"network_id\":#{nid_str},\"transport_uptime\":#{uptime_str}}"
    end

    # Format the full status output matching Python rnstatus program_setup().
    # Returns formatted string.
    def self.format_status(stats : TransportStats,
                           dispall : Bool = false,
                           name_filter : String? = nil,
                           astats : Bool = false,
                           lstats : Bool = false,
                           link_count : Int32? = nil,
                           sorting : String? = nil,
                           sort_reverse : Bool = false,
                           traffic_totals : Bool = false) : String
      output = [] of String

      interfaces = sort_interfaces(stats.interfaces, sorting, sort_reverse)

      interfaces.each do |ifstat|
        name = ifstat.name

        next if !dispall && hidden_interface?(name)
        next if name_filter && !name.downcase.includes?(name_filter.downcase)

        output << ""
        output << format_interface(ifstat, astats)
      end

      lstr = ""
      if link_count && lstats
        ms = link_count == 1 ? "y" : "ies"
        if stats.transport_id
          lstr = ", #{link_count} entr#{ms} in link table"
        else
          lstr = " #{link_count} entr#{ms} in link table"
        end
      end

      if traffic_totals
        rxb_str = "\u2193#{RNS.prettysize(stats.rxb.to_f64)}"
        txb_str = "\u2191#{RNS.prettysize(stats.txb.to_f64)}"
        strdiff = rxb_str.size - txb_str.size
        if strdiff > 0
          txb_str += " " * strdiff
        elsif strdiff < 0
          rxb_str += " " * (-strdiff)
        end

        rxstat = rxb_str + "  " + RNS.prettyspeed(stats.rxs.to_f64)
        txstat = txb_str + "  " + RNS.prettyspeed(stats.txs.to_f64)
        output << ""
        output << " Totals       : #{txstat}"
        output << "                #{rxstat}"
      end

      if tid = stats.transport_id
        output << ""
        output << " Transport Instance #{RNS.prettyhexrep(tid)} running"
        if nid = stats.network_id
          output << " Network Identity   #{RNS.prettyhexrep(nid)}"
        end
        if pr = stats.probe_responder
          output << " Probe responder at #{RNS.prettyhexrep(pr)} active"
        end
        if tu = stats.transport_uptime
          output << " Uptime is #{RNS.prettytime(tu)}#{lstr}"
        end
      else
        if lstr != ""
          output << ""
          output << lstr
        end
      end

      output << ""
      output.join("\n")
    end

    # Main entry point for the rnstatus binary.
    def self.main(argv : Array(String) = ARGV.to_a)
      args = parse_args(argv)

      if args.version
        puts version_string
        return
      end

      if args.json
        stats = get_interface_stats
        puts format_json(stats)
        return
      end

      if args.monitor
        loop do
          stats = get_interface_stats

          link_count = nil.as(Int32?)
          if args.link_stats
            link_count = Transport.link_table.size
          end

          result = format_status(
            stats,
            dispall: args.all,
            name_filter: args.filter,
            astats: args.announce_stats,
            lstats: args.link_stats,
            link_count: link_count,
            sorting: args.sort,
            sort_reverse: args.reverse,
            traffic_totals: args.totals,
          )

          # Clear screen and print
          print "\033[H\033[2J"
          print result
          STDOUT.flush

          sleep args.monitor_interval.seconds
        end
      else
        stats = get_interface_stats

        link_count = nil.as(Int32?)
        if args.link_stats
          link_count = Transport.link_table.size
        end

        result = format_status(
          stats,
          dispall: args.all,
          name_filter: args.filter,
          astats: args.announce_stats,
          lstats: args.link_stats,
          link_count: link_count,
          sorting: args.sort,
          sort_reverse: args.reverse,
          traffic_totals: args.totals,
        )

        print result
      end
    rescue ex : ArgumentError
      STDERR.puts "rnstatus: #{ex.message}"
      STDERR.puts "Usage: rnstatus [--config PATH] [-a] [-A] [-l] [-t] [-s SORT] [-r] [-j] [-m] [-I SECS] [-d] [-D] [-v] [filter]"
      exit(1)
    rescue ex
      if ex.message.try(&.includes?("Interrupt"))
        puts ""
      end
    end
  end
end
