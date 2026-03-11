module RNS
  module Rnprobe
    DEFAULT_PROBE_SIZE =   16
    DEFAULT_TIMEOUT    = 12.0

    # Parsed command-line arguments for rnprobe
    class Args
      property config : String?
      property size : Int32?
      property probes : Int32
      property timeout : Float64?
      property wait : Float64
      property verbose : Int32
      property full_name : String?
      property destination_hash : String?
      property version : Bool

      def initialize(
        @config = nil,
        @size = nil,
        @probes = 1,
        @timeout = nil,
        @wait = 0.0,
        @verbose = 0,
        @full_name = nil,
        @destination_hash = nil,
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
        when "-s", "--size"
          i += 1
          val = argv[i]? || raise ArgumentError.new("--size requires a byte count")
          args.size = val.to_i32
        when "-n", "--probes"
          i += 1
          val = argv[i]? || raise ArgumentError.new("--probes requires a count")
          args.probes = val.to_i32
        when "-t", "--timeout"
          i += 1
          val = argv[i]? || raise ArgumentError.new("--timeout requires a seconds value")
          args.timeout = val.to_f64
        when "-w", "--wait"
          i += 1
          val = argv[i]? || raise ArgumentError.new("--wait requires a seconds value")
          args.wait = val.to_f64
        when "--version"
          args.version = true
        when /^-[vsntwv]+$/
          # Handle combined short flags, but only -v can be combined
          arg[1..].each_char do |c|
            case c
            when 'v' then args.verbose += 1
            else
              raise ArgumentError.new("Unknown flag: -#{c}")
            end
          end
        else
          if arg.starts_with?("-")
            raise ArgumentError.new("Unknown argument: #{arg}")
          else
            # First positional = full_name, second = destination_hash
            if args.full_name.nil?
              args.full_name = arg
            elsif args.destination_hash.nil?
              args.destination_hash = arg
            else
              raise ArgumentError.new("Unexpected positional argument: #{arg}")
            end
          end
        end
        i += 1
      end
      args
    end

    # Version string matching Python's "rnprobe {version}" format.
    def self.version_string : String
      "rnprobe #{RNS::VERSION}"
    end

    # Usage message matching Python argparse output.
    def self.usage_string : String
      <<-USAGE
      Reticulum Probe Utility

      Usage: rnprobe [--config PATH] [-s SIZE] [-n PROBES] [-t SECONDS] [-w SECONDS] [-v] full_name destination_hash

      Positional arguments:
        full_name             full destination name in dotted notation
        destination_hash      hexadecimal hash of the destination

      Options:
        --config PATH         path to alternative Reticulum config directory
        -s, --size SIZE       size of probe packet payload in bytes
        -n, --probes COUNT    number of probes to send (default: 1)
        -t, --timeout SECS    timeout before giving up
        -w, --wait SECS       time between each probe (default: 0)
        -v, --verbose         increase verbosity
        --version             show version and exit
      USAGE
    end

    # Validate a hex destination hash string, returning the bytes.
    def self.parse_destination_hash(hex : String) : Bytes
      dest_len = (Reticulum::TRUNCATED_HASHLENGTH // 8) * 2
      unless hex.size == dest_len
        raise ArgumentError.new(
          "Destination length is invalid, must be #{dest_len} hexadecimal characters (#{dest_len // 2} bytes)."
        )
      end
      begin
        hex.hexbytes
      rescue
        raise ArgumentError.new("Invalid destination entered. Check your input.")
      end
    end

    # Format a probe result string.
    def self.format_probe_reply(destination_hash : Bytes, hops : Int32, rtt : Float64, reception_stats : String = "") : String
      ms = hops != 1 ? "s" : ""

      if rtt >= 1.0
        rtt_rounded = rtt.round(3)
        rtt_string = "#{rtt_rounded} seconds"
      else
        rtt_rounded = (rtt * 1000).round(3)
        rtt_string = "#{rtt_rounded} milliseconds"
      end

      "Valid reply from #{RNS.prettyhexrep(destination_hash)}\n" \
      "Round-trip time is #{rtt_string} over #{hops} hop#{ms}#{reception_stats}\n"
    end

    # Format probe summary string.
    def self.format_probe_summary(sent : Int32, replies : Int32) : String
      loss = ((1.0 - (replies.to_f64 / sent.to_f64)) * 100).round(2)
      "Sent #{sent}, received #{replies}, packet loss #{loss}%"
    end

    # Spinner characters matching Python's braille spinner.
    SPINNER_SYMS = "\u28C4\u28C2\u28C1\u2841\u2848\u2850\u2860"

    # Main entry point for the rnprobe binary.
    def self.main(argv : Array(String) = ARGV.to_a)
      args = parse_args(argv)

      if args.version
        puts version_string
        return
      end

      if args.destination_hash.nil?
        puts ""
        puts usage_string
        puts ""
        return
      end

      full_name = args.full_name
      if full_name.nil?
        puts "The full destination name including application name aspects must be specified for the destination"
        exit(1)
      end

      begin
        app_name, aspects = Destination.app_and_aspects_from_name(full_name)
      rescue ex
        puts ex.message
        exit(1)
      end

      destination_hash = parse_destination_hash(args.destination_hash.not_nil!)
      size = args.size || DEFAULT_PROBE_SIZE

      if args.verbose > 0
        more_output = true
        verbosity = args.verbose - 1
      else
        more_output = false
        verbosity = -1
      end

      reticulum = ReticulumInstance.new(configdir: args.config, loglevel: 3 + verbosity)

      if !Transport.has_path(destination_hash)
        Transport.request_path(destination_hash)
        print "Path to #{RNS.prettyhexrep(destination_hash)} requested  "
        STDOUT.flush

        timeout_val = args.timeout || (DEFAULT_TIMEOUT + Transport.first_hop_timeout(destination_hash))
        limit = Time.utc.to_unix_f + timeout_val
        sym_idx = 0

        while !Transport.has_path(destination_hash) && Time.utc.to_unix_f < limit
          sleep 0.1.seconds
          print "\b\b#{SPINNER_SYMS[sym_idx]} "
          STDOUT.flush
          sym_idx = (sym_idx + 1) % SPINNER_SYMS.size
        end

        if Time.utc.to_unix_f > limit
          puts "\r                                                          \rPath request timed out"
          exit(1)
        end
      end

      server_identity = Identity.recall(destination_hash)

      if server_identity.nil?
        puts "Could not recall identity for #{RNS.prettyhexrep(destination_hash)}"
        exit(1)
      end

      request_destination = Destination.new(
        server_identity,
        Destination::OUT,
        Destination::SINGLE,
        app_name,
        aspects
      )

      sent = 0
      replies = 0
      probes_remaining = args.probes

      while probes_remaining > 0
        if sent > 0
          sleep args.wait.seconds
        end

        probe_data = Random::Secure.random_bytes(size)
        probe = Packet.new(request_destination, probe_data)

        begin
          probe.pack
        rescue
          puts "Error: Probe packet size of #{probe.raw.try(&.size) || 0} bytes exceeds MTU of #{Reticulum::MTU} bytes"
          exit(3)
        end

        receipt = probe.send
        sent += 1

        if more_output
          nhd = Transport.next_hop(destination_hash)
          via_str = nhd ? " via #{RNS.prettyhexrep(nhd)}" : ""
          next_hop_if = Transport.next_hop_interface(destination_hash)
          if_str = next_hop_if ? " on #{next_hop_if.hexstring}" : ""
          more = via_str + if_str
        else
          more = ""
        end

        print "\rSent probe #{sent} (#{size} bytes) to #{RNS.prettyhexrep(destination_hash)}#{more}  "

        if receipt
          timeout_val = args.timeout || (DEFAULT_TIMEOUT + Transport.first_hop_timeout(destination_hash))
          limit = Time.utc.to_unix_f + timeout_val
          sym_idx = 0

          while receipt.status == PacketReceipt::SENT && Time.utc.to_unix_f < limit
            sleep 0.1.seconds
            print "\b\b#{SPINNER_SYMS[sym_idx]} "
            STDOUT.flush
            sym_idx = (sym_idx + 1) % SPINNER_SYMS.size
          end

          if Time.utc.to_unix_f > limit
            puts "\r                                                                \rProbe timed out"
          else
            print "\b\b "
            STDOUT.flush

            if receipt.status == PacketReceipt::DELIVERED
              replies += 1
              hops = Transport.hops_to(destination_hash)

              rtt = receipt.get_rtt
              reception_stats = ""

              if Transport.is_connected_to_shared_instance?
                # Could retrieve RSSI/SNR/Q from shared instance
                # but these methods may not be fully implemented yet
              else
                if proof_pkt = receipt.proof_packet
                  if rssi = proof_pkt.rssi
                    reception_stats += " [RSSI #{rssi} dBm]"
                  end
                  if snr = proof_pkt.snr
                    reception_stats += " [SNR #{snr} dB]"
                  end
                end
              end

              puts format_probe_reply(request_destination.hash, hops, rtt, reception_stats)
            else
              puts "\r                                                          \rProbe timed out"
            end
          end
        else
          puts "\r                                                          \rProbe send failed"
        end

        probes_remaining -= 1
      end

      puts format_probe_summary(sent, replies)
      loss = ((1.0 - (replies.to_f64 / sent.to_f64)) * 100).round(2)
      if loss > 0
        exit(2)
      else
        exit(0)
      end
    rescue ex : ArgumentError
      STDERR.puts "rnprobe: #{ex.message}"
      exit(1)
    rescue ex
      if ex.message.try(&.includes?("Interrupt"))
        puts ""
      end
    end
  end
end
