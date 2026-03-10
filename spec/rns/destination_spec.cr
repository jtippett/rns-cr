require "../spec_helper"

describe RNS::Destination do
  # Helper to clear transport state between tests
  before_each do
    RNS::Transport.clear_destinations
  end

  # ─── Constants ───────────────────────────────────────────────────────
  describe "constants" do
    it "has correct type constants" do
      RNS::Destination::SINGLE.should eq 0x00_u8
      RNS::Destination::GROUP.should eq 0x01_u8
      RNS::Destination::PLAIN.should eq 0x02_u8
      RNS::Destination::LINK.should eq 0x03_u8
    end

    it "has correct direction constants" do
      RNS::Destination::IN.should eq 0x11_u8
      RNS::Destination::OUT.should eq 0x12_u8
    end

    it "has correct proof strategy constants matching Python" do
      RNS::Destination::PROVE_NONE.should eq 0x21_u8
      RNS::Destination::PROVE_APP.should eq 0x22_u8
      RNS::Destination::PROVE_ALL.should eq 0x23_u8
    end

    it "has correct request policy constants" do
      RNS::Destination::ALLOW_NONE.should eq 0x00_u8
      RNS::Destination::ALLOW_ALL.should eq 0x01_u8
      RNS::Destination::ALLOW_LIST.should eq 0x02_u8
    end

    it "has correct ratchet constants" do
      RNS::Destination::PR_TAG_WINDOW.should eq 30
      RNS::Destination::RATCHET_COUNT.should eq 512
      RNS::Destination::RATCHET_INTERVAL.should eq 1800
    end

    it "has TYPES array containing all types" do
      RNS::Destination::TYPES.should contain(RNS::Destination::SINGLE)
      RNS::Destination::TYPES.should contain(RNS::Destination::GROUP)
      RNS::Destination::TYPES.should contain(RNS::Destination::PLAIN)
      RNS::Destination::TYPES.should contain(RNS::Destination::LINK)
    end

    it "has DIRECTIONS array" do
      RNS::Destination::DIRECTIONS.should contain(RNS::Destination::IN)
      RNS::Destination::DIRECTIONS.should contain(RNS::Destination::OUT)
    end

    it "has PROOF_STRATEGIES array" do
      RNS::Destination::PROOF_STRATEGIES.should contain(RNS::Destination::PROVE_NONE)
      RNS::Destination::PROOF_STRATEGIES.should contain(RNS::Destination::PROVE_APP)
      RNS::Destination::PROOF_STRATEGIES.should contain(RNS::Destination::PROVE_ALL)
    end

    it "has REQUEST_POLICIES array" do
      RNS::Destination::REQUEST_POLICIES.should contain(RNS::Destination::ALLOW_NONE)
      RNS::Destination::REQUEST_POLICIES.should contain(RNS::Destination::ALLOW_ALL)
      RNS::Destination::REQUEST_POLICIES.should contain(RNS::Destination::ALLOW_LIST)
    end
  end

  # ─── Static methods ─────────────────────────────────────────────────
  describe ".expand_name" do
    it "builds name from app_name and aspects" do
      name = RNS::Destination.expand_name(nil, "testapp", ["aspect1", "aspect2"])
      name.should eq "testapp.aspect1.aspect2"
    end

    it "builds name with no aspects" do
      name = RNS::Destination.expand_name(nil, "testapp", [] of String)
      name.should eq "testapp"
    end

    it "appends identity hexhash when identity is provided" do
      identity = RNS::Identity.new
      name = RNS::Destination.expand_name(identity, "testapp", ["aspect1"])
      name.should end_with(identity.hexhash.not_nil!)
      name.should start_with("testapp.aspect1.")
    end

    it "raises on dots in app_name" do
      expect_raises(ArgumentError, /Dots/) do
        RNS::Destination.expand_name(nil, "test.app", [] of String)
      end
    end

    it "raises on dots in aspects" do
      expect_raises(ArgumentError, /Dots/) do
        RNS::Destination.expand_name(nil, "testapp", ["bad.aspect"])
      end
    end

    it "works with splat arguments" do
      name = RNS::Destination.expand_name(nil, "testapp", "a", "b")
      name.should eq "testapp.a.b"
    end
  end

  describe ".hash" do
    it "produces a 16-byte hash (TRUNCATED_HASHLENGTH // 8)" do
      identity = RNS::Identity.new
      h = RNS::Destination.hash(identity, "testapp", ["aspect1"])
      h.size.should eq(RNS::Reticulum::TRUNCATED_HASHLENGTH // 8)
    end

    it "produces different hashes for different app_names" do
      identity = RNS::Identity.new
      h1 = RNS::Destination.hash(identity, "app1", ["aspect"])
      h2 = RNS::Destination.hash(identity, "app2", ["aspect"])
      h1.should_not eq h2
    end

    it "produces different hashes for different identities" do
      id1 = RNS::Identity.new
      id2 = RNS::Identity.new
      h1 = RNS::Destination.hash(id1, "testapp", ["aspect"])
      h2 = RNS::Destination.hash(id2, "testapp", ["aspect"])
      h1.should_not eq h2
    end

    it "produces same hash for nil identity (PLAIN destinations)" do
      h1 = RNS::Destination.hash(nil, "testapp", ["aspect"])
      h2 = RNS::Destination.hash(nil, "testapp", ["aspect"])
      h1.should eq h2
    end

    it "accepts raw bytes as identity hash" do
      identity = RNS::Identity.new
      id_hash = identity.hash.not_nil!

      h1 = RNS::Destination.hash(identity, "testapp", ["aspect"])
      h2 = RNS::Destination.hash(id_hash, "testapp", ["aspect"])
      h1.should eq h2
    end

    it "raises on invalid identity hash bytes size" do
      expect_raises(RNS::TypeError, /Invalid material/) do
        RNS::Destination.hash(Bytes.new(5), "testapp", ["aspect"])
      end
    end

    it "hash matches expected computation" do
      # Verify the hash computation: full_hash(name_hash + identity.hash)[0, 16]
      identity = RNS::Identity.new
      aspects = ["aspect1"]

      name_hash = RNS::Identity.full_hash(
        RNS::Destination.expand_name(nil, "testapp", aspects).to_slice
      )[0, RNS::Identity::NAME_HASH_LENGTH // 8]

      id_hash = identity.hash.not_nil!
      material = Bytes.new(name_hash.size + id_hash.size)
      name_hash.copy_to(material)
      id_hash.copy_to(material + name_hash.size)
      expected = RNS::Identity.full_hash(material)[0, RNS::Reticulum::TRUNCATED_HASHLENGTH // 8]

      computed = RNS::Destination.hash(identity, "testapp", aspects)
      computed.should eq expected
    end
  end

  describe ".app_and_aspects_from_name" do
    it "splits a full name into app and aspects" do
      app_name, aspects = RNS::Destination.app_and_aspects_from_name("myapp.aspect1.aspect2")
      app_name.should eq "myapp"
      aspects.should eq ["aspect1", "aspect2"]
    end

    it "handles name with no aspects" do
      app_name, aspects = RNS::Destination.app_and_aspects_from_name("myapp")
      app_name.should eq "myapp"
      aspects.should be_empty
    end
  end

  describe ".hash_from_name_and_identity" do
    it "produces same hash as direct hash call" do
      identity = RNS::Identity.new
      full_name = "testapp.aspect1"

      h1 = RNS::Destination.hash_from_name_and_identity(full_name, identity)
      h2 = RNS::Destination.hash(identity, "testapp", ["aspect1"])
      h1.should eq h2
    end
  end

  # ─── Constructor ────────────────────────────────────────────────────
  describe "#initialize" do
    it "creates a SINGLE IN destination, auto-creating identity" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", ["aspect1"], register: false)
      dest.type.should eq RNS::Destination::SINGLE
      dest.direction.should eq RNS::Destination::IN
      dest.identity.should_not be_nil
      dest.hash.size.should eq(RNS::Reticulum::TRUNCATED_HASHLENGTH // 8)
      dest.hexhash.size.should eq(RNS::Reticulum::TRUNCATED_HASHLENGTH // 8 * 2)
      dest.name_hash.size.should eq(RNS::Identity::NAME_HASH_LENGTH // 8)
    end

    it "creates a SINGLE OUT destination with provided identity" do
      identity = RNS::Identity.new
      dest = RNS::Destination.new(identity, RNS::Destination::OUT, RNS::Destination::SINGLE, "testapp", ["aspect1"], register: false)
      dest.type.should eq RNS::Destination::SINGLE
      dest.direction.should eq RNS::Destination::OUT
      dest.identity.should eq identity
    end

    it "raises when creating SINGLE OUT without identity" do
      expect_raises(ArgumentError, /Can't create outbound/) do
        RNS::Destination.new(nil, RNS::Destination::OUT, RNS::Destination::SINGLE, "testapp", register: false)
      end
    end

    it "creates a PLAIN destination without identity" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", ["aspect1"], register: false)
      dest.type.should eq RNS::Destination::PLAIN
      dest.identity.should be_nil
    end

    it "raises when creating PLAIN destination with identity" do
      identity = RNS::Identity.new
      expect_raises(RNS::TypeError, /PLAIN cannot hold/) do
        RNS::Destination.new(identity, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
      end
    end

    it "creates a GROUP destination" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::GROUP, "testapp", ["aspect1"], register: false)
      dest.type.should eq RNS::Destination::GROUP
      dest.identity.should_not be_nil # auto-creates identity
    end

    it "raises on invalid type" do
      expect_raises(ArgumentError, /Unknown destination type/) do
        RNS::Destination.new(nil, RNS::Destination::IN, 0xFF_u8, "testapp", register: false)
      end
    end

    it "raises on invalid direction" do
      expect_raises(ArgumentError, /Unknown destination direction/) do
        RNS::Destination.new(nil, 0xFF_u8, RNS::Destination::PLAIN, "testapp", register: false)
      end
    end

    it "raises on dots in app_name" do
      expect_raises(ArgumentError, /Dots/) do
        RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "test.app", register: false)
      end
    end

    it "raises on dots in aspects" do
      expect_raises(ArgumentError, /Dots/) do
        RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", ["bad.aspect"], register: false)
      end
    end

    it "initializes default property values" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
      dest.accept_link_requests.should be_true
      dest.proof_strategy.should eq RNS::Destination::PROVE_NONE
      dest.ratchets.should be_nil
      dest.ratchets_path.should be_nil
      dest.ratchet_interval.should eq RNS::Destination::RATCHET_INTERVAL
      dest.retained_ratchets.should eq RNS::Destination::RATCHET_COUNT
      dest.latest_ratchet_time.should be_nil
      dest.latest_ratchet_id.should be_nil
      dest.mtu.should eq 0
      dest.prv_bytes.should be_nil
      dest.prv.should be_nil
      dest.default_app_data.should be_nil
    end

    it "registers with Transport by default" do
      RNS::Transport.clear_destinations
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp")
      RNS::Transport.destinations.should contain(dest)
    end

    it "skips Transport registration when register: false" do
      RNS::Transport.clear_destinations
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
      RNS::Transport.destinations.should_not contain(dest)
    end
  end

  # ─── Name and hash computation ──────────────────────────────────────
  describe "name and hash" do
    it "name includes app_name and aspects" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", ["aspect1", "aspect2"], register: false)
      dest.name.should start_with("testapp.aspect1.aspect2")
    end

    it "SINGLE IN name includes hexhash twice (aspect + expand_name)" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", ["aspect1"], register: false)
      identity = dest.identity.not_nil!
      hexhash = identity.hexhash.not_nil!
      # The hexhash appears as an aspect (from constructor) and from expand_name
      parts = dest.name.split(".")
      parts.count { |p| p == hexhash }.should eq 2
    end

    it "hexhash matches hash hex representation" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.hexhash.should eq dest.hash.hexstring
    end

    it "two SINGLE destinations with same identity produce same hash" do
      identity = RNS::Identity.new
      h1 = RNS::Destination.hash(identity, "testapp", ["aspect1"])
      h2 = RNS::Destination.hash(identity, "testapp", ["aspect1"])
      h1.should eq h2
    end

    it "different destinations produce different hashes" do
      dest1 = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", ["a"], register: false)
      dest2 = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", ["a"], register: false)
      dest1.hash.should_not eq dest2.hash # Different auto-created identities
    end

    it "name_hash is NAME_HASH_LENGTH bits" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.name_hash.size.should eq(RNS::Identity::NAME_HASH_LENGTH // 8)
    end
  end

  # ─── String representation ──────────────────────────────────────────
  describe "#to_s" do
    it "includes name and hexhash" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", ["aspect1"], register: false)
      str = dest.to_s
      str.should start_with("<testapp.aspect1:")
      str.should end_with(">")
      str.should contain(dest.hexhash)
    end
  end

  # ─── Callbacks ──────────────────────────────────────────────────────
  describe "callbacks" do
    it "sets link established callback" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      called = false
      dest.set_link_established_callback(->{ called = true; nil })
      dest.callbacks.link_established.should_not be_nil
    end

    it "sets packet callback" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.set_packet_callback(->(data : Bytes, pkt : RNS::Packet) { nil })
      dest.callbacks.packet.should_not be_nil
    end

    it "sets proof requested callback" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.set_proof_requested_callback(->(pkt : RNS::Packet) { true })
      dest.callbacks.proof_requested.should_not be_nil
    end
  end

  # ─── Proof strategy ────────────────────────────────────────────────
  describe "#set_proof_strategy" do
    it "sets PROVE_NONE" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.set_proof_strategy(RNS::Destination::PROVE_NONE)
      dest.proof_strategy.should eq RNS::Destination::PROVE_NONE
    end

    it "sets PROVE_ALL" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.set_proof_strategy(RNS::Destination::PROVE_ALL)
      dest.proof_strategy.should eq RNS::Destination::PROVE_ALL
    end

    it "sets PROVE_APP" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.set_proof_strategy(RNS::Destination::PROVE_APP)
      dest.proof_strategy.should eq RNS::Destination::PROVE_APP
    end

    it "raises on unsupported strategy" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      expect_raises(RNS::TypeError, /Unsupported proof strategy/) do
        dest.set_proof_strategy(0xFF_u8)
      end
    end
  end

  # ─── Accepts links ─────────────────────────────────────────────────
  describe "accepts_links" do
    it "defaults to true" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.accepts_links.should be_true
    end

    it "can be set to false" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.accepts_links = false
      dest.accepts_links.should be_false
    end

    it "can be set back to true" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.accepts_links = false
      dest.accepts_links = true
      dest.accepts_links.should be_true
    end
  end

  # ─── Request handlers ──────────────────────────────────────────────
  describe "request handlers" do
    it "registers a request handler" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      handler = ->(path : String, data : Bytes?, req_id : Bytes, link_id : Bytes, identity : RNS::Identity?, requested_at : Float64) { nil.as(Bytes?) }
      dest.register_request_handler("/test", handler, RNS::Destination::ALLOW_ALL)
      dest.request_handlers.size.should eq 1
    end

    it "raises on empty path" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      handler = ->(path : String, data : Bytes?, req_id : Bytes, link_id : Bytes, identity : RNS::Identity?, requested_at : Float64) { nil.as(Bytes?) }
      expect_raises(ArgumentError, /Invalid path/) do
        dest.register_request_handler("", handler, RNS::Destination::ALLOW_ALL)
      end
    end

    it "raises on invalid request policy" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      handler = ->(path : String, data : Bytes?, req_id : Bytes, link_id : Bytes, identity : RNS::Identity?, requested_at : Float64) { nil.as(Bytes?) }
      expect_raises(ArgumentError, /Invalid request policy/) do
        dest.register_request_handler("/test", handler, 0xFF_u8)
      end
    end

    it "deregisters a request handler" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      handler = ->(path : String, data : Bytes?, req_id : Bytes, link_id : Bytes, identity : RNS::Identity?, requested_at : Float64) { nil.as(Bytes?) }
      dest.register_request_handler("/test", handler)
      dest.deregister_request_handler("/test").should be_true
      dest.request_handlers.size.should eq 0
    end

    it "returns false when deregistering non-existent handler" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.deregister_request_handler("/nonexistent").should be_false
    end

    it "registers multiple handlers on different paths" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      handler = ->(path : String, data : Bytes?, req_id : Bytes, link_id : Bytes, identity : RNS::Identity?, requested_at : Float64) { nil.as(Bytes?) }
      dest.register_request_handler("/path1", handler)
      dest.register_request_handler("/path2", handler)
      dest.request_handlers.size.should eq 2
    end
  end

  # ─── GROUP key management ───────────────────────────────────────────
  describe "GROUP keys" do
    it "creates keys for GROUP destination" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::GROUP, "testapp", register: false)
      dest.create_keys
      dest.prv_bytes.should_not be_nil
      dest.prv.should_not be_nil
    end

    it "get_private_key returns the key" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::GROUP, "testapp", register: false)
      dest.create_keys
      key = dest.get_private_key
      key.should eq dest.prv_bytes.not_nil!
    end

    it "load_private_key loads a key" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::GROUP, "testapp", register: false)
      key = RNS::Cryptography::Token.generate_key
      dest.load_private_key(key)
      dest.prv_bytes.should eq key
      dest.prv.should_not be_nil
    end

    it "raises create_keys on PLAIN destination" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
      expect_raises(RNS::TypeError, /plain destination/) do
        dest.create_keys
      end
    end

    it "raises create_keys on SINGLE destination" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      expect_raises(RNS::TypeError, /single destination/) do
        dest.create_keys
      end
    end

    it "raises get_private_key on PLAIN destination" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
      expect_raises(RNS::TypeError, /plain destination/) do
        dest.get_private_key
      end
    end

    it "raises get_private_key on SINGLE destination" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      expect_raises(RNS::TypeError, /single destination/) do
        dest.get_private_key
      end
    end

    it "raises load_private_key on PLAIN destination" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
      expect_raises(RNS::TypeError, /plain destination/) do
        dest.load_private_key(Bytes.new(64))
      end
    end

    it "raises load_public_key on any destination" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      expect_raises(RNS::TypeError) do
        dest.load_public_key(Bytes.new(64))
      end
    end
  end

  # ─── Encryption / Decryption ────────────────────────────────────────
  describe "encryption and decryption" do
    describe "PLAIN destination" do
      it "encrypt returns plaintext unchanged" do
        dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
        plaintext = "Hello, World!".to_slice
        dest.encrypt(plaintext).should eq plaintext
      end

      it "decrypt returns ciphertext unchanged" do
        dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
        data = "Hello, World!".to_slice
        dest.decrypt(data).should eq data
      end
    end

    describe "SINGLE destination" do
      it "encrypt/decrypt roundtrip" do
        dest_in = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
        identity = dest_in.identity.not_nil!

        # Create an OUT destination with the same identity for encryption
        dest_out = RNS::Destination.new(identity, RNS::Destination::OUT, RNS::Destination::SINGLE, "testapp",
          [identity.hexhash.not_nil!], register: false)

        plaintext = "Secret message".to_slice
        ciphertext = dest_out.encrypt(plaintext)
        ciphertext.should_not eq plaintext
        ciphertext.size.should be > plaintext.size

        decrypted = dest_in.decrypt(ciphertext)
        decrypted.should_not be_nil
        decrypted.not_nil!.should eq plaintext
      end

      it "encryption adds overhead" do
        dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
        plaintext = "test".to_slice
        ciphertext = dest.encrypt(plaintext)
        ciphertext.size.should be > plaintext.size
      end

      it "different encryptions produce different ciphertext (random IV)" do
        dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
        plaintext = "test data".to_slice
        c1 = dest.encrypt(plaintext)
        c2 = dest.encrypt(plaintext)
        c1.should_not eq c2
      end

      it "wrong identity cannot decrypt" do
        dest1 = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
        dest2 = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)

        plaintext = "Secret".to_slice
        ciphertext = dest1.encrypt(plaintext)
        decrypted = dest2.decrypt(ciphertext)
        decrypted.should be_nil
      end

      it "handles empty plaintext" do
        dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
        plaintext = Bytes.empty
        ciphertext = dest.encrypt(plaintext)
        decrypted = dest.decrypt(ciphertext)
        decrypted.should_not be_nil
        decrypted.not_nil!.should eq plaintext
      end

      it "100 random encrypt/decrypt roundtrips" do
        dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
        100.times do
          size = Random::Secure.rand(1..200)
          plaintext = Random::Secure.random_bytes(size)
          ciphertext = dest.encrypt(plaintext)
          decrypted = dest.decrypt(ciphertext)
          decrypted.should_not be_nil
          decrypted.not_nil!.should eq plaintext
        end
      end
    end

    describe "GROUP destination" do
      it "encrypt/decrypt roundtrip" do
        dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::GROUP, "testapp", register: false)
        dest.create_keys

        plaintext = "Group secret".to_slice
        ciphertext = dest.encrypt(plaintext)
        ciphertext.should_not eq plaintext

        decrypted = dest.decrypt(ciphertext)
        decrypted.should_not be_nil
        decrypted.not_nil!.should eq plaintext
      end

      it "raises encrypt without key" do
        dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::GROUP, "testapp", register: false)
        expect_raises(ArgumentError, /No private key/) do
          dest.encrypt("test".to_slice)
        end
      end

      it "raises decrypt without key" do
        dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::GROUP, "testapp", register: false)
        expect_raises(ArgumentError, /No private key/) do
          dest.decrypt("test".to_slice)
        end
      end

      it "shared GROUP key encrypt/decrypt" do
        dest1 = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::GROUP, "testapp", register: false)
        dest1.create_keys
        key = dest1.get_private_key

        dest2 = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::GROUP, "testapp", register: false)
        dest2.load_private_key(key)

        plaintext = "Shared group message".to_slice
        ciphertext = dest1.encrypt(plaintext)
        decrypted = dest2.decrypt(ciphertext)
        decrypted.should_not be_nil
        decrypted.not_nil!.should eq plaintext
      end

      it "50 random GROUP encrypt/decrypt roundtrips" do
        dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::GROUP, "testapp", register: false)
        dest.create_keys

        50.times do
          size = Random::Secure.rand(1..200)
          plaintext = Random::Secure.random_bytes(size)
          ciphertext = dest.encrypt(plaintext)
          decrypted = dest.decrypt(ciphertext)
          decrypted.should_not be_nil
          decrypted.not_nil!.should eq plaintext
        end
      end
    end
  end

  # ─── Signing ────────────────────────────────────────────────────────
  describe "#sign" do
    it "signs with SINGLE destination" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      message = "Sign this".to_slice
      signature = dest.sign(message)
      signature.should_not be_nil
      signature.not_nil!.size.should eq(RNS::Identity::SIGLENGTH // 8)
    end

    it "signature can be verified by identity" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      message = "Verify this".to_slice
      signature = dest.sign(message).not_nil!
      dest.identity.not_nil!.validate(signature, message).should be_true
    end

    it "returns nil for PLAIN destination" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
      dest.sign("test".to_slice).should be_nil
    end

    it "returns nil for GROUP destination" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::GROUP, "testapp", register: false)
      dest.sign("test".to_slice).should be_nil
    end
  end

  # ─── Default app data ──────────────────────────────────────────────
  describe "default app data" do
    it "sets bytes app data" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      data = "app data".to_slice
      dest.set_default_app_data(data)
      dest.default_app_data.should eq data
    end

    it "sets callable app data" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.set_default_app_data(->{ "dynamic".to_slice.as(Bytes?) })
      dest.default_app_data.should_not be_nil
    end

    it "clears app data" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.set_default_app_data("data".to_slice)
      dest.clear_default_app_data
      dest.default_app_data.should be_nil
    end
  end

  # ─── Announce ───────────────────────────────────────────────────────
  describe "#announce" do
    it "creates announce packet for SINGLE IN destination" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      packet = dest.announce(send: false)
      packet.should_not be_nil
      pkt = packet.not_nil!
      pkt.packet_type.should eq RNS::Packet::ANNOUNCE
      pkt.context.should eq RNS::Packet::NONE
    end

    it "announce data contains public key" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      packet = dest.announce(send: false).not_nil!
      pub_key = dest.identity.not_nil!.get_public_key
      # The announce data starts with the public key
      packet.data[0, pub_key.size].should eq pub_key
    end

    it "announce data contains name_hash" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      packet = dest.announce(send: false).not_nil!
      pub_key_size = dest.identity.not_nil!.get_public_key.size
      name_hash_size = RNS::Identity::NAME_HASH_LENGTH // 8
      # name_hash follows the public key
      packet.data[pub_key_size, name_hash_size].should eq dest.name_hash
    end

    it "announce data has correct structure" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      packet = dest.announce(send: false).not_nil!

      pub_key_size = RNS::Identity::KEYSIZE // 8  # 64 bytes
      name_hash_size = RNS::Identity::NAME_HASH_LENGTH // 8  # 10 bytes
      random_hash_size = 10
      signature_size = RNS::Identity::SIGLENGTH // 8  # 64 bytes

      # Without ratchet: pub_key(64) + name_hash(10) + random_hash(10) + signature(64) = 148
      expected_min_size = pub_key_size + name_hash_size + random_hash_size + signature_size
      packet.data.size.should eq expected_min_size
    end

    it "announce includes app_data when provided" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      app_data = "my app data".to_slice
      packet = dest.announce(app_data: app_data, send: false).not_nil!

      pub_key_size = RNS::Identity::KEYSIZE // 8
      name_hash_size = RNS::Identity::NAME_HASH_LENGTH // 8
      random_hash_size = 10
      signature_size = RNS::Identity::SIGLENGTH // 8

      expected_size = pub_key_size + name_hash_size + random_hash_size + signature_size + app_data.size
      packet.data.size.should eq expected_size

      # app_data is at the end
      packet.data[(packet.data.size - app_data.size)..].should eq app_data
    end

    it "announce uses default app_data when none provided" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      default_data = "default data".to_slice
      dest.set_default_app_data(default_data)

      packet = dest.announce(send: false).not_nil!
      # app_data at end of data
      packet.data[(packet.data.size - default_data.size)..].should eq default_data
    end

    it "announce uses callable default app_data" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      call_data = "callable data".to_slice
      dest.set_default_app_data(->{ call_data.as(Bytes?) })

      packet = dest.announce(send: false).not_nil!
      packet.data[(packet.data.size - call_data.size)..].should eq call_data
    end

    it "announce sets context to PATH_RESPONSE when path_response is true" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      packet = dest.announce(path_response: true, send: false).not_nil!
      packet.context.should eq RNS::Packet::PATH_RESPONSE
    end

    it "raises when announcing GROUP destination" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::GROUP, "testapp", register: false)
      expect_raises(RNS::TypeError, /Only SINGLE/) do
        dest.announce(send: false)
      end
    end

    it "raises when announcing OUT destination" do
      identity = RNS::Identity.new
      dest = RNS::Destination.new(identity, RNS::Destination::OUT, RNS::Destination::SINGLE, "testapp", register: false)
      expect_raises(RNS::TypeError, /Only IN/) do
        dest.announce(send: false)
      end
    end

    it "announce data signature is valid" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      identity = dest.identity.not_nil!
      packet = dest.announce(send: false).not_nil!

      pub_key_size = RNS::Identity::KEYSIZE // 8
      name_hash_size = RNS::Identity::NAME_HASH_LENGTH // 8
      random_hash_size = 10
      signature_size = RNS::Identity::SIGLENGTH // 8

      pub_key = packet.data[0, pub_key_size]
      name_hash = packet.data[pub_key_size, name_hash_size]
      random_hash = packet.data[pub_key_size + name_hash_size, random_hash_size]
      signature = packet.data[pub_key_size + name_hash_size + random_hash_size, signature_size]

      # Reconstruct signed data: hash + public_key + name_hash + random_hash
      signed_io = IO::Memory.new
      signed_io.write(dest.hash)
      signed_io.write(pub_key)
      signed_io.write(name_hash)
      signed_io.write(random_hash)

      identity.validate(signature, signed_io.to_slice).should be_true
    end

    it "two announces produce different data (random hash)" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      p1 = dest.announce(send: false).not_nil!
      p2 = dest.announce(send: false).not_nil!
      p1.data.should_not eq p2.data
    end
  end

  # ─── Ratchet support ───────────────────────────────────────────────
  describe "ratchets" do
    it "enable_ratchets creates new ratchet file" do
      Dir.cd(Dir.tempdir) do
        ratchet_path = File.join(Dir.tempdir, "test_ratchets_#{Random::Secure.hex(4)}")
        begin
          dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
          dest.enable_ratchets(ratchet_path).should be_true
          dest.ratchets.should_not be_nil
          dest.ratchets_path.should eq ratchet_path
          File.exists?(ratchet_path).should be_true
        ensure
          File.delete(ratchet_path) if File.exists?(ratchet_path)
        end
      end
    end

    it "rotate_ratchets adds a new ratchet" do
      ratchet_path = File.join(Dir.tempdir, "test_ratchets_#{Random::Secure.hex(4)}")
      begin
        dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
        dest.enable_ratchets(ratchet_path)
        dest.rotate_ratchets.should be_true
        dest.ratchets.not_nil!.size.should eq 1
      ensure
        File.delete(ratchet_path) if File.exists?(ratchet_path)
      end
    end

    it "rotate_ratchets respects interval" do
      ratchet_path = File.join(Dir.tempdir, "test_ratchets_#{Random::Secure.hex(4)}")
      begin
        dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
        dest.enable_ratchets(ratchet_path)
        dest.rotate_ratchets
        initial_count = dest.ratchets.not_nil!.size

        # Second rotate within interval shouldn't add a new ratchet
        dest.rotate_ratchets
        dest.ratchets.not_nil!.size.should eq initial_count
      ensure
        File.delete(ratchet_path) if File.exists?(ratchet_path)
      end
    end

    it "enforce_ratchets returns true when ratchets enabled" do
      ratchet_path = File.join(Dir.tempdir, "test_ratchets_#{Random::Secure.hex(4)}")
      begin
        dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
        dest.enable_ratchets(ratchet_path)
        dest.enforce_ratchets.should be_true
      ensure
        File.delete(ratchet_path) if File.exists?(ratchet_path)
      end
    end

    it "enforce_ratchets returns false when ratchets not enabled" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.enforce_ratchets.should be_false
    end

    it "set_retained_ratchets updates the value" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.set_retained_ratchets(100).should be_true
      dest.retained_ratchets.should eq 100
    end

    it "set_retained_ratchets rejects zero" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.set_retained_ratchets(0).should be_false
    end

    it "set_retained_ratchets rejects negative" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.set_retained_ratchets(-1).should be_false
    end

    it "set_ratchet_interval updates the value" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.set_ratchet_interval(300).should be_true
      dest.ratchet_interval.should eq 300
    end

    it "set_ratchet_interval rejects zero" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      dest.set_ratchet_interval(0).should be_false
    end

    it "rotate_ratchets raises when ratchets not enabled" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      expect_raises(IO::Error, /ratchets are not enabled/) do
        dest.rotate_ratchets
      end
    end

    it "ratchet file persists and reloads" do
      ratchet_path = File.join(Dir.tempdir, "test_ratchets_#{Random::Secure.hex(4)}")
      begin
        # Create destination with ratchets and rotate
        dest1 = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
        identity = dest1.identity.not_nil!
        dest1.enable_ratchets(ratchet_path)
        dest1.rotate_ratchets

        ratchet_count = dest1.ratchets.not_nil!.size
        ratchet_count.should be > 0

        # Create a new destination with the same identity and reload ratchets
        dest2 = RNS::Destination.new(identity, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp",
          [identity.hexhash.not_nil!], register: false)
        dest2.enable_ratchets(ratchet_path)

        dest2.ratchets.should_not be_nil
        dest2.ratchets.not_nil!.size.should eq ratchet_count
      ensure
        File.delete(ratchet_path) if File.exists?(ratchet_path)
      end
    end
  end

  # ─── Receive ────────────────────────────────────────────────────────
  describe "#receive" do
    it "calls packet callback for DATA packets" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      received_data : Bytes? = nil

      dest.set_packet_callback(->(data : Bytes, pkt : RNS::Packet) {
        received_data = data
        nil
      })

      plaintext = "Hello".to_slice
      ciphertext = dest.encrypt(plaintext)

      # Create a packet with encrypted data (simulate received packet)
      stub = RNS::Destination::Stub.new(hash: dest.hash, type: RNS::Destination::SINGLE)
      packet = RNS::Packet.new(stub, ciphertext, packet_type: RNS::Packet::DATA)

      dest.receive(packet).should be_true
      received_data.should_not be_nil
      received_data.not_nil!.should eq plaintext
    end

    it "returns false when decryption fails" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      # Create garbage ciphertext
      garbage = Random::Secure.random_bytes(100)
      stub = RNS::Destination::Stub.new(hash: dest.hash, type: RNS::Destination::SINGLE)
      packet = RNS::Packet.new(stub, garbage, packet_type: RNS::Packet::DATA)

      dest.receive(packet).should be_false
    end

    it "PLAIN destination receives plaintext directly" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
      received_data : Bytes? = nil

      dest.set_packet_callback(->(data : Bytes, pkt : RNS::Packet) {
        received_data = data
        nil
      })

      plaintext = "Plain data".to_slice
      stub = RNS::Destination::Stub.new(hash: dest.hash, type: RNS::Destination::PLAIN)
      packet = RNS::Packet.new(stub, plaintext, packet_type: RNS::Packet::DATA)

      dest.receive(packet).should be_true
      received_data.should_not be_nil
      received_data.not_nil!.should eq plaintext
    end
  end

  # ─── Transport integration ─────────────────────────────────────────
  describe "Transport integration" do
    it "registers destination with Transport" do
      RNS::Transport.clear_destinations
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp")
      RNS::Transport.destinations.size.should eq 1
      RNS::Transport.destinations[0].should eq dest
    end

    it "deregisters destination from Transport" do
      RNS::Transport.clear_destinations
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp")
      RNS::Transport.deregister_destination(dest)
      RNS::Transport.destinations.should be_empty
    end

    it "multiple destinations register" do
      RNS::Transport.clear_destinations
      dest1 = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "app1")
      dest2 = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "app2")
      RNS::Transport.destinations.size.should eq 2
    end
  end

  # ─── DestinationInterface compliance ────────────────────────────────
  describe "DestinationInterface" do
    it "Destination includes DestinationInterface" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
      dest.is_a?(RNS::Destination::DestinationInterface).should be_true
    end

    it "can be used as DestinationInterface" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::PLAIN, "testapp", register: false)
      iface : RNS::Destination::DestinationInterface = dest
      iface.hash.should eq dest.hash
      iface.type.should eq dest.type
      iface.encrypt("test".to_slice).should eq "test".to_slice # PLAIN passthrough
    end
  end

  # ─── Stress tests ──────────────────────────────────────────────────
  describe "stress tests" do
    it "50 destination creation roundtrips" do
      50.times do |i|
        dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "stresstest", ["aspect#{i}"], register: false)
        dest.hash.size.should eq(RNS::Reticulum::TRUNCATED_HASHLENGTH // 8)
        dest.identity.should_not be_nil
        dest.name.should start_with("stresstest.aspect#{i}")
      end
    end

    it "20 announce generation roundtrips" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      20.times do
        packet = dest.announce(send: false)
        packet.should_not be_nil
        packet.not_nil!.packet_type.should eq RNS::Packet::ANNOUNCE
      end
    end
  end
end
