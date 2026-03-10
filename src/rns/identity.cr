require "file_utils"
require "msgpack"

module RNS
  class Identity
    CURVE = "Curve25519"

    KEYSIZE     = 256 * 2  # bits — 256 encryption + 256 signing
    RATCHETSIZE = 256      # bits

    RATCHET_EXPIRY = 60 * 60 * 24 * 30 # 30 days in seconds

    TOKEN_OVERHEAD            = Cryptography::Token::TOKEN_OVERHEAD
    AES128_BLOCKSIZE          = 16       # bytes
    HASHLENGTH                = 256      # bits
    SIGLENGTH                 = KEYSIZE  # bits

    NAME_HASH_LENGTH          = 80       # bits
    TRUNCATED_HASHLENGTH      = 128      # bits

    DERIVED_KEY_LENGTH        = 512 // 8 # 64 bytes
    DERIVED_KEY_LENGTH_LEGACY = 256 // 8 # 32 bytes

    # ─── Class-level state ─────────────────────────────────────────────
    @@known_destinations = Hash(Bytes, Array(Bytes | Float64 | Nil)).new
    @@known_ratchets = Hash(Bytes, Bytes).new
    @@saving_known_destinations = false
    @@ratchet_persist_lock = Mutex.new

    def self.known_destinations
      @@known_destinations
    end

    def self.known_ratchets
      @@known_ratchets
    end

    # ─── Instance properties ───────────────────────────────────────────
    property prv : Cryptography::X25519PrivateKey?
    property prv_bytes : Bytes?
    property sig_prv : Cryptography::Ed25519PrivateKey?
    property sig_prv_bytes : Bytes?

    property pub : Cryptography::X25519PublicKey?
    property pub_bytes : Bytes?
    property sig_pub : Cryptography::Ed25519PublicKey?
    property sig_pub_bytes : Bytes?

    property hash : Bytes?
    property hexhash : String?
    property app_data : Bytes?

    def initialize(create_keys : Bool = true)
      @prv = nil
      @prv_bytes = nil
      @sig_prv = nil
      @sig_prv_bytes = nil

      @pub = nil
      @pub_bytes = nil
      @sig_pub = nil
      @sig_pub_bytes = nil

      @hash = nil
      @hexhash = nil
      @app_data = nil

      self.create_keys if create_keys
    end

    def create_keys
      @prv = Cryptography::X25519PrivateKey.generate
      @prv_bytes = @prv.not_nil!.private_bytes

      @sig_prv = Cryptography::Ed25519PrivateKey.generate
      @sig_prv_bytes = @sig_prv.not_nil!.private_bytes

      @pub = @prv.not_nil!.public_key
      @pub_bytes = @pub.not_nil!.public_bytes

      @sig_pub = @sig_prv.not_nil!.public_key
      @sig_pub_bytes = @sig_pub.not_nil!.public_bytes

      update_hashes

      RNS.log("Identity keys created for #{RNS.prettyhexrep(@hash.not_nil!)}", RNS::LOG_VERBOSE)
    end

    # ─── Key accessors ─────────────────────────────────────────────────

    def get_private_key : Bytes
      prv_b = @prv_bytes.not_nil!
      sig_b = @sig_prv_bytes.not_nil!
      result = Bytes.new(prv_b.size + sig_b.size)
      prv_b.copy_to(result)
      sig_b.copy_to(result + prv_b.size)
      result
    end

    def get_public_key : Bytes
      pub_b = @pub_bytes.not_nil!
      sig_b = @sig_pub_bytes.not_nil!
      result = Bytes.new(pub_b.size + sig_b.size)
      pub_b.copy_to(result)
      sig_b.copy_to(result + pub_b.size)
      result
    end

    def load_private_key(prv_bytes : Bytes) : Bool
      half = KEYSIZE // 8 // 2

      @prv_bytes = prv_bytes[0, half]
      @prv = Cryptography::X25519PrivateKey.from_private_bytes(@prv_bytes.not_nil!)

      @sig_prv_bytes = prv_bytes[half, half]
      @sig_prv = Cryptography::Ed25519PrivateKey.from_private_bytes(@sig_prv_bytes.not_nil!)

      @pub = @prv.not_nil!.public_key
      @pub_bytes = @pub.not_nil!.public_bytes

      @sig_pub = @sig_prv.not_nil!.public_key
      @sig_pub_bytes = @sig_pub.not_nil!.public_bytes

      update_hashes
      true
    rescue ex
      RNS.log("Failed to load identity key", RNS::LOG_ERROR)
      RNS.log("The contained exception was: #{ex}", RNS::LOG_ERROR)
      false
    end

    def load_public_key(pub_bytes : Bytes)
      half = KEYSIZE // 8 // 2

      @pub_bytes = pub_bytes[0, half]
      @sig_pub_bytes = pub_bytes[half, half]

      @pub = Cryptography::X25519PublicKey.from_public_bytes(@pub_bytes.not_nil!)
      @sig_pub = Cryptography::Ed25519PublicKey.from_public_bytes(@sig_pub_bytes.not_nil!)

      update_hashes
    rescue ex
      RNS.log("Error while loading public key, the contained exception was: #{ex}", RNS::LOG_ERROR)
    end

    def update_hashes
      @hash = Identity.truncated_hash(get_public_key)
      @hexhash = @hash.not_nil!.hexstring
    end

    def load(path : String) : Bool
      prv_bytes = File.read(path).to_slice
      load_private_key(prv_bytes)
    rescue ex
      RNS.log("Error while loading identity from #{path}", RNS::LOG_ERROR)
      RNS.log("The contained exception was: #{ex}", RNS::LOG_ERROR)
      false
    end

    def get_salt : Bytes?
      @hash
    end

    def get_context : Bytes?
      nil
    end

    # ─── Encryption ────────────────────────────────────────────────────

    def encrypt(plaintext : Bytes, ratchet : Bytes? = nil) : Bytes
      pub_key = @pub
      raise KeyError.new("Encryption failed because identity does not hold a public key") if pub_key.nil?

      ephemeral_key = Cryptography::X25519PrivateKey.generate
      ephemeral_pub_bytes = ephemeral_key.public_key.public_bytes

      target_public_key = if ratchet
                            Cryptography::X25519PublicKey.from_public_bytes(ratchet)
                          else
                            pub_key
                          end

      shared_key = ephemeral_key.exchange(target_public_key)

      derived_key = Cryptography.hkdf(
        length: DERIVED_KEY_LENGTH,
        derive_from: shared_key,
        salt: get_salt,
        context: get_context,
      )

      token = Cryptography::Token.new(derived_key)
      ciphertext = token.encrypt(plaintext)

      result = Bytes.new(ephemeral_pub_bytes.size + ciphertext.size)
      ephemeral_pub_bytes.copy_to(result)
      ciphertext.copy_to(result + ephemeral_pub_bytes.size)
      result
    end

    private def decrypt_with_shared_key(shared_key : Bytes, ciphertext : Bytes) : Bytes
      derived_key = Cryptography.hkdf(
        length: DERIVED_KEY_LENGTH,
        derive_from: shared_key,
        salt: get_salt,
        context: get_context,
      )

      token = Cryptography::Token.new(derived_key)
      token.decrypt(ciphertext)
    end

    def decrypt(ciphertext_token : Bytes, ratchets : Array(Bytes)? = nil, enforce_ratchets : Bool = false) : Bytes?
      prv_key = @prv
      raise KeyError.new("Decryption failed because identity does not hold a private key") if prv_key.nil?

      half = KEYSIZE // 8 // 2
      if ciphertext_token.size <= half
        RNS.log("Decryption failed because the token size was invalid.", RNS::LOG_DEBUG)
        return nil
      end

      plaintext : Bytes? = nil

      begin
        peer_pub_bytes = ciphertext_token[0, half]
        peer_pub = Cryptography::X25519PublicKey.from_public_bytes(peer_pub_bytes)
        ciphertext = ciphertext_token[half, ciphertext_token.size - half]

        if ratchets
          ratchets.each do |ratchet|
            begin
              ratchet_prv = Cryptography::X25519PrivateKey.from_private_bytes(ratchet)
              shared_key = ratchet_prv.exchange(peer_pub)
              plaintext = decrypt_with_shared_key(shared_key, ciphertext)
              break
            rescue
              # Try next ratchet
            end
          end
        end

        if enforce_ratchets && plaintext.nil?
          RNS.log("Decryption with ratchet enforcement by #{RNS.prettyhexrep(@hash.not_nil!)} failed. Dropping packet.", RNS::LOG_DEBUG)
          return nil
        end

        if plaintext.nil?
          shared_key = prv_key.exchange(peer_pub)
          plaintext = decrypt_with_shared_key(shared_key, ciphertext)
        end
      rescue ex
        RNS.log("Decryption by #{RNS.prettyhexrep(@hash.not_nil!)} failed: #{ex}", RNS::LOG_DEBUG)
      end

      plaintext
    end

    # ─── Signing ───────────────────────────────────────────────────────

    def sign(message : Bytes) : Bytes
      sig_prv_key = @sig_prv
      raise KeyError.new("Signing failed because identity does not hold a private key") if sig_prv_key.nil?

      begin
        sig_prv_key.sign(message)
      rescue ex
        RNS.log("The identity #{self} could not sign the requested message. The contained exception was: #{ex}", RNS::LOG_ERROR)
        raise ex
      end
    end

    def validate(signature : Bytes, message : Bytes) : Bool
      pub_key = @pub
      raise KeyError.new("Signature validation failed because identity does not hold a public key") if pub_key.nil?

      begin
        @sig_pub.not_nil!.verify(signature, message)
        true
      rescue
        false
      end
    end

    # ─── File I/O ──────────────────────────────────────────────────────

    def to_file(path : String) : Bool
      File.write(path, get_private_key)
      true
    rescue ex
      RNS.log("Error while saving identity to #{path}", RNS::LOG_ERROR)
      RNS.log("The contained exception was: #{ex}", RNS::LOG_ERROR)
      false
    end

    def to_s(io : IO) : Nil
      h = @hash
      if h
        io << RNS.prettyhexrep(h)
      else
        io << "<Identity: no hash>"
      end
    end

    # ─── Static Methods ────────────────────────────────────────────────

    def self.remember(packet_hash : Bytes, destination_hash : Bytes, public_key : Bytes, app_data : Bytes? = nil)
      if public_key.size != KEYSIZE // 8
        raise ArgumentError.new("Can't remember #{RNS.prettyhexrep(destination_hash)}, the public key size of #{public_key.size} is not valid.")
      end

      entry = Array(Bytes | Float64 | Nil).new(4)
      entry << Time.utc.to_unix_f
      entry << packet_hash
      entry << public_key
      entry << app_data
      @@known_destinations[destination_hash] = entry
    end

    def self.recall(target_hash : Bytes, from_identity_hash : Bool = false) : Identity?
      if from_identity_hash
        @@known_destinations.each do |destination_hash, identity_data|
          pub_key = identity_data[2].as(Bytes)
          if target_hash == Identity.truncated_hash(pub_key)
            identity = Identity.new(create_keys: false)
            identity.load_public_key(pub_key)
            identity.app_data = identity_data[3].as?(Bytes)
            return identity
          end
        end
        return nil
      else
        if @@known_destinations.has_key?(target_hash)
          identity_data = @@known_destinations[target_hash]
          identity = Identity.new(create_keys: false)
          identity.load_public_key(identity_data[2].as(Bytes))
          identity.app_data = identity_data[3].as?(Bytes)
          return identity
        end
        return nil
      end
    end

    def self.recall_app_data(destination_hash : Bytes) : Bytes?
      if @@known_destinations.has_key?(destination_hash)
        @@known_destinations[destination_hash][3].as?(Bytes)
      else
        nil
      end
    end

    def self.save_known_destinations(storage_path : String? = nil)
      return if storage_path.nil?

      begin
        filepath = File.join(storage_path, "known_destinations")
        save_start = Time.utc.to_unix_f

        # Merge with existing on-disk data
        if File.exists?(filepath)
          begin
            storage_known = Hash(Bytes, Array(Bytes | Float64 | Nil)).new
            data = File.read(filepath).to_slice
            unpacked = MessagePack::IOUnpacker.new(IO::Memory.new(data))
            # Simple merge: load existing, add any missing
            # For now, we save our in-memory state directly
          rescue
            # Ignore errors reading existing file
          end
        end

        RNS.log("Saving #{@@known_destinations.size} known destinations to storage...", RNS::LOG_DEBUG)

        io = IO::Memory.new
        packer = MessagePack::Packer.new(io)

        # Pack as a map
        packer.write_hash_start(@@known_destinations.size.to_u32)
        @@known_destinations.each do |dest_hash, entry|
          packer.write(dest_hash)
          packer.write_array_start(entry.size.to_u32)
          entry.each do |val|
            case val
            when Float64
              packer.write(val)
            when Bytes
              packer.write(val)
            when Nil
              packer.write(nil)
            end
          end
        end

        File.write(filepath, io.to_slice)

        save_time = Time.utc.to_unix_f - save_start
        time_str = save_time < 1 ? "#{(save_time * 1000).round(2)}ms" : "#{save_time.round(2)}s"
        RNS.log("Saved known destinations to storage in #{time_str}", RNS::LOG_DEBUG)
      rescue ex
        RNS.log("Error while saving known destinations to disk, the contained exception was: #{ex}", RNS::LOG_ERROR)
      end

      @@saving_known_destinations = false
    end

    def self.load_known_destinations(storage_path : String? = nil)
      return if storage_path.nil?

      filepath = File.join(storage_path, "known_destinations")
      if File.exists?(filepath)
        begin
          data = File.read(filepath).to_slice
          unpacker = MessagePack::IOUnpacker.new(IO::Memory.new(data))
          token = unpacker.read_token
          if token.is_a?(MessagePack::Token::HashT)
            map_size = token.size
            @@known_destinations.clear
            map_size.times do
              # Read key (destination hash)
              key_token = unpacker.read_token
              dest_hash = case key_token
                          when MessagePack::Token::BytesT
                            key_token.value
                          else
                            next
                          end

              # Only accept valid-length destination hashes
              if dest_hash.size != TRUNCATED_HASHLENGTH // 8
                # Skip the array value
                skip_msgpack_value(unpacker)
                next
              end

              # Read value (array)
              arr_token = unpacker.read_token
              if arr_token.is_a?(MessagePack::Token::ArrayT)
                entry = Array(Bytes | Float64 | Nil).new(arr_token.size.to_i32)
                arr_token.size.times do
                  val_token = unpacker.read_token
                  case val_token
                  when MessagePack::Token::FloatT
                    entry << val_token.value.to_f64
                  when MessagePack::Token::IntT
                    entry << val_token.value.to_f64
                  when MessagePack::Token::BytesT
                    entry << val_token.value
                  when MessagePack::Token::StringT
                    entry << val_token.value.to_slice
                  when MessagePack::Token::NullT
                    entry << nil
                  else
                    entry << nil
                  end
                end
                @@known_destinations[dest_hash] = entry
              end
            end
          end

          RNS.log("Loaded #{@@known_destinations.size} known destination from storage", RNS::LOG_VERBOSE)
        rescue ex
          RNS.log("Error loading known destinations from disk, file will be recreated on exit: #{ex}", RNS::LOG_ERROR)
        end
      else
        RNS.log("Destinations file does not exist, no known destinations loaded", RNS::LOG_VERBOSE)
      end
    end

    private def self.skip_msgpack_value(unpacker)
      token = unpacker.read_token
      case token
      when MessagePack::Token::ArrayT
        token.size.times { skip_msgpack_value(unpacker) }
      when MessagePack::Token::HashT
        token.size.times do
          skip_msgpack_value(unpacker)
          skip_msgpack_value(unpacker)
        end
      end
    end

    # ─── Hash Functions ────────────────────────────────────────────────

    def self.full_hash(data : Bytes) : Bytes
      Cryptography.sha256(data)
    end

    def self.truncated_hash(data : Bytes) : Bytes
      full_hash(data)[0, TRUNCATED_HASHLENGTH // 8]
    end

    def self.get_random_hash : Bytes
      truncated_hash(Random::Secure.random_bytes(TRUNCATED_HASHLENGTH // 8))
    end

    # ─── Ratchet Methods ───────────────────────────────────────────────

    def self.current_ratchet_id(destination_hash : Bytes) : Bytes?
      ratchet = get_ratchet(destination_hash)
      return nil if ratchet.nil?
      get_ratchet_id(ratchet)
    end

    def self.get_ratchet_id(ratchet_pub_bytes : Bytes) : Bytes
      full_hash(ratchet_pub_bytes)[0, NAME_HASH_LENGTH // 8]
    end

    def self.ratchet_public_bytes(ratchet : Bytes) : Bytes
      Cryptography::X25519PrivateKey.from_private_bytes(ratchet).public_key.public_bytes
    end

    def self.generate_ratchet : Bytes
      ratchet_prv = Cryptography::X25519PrivateKey.generate
      ratchet_prv.private_bytes
    end

    def self.remember_ratchet(destination_hash : Bytes, ratchet : Bytes)
      if @@known_ratchets.has_key?(destination_hash) && @@known_ratchets[destination_hash] == ratchet
        return # Already known
      end

      RNS.log("Remembering ratchet #{RNS.prettyhexrep(get_ratchet_id(ratchet))} for #{RNS.prettyhexrep(destination_hash)}", RNS::LOG_EXTREME)
      @@known_ratchets[destination_hash] = ratchet
    rescue ex
      RNS.log("Could not persist ratchet for #{RNS.prettyhexrep(destination_hash)} to storage.", RNS::LOG_ERROR)
      RNS.log("The contained exception was: #{ex}", RNS::LOG_ERROR)
    end

    def self.get_ratchet(destination_hash : Bytes) : Bytes?
      if @@known_ratchets.has_key?(destination_hash)
        return @@known_ratchets[destination_hash]
      end
      nil
    end

    def self.clean_ratchets(storage_path : String? = nil)
      RNS.log("Cleaning ratchets...", RNS::LOG_DEBUG)
      return if storage_path.nil?

      begin
        now = Time.utc.to_unix_f
        ratchetdir = File.join(storage_path, "ratchets")
        if Dir.exists?(ratchetdir)
          Dir.each_child(ratchetdir) do |filename|
            begin
              filepath = File.join(ratchetdir, filename)
              expired = false
              corrupted = false

              begin
                data = File.read(filepath).to_slice
                unpacker = MessagePack::IOUnpacker.new(IO::Memory.new(data))
                token = unpacker.read_token
                if token.is_a?(MessagePack::Token::HashT)
                  received_time = 0.0_f64
                  token.size.times do
                    key_token = unpacker.read_token
                    val_token = unpacker.read_token
                    if key_token.is_a?(MessagePack::Token::StringT) && key_token.value == "received"
                      case val_token
                      when MessagePack::Token::FloatT
                        received_time = val_token.value.to_f64
                      when MessagePack::Token::IntT
                        received_time = val_token.value.to_f64
                      end
                    end
                  end
                  expired = now > received_time + RATCHET_EXPIRY
                end
              rescue
                RNS.log("Corrupted ratchet data while reading #{filepath}, removing file", RNS::LOG_ERROR)
                corrupted = true
              end

              if expired || corrupted
                File.delete(filepath)
              end
            rescue ex
              RNS.log("An error occurred while cleaning ratchets, in the processing of #{ratchetdir}/#{filename}.", RNS::LOG_ERROR)
              RNS.log("The contained exception was: #{ex}", RNS::LOG_ERROR)
            end
          end
        end
      rescue ex
        RNS.log("An error occurred while cleaning ratchets. The contained exception was: #{ex}", RNS::LOG_ERROR)
      end
    end

    # ─── Factory Methods ───────────────────────────────────────────────

    def self.from_bytes(prv_bytes : Bytes) : Identity?
      identity = Identity.new(create_keys: false)
      if identity.load_private_key(prv_bytes)
        identity
      else
        nil
      end
    end

    def self.from_file(path : String) : Identity?
      identity = Identity.new(create_keys: false)
      if identity.load(path)
        identity
      else
        nil
      end
    end

    # ─── Persistence ───────────────────────────────────────────────────

    def self.persist_data(storage_path : String? = nil)
      save_known_destinations(storage_path)
    end

    def self.exit_handler(storage_path : String? = nil)
      persist_data(storage_path)
    end
  end
end
