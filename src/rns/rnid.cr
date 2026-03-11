require "base64"
require "qr-code"

module RNS
  module Rnid
    APP_NAME    = "rnid"
    SIG_EXT     = "rsg"
    ENCRYPT_EXT = "rfe"
    CHUNK_SIZE  = 16 * 1024 * 1024

    # Parsed command-line arguments for rnid
    class Args
      property config : String?
      property identity : String?
      property generate : String?
      property import_str : String?
      property export : Bool
      property verbose : Int32
      property quiet : Int32
      property announce : String?
      property hash_aspects : String?
      property encrypt : String?
      property decrypt : String?
      property sign : String?
      property validate : String?
      property read : String?
      property write : String?
      property force : Bool
      property stdin : Bool
      property stdout : Bool
      property request : Bool
      property timeout : Float64
      property print_identity : Bool
      property print_private : Bool
      property base64 : Bool
      property base32 : Bool
      property qr : Bool
      property version : Bool

      def initialize(
        @config = nil,
        @identity = nil,
        @generate = nil,
        @import_str = nil,
        @export = false,
        @verbose = 0,
        @quiet = 0,
        @announce = nil,
        @hash_aspects = nil,
        @encrypt = nil,
        @decrypt = nil,
        @sign = nil,
        @validate = nil,
        @read = nil,
        @write = nil,
        @force = false,
        @stdin = false,
        @stdout = false,
        @request = false,
        @timeout = Transport::PATH_REQUEST_TIMEOUT.to_f64,
        @print_identity = false,
        @print_private = false,
        @base64 = false,
        @base32 = false,
        @qr = false,
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
        when "-i", "--identity"
          i += 1
          args.identity = argv[i]? || raise ArgumentError.new("--identity requires an identity argument")
        when "-g", "--generate"
          i += 1
          args.generate = argv[i]? || raise ArgumentError.new("--generate requires a file path")
        when "-m", "--import"
          i += 1
          args.import_str = argv[i]? || raise ArgumentError.new("--import requires identity data")
        when "-x", "--export"
          args.export = true
        when "-a", "--announce"
          i += 1
          args.announce = argv[i]? || raise ArgumentError.new("--announce requires destination aspects")
        when "-H", "--hash"
          i += 1
          args.hash_aspects = argv[i]? || raise ArgumentError.new("--hash requires destination aspects")
        when "-e", "--encrypt"
          i += 1
          args.encrypt = argv[i]? || raise ArgumentError.new("--encrypt requires a file path")
        when "-d", "--decrypt"
          i += 1
          args.decrypt = argv[i]? || raise ArgumentError.new("--decrypt requires a file path")
        when "-s", "--sign"
          i += 1
          args.sign = argv[i]? || raise ArgumentError.new("--sign requires a file path")
        when "-V", "--validate"
          i += 1
          args.validate = argv[i]? || raise ArgumentError.new("--validate requires a file path")
        when "-r", "--read"
          i += 1
          args.read = argv[i]? || raise ArgumentError.new("--read requires a file path")
        when "-w", "--write"
          i += 1
          args.write = argv[i]? || raise ArgumentError.new("--write requires a file path")
        when "-f", "--force"
          args.force = true
        when "-I", "--stdin"
          args.stdin = true
        when "-O", "--stdout"
          args.stdout = true
        when "-R", "--request"
          args.request = true
        when "-t"
          i += 1
          val = argv[i]? || raise ArgumentError.new("-t requires a seconds value")
          args.timeout = val.to_f64
        when "-p", "--print-identity"
          args.print_identity = true
        when "-P", "--print-private"
          args.print_private = true
        when "-b", "--base64"
          args.base64 = true
        when "-B", "--base32"
          args.base32 = true
        when "-Q", "--qr"
          args.qr = true
        when "--version"
          args.version = true
        when /^-[vqfIORpPbBQx]+$/
          arg[1..].each_char do |c|
            case c
            when 'v' then args.verbose += 1
            when 'q' then args.quiet += 1
            when 'f' then args.force = true
            when 'I' then args.stdin = true
            when 'O' then args.stdout = true
            when 'R' then args.request = true
            when 'p' then args.print_identity = true
            when 'P' then args.print_private = true
            when 'b' then args.base64 = true
            when 'B' then args.base32 = true
            when 'Q' then args.qr = true
            when 'x' then args.export = true
            else
              raise ArgumentError.new("Unknown flag: -#{c}")
            end
          end
        else
          if arg.starts_with?("-")
            raise ArgumentError.new("Unknown argument: #{arg}")
          else
            raise ArgumentError.new("Unexpected positional argument: #{arg}")
          end
        end
        i += 1
      end
      args
    end

    # Version string matching Python's "rnid {version}" format.
    def self.version_string : String
      "rnid #{RNS::VERSION}"
    end

    # Usage message.
    def self.usage_string : String
      <<-USAGE
      Reticulum Identity & Encryption Utility

      Usage: rnid [options]

      Options:
        --config PATH         path to alternative Reticulum config directory
        -i, --identity ID     hexadecimal identity/destination hash, or path to Identity file
        -g, --generate FILE   generate a new Identity
        -m, --import DATA     import identity in hex, base32 or base64 format
        -x, --export          export identity to hex, base32 or base64 format
        -v, --verbose         increase verbosity
        -q, --quiet           decrease verbosity
        -a, --announce ASPS   announce a destination based on this Identity
        -H, --hash ASPECTS    show destination hashes for aspects for this Identity
        -e, --encrypt FILE    encrypt file
        -d, --decrypt FILE    decrypt file
        -s, --sign FILE       sign file
        -V, --validate FILE   validate signature
        -r, --read FILE       input file path
        -w, --write FILE      output file path
        -f, --force           write output even if it overwrites existing files
        -R, --request         request unknown Identities from the network
        -t SECONDS            identity request timeout (default: #{Transport::PATH_REQUEST_TIMEOUT})
        -p, --print-identity  print identity info and exit
        -P, --print-private   allow displaying private keys
        -b, --base64          use base64-encoded input and output
        -B, --base32          use base32-encoded input and output
        -Q, --qr              display identity hash as QR code
        --version             show version and exit
      USAGE
    end

    # Encode bytes using the selected encoding format.
    def self.encode_key(data : Bytes, args : Args) : String
      if args.base64
        Base64.urlsafe_encode(data)
      elsif args.base32
        base32_encode(data)
      else
        RNS.hexrep(data, delimit: false)
      end
    end

    # Decode an import string using the selected encoding format.
    def self.decode_import(str : String, args : Args) : Bytes
      if args.base64
        Base64.decode(str)
      elsif args.base32
        base32_decode(str)
      else
        str.hexbytes
      end
    end

    # Simple Base32 encoding (RFC 4648).
    def self.base32_encode(data : Bytes) : String
      # Simple base32 implementation (Crystal doesn't have base32 in stdlib)
      alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
      result = String::Builder.new
      bits = 0_u64
      nbits = 0

      data.each do |byte|
        bits = (bits << 8) | byte.to_u64
        nbits += 8
        while nbits >= 5
          nbits -= 5
          result << alphabet[(bits >> nbits) & 0x1f]
        end
      end

      if nbits > 0
        result << alphabet[(bits << (5 - nbits)) & 0x1f]
      end

      # Add padding
      encoded = result.to_s
      pad = (8 - (encoded.size % 8)) % 8
      encoded + "=" * pad
    end

    # Simple Base32 decoding (RFC 4648).
    def self.base32_decode(str : String) : Bytes
      alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
      # Remove padding
      clean = str.rstrip('=').upcase
      bits = 0_u64
      nbits = 0
      result = IO::Memory.new

      clean.each_char do |c|
        val = alphabet.index(c)
        raise ArgumentError.new("Invalid base32 character: #{c}") if val.nil?
        bits = (bits << 5) | val.to_u64
        nbits += 5
        if nbits >= 8
          nbits -= 8
          result.write_byte(((bits >> nbits) & 0xff_u64).to_u8)
        end
      end

      result.to_slice.dup
    end

    # Spinner animation matching Python's braille spinner.
    SPINNER_SYMS = "\u28C4\u28C2\u28C1\u2841\u2848\u2850\u2860"

    def self.spin(msg : String, timeout : Float64?, &check : -> Bool) : Bool
      sym_idx = 0
      limit = timeout ? Time.utc.to_unix_f + timeout : nil

      print "#{msg}  "
      STDOUT.flush

      while (limit.nil? || Time.utc.to_unix_f < limit) && !check.call
        sleep 0.1.seconds
        print "\b\b#{SPINNER_SYMS[sym_idx]} "
        STDOUT.flush
        sym_idx = (sym_idx + 1) % SPINNER_SYMS.size
      end

      print "\r#{" " * (msg.size + 2)}  \r"

      if limit && Time.utc.to_unix_f > limit
        false
      else
        true
      end
    end

    # Handle the --import flag.
    def self.handle_import(args : Args) : Nil
      import_str = args.import_str.not_nil!
      identity_bytes = nil.as(Bytes?)

      begin
        identity_bytes = decode_import(import_str, args)
      rescue ex
        puts "Invalid identity data specified for import: #{ex.message}"
        exit(41)
      end

      identity = nil.as(Identity?)
      begin
        identity = Identity.from_bytes(identity_bytes.not_nil!)
      rescue ex
        puts "Could not create Reticulum identity from specified data: #{ex.message}"
        exit(42)
      end

      id = identity.not_nil!
      RNS.log("Identity imported")
      RNS.log("Public Key  : #{encode_key(id.get_public_key, args)}")

      if id.prv
        if args.print_private
          RNS.log("Private Key : #{encode_key(id.get_private_key, args)}")
        else
          RNS.log("Private Key : Hidden")
        end
      end

      if wp = args.write
        begin
          expanded = File.expand_path(wp)
          if !File.exists?(expanded) || args.force
            id.to_file(expanded)
            RNS.log("Wrote imported identity to #{wp}")
          else
            puts "File #{expanded} already exists, not overwriting"
            exit(43)
          end
        rescue ex
          puts "Error while writing imported identity to file: #{ex.message}"
          exit(44)
        end
      end

      exit(0)
    end

    # Handle the --generate flag.
    def self.handle_generate(args : Args, identity_file : String) : Nil
      identity = Identity.new
      if !args.force && File.exists?(identity_file)
        RNS.log("Identity file #{identity_file} already exists. Not overwriting.", RNS::LOG_ERROR)
        exit(3)
      else
        begin
          identity.to_file(identity_file)
          RNS.log("New identity #{identity} written to #{identity_file}")
          exit(0)
        rescue ex
          RNS.log("An error occurred while saving the generated Identity.", RNS::LOG_ERROR)
          RNS.log("The contained exception was: #{ex.message}", RNS::LOG_ERROR)
          exit(4)
        end
      end
    end

    # Resolve an identity from hex hash or file path.
    def self.resolve_identity(identity_str : String, args : Args) : Identity
      dest_len = (Reticulum::TRUNCATED_HASHLENGTH // 8) * 2

      if identity_str.size == dest_len && !File.exists?(identity_str)
        # Try recalling Identity from hex-encoded hash
        begin
          ident_hash = identity_str.hexbytes
          identity = Identity.recall(ident_hash) || Identity.recall(ident_hash, from_identity_hash: true)

          if identity.nil?
            if !args.request
              RNS.log("Could not recall Identity for #{RNS.prettyhexrep(ident_hash)}.", RNS::LOG_ERROR)
              RNS.log("You can query the network for unknown Identities with the -R option.", RNS::LOG_ERROR)
              exit(5)
            else
              Transport.request_path(ident_hash)
              found = spin("Requesting unknown Identity for #{RNS.prettyhexrep(ident_hash)}", args.timeout) do
                Identity.recall(ident_hash) != nil
              end

              if !found
                RNS.log("Identity request timed out", RNS::LOG_ERROR)
                exit(6)
              else
                identity = Identity.recall(ident_hash)
                RNS.log("Received Identity #{identity} for destination #{RNS.prettyhexrep(ident_hash)} from the network")
              end
            end
          else
            ident_str = identity.to_s
            hash_str = RNS.prettyhexrep(ident_hash)
            if ident_str == hash_str
              RNS.log("Recalled Identity #{ident_str}")
            else
              RNS.log("Recalled Identity #{ident_str} for destination #{hash_str}")
            end
          end

          identity.not_nil!
        rescue ex : ArgumentError
          RNS.log("Invalid hexadecimal hash provided", RNS::LOG_ERROR)
          exit(7)
        end
      else
        # Try loading Identity from file
        if !File.exists?(identity_str)
          RNS.log("Specified Identity file not found")
          exit(8)
        end

        begin
          identity = Identity.from_file(identity_str)
          if identity.nil?
            RNS.log("Could not decode Identity from specified file")
            exit(9)
          end
          RNS.log("Loaded Identity #{identity} from #{identity_str}")
          identity.not_nil!
        rescue ex
          RNS.log("Could not decode Identity from specified file")
          exit(9)
          raise ex # unreachable
        end
      end
    end

    # Handle the --hash flag.
    def self.handle_hash(args : Args, identity : Identity) : Nil
      aspects_str = args.hash_aspects.not_nil!
      begin
        aspects = aspects_str.split(".")
        if aspects.empty?
          RNS.log("Invalid destination aspects specified", RNS::LOG_ERROR)
          exit(32)
        end

        app_name = aspects[0]
        dest_aspects = aspects[1..]

        if identity.pub
          destination = Destination.new(identity, Destination::OUT, Destination::SINGLE, app_name, dest_aspects)
          RNS.log("The #{aspects_str} destination for this Identity is #{RNS.prettyhexrep(destination.hash)}")
          RNS.log("The full destination specifier is #{destination}")
          sleep 0.25.seconds
          exit(0)
        else
          raise Exception.new("No public key known")
        end
      rescue ex
        RNS.log("An error occurred while attempting to compute the hash.", RNS::LOG_ERROR)
        RNS.log("The contained exception was: #{ex.message}", RNS::LOG_ERROR)
        exit(32)
      end
    end

    # Handle the --announce flag.
    def self.handle_announce(args : Args, identity : Identity) : Nil
      announce_str = args.announce.not_nil!
      begin
        aspects = announce_str.split(".")
        if aspects.size <= 1
          RNS.log("Invalid destination aspects specified", RNS::LOG_ERROR)
          exit(32)
        end

        app_name = aspects[0]
        dest_aspects = aspects[1..]

        if identity.prv
          destination = Destination.new(identity, Destination::IN, Destination::SINGLE, app_name, dest_aspects)
          RNS.log("Created destination #{destination}")
          RNS.log("Announcing destination #{RNS.prettyhexrep(destination.hash)}")
          sleep 1.1.seconds
          destination.announce
          sleep 0.25.seconds
          exit(0)
        else
          destination = Destination.new(identity, Destination::OUT, Destination::SINGLE, app_name, dest_aspects)
          RNS.log("The #{announce_str} destination for this Identity is #{RNS.prettyhexrep(destination.hash)}")
          RNS.log("The full destination specifier is #{destination}")
          RNS.log("Cannot announce this destination, since the private key is not held")
          sleep 0.25.seconds
          exit(33)
        end
      rescue ex
        RNS.log("An error occurred while attempting to send the announce.", RNS::LOG_ERROR)
        RNS.log("The contained exception was: #{ex.message}", RNS::LOG_ERROR)
        exit(32)
      end
    end

    # Handle the --print-identity flag.
    def self.handle_print_identity(args : Args, identity : Identity) : Nil
      RNS.log("Public Key  : #{encode_key(identity.get_public_key, args)}")

      if identity.prv
        if args.print_private
          RNS.log("Private Key : #{encode_key(identity.get_private_key, args)}")
        else
          RNS.log("Private Key : Hidden")
        end
      end
      exit(0)
    end

    # Generate a text-based QR code from a string.
    def self.generate_qr_text(data : String) : String
      qr = QRCode.new(data, level: :m)
      qr.to_s(dark: '\u2588', light: ' ', quiet_zone_size: 2)
    end

    # Handle the --qr flag.
    def self.handle_qr(args : Args, identity : Identity) : Nil
      hash_hex = identity.hexhash
      RNS.log("Identity hash: #{hash_hex}")
      puts ""
      puts generate_qr_text(hash_hex)
      puts ""
      exit(0)
    end

    # Handle the --export flag.
    def self.handle_export(args : Args, identity : Identity) : Nil
      if identity.prv
        RNS.log("Exported Identity : #{encode_key(identity.get_private_key, args)}")
      else
        RNS.log("Identity doesn't hold a private key, cannot export")
        exit(50)
      end
      exit(0)
    end

    # Handle the --sign flag.
    def self.handle_sign(args : Args, identity : Identity) : Nil
      if identity.prv.nil?
        RNS.log("Specified Identity does not hold a private key. Cannot sign.", RNS::LOG_ERROR)
        exit(14)
      end

      read_path = args.read || args.sign
      if read_path.nil?
        if !args.stdout
          RNS.log("Signing requested, but no input data specified", RNS::LOG_ERROR)
        end
        exit(17)
      end

      write_path = args.write
      if write_path.nil? && !args.stdout && read_path
        write_path = "#{read_path}.#{SIG_EXT}"
      end

      if write_path.nil?
        if !args.stdout
          RNS.log("Signing requested, but no output specified", RNS::LOG_ERROR)
        end
        exit(18)
      end

      if !args.force && File.exists?(write_path.not_nil!)
        RNS.log("Output file #{write_path} already exists. Not overwriting.", RNS::LOG_ERROR)
        exit(15)
      end

      if !File.exists?(read_path.not_nil!)
        RNS.log("Input file #{read_path} not found", RNS::LOG_ERROR)
        exit(12)
      end

      if !args.stdout
        RNS.log("Signing #{read_path}")
      end

      begin
        data = File.read(read_path.not_nil!).to_slice
        signature = identity.sign(data)
        File.write(write_path.not_nil!, signature)

        if !args.stdout
          RNS.log("File #{read_path} signed with #{identity} to #{write_path}")
        end
        exit(0)
      rescue ex
        if !args.stdout
          RNS.log("An error occurred while signing data.", RNS::LOG_ERROR)
          RNS.log("The contained exception was: #{ex.message}", RNS::LOG_ERROR)
        end
        exit(19)
      end
    end

    # Handle the --validate flag.
    def self.handle_validate(args : Args, identity : Identity) : Nil
      sig_path = args.validate.not_nil!
      read_path = args.read

      if read_path.nil? && sig_path.downcase.ends_with?(".#{SIG_EXT}")
        read_path = sig_path.gsub(/\.#{SIG_EXT}$/i, "")
      end

      if !File.exists?(sig_path)
        RNS.log("Signature file #{sig_path} not found", RNS::LOG_ERROR)
        exit(10)
      end

      if read_path.nil? || !File.exists?(read_path.not_nil!)
        RNS.log("Input file #{read_path} not found", RNS::LOG_ERROR)
        exit(11)
      end

      begin
        sig_data = File.read(sig_path).to_slice
        file_data = File.read(read_path.not_nil!).to_slice

        validated = identity.validate(sig_data, file_data)

        if !validated
          if !args.stdout
            RNS.log("Signature #{sig_path} for file #{read_path} is invalid", RNS::LOG_ERROR)
          end
          exit(22)
        else
          if !args.stdout
            RNS.log("Signature #{sig_path} for file #{read_path} made by Identity #{identity} is valid")
          end
          exit(0)
        end
      rescue ex
        if !args.stdout
          RNS.log("An error occurred while validating signature.", RNS::LOG_ERROR)
          RNS.log("The contained exception was: #{ex.message}", RNS::LOG_ERROR)
        end
        exit(23)
      end
    end

    # Handle the --encrypt flag.
    def self.handle_encrypt(args : Args, identity : Identity) : Nil
      read_path = args.read || args.encrypt
      write_path = args.write

      if write_path.nil? && !args.stdout && read_path
        write_path = "#{read_path}.#{ENCRYPT_EXT}"
      end

      if read_path.nil? || !File.exists?(read_path.not_nil!)
        if !args.stdout
          RNS.log("Encryption requested, but no input data specified", RNS::LOG_ERROR)
        end
        exit(24)
      end

      if write_path.nil?
        if !args.stdout
          RNS.log("Encryption requested, but no output specified", RNS::LOG_ERROR)
        end
        exit(25)
      end

      if !args.force && File.exists?(write_path.not_nil!)
        RNS.log("Output file #{write_path} already exists. Not overwriting.", RNS::LOG_ERROR)
        exit(15)
      end

      if !args.stdout
        RNS.log("Encrypting #{read_path}")
      end

      begin
        File.open(read_path.not_nil!, "rb") do |input|
          File.open(write_path.not_nil!, "wb") do |output|
            buf = Bytes.new(CHUNK_SIZE)
            while (bytes_read = input.read(buf)) > 0
              chunk = buf[0, bytes_read]
              output.write(identity.encrypt(chunk))
            end
          end
        end

        if !args.stdout
          RNS.log("File #{read_path} encrypted for #{identity} to #{write_path}")
        end
        exit(0)
      rescue ex
        if !args.stdout
          RNS.log("An error occurred while encrypting data.", RNS::LOG_ERROR)
          RNS.log("The contained exception was: #{ex.message}", RNS::LOG_ERROR)
        end
        exit(26)
      end
    end

    # Handle the --decrypt flag.
    def self.handle_decrypt(args : Args, identity : Identity) : Nil
      if identity.prv.nil?
        RNS.log("Specified Identity does not hold a private key. Cannot decrypt.", RNS::LOG_ERROR)
        exit(27)
      end

      read_path = args.read || args.decrypt
      write_path = args.write

      if write_path.nil? && !args.stdout && read_path
        rp = read_path.not_nil!
        if rp.downcase.ends_with?(".#{ENCRYPT_EXT}")
          write_path = rp.gsub(/\.#{ENCRYPT_EXT}$/i, "")
        end
      end

      if read_path.nil? || !File.exists?(read_path.not_nil!)
        if !args.stdout
          RNS.log("Decryption requested, but no input data specified", RNS::LOG_ERROR)
        end
        exit(28)
      end

      if write_path.nil?
        if !args.stdout
          RNS.log("Decryption requested, but no output specified", RNS::LOG_ERROR)
        end
        exit(29)
      end

      if !args.force && File.exists?(write_path.not_nil!)
        RNS.log("Output file #{write_path} already exists. Not overwriting.", RNS::LOG_ERROR)
        exit(15)
      end

      if !args.stdout
        RNS.log("Decrypting #{read_path}...")
      end

      begin
        File.open(read_path.not_nil!, "rb") do |input|
          File.open(write_path.not_nil!, "wb") do |output|
            buf = Bytes.new(CHUNK_SIZE)
            while (bytes_read = input.read(buf)) > 0
              chunk = buf[0, bytes_read]
              plaintext = identity.decrypt(chunk)
              if plaintext.nil?
                if !args.stdout
                  RNS.log("Data could not be decrypted with the specified Identity")
                end
                exit(30)
              else
                output.write(plaintext)
              end
            end
          end
        end

        if !args.stdout
          RNS.log("File #{read_path} decrypted with #{identity} to #{write_path}")
        end
        exit(0)
      rescue ex
        if !args.stdout
          RNS.log("An error occurred while decrypting data.", RNS::LOG_ERROR)
          RNS.log("The contained exception was: #{ex.message}", RNS::LOG_ERROR)
        end
        exit(31)
      end
    end

    # Main entry point for the rnid binary.
    def self.main(argv : Array(String) = ARGV.to_a)
      args = parse_args(argv)

      if args.version
        puts version_string
        return
      end

      # Count mutually exclusive operations
      ops = 0
      ops += 1 if args.encrypt
      ops += 1 if args.decrypt
      ops += 1 if args.validate
      ops += 1 if args.sign
      if ops > 1
        RNS.log("This utility currently only supports one of the encrypt, decrypt, sign or verify operations per invocation", RNS::LOG_ERROR)
        exit(1)
      end

      # Set default read path from operation
      if args.read.nil?
        args.read = args.encrypt if args.encrypt
        args.read = args.decrypt if args.decrypt
        args.read = args.sign if args.sign
      end

      # Handle import (doesn't need Reticulum initialization)
      if args.import_str
        handle_import(args)
        return
      end

      if args.generate.nil? && args.identity.nil?
        puts "\nNo identity provided, cannot continue\n"
        puts usage_string
        puts ""
        exit(2)
      end

      # Start Reticulum
      target_loglevel = 4
      target_loglevel = target_loglevel + args.verbose - args.quiet

      reticulum = ReticulumInstance.new(configdir: args.config, loglevel: target_loglevel)
      RNS.compact_log_fmt = true
      if args.stdout
        RNS.loglevel = -1
      end

      # Handle generate
      if gen_file = args.generate
        handle_generate(args, gen_file)
        return
      end

      # Resolve the identity
      identity_str = args.identity.not_nil!
      identity = resolve_identity(identity_str, args)

      # Handle operations on the resolved identity
      if args.hash_aspects
        handle_hash(args, identity)
      elsif args.announce
        handle_announce(args, identity)
      elsif args.print_identity
        handle_print_identity(args, identity)
      elsif args.export
        handle_export(args, identity)
      elsif args.qr
        handle_qr(args, identity)
      elsif args.sign
        handle_sign(args, identity)
      elsif args.validate
        handle_validate(args, identity)
      elsif args.encrypt
        handle_encrypt(args, identity)
      elsif args.decrypt
        handle_decrypt(args, identity)
      end
    rescue ex : ArgumentError
      STDERR.puts "rnid: #{ex.message}"
      exit(1)
    rescue ex
      if ex.message.try(&.includes?("Interrupt"))
        puts ""
        exit(255)
      end
    end
  end
end
