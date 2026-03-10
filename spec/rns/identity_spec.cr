require "../spec_helper"

describe RNS::Identity do
  # ─── Constants ───────────────────────────────────────────────────────
  describe "constants" do
    it "has CURVE = Curve25519" do
      RNS::Identity::CURVE.should eq "Curve25519"
    end

    it "has KEYSIZE = 512 bits" do
      RNS::Identity::KEYSIZE.should eq 512
    end

    it "has HASHLENGTH = 256 bits" do
      RNS::Identity::HASHLENGTH.should eq 256
    end

    it "has SIGLENGTH = KEYSIZE" do
      RNS::Identity::SIGLENGTH.should eq RNS::Identity::KEYSIZE
    end

    it "has NAME_HASH_LENGTH = 80 bits" do
      RNS::Identity::NAME_HASH_LENGTH.should eq 80
    end

    it "has TRUNCATED_HASHLENGTH = 128 bits" do
      RNS::Identity::TRUNCATED_HASHLENGTH.should eq 128
    end

    it "has RATCHETSIZE = 256 bits" do
      RNS::Identity::RATCHETSIZE.should eq 256
    end

    it "has RATCHET_EXPIRY = 30 days in seconds" do
      RNS::Identity::RATCHET_EXPIRY.should eq 60 * 60 * 24 * 30
    end

    it "has TOKEN_OVERHEAD = 48 bytes" do
      RNS::Identity::TOKEN_OVERHEAD.should eq 48
    end

    it "has DERIVED_KEY_LENGTH = 64 bytes" do
      RNS::Identity::DERIVED_KEY_LENGTH.should eq 64
    end

    it "has DERIVED_KEY_LENGTH_LEGACY = 32 bytes" do
      RNS::Identity::DERIVED_KEY_LENGTH_LEGACY.should eq 32
    end

    it "has AES128_BLOCKSIZE = 16 bytes" do
      RNS::Identity::AES128_BLOCKSIZE.should eq 16
    end
  end

  # ─── Key Generation ──────────────────────────────────────────────────
  describe "#create_keys" do
    it "generates keys on initialization by default" do
      id = RNS::Identity.new
      id.pub.should_not be_nil
      id.sig_pub.should_not be_nil
      id.prv.should_not be_nil
      id.sig_prv.should_not be_nil
    end

    it "does not generate keys when create_keys is false" do
      id = RNS::Identity.new(create_keys: false)
      id.pub.should be_nil
      id.sig_pub.should be_nil
      id.prv.should be_nil
      id.sig_prv.should be_nil
      id.hash.should be_nil
    end

    it "generates unique keys each time" do
      id1 = RNS::Identity.new
      id2 = RNS::Identity.new
      id1.get_private_key.should_not eq id2.get_private_key
      id1.get_public_key.should_not eq id2.get_public_key
    end

    it "generates public key bytes of correct size" do
      id = RNS::Identity.new
      # 32 bytes X25519 pub + 32 bytes Ed25519 pub = 64 bytes
      id.get_public_key.size.should eq RNS::Identity::KEYSIZE // 8
    end

    it "generates private key bytes of correct size" do
      id = RNS::Identity.new
      # 32 bytes X25519 prv + 32 bytes Ed25519 prv = 64 bytes
      id.get_private_key.size.should eq RNS::Identity::KEYSIZE // 8
    end

    it "computes hash on creation" do
      id = RNS::Identity.new
      id.hash.should_not be_nil
      id.hash.not_nil!.size.should eq RNS::Identity::TRUNCATED_HASHLENGTH // 8
    end

    it "computes hexhash on creation" do
      id = RNS::Identity.new
      id.hexhash.should_not be_nil
      id.hexhash.not_nil!.size.should eq (RNS::Identity::TRUNCATED_HASHLENGTH // 8) * 2
    end
  end

  # ─── Key Serialization ──────────────────────────────────────────────
  describe "#get_private_key / #load_private_key" do
    it "roundtrips private key" do
      id1 = RNS::Identity.new
      prv_bytes = id1.get_private_key

      id2 = RNS::Identity.new(create_keys: false)
      id2.load_private_key(prv_bytes).should be_true

      id2.get_private_key.should eq prv_bytes
      id2.get_public_key.should eq id1.get_public_key
      id2.hash.should eq id1.hash
    end

    it "derives the correct public key from private key" do
      id1 = RNS::Identity.new
      id2 = RNS::Identity.new(create_keys: false)
      id2.load_private_key(id1.get_private_key)

      id2.pub.should_not be_nil
      id2.sig_pub.should_not be_nil
      id2.get_public_key.should eq id1.get_public_key
    end
  end

  describe "#get_public_key / #load_public_key" do
    it "roundtrips public key" do
      id1 = RNS::Identity.new
      pub_bytes = id1.get_public_key

      id2 = RNS::Identity.new(create_keys: false)
      id2.load_public_key(pub_bytes)

      id2.get_public_key.should eq pub_bytes
      id2.hash.should eq id1.hash
    end

    it "loads only public key, no private key" do
      id1 = RNS::Identity.new
      id2 = RNS::Identity.new(create_keys: false)
      id2.load_public_key(id1.get_public_key)

      id2.pub.should_not be_nil
      id2.sig_pub.should_not be_nil
      id2.prv.should be_nil
      id2.sig_prv.should be_nil
    end
  end

  # ─── Hash Computation ───────────────────────────────────────────────
  describe ".full_hash" do
    it "returns SHA-256 hash" do
      data = "test data".to_slice
      hash = RNS::Identity.full_hash(data)
      hash.size.should eq 32
      hash.should eq RNS::Cryptography.sha256(data)
    end
  end

  describe ".truncated_hash" do
    it "returns truncated SHA-256 hash" do
      data = "test data".to_slice
      hash = RNS::Identity.truncated_hash(data)
      hash.size.should eq RNS::Identity::TRUNCATED_HASHLENGTH // 8
      hash.should eq RNS::Cryptography.sha256(data)[0, 16]
    end
  end

  describe ".get_random_hash" do
    it "returns a truncated hash" do
      hash = RNS::Identity.get_random_hash
      hash.size.should eq RNS::Identity::TRUNCATED_HASHLENGTH // 8
    end

    it "returns different hashes each time" do
      h1 = RNS::Identity.get_random_hash
      h2 = RNS::Identity.get_random_hash
      h1.should_not eq h2
    end
  end

  # ─── Signing and Verification ────────────────────────────────────────
  describe "#sign / #validate" do
    it "signs and verifies a message" do
      id = RNS::Identity.new
      message = "Hello, Reticulum!".to_slice
      signature = id.sign(message)
      signature.size.should eq 64
      id.validate(signature, message).should be_true
    end

    it "rejects invalid signature" do
      id = RNS::Identity.new
      message = "Hello, Reticulum!".to_slice
      signature = id.sign(message)

      # Tamper with signature
      tampered = signature.dup
      tampered[0] ^= 0xFF_u8
      id.validate(tampered, message).should be_false
    end

    it "rejects signature for wrong message" do
      id = RNS::Identity.new
      sig = id.sign("message1".to_slice)
      id.validate(sig, "message2".to_slice).should be_false
    end

    it "raises KeyError when signing without private key" do
      id = RNS::Identity.new(create_keys: false)
      id.load_public_key(RNS::Identity.new.get_public_key)
      expect_raises(KeyError) { id.sign("test".to_slice) }
    end

    it "raises KeyError when validating without public key" do
      id = RNS::Identity.new(create_keys: false)
      expect_raises(KeyError) { id.validate(Bytes.new(64), "test".to_slice) }
    end

    it "verifies signature from a different identity instance with same keys" do
      id1 = RNS::Identity.new
      id2 = RNS::Identity.new(create_keys: false)
      id2.load_public_key(id1.get_public_key)

      message = "cross-instance verify".to_slice
      sig = id1.sign(message)
      id2.validate(sig, message).should be_true
    end

    it "produces deterministic signatures" do
      id = RNS::Identity.new
      message = "deterministic".to_slice
      sig1 = id.sign(message)
      sig2 = id.sign(message)
      sig1.should eq sig2
    end

    it "signs empty messages" do
      id = RNS::Identity.new
      sig = id.sign(Bytes.empty)
      sig.size.should eq 64
      id.validate(sig, Bytes.empty).should be_true
    end
  end

  # ─── Encryption and Decryption ───────────────────────────────────────
  describe "#encrypt / #decrypt" do
    it "encrypts and decrypts a message" do
      id = RNS::Identity.new
      plaintext = "Secret message".to_slice
      ciphertext = id.encrypt(plaintext)
      decrypted = id.decrypt(ciphertext)
      decrypted.should_not be_nil
      decrypted.not_nil!.should eq plaintext
    end

    it "produces ciphertext larger than plaintext by expected overhead" do
      id = RNS::Identity.new
      plaintext = "test".to_slice
      ciphertext = id.encrypt(plaintext)
      # Overhead: 32 bytes ephemeral pub + TOKEN_OVERHEAD (48) + PKCS7 padding
      ciphertext.size.should be > plaintext.size + 32 + RNS::Identity::TOKEN_OVERHEAD
    end

    it "produces different ciphertext each time (random IV + ephemeral key)" do
      id = RNS::Identity.new
      plaintext = "same plaintext".to_slice
      ct1 = id.encrypt(plaintext)
      ct2 = id.encrypt(plaintext)
      ct1.should_not eq ct2
    end

    it "decrypts empty plaintext" do
      id = RNS::Identity.new
      ciphertext = id.encrypt(Bytes.empty)
      decrypted = id.decrypt(ciphertext)
      decrypted.should_not be_nil
      decrypted.not_nil!.should eq Bytes.empty
    end

    it "decrypts large plaintext" do
      id = RNS::Identity.new
      plaintext = Random::Secure.random_bytes(4096)
      ciphertext = id.encrypt(plaintext)
      decrypted = id.decrypt(ciphertext)
      decrypted.should_not be_nil
      decrypted.not_nil!.should eq plaintext
    end

    it "fails to decrypt with wrong identity" do
      id1 = RNS::Identity.new
      id2 = RNS::Identity.new
      ciphertext = id1.encrypt("secret".to_slice)
      decrypted = id2.decrypt(ciphertext)
      decrypted.should be_nil
    end

    it "fails to decrypt tampered ciphertext" do
      id = RNS::Identity.new
      ciphertext = id.encrypt("test".to_slice)
      tampered = ciphertext.dup
      tampered[40] ^= 0xFF_u8
      decrypted = id.decrypt(tampered)
      decrypted.should be_nil
    end

    it "fails to decrypt too-short ciphertext" do
      id = RNS::Identity.new
      short = Bytes.new(16) # Less than KEYSIZE//8//2 = 32
      decrypted = id.decrypt(short)
      decrypted.should be_nil
    end

    it "raises KeyError when encrypting without public key" do
      id = RNS::Identity.new(create_keys: false)
      expect_raises(KeyError) { id.encrypt("test".to_slice) }
    end

    it "raises KeyError when decrypting without private key" do
      id = RNS::Identity.new(create_keys: false)
      id.load_public_key(RNS::Identity.new.get_public_key)
      expect_raises(KeyError) { id.decrypt(Bytes.new(100)) }
    end

    it "encrypts with public key only, decrypts with private key" do
      id_full = RNS::Identity.new
      id_pub = RNS::Identity.new(create_keys: false)
      id_pub.load_public_key(id_full.get_public_key)

      plaintext = "encrypt with pub, decrypt with prv".to_slice
      ciphertext = id_pub.encrypt(plaintext)
      decrypted = id_full.decrypt(ciphertext)
      decrypted.should_not be_nil
      decrypted.not_nil!.should eq plaintext
    end

    it "roundtrips 100 random messages" do
      id = RNS::Identity.new
      100.times do
        size = rand(0..1000)
        plaintext = Random::Secure.random_bytes(size)
        ciphertext = id.encrypt(plaintext)
        decrypted = id.decrypt(ciphertext)
        decrypted.should_not be_nil
        decrypted.not_nil!.should eq plaintext
      end
    end
  end

  # ─── Encrypt/Decrypt with Ratchet ────────────────────────────────────
  describe "encryption with ratchet" do
    it "encrypts with ratchet and decrypts with ratchet list" do
      id = RNS::Identity.new
      plaintext = "ratcheted message".to_slice

      # Generate a ratchet (private key bytes)
      ratchet_prv = RNS::Cryptography::X25519PrivateKey.generate
      ratchet_bytes = ratchet_prv.private_bytes
      ratchet_pub_bytes = ratchet_prv.public_key.public_bytes

      # Encrypt targeting the ratchet public key
      ciphertext = id.encrypt(plaintext, ratchet: ratchet_pub_bytes)

      # Decrypt with ratchet list
      decrypted = id.decrypt(ciphertext, ratchets: [ratchet_bytes])
      decrypted.should_not be_nil
      decrypted.not_nil!.should eq plaintext
    end

    it "falls back to identity key when ratchet fails" do
      id = RNS::Identity.new
      plaintext = "no ratchet used".to_slice

      # Encrypt without ratchet (uses identity pub key)
      ciphertext = id.encrypt(plaintext)

      # Try to decrypt with wrong ratchet, should fall back to identity key
      wrong_ratchet = RNS::Cryptography::X25519PrivateKey.generate.private_bytes
      decrypted = id.decrypt(ciphertext, ratchets: [wrong_ratchet])
      decrypted.should_not be_nil
      decrypted.not_nil!.should eq plaintext
    end

    it "returns nil when enforce_ratchets is true and ratchet fails" do
      id = RNS::Identity.new
      plaintext = "enforced ratchet".to_slice

      # Encrypt without ratchet
      ciphertext = id.encrypt(plaintext)

      # Decrypt with enforce_ratchets - wrong ratchet should return nil
      wrong_ratchet = RNS::Cryptography::X25519PrivateKey.generate.private_bytes
      decrypted = id.decrypt(ciphertext, ratchets: [wrong_ratchet], enforce_ratchets: true)
      decrypted.should be_nil
    end
  end

  # ─── Remember / Recall ──────────────────────────────────────────────
  describe ".remember / .recall / .recall_app_data" do
    before_each do
      RNS::Identity.known_destinations.clear
    end

    it "remembers and recalls an identity" do
      id = RNS::Identity.new
      dest_hash = RNS::Identity.truncated_hash("test.dest".to_slice)
      packet_hash = RNS::Identity.get_random_hash
      pub_key = id.get_public_key
      app_data = "some app data".to_slice

      RNS::Identity.remember(packet_hash, dest_hash, pub_key, app_data)

      recalled = RNS::Identity.recall(dest_hash)
      recalled.should_not be_nil
      recalled.not_nil!.get_public_key.should eq pub_key
    end

    it "returns nil for unknown destination" do
      unknown_hash = RNS::Identity.get_random_hash
      RNS::Identity.recall(unknown_hash).should be_nil
    end

    it "recalls app_data" do
      id = RNS::Identity.new
      dest_hash = RNS::Identity.truncated_hash("test.app_data".to_slice)
      packet_hash = RNS::Identity.get_random_hash
      app_data = "my app data".to_slice

      RNS::Identity.remember(packet_hash, dest_hash, id.get_public_key, app_data)
      RNS::Identity.recall_app_data(dest_hash).should eq app_data
    end

    it "returns nil app_data for unknown destination" do
      RNS::Identity.recall_app_data(RNS::Identity.get_random_hash).should be_nil
    end

    it "rejects remember with invalid public key size" do
      dest_hash = RNS::Identity.get_random_hash
      packet_hash = RNS::Identity.get_random_hash
      bad_key = Bytes.new(32) # Should be 64

      expect_raises(ArgumentError) do
        RNS::Identity.remember(packet_hash, dest_hash, bad_key)
      end
    end

    it "overwrites previous remember for same destination" do
      id1 = RNS::Identity.new
      id2 = RNS::Identity.new
      dest_hash = RNS::Identity.truncated_hash("overwrite.test".to_slice)
      packet_hash = RNS::Identity.get_random_hash

      RNS::Identity.remember(packet_hash, dest_hash, id1.get_public_key, "data1".to_slice)
      RNS::Identity.remember(packet_hash, dest_hash, id2.get_public_key, "data2".to_slice)

      recalled = RNS::Identity.recall(dest_hash)
      recalled.should_not be_nil
      recalled.not_nil!.get_public_key.should eq id2.get_public_key
      RNS::Identity.recall_app_data(dest_hash).should eq "data2".to_slice
    end
  end

  # ─── Recall by Identity Hash ─────────────────────────────────────────
  describe ".recall with from_identity_hash" do
    before_each do
      RNS::Identity.known_destinations.clear
    end

    it "recalls identity by identity hash" do
      id = RNS::Identity.new
      dest_hash = RNS::Identity.truncated_hash("identity.lookup".to_slice)
      packet_hash = RNS::Identity.get_random_hash
      pub_key = id.get_public_key

      RNS::Identity.remember(packet_hash, dest_hash, pub_key)

      # The identity hash is the truncated hash of the public key
      identity_hash = RNS::Identity.truncated_hash(pub_key)
      recalled = RNS::Identity.recall(identity_hash, from_identity_hash: true)
      recalled.should_not be_nil
      recalled.not_nil!.get_public_key.should eq pub_key
    end

    it "returns nil for unknown identity hash" do
      unknown = RNS::Identity.get_random_hash
      RNS::Identity.recall(unknown, from_identity_hash: true).should be_nil
    end
  end

  # ─── File I/O ────────────────────────────────────────────────────────
  describe "#to_file / .from_file" do
    it "saves and loads identity from file" do
      id1 = RNS::Identity.new
      tempfile = File.tempname("rns_identity", ".key")

      begin
        id1.to_file(tempfile).should be_true

        id2 = RNS::Identity.from_file(tempfile)
        id2.should_not be_nil
        id2.not_nil!.get_private_key.should eq id1.get_private_key
        id2.not_nil!.get_public_key.should eq id1.get_public_key
        id2.not_nil!.hash.should eq id1.hash
      ensure
        File.delete(tempfile) if File.exists?(tempfile)
      end
    end

    it "returns nil for nonexistent file" do
      RNS::Identity.from_file("/tmp/nonexistent_rns_identity_file").should be_nil
    end
  end

  describe ".from_bytes" do
    it "creates identity from private key bytes" do
      id1 = RNS::Identity.new
      prv_bytes = id1.get_private_key

      id2 = RNS::Identity.from_bytes(prv_bytes)
      id2.should_not be_nil
      id2.not_nil!.get_public_key.should eq id1.get_public_key
      id2.not_nil!.hash.should eq id1.hash
    end

    it "restores signing capability" do
      id1 = RNS::Identity.new
      id2 = RNS::Identity.from_bytes(id1.get_private_key).not_nil!

      message = "restored signing".to_slice
      sig = id2.sign(message)
      id1.validate(sig, message).should be_true
    end

    it "restores encryption capability" do
      id1 = RNS::Identity.new
      id2 = RNS::Identity.from_bytes(id1.get_private_key).not_nil!

      plaintext = "restored encryption".to_slice
      ciphertext = id1.encrypt(plaintext)
      decrypted = id2.decrypt(ciphertext)
      decrypted.should_not be_nil
      decrypted.not_nil!.should eq plaintext
    end
  end

  # ─── Ratchet Methods ─────────────────────────────────────────────────
  describe "ratchet methods" do
    it "generates a ratchet of correct size" do
      ratchet = RNS::Identity.generate_ratchet
      ratchet.size.should eq RNS::Identity::RATCHETSIZE // 8
    end

    it "derives ratchet public bytes from ratchet private bytes" do
      ratchet = RNS::Identity.generate_ratchet
      pub = RNS::Identity.ratchet_public_bytes(ratchet)
      pub.size.should eq 32
    end

    it "computes ratchet ID from public bytes" do
      ratchet = RNS::Identity.generate_ratchet
      pub = RNS::Identity.ratchet_public_bytes(ratchet)
      ratchet_id = RNS::Identity.get_ratchet_id(pub)
      ratchet_id.size.should eq RNS::Identity::NAME_HASH_LENGTH // 8
    end

    it "generates unique ratchets each time" do
      r1 = RNS::Identity.generate_ratchet
      r2 = RNS::Identity.generate_ratchet
      r1.should_not eq r2
    end
  end

  # ─── Known Destinations Persistence ──────────────────────────────────
  describe "known destinations persistence" do
    before_each do
      RNS::Identity.known_destinations.clear
    end

    it "saves and loads known destinations" do
      id = RNS::Identity.new
      dest_hash = RNS::Identity.truncated_hash("persist.test".to_slice)
      packet_hash = RNS::Identity.get_random_hash
      pub_key = id.get_public_key
      app_data = "persist data".to_slice

      RNS::Identity.remember(packet_hash, dest_hash, pub_key, app_data)

      tempdir = File.tempname("rns_storage", "")
      Dir.mkdir_p(tempdir)

      begin
        RNS::Identity.save_known_destinations(tempdir)

        RNS::Identity.known_destinations.clear
        RNS::Identity.known_destinations.size.should eq 0

        RNS::Identity.load_known_destinations(tempdir)
        RNS::Identity.known_destinations.size.should eq 1

        recalled = RNS::Identity.recall(dest_hash)
        recalled.should_not be_nil
        recalled.not_nil!.get_public_key.should eq pub_key
      ensure
        FileUtils.rm_rf(tempdir)
      end
    end
  end

  # ─── Ratchet Persistence ─────────────────────────────────────────────
  describe "ratchet persistence" do
    before_each do
      RNS::Identity.known_ratchets.clear
    end

    it "remembers and retrieves a ratchet" do
      dest_hash = RNS::Identity.truncated_hash("ratchet.persist".to_slice)
      ratchet = RNS::Identity.generate_ratchet
      ratchet_pub = RNS::Identity.ratchet_public_bytes(ratchet)

      RNS::Identity.remember_ratchet(dest_hash, ratchet_pub)
      RNS::Identity.known_ratchets[dest_hash].should eq ratchet_pub
    end

    it "retrieves current ratchet ID" do
      dest_hash = RNS::Identity.truncated_hash("ratchet.id".to_slice)
      ratchet = RNS::Identity.generate_ratchet
      ratchet_pub = RNS::Identity.ratchet_public_bytes(ratchet)

      RNS::Identity.remember_ratchet(dest_hash, ratchet_pub)

      ratchet_id = RNS::Identity.current_ratchet_id(dest_hash)
      ratchet_id.should_not be_nil
      ratchet_id.not_nil!.size.should eq RNS::Identity::NAME_HASH_LENGTH // 8
    end

    it "returns nil ratchet ID for unknown destination" do
      unknown = RNS::Identity.get_random_hash
      RNS::Identity.current_ratchet_id(unknown).should be_nil
    end
  end

  # ─── to_s ────────────────────────────────────────────────────────────
  describe "#to_s" do
    it "returns prettyhexrep of hash" do
      id = RNS::Identity.new
      id.to_s.should eq RNS.prettyhexrep(id.hash.not_nil!)
    end
  end

  # ─── get_salt / get_context ──────────────────────────────────────────
  describe "#get_salt / #get_context" do
    it "returns hash as salt" do
      id = RNS::Identity.new
      id.get_salt.should eq id.hash
    end

    it "returns nil as context" do
      id = RNS::Identity.new
      id.get_context.should be_nil
    end
  end

  # ─── Stress Tests ────────────────────────────────────────────────────
  describe "stress tests" do
    it "100 sign/verify roundtrips" do
      id = RNS::Identity.new
      100.times do
        msg = Random::Secure.random_bytes(rand(0..500))
        sig = id.sign(msg)
        id.validate(sig, msg).should be_true
      end
    end

    it "50 key serialization roundtrips" do
      50.times do
        id1 = RNS::Identity.new
        id2 = RNS::Identity.from_bytes(id1.get_private_key).not_nil!
        id2.get_public_key.should eq id1.get_public_key
        id2.hash.should eq id1.hash

        msg = Random::Secure.random_bytes(64)
        sig = id1.sign(msg)
        id2.validate(sig, msg).should be_true
      end
    end
  end
end
