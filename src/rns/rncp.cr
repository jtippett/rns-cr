module RNS
  module Rncp
    APP_NAME = "rncp"

    REQ_FETCH_NOT_ALLOWED = 0xF0_u8

    # Spinner characters matching Python's braille spinner.
    SPINNER_SYMS = "⢄⢂⢁⡁⡈⡐⡠"

    # ANSI erase-to-start-of-line + carriage return
    ERASE_STR = "\33[2K\r"

    # Parsed command-line arguments for rncp
    class Args
      property config : String?
      property verbose : Int32
      property quiet : Int32
      property silent : Bool
      property listen : Bool
      property no_compress : Bool
      property allow_fetch : Bool
      property fetch : Bool
      property jail : String?
      property save : String?
      property overwrite : Bool
      property announce : Int32
      property allowed : Array(String)
      property no_auth : Bool
      property print_identity : Bool
      property identity : String?
      property timeout : Float64
      property phy_rates : Bool
      property version : Bool
      # Positional: file, destination
      property file : String?
      property destination : String?

      def initialize(
        @config = nil,
        @verbose = 0,
        @quiet = 0,
        @silent = false,
        @listen = false,
        @no_compress = false,
        @allow_fetch = false,
        @fetch = false,
        @jail = nil,
        @save = nil,
        @overwrite = false,
        @announce = -1,
        @allowed = [] of String,
        @no_auth = false,
        @print_identity = false,
        @identity = nil,
        @timeout = Transport::PATH_REQUEST_TIMEOUT.to_f64,
        @phy_rates = false,
        @version = false,
        @file = nil,
        @destination = nil,
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
        when "-S", "--silent"
          args.silent = true
        when "-l", "--listen"
          args.listen = true
        when "-C", "--no-compress"
          args.no_compress = true
        when "-F", "--allow-fetch"
          args.allow_fetch = true
        when "-f", "--fetch"
          args.fetch = true
        when "-j", "--jail"
          i += 1
          args.jail = argv[i]? || raise ArgumentError.new("--jail requires a path argument")
        when "-s", "--save"
          i += 1
          args.save = argv[i]? || raise ArgumentError.new("--save requires a path argument")
        when "-O", "--overwrite"
          args.overwrite = true
        when "-b"
          i += 1
          val = argv[i]? || raise ArgumentError.new("-b requires a seconds value")
          args.announce = val.to_i32
        when "-a"
          i += 1
          val = argv[i]? || raise ArgumentError.new("-a requires an allowed_hash argument")
          args.allowed << val
        when "-n", "--no-auth"
          args.no_auth = true
        when "-p", "--print-identity"
          args.print_identity = true
        when "-i"
          i += 1
          args.identity = argv[i]? || raise ArgumentError.new("-i requires an identity path")
        when "-w"
          i += 1
          val = argv[i]? || raise ArgumentError.new("-w requires a seconds value")
          args.timeout = val.to_f64
        when "-P", "--phy-rates"
          args.phy_rates = true
        when /^-[vqSClCFfOnpP]+$/
          # Handle combined short flags
          arg[1..].each_char do |char|
            case char
            when 'v' then args.verbose += 1
            when 'q' then args.quiet += 1
            when 'S' then args.silent = true
            when 'l' then args.listen = true
            when 'C' then args.no_compress = true
            when 'F' then args.allow_fetch = true
            when 'f' then args.fetch = true
            when 'O' then args.overwrite = true
            when 'n' then args.no_auth = true
            when 'p' then args.print_identity = true
            when 'P' then args.phy_rates = true
            else
              raise ArgumentError.new("Unknown flag: -#{char}")
            end
          end
        when "-v", "--verbose"
          args.verbose += 1
        when "-q", "--quiet"
          args.quiet += 1
        else
          if arg.starts_with?("-")
            raise ArgumentError.new("Unknown argument: #{arg}")
          else
            # Positional: first = file, second = destination
            if args.file.nil?
              args.file = arg
            elsif args.destination.nil?
              args.destination = arg
            else
              raise ArgumentError.new("Unexpected positional argument: #{arg}")
            end
          end
        end
        i += 1
      end
      args
    end

    # Version string matching Python's "rncp {version}" format.
    def self.version_string : String
      "rncp #{RNS::VERSION}"
    end

    # Usage message matching Python argparse output.
    def self.usage_string : String
      <<-USAGE
      Reticulum File Transfer Utility

      Usage: rncp [options] [file] [destination]

      Positional arguments:
        file                  file to be transferred
        destination           hexadecimal hash of the receiver

      Options:
        --config PATH         path to alternative Reticulum config directory
        -v, --verbose         increase verbosity
        -q, --quiet           decrease verbosity
        -S, --silent          disable transfer progress output
        -l, --listen          listen for incoming transfer requests
        -C, --no-compress     disable automatic compression
        -F, --allow-fetch     allow authenticated clients to fetch files
        -f, --fetch           fetch file from remote listener instead of sending
        -j, --jail PATH       restrict fetch requests to specified path
        -s, --save PATH       save received files in specified path
        -O, --overwrite       allow overwriting received files
        -b SECONDS            announce interval, 0 to only announce at startup
        -a HASH               allow this identity
        -n, --no-auth         accept requests from anyone
        -p, --print-identity  print identity and destination info and exit
        -i IDENTITY           path to identity to use
        -w SECONDS            sender timeout before giving up
        -P, --phy-rates       display physical layer transfer rates
        --version             show version and exit
      USAGE
    end

    # Validate a hex destination hash string, returning the bytes.
    def self.parse_destination_hash(hex : String) : Bytes
      dest_len = (Reticulum::TRUNCATED_HASHLENGTH // 8) * 2
      unless hex.size == dest_len
        raise ArgumentError.new(
          "Allowed destination length is invalid, must be #{dest_len} hexadecimal characters (#{dest_len // 2} bytes)."
        )
      end
      begin
        hex.hexbytes
      rescue
        raise ArgumentError.new("Invalid destination entered. Check your input.")
      end
    end

    # Size formatting matching Python's size_str exactly.
    # suffix='B' for bytes, suffix='b' for bits (multiplies by 8).
    def self.size_str(num : Float64 | Int32 | Int64 | UInt64, suffix : String = "B") : String
      n = num.to_f64
      units = ["", "K", "M", "G", "T", "P", "E", "Z"]
      last_unit = "Y"

      if suffix == "b"
        n *= 8
      end

      units.each do |unit|
        if n.abs < 1000.0
          if unit == ""
            return "%.0f %s%s" % {n, unit, suffix}
          else
            return "%.2f %s%s" % {n, unit, suffix}
          end
        end
        n /= 1000.0
      end

      "%.2f%s%s" % {n, last_unit, suffix}
    end

    # Prepare or load identity for rncp
    def self.prepare_identity(identity_path : String?) : Identity
      path = identity_path || (Reticulum.identitypath + "/" + APP_NAME)

      if File.exists?(path)
        id = Identity.from_file(path)
        if id.nil?
          RNS.log("Could not load identity for rncp. The identity file at \"#{path}\" may be corrupt or unreadable.", RNS::LOG_ERROR)
          RNS.exit(2)
        end
        return id.not_nil!
      end

      RNS.log("No valid saved identity found, creating new...", RNS::LOG_INFO)
      id = Identity.new
      id.to_file(path)
      id
    end

    # Format a transfer progress string.
    def self.format_progress(percent : Float64, current_size : String, total_size : String,
                             speed_str : String, phy_str : String = "") : String
      "#{percent}% - #{current_size} of #{total_size} - #{speed_str}ps#{phy_str}"
    end

    # Format a transfer complete string.
    def self.format_transfer_complete(percent : Float64, current_size : String, total_size : String,
                                      duration_str : String, speed_str : String, phy_str : String = "") : String
      "#{percent}% - #{current_size} of #{total_size} in #{duration_str} - #{speed_str}ps#{phy_str}"
    end

    # Main entry point for the rncp binary.
    def self.main(argv : Array(String) = ARGV.to_a)
      args = parse_args(argv)

      if args.version
        puts version_string
        return
      end

      if args.listen || args.print_identity
        listen(
          configdir: args.config,
          identitypath: args.identity,
          verbosity: args.verbose,
          quietness: args.quiet,
          allowed: args.allowed,
          fetch_allowed: args.allow_fetch,
          no_compress: args.no_compress,
          jail: args.jail,
          save: args.save,
          display_identity: args.print_identity,
          disable_auth: args.no_auth,
          announce: args.announce,
          allow_overwrite: args.overwrite,
        )
      elsif args.fetch
        if args.destination && args.file
          fetch(
            configdir: args.config,
            identitypath: args.identity,
            verbosity: args.verbose,
            quietness: args.quiet,
            destination: args.destination.not_nil!,
            file: args.file.not_nil!,
            timeout: args.timeout,
            silent: args.silent,
            phy_rates: args.phy_rates,
            save: args.save,
            allow_overwrite: args.overwrite,
          )
        else
          puts ""
          puts usage_string
          puts ""
        end
      elsif args.destination && args.file
        send(
          configdir: args.config,
          identitypath: args.identity,
          verbosity: args.verbose,
          quietness: args.quiet,
          destination: args.destination.not_nil!,
          file: args.file.not_nil!,
          timeout: args.timeout,
          silent: args.silent,
          phy_rates: args.phy_rates,
          no_compress: args.no_compress,
        )
      else
        puts ""
        puts usage_string
        puts ""
      end
    rescue ex : ArgumentError
      STDERR.puts "rncp: #{ex.message}"
      exit(1)
    rescue ex
      if ex.message.try(&.includes?("Interrupt"))
        puts ""
      end
    end

    # Listen mode — receive files from authenticated senders.
    def self.listen(configdir : String?, identitypath : String?, verbosity : Int32,
                    quietness : Int32, allowed : Array(String), fetch_allowed : Bool,
                    no_compress : Bool, jail : String?, save : String?,
                    display_identity : Bool, disable_auth : Bool, announce : Int32,
                    allow_overwrite : Bool)
      allow_all = disable_auth
      allow_fetch = fetch_allowed
      fetch_auto_compress = !no_compress
      allow_overwrite_on_receive = allow_overwrite
      allowed_identity_hashes = [] of Bytes

      ann = announce < 0 ? false : true

      targetloglevel = 3 + verbosity - quietness
      _reticulum = ReticulumInstance.new(configdir: configdir, loglevel: targetloglevel)

      fetch_jail : String? = nil
      if j = jail
        fetch_jail = File.expand_path(j)
        RNS.log("Restricting fetch requests to paths under \"#{fetch_jail}\"", RNS::LOG_VERBOSE)
      end

      save_path : String? = nil
      if s = save
        expanded = File.expand_path(s)
        if Dir.exists?(expanded)
          save_path = expanded
        else
          RNS.log("Output directory not found", RNS::LOG_ERROR)
          RNS.exit(3)
        end
        RNS.log("Saving received files in \"#{save_path}\"", RNS::LOG_VERBOSE)
      end

      identity = prepare_identity(identitypath)

      destination = Destination.new(identity, Destination::IN, Destination::SINGLE, APP_NAME, ["receive"])

      if display_identity
        puts "Identity     : #{identity}"
        puts "Listening on : #{RNS.prettyhexrep(destination.hash)}"
        RNS.exit(0)
      end

      unless disable_auth
        dest_len = (Reticulum::TRUNCATED_HASHLENGTH // 8) * 2

        # Load from allowed_identities files
        allowed_file : String? = nil
        ["/etc/rncp/allowed_identities",
         File.expand_path("~/.config/rncp/allowed_identities"),
         File.expand_path("~/.rncp/allowed_identities")].each do |path|
          if File.exists?(path)
            allowed_file = path
            break
          end
        end

        if af = allowed_file
          begin
            ali = File.read(af).gsub("\r", "").split("\n").select { |alias_line| alias_line.size == dest_len }
            if ali.size > 0
              if allowed.empty?
                allowed = ali
              else
                allowed.concat(ali)
              end
              ms = ali.size == 1 ? "y" : "ies"
              RNS.log("Loaded #{ali.size} allowed identit#{ms} from #{af}", RNS::LOG_VERBOSE)
            end
          rescue ex
            RNS.log("Error while parsing allowed_identities file. The contained exception was: #{ex}", RNS::LOG_ERROR)
          end
        end

        allowed.each do |entry|
          if entry.size != dest_len
            puts "Allowed destination length is invalid, must be #{dest_len} hexadecimal characters (#{dest_len // 2} bytes)."
            RNS.exit(1)
          end
          begin
            allowed_identity_hashes << entry.hexbytes
          rescue
            puts "Invalid destination entered. Check your input."
            RNS.exit(1)
          end
        end
      end

      if allowed_identity_hashes.size < 1 && !disable_auth
        puts "Warning: No allowed identities configured, rncp will not accept any files!"
      end

      destination.set_link_established_callback(->(link : Link) {
        RNS.log("Incoming link established", RNS::LOG_VERBOSE)
        link.set_remote_identified_callback(->(lnk : Link, ident : Identity) {
          if allowed_identity_hashes.any? { |hash| hash == ident.hash }
            RNS.log("Authenticated sender", RNS::LOG_VERBOSE)
          elsif !allow_all
            RNS.log("Sender not allowed, tearing down link", RNS::LOG_VERBOSE)
            lnk.teardown
          end
        })
        link.set_resource_strategy(Link::ACCEPT_APP)
        link.set_resource_callback(->(resource_adv : ResourceAdvertisement) {
          sender_identity = resource_adv.link.try(&.get_remote_identity)
          if si = sender_identity
            return true if allowed_identity_hashes.any? { |hash| hash == si.hash }
          end
          return true if allow_all
          false
        })
        link.set_resource_started_callback(->(resource : Resource) {
          id_str = ""
          if ri = resource.link.try(&.get_remote_identity)
            if rh = ri.hash
              id_str = " from #{RNS.prettyhexrep(rh)}"
            end
          end
          puts "Starting resource transfer #{RNS.prettyhexrep(resource.hash)}#{id_str}"
        })
        link.set_resource_concluded_callback(->(resource : Resource) {
          if resource.status == Resource::COMPLETE
            puts "#{resource} completed"
            raw_meta = resource.metadata
            if raw_meta.nil?
              puts "Invalid data received, ignoring resource"
              return
            end
            begin
              meta = MessagePack::Any.from_msgpack(raw_meta)
              name_raw = meta["name"].raw
              name_str = name_raw.is_a?(Bytes) ? String.new(name_raw) : name_raw.to_s
              filename = File.basename(name_str)
              counter = 0
              saved_filename = if sp = save_path
                                 full = File.expand_path(sp + "/" + filename)
                                 unless full.starts_with?(sp + "/")
                                   RNS.log("Invalid save path #{full}, ignoring", RNS::LOG_ERROR)
                                   return
                                 end
                                 full
                               else
                                 filename
                               end

              full_save_path = saved_filename
              if allow_overwrite_on_receive && File.exists?(full_save_path)
                begin
                  File.delete(full_save_path)
                rescue ex
                  RNS.log("Could not overwrite existing file #{full_save_path}, renaming instead", RNS::LOG_ERROR)
                end
              end

              while File.exists?(full_save_path)
                counter += 1
                full_save_path = "#{saved_filename}.#{counter}"
              end

              if data = resource.data
                File.write(full_save_path, data)
              end
            rescue ex
              RNS.log("An error occurred while saving received resource: #{ex}", RNS::LOG_ERROR)
            end
          else
            puts "Resource failed"
          end
        })
      })

      if allow_fetch
        # Register fetch request handler
        if allow_all
          RNS.log("Allowing unauthenticated fetch requests", RNS::LOG_WARNING)
          destination.register_request_handler("fetch_file",
            response_generator: ->(_path : String, data : Bytes?, _request_id : Bytes, _link_id : Bytes, _remote_identity : Identity?, _requested_at : Float64) {
              handle_fetch_request(data, fetch_jail, fetch_auto_compress)
            },
            allow: Destination::ALLOW_ALL)
        else
          destination.register_request_handler("fetch_file",
            response_generator: ->(_path : String, data : Bytes?, _request_id : Bytes, _link_id : Bytes, _remote_identity : Identity?, _requested_at : Float64) {
              handle_fetch_request(data, fetch_jail, fetch_auto_compress)
            },
            allow: Destination::ALLOW_LIST,
            allowed_list: allowed_identity_hashes)
        end
      end

      puts "rncp listening on #{RNS.prettyhexrep(destination.hash)}"

      if ann && announce >= 0
        spawn do
          destination.announce
          if announce > 0
            loop do
              sleep announce.seconds
              destination.announce
            end
          end
        end
      end

      # Block forever
      loop { sleep 1.second }
    end

    # Handle a fetch file request from a remote client.
    private def self.handle_fetch_request(data : Bytes?, fetch_jail : String?,
                                          fetch_auto_compress : Bool) : Bytes?
      return nil if data.nil?
      file_path_str = String.new(data)
      if fj = fetch_jail
        if file_path_str.starts_with?(fj + "/")
          file_path_str = file_path_str.sub(fj + "/", "")
        end
        file_path = File.expand_path("#{fj}/#{file_path_str}")
        unless file_path.starts_with?(fj + "/")
          RNS.log("Disallowing fetch request for #{file_path} outside of fetch jail #{fj}", RNS::LOG_WARNING)
          return nil
        end
      else
        file_path = File.expand_path(file_path_str)
      end

      unless File.exists?(file_path)
        RNS.log("Client-requested file not found: #{file_path}", RNS::LOG_VERBOSE)
        return nil
      end

      RNS.log("Sending file #{file_path} to client", RNS::LOG_VERBOSE)
      File.read(file_path).to_slice
    end

    # Send mode — send a file to a remote rncp listener.
    def self.send(configdir : String?, identitypath : String?, verbosity : Int32,
                  quietness : Int32, destination : String, file : String,
                  timeout : Float64, silent : Bool, phy_rates : Bool, no_compress : Bool)
      targetloglevel = 3 + verbosity - quietness

      destination_hash = parse_destination_hash(destination)

      file_path = File.expand_path(file)
      unless File.exists?(file_path)
        puts "File not found"
        exit(1)
      end

      print ERASE_STR

      _reticulum = ReticulumInstance.new(configdir: configdir, loglevel: targetloglevel)
      identity = prepare_identity(identitypath)

      if !Transport.has_path(destination_hash)
        Transport.request_path(destination_hash)
        if silent
          puts "Path to #{RNS.prettyhexrep(destination_hash)} requested"
        else
          print "Path to #{RNS.prettyhexrep(destination_hash)} requested  "
          STDOUT.flush
        end
      end

      sym_idx = 0
      estab_timeout = Time.utc.to_unix_f + timeout
      while !Transport.has_path(destination_hash) && Time.utc.to_unix_f < estab_timeout
        unless silent
          sleep 0.1.seconds
          print "\b\b#{SPINNER_SYMS[sym_idx]} "
          STDOUT.flush
          sym_idx = (sym_idx + 1) % SPINNER_SYMS.size
        end
      end

      if !Transport.has_path(destination_hash)
        if silent
          puts "Path not found"
        else
          puts "#{ERASE_STR}Path not found"
        end
        RNS.exit(1)
      else
        if silent
          puts "Establishing link with #{RNS.prettyhexrep(destination_hash)}"
        else
          print "#{ERASE_STR}Establishing link with #{RNS.prettyhexrep(destination_hash)} "
          STDOUT.flush
        end
      end

      receiver_identity = Identity.recall(destination_hash)
      if receiver_identity.nil?
        puts "Could not recall identity for #{RNS.prettyhexrep(destination_hash)}"
        RNS.exit(1)
      end

      receiver_destination = Destination.new(
        receiver_identity.not_nil!,
        Destination::OUT,
        Destination::SINGLE,
        APP_NAME,
        ["receive"]
      )

      link = Link.new(receiver_destination)
      while link.status != Link::ACTIVE && Time.utc.to_unix_f < estab_timeout
        unless silent
          sleep 0.1.seconds
          print "\b\b#{SPINNER_SYMS[sym_idx]} "
          STDOUT.flush
          sym_idx = (sym_idx + 1) % SPINNER_SYMS.size
        end
      end

      if Time.utc.to_unix_f > estab_timeout
        if silent
          puts "Link establishment with #{RNS.prettyhexrep(destination_hash)} timed out"
        else
          puts "#{ERASE_STR}Link establishment with #{RNS.prettyhexrep(destination_hash)} timed out"
        end
        RNS.exit(1)
      elsif !Transport.has_path(destination_hash)
        if silent
          puts "No path found to #{RNS.prettyhexrep(destination_hash)}"
        else
          puts "#{ERASE_STR}No path found to #{RNS.prettyhexrep(destination_hash)}"
        end
        RNS.exit(1)
      else
        if silent
          puts "Advertising file resource..."
        else
          print "#{ERASE_STR}Advertising file resource  "
          STDOUT.flush
        end
      end

      link.identify(identity)
      auto_compress = !no_compress

      # Progress tracking state
      stats = [] of Tuple(Float64, Float64, Float64)
      stats_max = 32
      speed = 0.0
      phy_speed = 0.0
      resource_done = false

      progress_callback = ->(resource : Resource) {
        now = Time.utc.to_unix_f
        got = resource.get_progress * resource.get_data_size
        phy_got = resource.get_segment_progress * resource.get_transfer_size

        stats << {now, got, phy_got}
        while stats.size > stats_max
          stats.shift
        end

        span = now - stats[0][0]
        if span == 0
          speed = 0.0
          phy_speed = 0.0
        else
          diff = got - stats[0][1]
          speed = diff / span
          phy_diff = phy_got - stats[0][2]
          phy_speed = phy_diff / span if phy_diff > 0
        end

        if resource.status < Resource::COMPLETE
          resource_done = false
        else
          resource_done = true
        end
      }

      meta_hash = Hash(MessagePack::Type, MessagePack::Type).new
      meta_hash["name"] = File.basename(file_path).to_slice.as(MessagePack::Type)
      metadata = MessagePack::Any.new(meta_hash.as(MessagePack::Type))
      begin
        resource = Resource.new(File.read(file_path).to_slice, link, metadata: metadata,
          callback: progress_callback, progress_callback: progress_callback,
          auto_compress: auto_compress)
      rescue ex
        puts "Could not start transfer: #{ex}"
        exit(1)
      end

      while resource.status < Resource::TRANSFERRING
        unless silent
          sleep 0.1.seconds
          print "\b\b#{SPINNER_SYMS[sym_idx]} "
          STDOUT.flush
          sym_idx = (sym_idx + 1) % SPINNER_SYMS.size
        end
      end

      resource_started_at = Time.utc.to_unix_f

      if resource.status > Resource::COMPLETE
        if silent
          puts "File was not accepted by #{RNS.prettyhexrep(destination_hash)}"
        else
          puts "#{ERASE_STR}File was not accepted by #{RNS.prettyhexrep(destination_hash)}"
        end
        RNS.exit(1)
      else
        if silent
          puts "Transferring file..."
        else
          print "#{ERASE_STR}Transferring file  "
          STDOUT.flush
        end
      end

      while !resource_done
        unless silent
          sleep 0.1.seconds
          prg = resource.get_progress
          percent = (prg * 100.0).round(1)
          phy_str = phy_rates ? " (#{size_str(phy_speed, "b")}ps at physical layer)" : ""
          cs = size_str((prg * resource.total_size).to_i64)
          ts = size_str(resource.total_size.to_i64)
          ss = size_str(speed, "b")
          stat_str = format_progress(percent, cs, ts, ss, phy_str)
          print "#{ERASE_STR}Transferring file #{SPINNER_SYMS[sym_idx]} #{stat_str}  "
          STDOUT.flush
          sym_idx = (sym_idx + 1) % SPINNER_SYMS.size
        end
      end

      resource_concluded_at = Time.utc.to_unix_f
      transfer_time = resource_concluded_at - resource_started_at
      speed = resource.total_size / transfer_time if transfer_time > 0

      unless silent
        prg = resource.get_progress
        percent = (prg * 100.0).round(1)
        phy_str = phy_rates ? " (#{size_str(phy_speed, "b")}ps at physical layer)" : ""
        cs = size_str((prg * resource.total_size).to_i64)
        ts = size_str(resource.total_size.to_i64)
        ss = size_str(speed, "b")
        dt_str = RNS.prettytime(transfer_time)
        stat_str = format_transfer_complete(percent, cs, ts, dt_str, ss, phy_str)
        print "#{ERASE_STR}Transfer complete  #{stat_str}  "
        STDOUT.flush
      end

      if resource.status != Resource::COMPLETE
        if silent
          puts "The transfer failed"
        else
          puts "#{ERASE_STR}The transfer failed"
        end
        RNS.exit(1)
      else
        if silent
          puts "#{file_path} copied to #{RNS.prettyhexrep(destination_hash)}"
        else
          puts "\n#{file_path} copied to #{RNS.prettyhexrep(destination_hash)}"
        end
        link.teardown
        sleep 0.25.seconds
        RNS.exit(0)
      end
    end

    # Fetch mode — fetch a file from a remote rncp listener.
    def self.fetch(configdir : String?, identitypath : String?, verbosity : Int32,
                   quietness : Int32, destination : String, file : String,
                   timeout : Float64, silent : Bool, phy_rates : Bool,
                   save : String?, allow_overwrite : Bool)
      targetloglevel = 3 + verbosity - quietness

      save_path : String? = nil
      if s = save
        expanded = File.expand_path(s)
        if Dir.exists?(expanded)
          save_path = expanded
        else
          RNS.log("Output directory not found", RNS::LOG_ERROR)
          RNS.exit(3)
        end
      end

      destination_hash = parse_destination_hash(destination)

      _reticulum = ReticulumInstance.new(configdir: configdir, loglevel: targetloglevel)
      identity = prepare_identity(identitypath)

      if !Transport.has_path(destination_hash)
        Transport.request_path(destination_hash)
        if silent
          puts "Path to #{RNS.prettyhexrep(destination_hash)} requested"
        else
          print "Path to #{RNS.prettyhexrep(destination_hash)} requested  "
          STDOUT.flush
        end
      end

      sym_idx = 0
      estab_timeout = Time.utc.to_unix_f + timeout
      while !Transport.has_path(destination_hash) && Time.utc.to_unix_f < estab_timeout
        unless silent
          sleep 0.1.seconds
          print "\b\b#{SPINNER_SYMS[sym_idx]} "
          STDOUT.flush
          sym_idx = (sym_idx + 1) % SPINNER_SYMS.size
        end
      end

      if !Transport.has_path(destination_hash)
        if silent
          puts "Path not found"
        else
          puts "#{ERASE_STR}Path not found"
        end
        RNS.exit(1)
      else
        if silent
          puts "Establishing link with #{RNS.prettyhexrep(destination_hash)}"
        else
          print "#{ERASE_STR}Establishing link with #{RNS.prettyhexrep(destination_hash)}  "
          STDOUT.flush
        end
      end

      listener_identity = Identity.recall(destination_hash)
      if listener_identity.nil?
        puts "Could not recall identity for #{RNS.prettyhexrep(destination_hash)}"
        RNS.exit(1)
      end

      listener_destination = Destination.new(
        listener_identity.not_nil!,
        Destination::OUT,
        Destination::SINGLE,
        APP_NAME,
        ["receive"]
      )

      link = Link.new(listener_destination)
      while link.status != Link::ACTIVE && Time.utc.to_unix_f < estab_timeout
        unless silent
          sleep 0.1.seconds
          print "\b\b#{SPINNER_SYMS[sym_idx]} "
          STDOUT.flush
          sym_idx = (sym_idx + 1) % SPINNER_SYMS.size
        end
      end

      if !Transport.has_path(destination_hash)
        if silent
          puts "Could not establish link with #{RNS.prettyhexrep(destination_hash)}"
        else
          puts "#{ERASE_STR}Could not establish link with #{RNS.prettyhexrep(destination_hash)}"
        end
        RNS.exit(1)
      else
        if silent
          puts "Requesting file from remote..."
        else
          print "#{ERASE_STR}Requesting file from remote  "
          STDOUT.flush
        end
      end

      link.identify(identity)

      # State for fetch request/resource
      request_resolved = false
      request_status = "unknown"
      resource_resolved = false
      current_resource : Resource? = nil
      current_transfer_started : Float64? = nil

      # Progress tracking
      stats = [] of Tuple(Float64, Float64, Float64)
      stats_max = 32
      speed = 0.0
      phy_speed = 0.0

      link.set_resource_strategy(Link::ACCEPT_ALL)
      link.set_resource_started_callback(->(resource : Resource) {
        current_resource = resource
        resource.progress_callback_proc = ->(r : Resource) {
          now = Time.utc.to_unix_f
          got = r.get_progress * r.get_data_size
          phy_got = r.get_segment_progress * r.get_transfer_size
          stats << {now, got, phy_got}
          while stats.size > stats_max
            stats.shift
          end
          span = now - stats[0][0]
          if span == 0
            speed = 0.0
            phy_speed = 0.0
          else
            speed = (got - stats[0][1]) / span
            phy_diff = phy_got - stats[0][2]
            phy_speed = phy_diff / span if phy_diff > 0
          end
        }
        current_transfer_started = Time.utc.to_unix_f if current_transfer_started.nil?
      })

      link.set_resource_concluded_callback(->(resource : Resource) {
        if resource.status == Resource::COMPLETE
          raw_meta = resource.metadata
          if raw_meta.nil?
            puts "Invalid data received, ignoring resource"
            resource_resolved = true
            return
          end
          begin
            meta = MessagePack::Any.from_msgpack(raw_meta)
            name_raw = meta["name"].raw
            name_str = name_raw.is_a?(Bytes) ? String.new(name_raw) : name_raw.to_s
            filename = File.basename(name_str)
            counter = 0
            saved_filename = if sp = save_path
                               full = File.expand_path(sp + "/" + filename)
                               unless full.starts_with?(sp + "/")
                                 puts "Invalid save path #{full}, ignoring"
                                 resource_resolved = true
                                 return
                               end
                               full
                             else
                               filename
                             end

            full_save_path = saved_filename
            if allow_overwrite && File.exists?(full_save_path)
              begin
                File.delete(full_save_path)
              rescue
                puts "Could not overwrite existing file #{full_save_path}, renaming instead"
              end
            end

            while File.exists?(full_save_path)
              counter += 1
              full_save_path = "#{saved_filename}.#{counter}"
            end

            if data = resource.data
              File.write(full_save_path, data)
            end
          rescue ex
            puts "An error occurred while saving received resource: #{ex}"
          end
        else
          puts "Resource failed"
        end
        resource_resolved = true
      })

      link.request("fetch_file", data: file.to_slice,
        response_callback: ->(receipt : RequestReceipt) {
          resp = receipt.response
          if resp.is_a?(Bool) && !resp
            request_status = "not_found"
          elsif resp.nil?
            request_status = "remote_error"
          elsif resp.is_a?(UInt8) && resp == REQ_FETCH_NOT_ALLOWED
            request_status = "fetch_not_allowed"
          else
            request_status = "found"
          end
          request_resolved = true
        },
        failed_callback: ->(_receipt : RequestReceipt) {
          request_status = "unknown"
          request_resolved = true
        })

      while !request_resolved
        unless silent
          sleep 0.1.seconds
          print "\b\b#{SPINNER_SYMS[sym_idx]} "
          STDOUT.flush
          sym_idx = (sym_idx + 1) % SPINNER_SYMS.size
        end
      end

      case request_status
      when "fetch_not_allowed"
        print ERASE_STR unless silent
        puts "Fetch request failed, fetching the file #{file} was not allowed by the remote"
        link.teardown
        sleep 0.15.seconds
        RNS.exit(0)
      when "not_found"
        print ERASE_STR unless silent
        puts "Fetch request failed, the file #{file} was not found on the remote"
        link.teardown
        sleep 0.15.seconds
        RNS.exit(0)
      when "remote_error"
        print ERASE_STR unless silent
        puts "Fetch request failed due to an error on the remote system"
        link.teardown
        sleep 0.15.seconds
        RNS.exit(0)
      when "unknown"
        print ERASE_STR unless silent
        puts "Fetch request failed due to an unknown error (probably not authorised)"
        link.teardown
        sleep 0.15.seconds
        RNS.exit(0)
      when "found"
        print ERASE_STR unless silent
      end

      while !resource_resolved
        unless silent
          sleep 0.1.seconds
          if cr = current_resource
            prg = cr.get_progress
            percent = (prg * 100.0).round(1)
            phy_str = phy_rates ? " (#{size_str(phy_speed, "b")}ps at physical layer)" : ""
            ps = size_str((prg * cr.total_size).to_i64)
            ts = size_str(cr.total_size.to_i64)
            ss = size_str(speed, "b")
            if prg != 1.0
              stat_str = format_progress(percent, ps, ts, ss, phy_str)
              print "#{ERASE_STR}Transferring file #{SPINNER_SYMS[sym_idx]} #{stat_str}  "
            else
              if cts = current_transfer_started
                end_time = Time.utc.to_unix_f
                delta_time = end_time - cts
                speed = cr.total_size / delta_time if delta_time > 0
                dt_str = RNS.prettytime(delta_time)
                ss = size_str(speed, "b")
                stat_str = format_transfer_complete(percent, ps, ts, dt_str, ss, phy_str)
              else
                stat_str = format_progress(percent, ps, ts, ss, phy_str)
              end
              print "#{ERASE_STR}Transfer complete  #{stat_str}  "
            end
          else
            print "#{ERASE_STR}Waiting for transfer to start #{SPINNER_SYMS[sym_idx]} "
          end
          STDOUT.flush
          sym_idx = (sym_idx + 1) % SPINNER_SYMS.size
        end
      end

      cr = current_resource
      if cr.nil? || cr.status != Resource::COMPLETE
        if silent
          puts "The transfer failed"
        else
          puts "#{ERASE_STR}The transfer failed"
        end
        RNS.exit(1)
      else
        if silent
          puts "#{file} fetched from #{RNS.prettyhexrep(destination_hash)}"
        else
          puts "\n#{file} fetched from #{RNS.prettyhexrep(destination_hash)}"
        end
        link.teardown
        sleep 0.1.seconds
        RNS.exit(0)
      end
    end
  end
end
