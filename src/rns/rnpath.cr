module RNS
  module Rnpath
    # Parsed command-line arguments for rnpath
    class Args
      property config : String?
      property verbose : Int32
      property table : Bool
      property max_hops : Int32?
      property rates : Bool
      property drop : Bool
      property drop_announces : Bool
      property drop_via : Bool
      property timeout : Float64
      property remote : String?
      property identity : String?
      property remote_timeout : Float64
      property blackholed : Bool
      property blackhole : Bool
      property unblackhole : Bool
      property duration : Float64?
      property reason : String?
      property blackholed_list : Bool
      property json : Bool
      property destination : String?
      property list_filter : String?
      property version : Bool

      def initialize(
        @config = nil,
        @verbose = 0,
        @table = false,
        @max_hops = nil,
        @rates = false,
        @drop = false,
        @drop_announces = false,
        @drop_via = false,
        @timeout = Transport::PATH_REQUEST_TIMEOUT.to_f64,
        @remote = nil,
        @identity = nil,
        @remote_timeout = Transport::PATH_REQUEST_TIMEOUT.to_f64,
        @blackholed = false,
        @blackhole = false,
        @unblackhole = false,
        @duration = nil,
        @reason = nil,
        @blackholed_list = false,
        @json = false,
        @destination = nil,
        @list_filter = nil,
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
        when "-t", "--table"
          args.table = true
        when "-m", "--max"
          i += 1
          val = argv[i]? || raise ArgumentError.new("--max requires a hops value")
          args.max_hops = val.to_i32
        when "-r", "--rates"
          args.rates = true
        when "-d", "--drop"
          args.drop = true
        when "-D", "--drop-announces"
          args.drop_announces = true
        when "-x", "--drop-via"
          args.drop_via = true
        when "-w"
          i += 1
          val = argv[i]? || raise ArgumentError.new("-w requires a seconds value")
          args.timeout = val.to_f64
        when "-R"
          i += 1
          args.remote = argv[i]? || raise ArgumentError.new("-R requires a hash argument")
        when "-i"
          i += 1
          args.identity = argv[i]? || raise ArgumentError.new("-i requires a path argument")
        when "-W"
          i += 1
          val = argv[i]? || raise ArgumentError.new("-W requires a seconds value")
          args.remote_timeout = val.to_f64
        when "-b", "--blackholed"
          args.blackholed = true
        when "-B", "--blackhole"
          args.blackhole = true
        when "-U", "--unblackhole"
          args.unblackhole = true
        when "--duration"
          i += 1
          val = argv[i]? || raise ArgumentError.new("--duration requires a value")
          args.duration = val.to_f64
        when "--reason"
          i += 1
          args.reason = argv[i]? || raise ArgumentError.new("--reason requires a value")
        when "-p", "--blackholed-list"
          args.blackholed_list = true
        when "-j", "--json"
          args.json = true
        when /^-[vtrdDxbBUpj]+$/
          arg[1..].each_char do |c|
            case c
            when 'v' then args.verbose += 1
            when 't' then args.table = true
            when 'r' then args.rates = true
            when 'd' then args.drop = true
            when 'D' then args.drop_announces = true
            when 'x' then args.drop_via = true
            when 'b' then args.blackholed = true
            when 'B' then args.blackhole = true
            when 'U' then args.unblackhole = true
            when 'p' then args.blackholed_list = true
            when 'j' then args.json = true
            else
              raise ArgumentError.new("Unknown flag: -#{c}")
            end
          end
        else
          if arg.starts_with?("-")
            raise ArgumentError.new("Unknown argument: #{arg}")
          else
            # First positional = destination, second = list_filter
            if args.destination.nil?
              args.destination = arg
            else
              args.list_filter = arg
            end
          end
        end
        i += 1
      end
      args
    end

    # Version string matching Python's "rnpath {version}" format.
    def self.version_string : String
      "rnpath #{RNS::VERSION}"
    end

    # A path table entry for display purposes.
    record PathTableEntry,
      hash : Bytes,
      timestamp : Float64,
      via : Bytes,
      hops : Int32,
      expires : Float64,
      interface : String

    # A rate table entry for display purposes.
    record RateTableEntry,
      hash : Bytes,
      last : Float64,
      rate_violations : Int32,
      blocked_until : Float64,
      timestamps : Array(Float64)

    # Collect path table from Transport, matching Python Reticulum.get_path_table().
    def self.get_path_table(max_hops : Int32? = nil) : Array(PathTableEntry)
      table = [] of PathTableEntry

      Transport.path_table.each do |dest_hex, entry|
        if max_hops.nil? || entry.hops <= max_hops
          hash_bytes = dest_hex.hexbytes
          table << PathTableEntry.new(
            hash: hash_bytes,
            timestamp: entry.timestamp,
            via: entry.next_hop,
            hops: entry.hops,
            expires: entry.expires,
            interface: entry.receiving_interface.try(&.hexstring) || "unknown",
          )
        end
      end

      table
    end

    # Collect rate table from Transport, matching Python Reticulum.get_rate_table().
    def self.get_rate_table : Array(RateTableEntry)
      table = [] of RateTableEntry

      Transport.announce_rate_table.each do |dest_hex, entry|
        hash_bytes = dest_hex.hexbytes
        table << RateTableEntry.new(
          hash: hash_bytes,
          last: entry.last,
          rate_violations: entry.rate_violations,
          blocked_until: entry.blocked_until,
          timestamps: entry.timestamps,
        )
      end

      table
    end

    # Drop path to a destination, matching Python Reticulum.drop_path().
    def self.drop_path(destination_hash : Bytes) : Bool
      Transport.expire_path(destination_hash)
    end

    # Drop all paths via a transport instance, matching Python Reticulum.drop_all_via().
    def self.drop_all_via(transport_hash : Bytes) : Int32
      dropped = 0
      Transport.path_table.each do |dest_hex, entry|
        if entry.next_hop == transport_hash
          Transport.expire_path(dest_hex.hexbytes)
          dropped += 1
        end
      end
      dropped
    end

    # Drop all announce queues, matching Python Reticulum.drop_announce_queues().
    def self.drop_announce_queues
      Transport.drop_announce_queues
    end

    # Convert a relative timestamp to a human-readable "X ago" string.
    # Matches Python rnpath.py pretty_date() behavior.
    def self.pretty_date(timestamp : Int64) : String
      now = Time.utc
      ts_time = Time.unix(timestamp)
      diff = now - ts_time
      second_diff = diff.total_seconds.to_i
      day_diff = (diff.total_seconds / 86400).to_i

      return "" if day_diff < 0

      if day_diff == 0
        return "#{second_diff} seconds" if second_diff < 10
        return "#{second_diff} seconds" if second_diff < 60
        return "1 minute" if second_diff < 120
        return "#{second_diff // 60} minutes" if second_diff < 3600
        return "an hour" if second_diff < 7200
        return "#{second_diff // 3600} hours" if second_diff < 86400
      end

      return "1 day" if day_diff == 1
      return "#{day_diff} days" if day_diff < 7
      return "#{day_diff // 7} weeks" if day_diff < 31
      return "#{day_diff // 30} months" if day_diff < 365
      return "#{day_diff // 365} years"
    end

    # Validate a hex hash string, returning the bytes.
    # Raises ValueError on invalid input.
    def self.parse_hash(input : String) : Bytes
      dest_len = (Reticulum::TRUNCATED_HASHLENGTH // 8) * 2
      unless input.size == dest_len
        raise ArgumentError.new(
          "Destination length is invalid, must be #{dest_len} hexadecimal characters (#{dest_len // 2} bytes)."
        )
      end
      begin
        input.hexbytes
      rescue
        raise ArgumentError.new("Invalid destination entered. Check your input.")
      end
    end

    # Format path table output. Returns formatted string.
    def self.format_path_table(table : Array(PathTableEntry), destination_hash : Bytes? = nil) : String
      sorted = table.sort_by { |e| {e.interface, e.hops} }
      output = [] of String
      displayed = 0

      sorted.each do |path|
        next if destination_hash && destination_hash != path.hash
        displayed += 1
        m_str = path.hops == 1 ? " " : "s"
        output << "#{RNS.prettyhexrep(path.hash)} is #{path.hops} hop#{m_str} away via #{RNS.prettyhexrep(path.via)} on #{path.interface} expires #{RNS.timestamp_str(path.expires)}"
      end

      if destination_hash && displayed == 0
        return "No path known"
      end

      output.join("\n")
    end

    # Format rate table output. Returns formatted string.
    def self.format_rate_table(table : Array(RateTableEntry), destination_hash : Bytes? = nil) : String
      return "No information available" if table.empty?

      sorted = table.sort_by { |e| e.last }
      output = [] of String
      displayed = 0

      sorted.each do |entry|
        next if destination_hash && destination_hash != entry.hash
        displayed += 1

        begin
          last_str = pretty_date(entry.last.to_i64)
          start_ts = entry.timestamps.first? || Time.utc.to_unix_f
          span = {Time.utc.to_unix_f - start_ts, 3600.0}.max
          span_hours = span / 3600.0
          span_str = pretty_date(start_ts.to_i64)
          hour_rate = (entry.timestamps.size / span_hours).round(3)

          if hour_rate - hour_rate.to_i == 0
            hour_rate_display = hour_rate.to_i.to_s
          else
            hour_rate_display = hour_rate.to_s
          end

          rv_str = ""
          if entry.rate_violations > 0
            s_str = entry.rate_violations == 1 ? "" : "s"
            rv_str = ", #{entry.rate_violations} active rate violation#{s_str}"
          end

          bl_str = ""
          if entry.blocked_until > Time.utc.to_unix_f
            bli = Time.utc.to_unix_f - (entry.blocked_until - Time.utc.to_unix_f)
            bl_str = ", new announces allowed in #{pretty_date(bli.to_i64)}"
          end

          output << "#{RNS.prettyhexrep(entry.hash)} last heard #{last_str} ago, #{hour_rate_display} announces/hour in the last #{span_str}#{rv_str}#{bl_str}"
        rescue ex
          output << "Error while processing entry for #{RNS.prettyhexrep(entry.hash)}"
        end
      end

      if destination_hash && displayed == 0
        return "No information available"
      end

      output.join("\n")
    end

    # Format a path found response.
    def self.format_path_found(destination_hash : Bytes, hops : Int32, next_hop : Bytes, next_hop_interface : String) : String
      ms = hops != 1 ? "s" : ""
      "Path found, destination #{RNS.prettyhexrep(destination_hash)} is #{hops} hop#{ms} away via #{RNS.prettyhexrep(next_hop)} on #{next_hop_interface}"
    end

    # Main entry point for the rnpath binary.
    def self.main(argv : Array(String) = ARGV.to_a)
      args = parse_args(argv)

      if args.version
        puts version_string
        return
      end

      if !args.drop_announces && !args.table && !args.rates &&
         args.destination.nil? && !args.drop_via && !args.blackholed
        puts ""
        puts "Reticulum Path Management Utility"
        puts ""
        puts "Usage: rnpath [--config PATH] [-t] [-m HOPS] [-r] [-d] [-D] [-x] [-w SECONDS] [-j] [-v] [destination]"
        puts ""
        return
      end

      if args.table
        destination_hash = nil.as(Bytes?)
        if dest_hex = args.destination
          destination_hash = parse_hash(dest_hex)
        end

        table = get_path_table(args.max_hops)
        puts format_path_table(table, destination_hash)
      elsif args.rates
        destination_hash = nil.as(Bytes?)
        if dest_hex = args.destination
          destination_hash = parse_hash(dest_hex)
        end

        table = get_rate_table
        puts format_rate_table(table, destination_hash)
      elsif args.drop_announces
        puts "Dropping announce queues on all interfaces..."
        drop_announce_queues
      elsif args.drop
        dest_hex = args.destination || raise ArgumentError.new("--drop requires a destination hash")
        destination_hash = parse_hash(dest_hex)

        if drop_path(destination_hash)
          puts "Dropped path to #{RNS.prettyhexrep(destination_hash)}"
        else
          puts "Unable to drop path to #{RNS.prettyhexrep(destination_hash)}. Does it exist?"
          exit(1)
        end
      elsif args.drop_via
        dest_hex = args.destination || raise ArgumentError.new("--drop-via requires a transport instance hash")
        destination_hash = parse_hash(dest_hex)

        count = drop_all_via(destination_hash)
        if count > 0
          puts "Dropped all paths via #{RNS.prettyhexrep(destination_hash)}"
        else
          puts "Unable to drop paths via #{RNS.prettyhexrep(destination_hash)}. Does the transport instance exist?"
          exit(1)
        end
      else
        # Path request mode
        dest_hex = args.destination || raise ArgumentError.new("A destination hash is required")
        destination_hash = parse_hash(dest_hex)

        if !Transport.has_path(destination_hash)
          Transport.request_path(destination_hash)
          print "Path to #{RNS.prettyhexrep(destination_hash)} requested  "
          STDOUT.flush

          syms = "\u28C4\u28C2\u28C1\u2841\u2848\u2850\u2860"
          sym_idx = 0
          limit = Time.utc.to_unix_f + args.timeout

          while !Transport.has_path(destination_hash) && Time.utc.to_unix_f < limit
            sleep 0.1.seconds
            print "\b\b#{syms[sym_idx]} "
            STDOUT.flush
            sym_idx = (sym_idx + 1) % syms.size
          end
        end

        if Transport.has_path(destination_hash)
          hops = Transport.hops_to(destination_hash)
          next_hop_bytes = Transport.next_hop(destination_hash)

          if next_hop_bytes.nil?
            puts "\r                                                       \rError: Invalid path data returned"
            exit(1)
          else
            next_hop_interface_hash = Transport.next_hop_interface(destination_hash)
            next_hop_if_name = next_hop_interface_hash.try(&.hexstring) || "unknown"

            puts "\r#{format_path_found(destination_hash, hops, next_hop_bytes, next_hop_if_name)}"
          end
        else
          puts "\r                                                       \rPath not found"
          exit(1)
        end
      end
    rescue ex : ArgumentError
      STDERR.puts "rnpath: #{ex.message}"
      exit(1)
    rescue ex
      if ex.message.try(&.includes?("Interrupt"))
        puts ""
      end
    end
  end
end
