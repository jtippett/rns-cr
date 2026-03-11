module RNS
  class TypeError < Exception; end

  class Destination
    # ─── Destination-like interface for use by Packet ─────────────────
    module DestinationInterface
      abstract def hash : Bytes
      abstract def type : UInt8
      abstract def encrypt(plaintext : Bytes) : Bytes
    end

    # Lightweight stub used for testing Packet independently
    class Stub
      include DestinationInterface

      getter hash : Bytes
      getter type : UInt8
      getter identity : RNS::Identity?
      getter link_id : Bytes?
      property latest_ratchet_id : Bytes?
      property mtu : Int32

      def initialize(*, @hash : Bytes, @type : UInt8, @identity : RNS::Identity? = nil,
                     @link_id : Bytes? = nil, @mtu : Int32 = RNS::Reticulum::MTU)
      end

      def encrypt(plaintext : Bytes) : Bytes
        id = @identity
        if id
          id.encrypt(plaintext)
        else
          plaintext
        end
      end
    end

    # ─── Callbacks container ──────────────────────────────────────────
    class DestinationCallbacks
      property link_established : Proc(Link, Nil)?
      property packet : Proc(Bytes, Packet, Nil)?
      property proof_requested : Proc(Packet, Bool)?

      def initialize
        @link_established = nil
        @packet = nil
        @proof_requested = nil
      end
    end

    # ─── Request handler record ───────────────────────────────────────
    struct RequestHandler
      getter path : String
      getter response_generator : Proc(String, Bytes?, Bytes, Bytes, Identity?, Float64, Bytes?)
      getter allow : UInt8
      getter allowed_list : Array(Bytes)?
      getter auto_compress : Bool

      def initialize(@path, @response_generator, @allow, @allowed_list = nil, @auto_compress = true)
      end
    end

    include DestinationInterface

    # ─── Type constants ───────────────────────────────────────────────
    SINGLE = 0x00_u8
    GROUP  = 0x01_u8
    PLAIN  = 0x02_u8
    LINK   = 0x03_u8
    TYPES  = [SINGLE, GROUP, PLAIN, LINK]

    # ─── Proof strategy constants ─────────────────────────────────────
    PROVE_NONE = 0x21_u8
    PROVE_APP  = 0x22_u8
    PROVE_ALL  = 0x23_u8
    PROOF_STRATEGIES = [PROVE_NONE, PROVE_APP, PROVE_ALL]

    # ─── Request policy constants ─────────────────────────────────────
    ALLOW_NONE = 0x00_u8
    ALLOW_ALL  = 0x01_u8
    ALLOW_LIST = 0x02_u8
    REQUEST_POLICIES = [ALLOW_NONE, ALLOW_ALL, ALLOW_LIST]

    # ─── Direction constants ──────────────────────────────────────────
    IN  = 0x11_u8
    OUT = 0x12_u8
    DIRECTIONS = [IN, OUT]

    # ─── Ratchet constants ────────────────────────────────────────────
    PR_TAG_WINDOW    = 30
    RATCHET_COUNT    = 512
    RATCHET_INTERVAL = 30 * 60 # 1800 seconds

    # ─── Instance properties ──────────────────────────────────────────
    property hash : Bytes
    getter type : UInt8
    getter direction : UInt8
    getter name : String
    getter name_hash : Bytes
    property hexhash : String
    getter identity : Identity?

    property accept_link_requests : Bool
    property callbacks : DestinationCallbacks
    property proof_strategy : UInt8
    property default_app_data : (Bytes | Proc(Bytes?) | Nil)
    property latest_ratchet_id : Bytes?
    property mtu : Int32

    # Ratchet properties
    property ratchets : Array(Bytes)?
    property ratchets_path : String?
    property ratchet_interval : Int32
    property retained_ratchets : Int32
    property latest_ratchet_time : Float64?

    # GROUP key properties
    property prv_bytes : Bytes?
    property prv : Cryptography::Token?

    @enforce_ratchets_enabled : Bool
    @path_responses : Hash(Bytes, {Float64, Bytes})
    @request_handlers : Hash(String, RequestHandler)

    # ─── Constructor ──────────────────────────────────────────────────
    def initialize(identity : Identity?, @direction : UInt8, @type : UInt8,
                   app_name : String, aspects : Array(String) = [] of String,
                   register : Bool = true)
      # Validation
      raise ArgumentError.new("Dots can't be used in app names") if app_name.includes?('.')
      raise ArgumentError.new("Unknown destination type") unless TYPES.includes?(@type)
      raise ArgumentError.new("Unknown destination direction") unless DIRECTIONS.includes?(@direction)

      aspects.each do |aspect|
        raise ArgumentError.new("Dots can't be used in aspects") if aspect.includes?('.')
      end

      # Initialize properties
      @accept_link_requests = true
      @callbacks = DestinationCallbacks.new
      @request_handlers = Hash(String, RequestHandler).new
      @proof_strategy = PROVE_NONE
      @ratchets = nil
      @ratchets_path = nil
      @ratchet_interval = RATCHET_INTERVAL
      @retained_ratchets = RATCHET_COUNT
      @latest_ratchet_time = nil
      @latest_ratchet_id = nil
      @enforce_ratchets_enabled = false
      @mtu = 0
      @path_responses = Hash(Bytes, {Float64, Bytes}).new
      @prv_bytes = nil
      @prv = nil
      @default_app_data = nil

      # Handle identity creation for IN destinations
      actual_aspects = aspects.dup
      actual_identity = identity

      if actual_identity.nil? && @direction == IN && @type != PLAIN
        actual_identity = Identity.new
        actual_aspects << actual_identity.hexhash.not_nil!
      end

      if actual_identity.nil? && @direction == OUT && @type != PLAIN
        raise ArgumentError.new("Can't create outbound SINGLE destination without an identity")
      end

      if !actual_identity.nil? && @type == PLAIN
        raise TypeError.new("Selected destination type PLAIN cannot hold an identity")
      end

      @identity = actual_identity
      @name = Destination.expand_name(actual_identity, app_name, actual_aspects)
      @hash = Destination.hash(actual_identity, app_name, actual_aspects)
      @name_hash = Identity.full_hash(Destination.expand_name(nil, app_name, actual_aspects).to_slice)[0, Identity::NAME_HASH_LENGTH // 8]
      @hexhash = @hash.hexstring

      Transport.register_destination(self) if register
    end

    # ─── Static methods ───────────────────────────────────────────────

    def self.expand_name(identity : Identity?, app_name : String, aspects : Array(String)) : String
      raise ArgumentError.new("Dots can't be used in app names") if app_name.includes?('.')

      name = app_name
      aspects.each do |aspect|
        raise ArgumentError.new("Dots can't be used in aspects") if aspect.includes?('.')
        name += "." + aspect
      end

      if identity
        hexhash = identity.hexhash
        name += "." + hexhash.not_nil! if hexhash
      end

      name
    end

    def self.expand_name(identity : Identity?, app_name : String, *aspects : String) : String
      expand_name(identity, app_name, aspects.to_a)
    end

    def self.hash(identity : Identity?, app_name : String, aspects : Array(String)) : Bytes
      name_hash = Identity.full_hash(
        expand_name(nil, app_name, aspects).to_slice
      )[0, Identity::NAME_HASH_LENGTH // 8]

      addr_hash_material = IO::Memory.new
      addr_hash_material.write(name_hash)

      if identity
        id_hash = identity.hash
        addr_hash_material.write(id_hash.not_nil!) if id_hash
      end

      Identity.full_hash(addr_hash_material.to_slice)[0, Reticulum::TRUNCATED_HASHLENGTH // 8]
    end

    def self.hash(identity_hash : Bytes, app_name : String, aspects : Array(String)) : Bytes
      name_hash = Identity.full_hash(
        expand_name(nil, app_name, aspects).to_slice
      )[0, Identity::NAME_HASH_LENGTH // 8]

      if identity_hash.size != Reticulum::TRUNCATED_HASHLENGTH // 8
        raise TypeError.new("Invalid material supplied for destination hash calculation")
      end

      addr_hash_material = IO::Memory.new
      addr_hash_material.write(name_hash)
      addr_hash_material.write(identity_hash)

      Identity.full_hash(addr_hash_material.to_slice)[0, Reticulum::TRUNCATED_HASHLENGTH // 8]
    end

    def self.hash(identity : Identity?, app_name : String, *aspects : String) : Bytes
      hash(identity, app_name, aspects.to_a)
    end

    def self.app_and_aspects_from_name(full_name : String) : {String, Array(String)}
      components = full_name.split(".")
      {components[0], components[1..]}
    end

    def self.hash_from_name_and_identity(full_name : String, identity : Identity?) : Bytes
      app_name, aspects = app_and_aspects_from_name(full_name)
      hash(identity, app_name, aspects)
    end

    # ─── String representation ────────────────────────────────────────

    def to_s(io : IO) : Nil
      io << "<" << @name << ":" << @hexhash << ">"
    end

    # ─── Ratchet methods ──────────────────────────────────────────────

    private def clean_ratchets
      r = @ratchets
      if r && r.size > @retained_ratchets
        @ratchets = r[0, RATCHET_COUNT]
      end
    end

    private def persist_ratchets
      rpath = @ratchets_path
      return if rpath.nil?

      begin
        r = @ratchets
        return if r.nil?

        temp_write_path = rpath + ".tmp"

        packed_ratchets = IO::Memory.new
        packer = MessagePack::Packer.new(packed_ratchets)
        packer.write_array_start(r.size.to_u32)
        r.each { |ratchet| packer.write(ratchet) }
        packed_bytes = packed_ratchets.to_slice

        signature = sign(packed_bytes)
        return if signature.nil?

        persisted_io = IO::Memory.new
        persisted_packer = MessagePack::Packer.new(persisted_io)
        persisted_packer.write_hash_start(2_u32)
        persisted_packer.write("signature")
        persisted_packer.write(signature)
        persisted_packer.write("ratchets")
        persisted_packer.write(packed_bytes)

        File.write(temp_write_path, persisted_io.to_slice)
        File.delete(rpath) if File.exists?(rpath)
        File.rename(temp_write_path, rpath)
      rescue ex
        @ratchets = nil
        @ratchets_path = nil
        raise IO::Error.new("Could not write ratchet file contents for #{self}. The contained exception was: #{ex}")
      end
    end

    def rotate_ratchets : Bool
      r = @ratchets
      if r
        now = Time.utc.to_unix_f
        lt = @latest_ratchet_time
        if lt.nil? || now > lt + @ratchet_interval
          RNS.log("Rotating ratchets for #{self}", RNS::LOG_DEBUG)
          new_ratchet = Identity.generate_ratchet
          r.insert(0, new_ratchet)
          @latest_ratchet_time = now
          clean_ratchets
          persist_ratchets
        end
        true
      else
        raise IO::Error.new("Cannot rotate ratchet on #{self}, ratchets are not enabled")
      end
    end

    private def reload_ratchets(ratchets_path : String)
      if File.exists?(ratchets_path)
        begin
          data = File.read(ratchets_path).to_slice
          unpacker = MessagePack::IOUnpacker.new(IO::Memory.new(data))

          # Read top-level map
          top_token = unpacker.read_token
          raise IO::Error.new("Invalid ratchet file format") unless top_token.is_a?(MessagePack::Token::HashT)

          signature : Bytes? = nil
          packed_ratchets : Bytes? = nil

          top_token.size.times do
            key_token = unpacker.read_token
            key = key_token.is_a?(MessagePack::Token::StringT) ? key_token.value : ""
            val_token = unpacker.read_token

            case key
            when "signature"
              signature = val_token.as(MessagePack::Token::BytesT).value if val_token.is_a?(MessagePack::Token::BytesT)
            when "ratchets"
              packed_ratchets = val_token.as(MessagePack::Token::BytesT).value if val_token.is_a?(MessagePack::Token::BytesT)
            end
          end

          if signature && packed_ratchets
            id = @identity
            if id && id.validate(signature, packed_ratchets)
              # Unpack the ratchets array
              ratchet_unpacker = MessagePack::IOUnpacker.new(IO::Memory.new(packed_ratchets))
              arr_token = ratchet_unpacker.read_token
              if arr_token.is_a?(MessagePack::Token::ArrayT)
                loaded_ratchets = [] of Bytes
                arr_token.size.times do
                  item = ratchet_unpacker.read_token
                  if item.is_a?(MessagePack::Token::BytesT)
                    loaded_ratchets << item.value
                  end
                end
                @ratchets = loaded_ratchets
                @ratchets_path = ratchets_path
              else
                raise KeyError.new("Invalid ratchet data format")
              end
            else
              raise KeyError.new("Invalid ratchet file signature")
            end
          else
            raise KeyError.new("Missing signature or ratchets in ratchet file")
          end
        rescue ex
          @ratchets = nil
          @ratchets_path = nil
          RNS.log("The ratchet file located at #{ratchets_path} could not be loaded.", RNS::LOG_CRITICAL)
          raise IO::Error.new("Could not read ratchet file contents for #{self}. The contained exception was: #{ex}")
        end
      else
        RNS.log("No existing ratchet data found, initialising new ratchet file for #{self}", RNS::LOG_DEBUG)
        @ratchets = [] of Bytes
        @ratchets_path = ratchets_path
        persist_ratchets
      end
    end

    def enable_ratchets(ratchets_path : String) : Bool
      @latest_ratchet_time = 0.0
      reload_ratchets(ratchets_path)
      RNS.log("Ratchets enabled on #{self}", RNS::LOG_DEBUG)
      true
    end

    def enforce_ratchets : Bool
      if @ratchets
        @enforce_ratchets_enabled = true
        RNS.log("Ratchets enforced on #{self}", RNS::LOG_DEBUG)
        true
      else
        false
      end
    end

    def set_retained_ratchets(retained_ratchets : Int32) : Bool
      if retained_ratchets > 0
        @retained_ratchets = retained_ratchets
        clean_ratchets
        true
      else
        false
      end
    end

    def set_ratchet_interval(interval : Int32) : Bool
      if interval > 0
        @ratchet_interval = interval
        true
      else
        false
      end
    end

    # ─── Announce ─────────────────────────────────────────────────────

    def announce(app_data : Bytes? = nil, path_response : Bool = false,
                 attached_interface = nil, tag : Bytes? = nil, send : Bool = true) : Packet?
      unless @type == SINGLE
        raise TypeError.new("Only SINGLE destination types can be announced")
      end

      unless @direction == IN
        raise TypeError.new("Only IN destination types can be announced")
      end

      ratchet = Bytes.empty
      now = Time.utc.to_unix_f

      # Clean stale path responses
      stale_tags = [] of Bytes
      @path_responses.each do |entry_tag, entry|
        if now > entry[0] + PR_TAG_WINDOW
          stale_tags << entry_tag
        end
      end
      stale_tags.each { |t| @path_responses.delete(t) }

      announce_data : Bytes

      if path_response && tag && @path_responses.has_key?(tag)
        RNS.log("Using cached announce data for answering path request with tag #{RNS.prettyhexrep(tag)}", RNS::LOG_EXTREME)
        announce_data = @path_responses[tag][1]
      else
        id = @identity.not_nil!

        # 5 bytes random + 5 bytes timestamp = 10 bytes
        random_part = Identity.get_random_hash[0, 5]
        time_val = Time.utc.to_unix
        time_bytes = Bytes.new(5)
        time_bytes[0] = ((time_val >> 32) & 0xFF).to_u8
        time_bytes[1] = ((time_val >> 24) & 0xFF).to_u8
        time_bytes[2] = ((time_val >> 16) & 0xFF).to_u8
        time_bytes[3] = ((time_val >> 8) & 0xFF).to_u8
        time_bytes[4] = (time_val & 0xFF).to_u8
        random_hash = Bytes.new(10)
        random_part.copy_to(random_hash)
        time_bytes.copy_to(random_hash + 5)

        if @ratchets
          rotate_ratchets
          r = @ratchets.not_nil!
          if r.size > 0
            ratchet = Identity.ratchet_public_bytes(r[0])
            Identity.remember_ratchet(@hash, ratchet)
          end
        end

        # Resolve default app_data if none provided
        if app_data.nil? && @default_app_data
          case dad = @default_app_data
          when Bytes
            app_data = dad
          when Proc(Bytes?)
            returned = dad.call
            app_data = returned if returned.is_a?(Bytes)
          end
        end

        # Build signed data: hash + public_key + name_hash + random_hash + ratchet [+ app_data]
        signed_io = IO::Memory.new
        signed_io.write(@hash)
        signed_io.write(id.get_public_key)
        signed_io.write(@name_hash)
        signed_io.write(random_hash)
        signed_io.write(ratchet) if ratchet.size > 0
        signed_io.write(app_data) if app_data

        signature = id.sign(signed_io.to_slice)

        # Build announce data: public_key + name_hash + random_hash + ratchet + signature [+ app_data]
        announce_io = IO::Memory.new
        announce_io.write(id.get_public_key)
        announce_io.write(@name_hash)
        announce_io.write(random_hash)
        announce_io.write(ratchet) if ratchet.size > 0
        announce_io.write(signature)
        announce_io.write(app_data) if app_data

        announce_data = announce_io.to_slice

        if tag
          @path_responses[tag] = {now, announce_data}
        end
      end

      announce_context = path_response ? Packet::PATH_RESPONSE : Packet::NONE

      context_flag = ratchet.size > 0 ? Packet::FLAG_SET : Packet::FLAG_UNSET

      announce_packet = Packet.new(
        self,
        announce_data,
        packet_type: Packet::ANNOUNCE,
        context: announce_context,
        context_flag: context_flag,
      )

      if send
        announce_packet.send
        nil
      else
        announce_packet
      end
    end

    # ─── Link management ──────────────────────────────────────────────

    def accepts_links : Bool
      @accept_link_requests
    end

    def accepts_links=(accepts : Bool)
      @accept_link_requests = accepts
    end

    def set_link_established_callback(callback : Proc(Link, Nil))
      @callbacks.link_established = callback
    end

    def set_packet_callback(callback : Proc(Bytes, Packet, Nil))
      @callbacks.packet = callback
    end

    def set_proof_requested_callback(callback : Proc(Packet, Bool))
      @callbacks.proof_requested = callback
    end

    def set_proof_strategy(proof_strategy : UInt8)
      unless PROOF_STRATEGIES.includes?(proof_strategy)
        raise TypeError.new("Unsupported proof strategy")
      end
      @proof_strategy = proof_strategy
    end

    # ─── Request handlers ─────────────────────────────────────────────

    def register_request_handler(path : String,
                                  response_generator : Proc(String, Bytes?, Bytes, Bytes, Identity?, Float64, Bytes?),
                                  allow : UInt8 = ALLOW_NONE,
                                  allowed_list : Array(Bytes)? = nil,
                                  auto_compress : Bool = true)
      raise ArgumentError.new("Invalid path specified") if path.empty?
      raise ArgumentError.new("Invalid request policy") unless REQUEST_POLICIES.includes?(allow)

      path_hash = Identity.truncated_hash(path.to_slice)
      handler = RequestHandler.new(path, response_generator, allow, allowed_list, auto_compress)
      @request_handlers[path_hash.hexstring] = handler
    end

    def deregister_request_handler(path : String) : Bool
      path_hash = Identity.truncated_hash(path.to_slice)
      key = path_hash.hexstring
      if @request_handlers.has_key?(key)
        @request_handlers.delete(key)
        true
      else
        false
      end
    end

    def request_handlers
      @request_handlers
    end

    # ─── Receive ──────────────────────────────────────────────────────

    def receive(packet : Packet) : Bool
      if packet.packet_type == Packet::LINKREQUEST
        incoming_link_request(packet.data, packet)
        true
      else
        plaintext = decrypt(packet.data)
        @latest_ratchet_id = nil # TODO: set properly when Identity tracks ratchet_id
        if plaintext.nil?
          false
        else
          if packet.packet_type == Packet::DATA
            cb = @callbacks.packet
            if cb
              begin
                cb.call(plaintext, packet)
              rescue ex
                RNS.log("Error while executing receive callback from #{self}. The contained exception was: #{ex}", RNS::LOG_ERROR)
              end
            end
          end
          true
        end
      end
    end

    private def incoming_link_request(data : Bytes, packet : Packet)
      if @accept_link_requests
        # TODO: Link.validate_request(self, data, packet) when Link is implemented
      end
    end

    # ─── GROUP key management ─────────────────────────────────────────

    def create_keys
      if @type == PLAIN
        raise TypeError.new("A plain destination does not hold any keys")
      end

      if @type == SINGLE
        raise TypeError.new("A single destination holds keys through an Identity instance")
      end

      if @type == GROUP
        @prv_bytes = Cryptography::Token.generate_key
        @prv = Cryptography::Token.new(@prv_bytes.not_nil!)
      end
    end

    def get_private_key : Bytes
      if @type == PLAIN
        raise TypeError.new("A plain destination does not hold any keys")
      elsif @type == SINGLE
        raise TypeError.new("A single destination holds keys through an Identity instance")
      else
        @prv_bytes.not_nil!
      end
    end

    def load_private_key(key : Bytes)
      if @type == PLAIN
        raise TypeError.new("A plain destination does not hold any keys")
      end

      if @type == SINGLE
        raise TypeError.new("A single destination holds keys through an Identity instance")
      end

      if @type == GROUP
        @prv_bytes = key
        @prv = Cryptography::Token.new(key)
      end
    end

    def load_public_key(key : Bytes)
      if @type != SINGLE
        raise TypeError.new("Only the \"single\" destination type can hold a public key")
      else
        raise TypeError.new("A single destination holds keys through an Identity instance")
      end
    end

    # ─── Encryption / Decryption ──────────────────────────────────────

    def encrypt(plaintext : Bytes) : Bytes
      if @type == PLAIN
        return plaintext
      end

      if @type == SINGLE
        id = @identity
        if id
          selected_ratchet = Identity.get_ratchet(@hash)
          if selected_ratchet
            @latest_ratchet_id = Identity.get_ratchet_id(selected_ratchet)
          end
          return id.encrypt(plaintext, ratchet: selected_ratchet)
        end
      end

      if @type == GROUP
        p = @prv
        if p
          begin
            return p.encrypt(plaintext)
          rescue ex
            RNS.log("The GROUP destination could not encrypt data", RNS::LOG_ERROR)
            RNS.log("The contained exception was: #{ex}", RNS::LOG_ERROR)
            raise ex
          end
        else
          raise ArgumentError.new("No private key held by GROUP destination. Did you create or load one?")
        end
      end

      plaintext
    end

    def decrypt(ciphertext : Bytes) : Bytes?
      if @type == PLAIN
        return ciphertext
      end

      if @type == SINGLE
        id = @identity
        if id
          r = @ratchets
          if r && !r.empty?
            decrypted : Bytes? = nil
            begin
              decrypted = id.decrypt(ciphertext, ratchets: r, enforce_ratchets: @enforce_ratchets_enabled)
            rescue
              decrypted = nil
            end

            if decrypted.nil?
              begin
                rpath = @ratchets_path
                if rpath
                  RNS.log("Decryption with ratchets failed on #{self}, reloading ratchets from storage and retrying", RNS::LOG_ERROR)
                  reload_ratchets(rpath)
                  r2 = @ratchets
                  decrypted = id.decrypt(ciphertext, ratchets: r2, enforce_ratchets: @enforce_ratchets_enabled)
                end
              rescue ex
                RNS.log("Decryption still failing after ratchet reload. The contained exception was: #{ex}", RNS::LOG_ERROR)
                raise ex
              end

              if decrypted
                RNS.log("Decryption succeeded after ratchet reload", RNS::LOG_NOTICE)
              end
            end

            return decrypted
          else
            return id.decrypt(ciphertext, ratchets: nil, enforce_ratchets: @enforce_ratchets_enabled)
          end
        end
      end

      if @type == GROUP
        p = @prv
        if p
          begin
            return p.decrypt(ciphertext)
          rescue ex
            RNS.log("The GROUP destination could not decrypt data", RNS::LOG_ERROR)
            RNS.log("The contained exception was: #{ex}", RNS::LOG_ERROR)
            return nil
          end
        else
          raise ArgumentError.new("No private key held by GROUP destination. Did you create or load one?")
        end
      end

      nil
    end

    # ─── Signing ──────────────────────────────────────────────────────

    def sign(message : Bytes) : Bytes?
      if @type == SINGLE
        id = @identity
        if id
          return id.sign(message)
        end
      end
      nil
    end

    # ─── Default app data ────────────────────────────────────────────

    def set_default_app_data(app_data : Bytes | Proc(Bytes?) | Nil = nil)
      @default_app_data = app_data
    end

    def clear_default_app_data
      set_default_app_data(nil)
    end
  end
end
