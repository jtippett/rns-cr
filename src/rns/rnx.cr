module RNS
  module Rnx
    APP_NAME          = "rnx"
    REMOTE_EXEC_GRACE = 2.0

    # Spinner characters matching Python's braille spinner.
    SPINNER_SYMS = "⢄⢂⢁⡁⡈⡐⡠"

    # Parsed command-line arguments for rnx
    class Args
      property config : String?
      property verbose : Int32
      property quiet : Int32
      property print_identity : Bool
      property listen : Bool
      property identity : String?
      property interactive : Bool
      property no_announce : Bool
      property allowed : Array(String)
      property noauth : Bool
      property noid : Bool
      property detailed : Bool
      property mirror : Bool
      property timeout : Float64
      property result_timeout : Float64?
      property stdin_data : String?
      property stdout_limit : Int32?
      property stderr_limit : Int32?
      property version : Bool
      # Positional: destination, command
      property destination : String?
      property command : String?

      def initialize(
        @config = nil,
        @verbose = 0,
        @quiet = 0,
        @print_identity = false,
        @listen = false,
        @identity = nil,
        @interactive = false,
        @no_announce = false,
        @allowed = [] of String,
        @noauth = false,
        @noid = false,
        @detailed = false,
        @mirror = false,
        @timeout = Transport::PATH_REQUEST_TIMEOUT.to_f64,
        @result_timeout = nil,
        @stdin_data = nil,
        @stdout_limit = nil,
        @stderr_limit = nil,
        @version = false,
        @destination = nil,
        @command = nil,
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
        when "-p", "--print-identity"
          args.print_identity = true
        when "-l", "--listen"
          args.listen = true
        when "-i"
          i += 1
          args.identity = argv[i]? || raise ArgumentError.new("-i requires an identity path")
        when "-x", "--interactive"
          args.interactive = true
        when "-b", "--no-announce"
          args.no_announce = true
        when "-a"
          i += 1
          val = argv[i]? || raise ArgumentError.new("-a requires an allowed_hash argument")
          args.allowed << val
        when "-n", "--noauth"
          args.noauth = true
        when "-N", "--noid"
          args.noid = true
        when "-d", "--detailed"
          args.detailed = true
        when "-m"
          args.mirror = true
        when "-w"
          i += 1
          val = argv[i]? || raise ArgumentError.new("-w requires a seconds value")
          args.timeout = val.to_f64
        when "-W"
          i += 1
          val = argv[i]? || raise ArgumentError.new("-W requires a seconds value")
          args.result_timeout = val.to_f64
        when "--stdin"
          i += 1
          args.stdin_data = argv[i]? || raise ArgumentError.new("--stdin requires an input string")
        when "--stdout"
          i += 1
          val = argv[i]? || raise ArgumentError.new("--stdout requires a byte count")
          args.stdout_limit = val.to_i32
        when "--stderr"
          i += 1
          val = argv[i]? || raise ArgumentError.new("--stderr requires a byte count")
          args.stderr_limit = val.to_i32
        when "-v", "--verbose"
          args.verbose += 1
        when "-q", "--quiet"
          args.quiet += 1
        when /^-[vqplxbnNdm]+$/
          # Handle combined short flags
          arg[1..].each_char do |c|
            case c
            when 'v' then args.verbose += 1
            when 'q' then args.quiet += 1
            when 'p' then args.print_identity = true
            when 'l' then args.listen = true
            when 'x' then args.interactive = true
            when 'b' then args.no_announce = true
            when 'n' then args.noauth = true
            when 'N' then args.noid = true
            when 'd' then args.detailed = true
            when 'm' then args.mirror = true
            else
              raise ArgumentError.new("Unknown flag: -#{c}")
            end
          end
        else
          if arg.starts_with?("-")
            raise ArgumentError.new("Unknown argument: #{arg}")
          else
            # Positional: first = destination, second = command
            if args.destination.nil?
              args.destination = arg
            elsif args.command.nil?
              args.command = arg
            else
              raise ArgumentError.new("Unexpected positional argument: #{arg}")
            end
          end
        end
        i += 1
      end
      args
    end

    # Version string matching Python's "rnx {version}" format.
    def self.version_string : String
      "rnx #{RNS::VERSION}"
    end

    # Usage message matching Python argparse output.
    def self.usage_string : String
      <<-USAGE
      Reticulum Remote Execution Utility

      Usage: rnx [options] [destination] [command]

      Positional arguments:
        destination           hexadecimal hash of the listener
        command               command to be executed

      Options:
        --config PATH         path to alternative Reticulum config directory
        -v, --verbose         increase verbosity
        -q, --quiet           decrease verbosity
        -p, --print-identity  print identity and destination info and exit
        -l, --listen          listen for incoming commands
        -i IDENTITY           path to identity to use
        -x, --interactive     enter interactive mode
        -b, --no-announce     don't announce at program start
        -a HASH               accept from this identity
        -n, --noauth          accept commands from anyone
        -N, --noid            don't identify to listener
        -d, --detailed        show detailed result output
        -m                    mirror exit code of remote command
        -w SECONDS            connect and request timeout before giving up
        -W SECONDS            max result download time
        --stdin INPUT         pass input to stdin
        --stdout BYTES        max size in bytes of returned stdout
        --stderr BYTES        max size in bytes of returned stderr
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

    # Pretty time formatting matching Python's pretty_time exactly.
    def self.pretty_time(time_val : Float64, verbose : Bool = false) : String
      days = (time_val / (24 * 3600)).to_i
      remainder = time_val % (24 * 3600)
      hours = (remainder / 3600).to_i
      remainder = remainder % 3600
      minutes = (remainder / 60).to_i
      remainder = remainder % 60
      seconds = remainder.round(2)

      ss = seconds == 1.0 ? "" : "s"
      sm = minutes == 1 ? "" : "s"
      sh = hours == 1 ? "" : "s"
      sd = days == 1 ? "" : "s"

      components = [] of String
      if days > 0
        components << (verbose ? "#{days} day#{sd}" : "#{days}d")
      end
      if hours > 0
        components << (verbose ? "#{hours} hour#{sh}" : "#{hours}h")
      end
      if minutes > 0
        components << (verbose ? "#{minutes} minute#{sm}" : "#{minutes}m")
      end
      if seconds > 0
        components << (verbose ? "#{seconds} second#{ss}" : "#{seconds}s")
      end

      tstr = ""
      components.each_with_index do |c, idx|
        i = idx + 1
        if i == 1
          # first component, no prefix
        elsif i < components.size
          tstr += ", "
        elsif i == components.size
          tstr += " and "
        end
        tstr += c
      end

      tstr
    end

    # Prepare or load identity for rnx.
    def self.prepare_identity(identity_path : String?) : Identity
      path = identity_path || (Reticulum.identitypath + "/" + APP_NAME)

      if File.exists?(path)
        id = Identity.from_file(path)
        return id.not_nil! if id
      end

      RNS.log("No valid saved identity found, creating new...", RNS::LOG_INFO)
      id = Identity.new
      id.to_file(path)
      id
    end

    # Spin with message until condition met or timeout. Returns false on timeout.
    def self.spin(msg : String, timeout : Float64? = nil, &until_block : -> Bool) : Bool
      sym_idx = 0
      deadline = timeout ? Time.utc.to_unix_f + timeout : nil

      print "#{msg}  "
      STDOUT.flush

      while (deadline.nil? || Time.utc.to_unix_f < deadline) && !until_block.call
        sleep 0.1.seconds
        print "\b\b#{SPINNER_SYMS[sym_idx]} "
        STDOUT.flush
        sym_idx = (sym_idx + 1) % SPINNER_SYMS.size
      end

      print "\r#{" " * (msg.size + 4)}\r"
      STDOUT.flush

      if deadline && Time.utc.to_unix_f > deadline
        false
      else
        true
      end
    end

    # Format a command execution request data array.
    # Returns an array matching the Python protocol:
    #   [command_bytes, timeout, stdout_limit, stderr_limit, stdin_bytes]
    def self.format_request_data(command : String, timeout : Float64?,
                                 stdout_limit : Int32?, stderr_limit : Int32?,
                                 stdin_data : String?) : Array(Bytes | Float64? | Int32? | Nil)
      request_data = [] of Bytes | Float64? | Int32? | Nil
      request_data << command.encode("UTF-8").to_slice
      request_data << timeout
      request_data << stdout_limit
      request_data << stderr_limit
      if sd = stdin_data
        request_data << sd.encode("UTF-8").to_slice
      else
        request_data << nil
      end
      request_data
    end

    # Format execution result for display.
    # Result array from remote: [executed, retval, stdout, stderr, outlen, errlen, started, concluded]
    def self.format_result(result : Array, detailed : Bool, mirror : Bool,
                           stdout_limit : Int32?, stderr_limit : Int32?) : {String, Int32?}
      executed = result[0].as(Bool)
      retval = result[1].as(Int32?)
      stdout_data = result[2].as(Bytes?)
      stderr_data = result[3].as(Bytes?)
      outlen = result[4].as(Int32?)
      errlen = result[5].as(Int32?)
      started = result[6].as(Float64?)
      concluded = result[7].as(Float64?)

      output = String::Builder.new

      unless executed
        output << "Remote could not execute command\n"
        return {output.to_s, nil}
      end

      if so = stdout_data
        output << String.new(so) if so.size > 0
      end
      if se = stderr_data
        output << String.new(se) if se.size > 0
      end

      if detailed
        output << "\n--- End of remote output, rnx done ---\n"
        if started && concluded
          s = started.not_nil!
          c = concluded.not_nil!
          cmd_duration = (c - s).round(3)
          output << "Remote command execution took #{cmd_duration} seconds\n"
        end

        if ol = outlen
          if so = stdout_data
            if so.size < ol
              output << "Remote wrote #{ol} bytes to stdout, #{so.size} bytes displayed\n"
            else
              output << "Remote wrote #{ol} bytes to stdout\n"
            end
          end
        end

        if el = errlen
          if se = stderr_data
            if se.size < el
              output << "Remote wrote #{el} bytes to stderr, #{se.size} bytes displayed\n"
            else
              output << "Remote wrote #{el} bytes to stderr\n"
            end
          end
        end
      else
        # Non-detailed: check for truncation
        truncated_parts = [] of String
        if stdout_limit != 0 && (so = stdout_data) && (ol = outlen) && so.size < ol
          truncated_parts << "  stdout truncated to #{so.size} bytes"
        end
        if stderr_limit != 0 && (se = stderr_data) && (el = errlen) && se.size < el
          truncated_parts << "  stderr truncated to #{se.size} bytes"
        end
        if truncated_parts.size > 0
          output << "\nOutput truncated before being returned:\n"
          truncated_parts.each { |p| output << p << "\n" }
        end
      end

      {output.to_s, retval}
    end

    # Main entry point for the rnx binary.
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
          print_identity: args.print_identity,
          disable_auth: args.noauth,
          disable_announce: args.no_announce,
        )
      elsif args.destination && args.command
        execute(
          configdir: args.config,
          identitypath: args.identity,
          verbosity: args.verbose,
          quietness: args.quiet,
          detailed: args.detailed,
          mirror: args.mirror,
          noid: args.noid,
          destination: args.destination.not_nil!,
          command: args.command.not_nil!,
          stdin_data: args.stdin_data,
          stdout_limit: args.stdout_limit,
          stderr_limit: args.stderr_limit,
          timeout: args.timeout,
          result_timeout: args.result_timeout,
          interactive: args.interactive,
        )

        if args.interactive
          code : Int32? = nil
          loop do
            cstr = (code && code != 0) ? code.to_s : ""
            print "#{cstr}> "
            begin
              command = gets
              break if command.nil?
              command = command.strip
              break if command.downcase == "exit" || command.downcase == "quit"
            rescue
              break
            end

            if command.downcase == "clear"
              print "\033c"
            else
              code = execute(
                configdir: args.config,
                identitypath: args.identity,
                verbosity: args.verbose,
                quietness: args.quiet,
                detailed: args.detailed,
                mirror: args.mirror,
                noid: args.noid,
                destination: args.destination.not_nil!,
                command: command,
                stdin_data: nil,
                stdout_limit: args.stdout_limit,
                stderr_limit: args.stderr_limit,
                timeout: args.timeout,
                result_timeout: args.result_timeout,
                interactive: true,
              )
            end
          end
        end
      else
        puts ""
        puts usage_string
        puts ""
      end
    rescue ex : ArgumentError
      STDERR.puts "rnx: #{ex.message}"
      exit(1)
    rescue ex
      if ex.message.try(&.includes?("Interrupt"))
        puts ""
      end
    end

    # Listen mode — receive and execute commands from authenticated clients.
    def self.listen(configdir : String?, identitypath : String?, verbosity : Int32,
                    quietness : Int32, allowed : Array(String), print_identity : Bool,
                    disable_auth : Bool, disable_announce : Bool)
      allow_all = disable_auth
      allowed_identity_hashes = [] of Bytes

      targetloglevel = 3 + verbosity - quietness
      reticulum = ReticulumInstance.new(configdir: configdir, loglevel: targetloglevel)

      identity = prepare_identity(identitypath)
      destination = Destination.new(identity, Destination::IN, Destination::SINGLE, APP_NAME, "execute")

      if print_identity
        puts "Identity     : #{identity}"
        puts "Listening on : #{RNS.prettyhexrep(destination.hash)}"
        exit(0)
      end

      unless disable_auth
        dest_len = (Reticulum::TRUNCATED_HASHLENGTH // 8) * 2

        allowed.each do |a|
          if a.size != dest_len
            puts "Allowed destination length is invalid, must be #{dest_len} hexadecimal characters (#{dest_len // 2} bytes)."
            exit(1)
          end
          begin
            allowed_identity_hashes << a.hexbytes
          rescue
            puts "Invalid destination entered. Check your input."
            exit(1)
          end
        end

        # Load from allowed_identities files
        allowed_file : String? = nil
        ["/etc/rnx/allowed_identities",
         File.expand_path("~/.config/rnx/allowed_identities"),
         File.expand_path("~/.rnx/allowed_identities")].each do |path|
          if File.exists?(path)
            allowed_file = path
            break
          end
        end

        if af = allowed_file
          begin
            File.read(af).gsub("\r", "").split("\n").each do |line|
              if line.size == dest_len
                allowed_identity_hashes << line.hexbytes
              end
            end
          rescue ex
            puts ex.message
            exit(1)
          end
        end
      end

      if allowed_identity_hashes.size < 1 && !disable_auth
        puts "Warning: No allowed identities configured, rnx will not accept any commands!"
      end

      destination.set_link_established_callback(->(link : Link) {
        link.set_remote_identified_callback(->(lnk : Link, ident : Identity) {
          RNS.log("Initiator of link #{lnk} identified as #{RNS.prettyhexrep(ident.hash)}")
          if !allow_all && !allowed_identity_hashes.any? { |h| h == ident.hash }
            RNS.log("Identity #{RNS.prettyhexrep(ident.hash)} not allowed, tearing down link")
            lnk.teardown
          end
        })
        link.set_link_closed_callback(->(lnk : Link) {
          RNS.log("Command link #{lnk} closed")
        })
        RNS.log("Command link #{link} established")
      })

      if !allow_all
        destination.register_request_handler("command",
          response_generator: ->(path : String, data : Bytes, request_id : Bytes, link_id : Bytes, remote_identity : Identity?, requested_at : Float64) {
            execute_received_command(data, remote_identity)
          },
          allow: Destination::ALLOW_LIST,
          allowed_list: allowed_identity_hashes)
      else
        destination.register_request_handler("command",
          response_generator: ->(path : String, data : Bytes, request_id : Bytes, link_id : Bytes, remote_identity : Identity?, requested_at : Float64) {
            execute_received_command(data, remote_identity)
          },
          allow: Destination::ALLOW_ALL)
      end

      RNS.log("rnx listening for commands on #{RNS.prettyhexrep(destination.hash)}")

      unless disable_announce
        destination.announce
      end

      loop { sleep 1.second }
    end

    # Execute a command received from a remote client.
    # Data is a msgpack array: [command_bytes, timeout, o_limit, e_limit, stdin_bytes]
    # Returns a result array: [executed, retval, stdout, stderr, outlen, errlen, started, concluded]
    def self.execute_received_command(data : Bytes, remote_identity : Identity?) : Array
      # Unpack the request data (msgpack array)
      unpacked = Array(MessagePack::Type).from_msgpack(data)
      command = String.new(unpacked[0].as(Bytes))
      timeout_val = unpacked[1].as?(Float64 | Int64)
      o_limit = unpacked[2].as?(Int64)
      e_limit = unpacked[3].as?(Int64)
      stdin_data = unpacked[4].as?(Bytes)

      if ri = remote_identity
        RNS.log("Executing command [#{command}] for #{RNS.prettyhexrep(ri.hash)}")
      else
        RNS.log("Executing command [#{command}] for unknown requestor")
      end

      started = Time.utc.to_unix_f
      result = Array(Bool | Int32? | Bytes? | Int64? | Float64?).new(8, nil)
      result[0] = false # executed
      result[6] = started

      begin
        process = Process.new(command, shell: true,
          input: Process::Redirect::Pipe,
          output: Process::Redirect::Pipe,
          error: Process::Redirect::Pipe)
        result[0] = true
      rescue ex
        result[0] = false
        return result.map(&.as(Bool | Int32? | Bytes? | Int64? | Float64?))
      end

      if sd = stdin_data
        process.input.write(sd)
      end
      process.input.close

      stdout_bytes = process.output.gets_to_end.to_slice
      stderr_bytes = process.error.gets_to_end.to_slice

      status = process.wait

      timeout_f = timeout_val.try(&.to_f64)
      if timeout_f && Time.utc.to_unix_f < started + timeout_f
        result[7] = Time.utc.to_unix_f
      end

      result[1] = status.exit_code

      if ol = o_limit
        if stdout_bytes.size > ol
          result[2] = ol == 0 ? Bytes.empty : stdout_bytes[0, ol.to_i32]
        else
          result[2] = stdout_bytes
        end
      else
        result[2] = stdout_bytes
      end

      if el = e_limit
        if stderr_bytes.size > el
          result[3] = el == 0 ? Bytes.empty : stderr_bytes[0, el.to_i32]
        else
          result[3] = stderr_bytes
        end
      else
        result[3] = stderr_bytes
      end

      result[4] = stdout_bytes.size.to_i64
      result[5] = stderr_bytes.size.to_i64

      if ri = remote_identity
        RNS.log("Delivering result of command [#{command}] to #{RNS.prettyhexrep(ri.hash)}")
      else
        RNS.log("Delivering result of command [#{command}] to unknown requestor")
      end

      result.map(&.as(Bool | Int32? | Bytes? | Int64? | Float64?))
    end

    # Execute a command on a remote rnx listener.
    def self.execute(configdir : String?, identitypath : String?, verbosity : Int32,
                     quietness : Int32, detailed : Bool, mirror : Bool, noid : Bool,
                     destination : String, command : String, stdin_data : String?,
                     stdout_limit : Int32?, stderr_limit : Int32?,
                     timeout : Float64, result_timeout : Float64?,
                     interactive : Bool) : Int32?
      destination_hash = parse_destination_hash(destination)

      targetloglevel = 3 + verbosity - quietness
      reticulum = ReticulumInstance.new(configdir: configdir, loglevel: targetloglevel)
      identity = prepare_identity(identitypath)

      if !Transport.has_path(destination_hash)
        Transport.request_path(destination_hash)
        unless spin("Path to #{RNS.prettyhexrep(destination_hash)} requested", timeout: timeout) {
                 Transport.has_path(destination_hash)
               }
          puts "Path not found"
          return nil if interactive
          exit(242)
        end
      end

      listener_identity = Identity.recall(destination_hash)
      if listener_identity.nil?
        puts "Could not recall identity for #{RNS.prettyhexrep(destination_hash)}"
        return nil if interactive
        exit(242)
      end

      listener_destination = Destination.new(
        listener_identity.not_nil!,
        Destination::OUT,
        Destination::SINGLE,
        APP_NAME,
        "execute"
      )

      link = Link.new(listener_destination)

      unless spin("Establishing link with #{RNS.prettyhexrep(destination_hash)}", timeout: timeout) {
               link.status == Link::ACTIVE
             }
        puts "Could not establish link with #{RNS.prettyhexrep(destination_hash)}"
        return nil if interactive
        exit(243)
      end

      unless noid
        link.identify(identity)
      end

      sd = stdin_data ? stdin_data.encode("UTF-8").to_slice : nil

      request_data = [
        command.encode("UTF-8").to_slice,
        timeout,
        stdout_limit,
        stderr_limit,
        sd,
      ]

      rexec_timeout = timeout + link.rtt * 4 + REMOTE_EXEC_GRACE

      request_receipt = link.request(
        path: "command",
        data: request_data,
        response_callback: ->(receipt : RequestReceipt) { },
        failed_callback: ->(receipt : RequestReceipt) { },
        timeout: rexec_timeout
      )

      spin("Sending execution request", timeout: rexec_timeout + 0.5) {
        link.status == Link::CLOSED ||
          (request_receipt.status != RequestReceipt::FAILED &&
            request_receipt.status != RequestReceipt::SENT)
      }

      if link.status == Link::CLOSED
        puts "Could not request remote execution, link was closed"
        return nil if interactive
        exit(244)
      end

      if request_receipt.status == RequestReceipt::FAILED
        puts "Could not request remote execution"
        return nil if interactive
        exit(244)
      end

      spin("Command delivered, awaiting result", timeout: timeout) {
        request_receipt.status != RequestReceipt::DELIVERED
      }

      if request_receipt.status == RequestReceipt::FAILED
        puts "No result was received"
        return nil if interactive
        exit(245)
      end

      # Wait for result download with progress display
      # (simplified — no progress spinner for result download in this port)
      spin("Receiving result", timeout: result_timeout) {
        request_receipt.status != RequestReceipt::RECEIVING
      }

      if request_receipt.status == RequestReceipt::FAILED
        puts "Receiving result failed"
        return nil if interactive
        exit(246)
      end

      if response = request_receipt.response
        begin
          result_arr = response.as(Array)
          output, retval = format_result(result_arr, detailed, mirror, stdout_limit, stderr_limit)
          print output
        rescue ex
          puts "Received invalid result"
          return nil if interactive
          exit(247)
        end
      else
        puts "No response"
        return nil if interactive
        exit(249)
      end

      unless interactive
        link.teardown
      end

      if !interactive && mirror
        if rv = retval
          exit(rv)
        else
          exit(240)
        end
      else
        if interactive
          return mirror ? retval : nil
        else
          exit(0)
        end
      end
    end
  end
end
