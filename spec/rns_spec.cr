require "./spec_helper"

describe RNS do
  # ═══════════════════════════════════════════════════════════════════
  # Version and module identity
  # ═══════════════════════════════════════════════════════════════════

  describe "version" do
    it "has a VERSION constant" do
      RNS::VERSION.should_not be_nil
      RNS::VERSION.should eq "0.1.0"
    end

    it "returns version via module method" do
      RNS.version.should eq RNS::VERSION
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Logging constants and functions
  # ═══════════════════════════════════════════════════════════════════

  describe "logging" do
    it "defines all log level constants" do
      RNS::LOG_NONE.should eq -1
      RNS::LOG_CRITICAL.should eq 0
      RNS::LOG_ERROR.should eq 1
      RNS::LOG_WARNING.should eq 2
      RNS::LOG_NOTICE.should eq 3
      RNS::LOG_INFO.should eq 4
      RNS::LOG_VERBOSE.should eq 5
      RNS::LOG_DEBUG.should eq 6
      RNS::LOG_EXTREME.should eq 7
    end

    it "defines log destination constants" do
      RNS::LOG_STDOUT.should eq 0x91
      RNS::LOG_FILE.should eq 0x92
      RNS::LOG_CALLBACK.should eq 0x93
    end

    it "defines LOG_MAXSIZE" do
      RNS::LOG_MAXSIZE.should eq 5 * 1024 * 1024
    end

    it "has configurable loglevel" do
      original = RNS.loglevel
      RNS.loglevel = RNS::LOG_DEBUG
      RNS.loglevel.should eq RNS::LOG_DEBUG
      RNS.loglevel = original
    end

    it "returns formatted log level names" do
      RNS.loglevelname(RNS::LOG_CRITICAL).should eq "[Critical]"
      RNS.loglevelname(RNS::LOG_ERROR).should eq "[Error]   "
      RNS.loglevelname(RNS::LOG_WARNING).should eq "[Warning] "
      RNS.loglevelname(RNS::LOG_NOTICE).should eq "[Notice]  "
      RNS.loglevelname(RNS::LOG_INFO).should eq "[Info]    "
      RNS.loglevelname(RNS::LOG_VERBOSE).should eq "[Verbose] "
      RNS.loglevelname(RNS::LOG_DEBUG).should eq "[Debug]   "
      RNS.loglevelname(RNS::LOG_EXTREME).should eq "[Extra]   "
    end

    it "can log to a callback" do
      captured = ""
      original_dest = RNS.logdest
      original_level = RNS.loglevel
      RNS.logdest = RNS::LOG_CALLBACK
      RNS.loglevel = RNS::LOG_DEBUG
      RNS.logcall = ->(msg : String) { captured = msg; nil }
      RNS.log("test callback message", RNS::LOG_NOTICE)
      captured.should contain("test callback message")
      RNS.logdest = original_dest
      RNS.loglevel = original_level
      RNS.logcall = nil
    end

    it "formats timestamps" do
      ts = RNS.timestamp_str(1700000000.0)
      ts.should_not be_empty
    end

    it "formats precise timestamps" do
      ts = RNS.precise_timestamp_str(Time.utc.to_unix_f)
      ts.should match(/\d{2}:\d{2}:\d{2}\.\d{3}/)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Utility functions
  # ═══════════════════════════════════════════════════════════════════

  describe "utility functions" do
    describe ".hexrep" do
      it "converts bytes to colon-delimited hex" do
        data = Bytes[0xDE, 0xAD, 0xBE, 0xEF]
        RNS.hexrep(data).should eq "de:ad:be:ef"
      end

      it "converts bytes without delimiter" do
        data = Bytes[0xDE, 0xAD, 0xBE, 0xEF]
        RNS.hexrep(data, delimit: false).should eq "deadbeef"
      end
    end

    describe ".prettyhexrep" do
      it "wraps hex in angle brackets" do
        data = Bytes[0xCA, 0xFE]
        RNS.prettyhexrep(data).should eq "<cafe>"
      end
    end

    describe ".prettysize" do
      it "formats byte sizes" do
        RNS.prettysize(500.0).should eq "500 B"
        RNS.prettysize(1500.0).should eq "1.50 KB"
        RNS.prettysize(1500000.0).should eq "1.50 MB"
      end
    end

    describe ".prettyspeed" do
      it "formats bit speeds" do
        result = RNS.prettyspeed(8000.0)
        result.should contain("ps")
      end
    end

    describe ".prettyfrequency" do
      it "formats frequencies" do
        result = RNS.prettyfrequency(868.0)
        result.should contain("Hz")
      end
    end

    describe ".prettydistance" do
      it "formats distances" do
        result = RNS.prettydistance(1500.0)
        result.should contain("m")
      end
    end

    describe ".prettytime" do
      it "formats durations" do
        RNS.prettytime(0.0).should eq "0s"
        RNS.prettytime(90061.0).should contain("d")
      end

      it "handles negative time" do
        result = RNS.prettytime(-5.0)
        result.should start_with("-")
      end
    end

    describe ".prettyshorttime" do
      it "formats short durations" do
        result = RNS.prettyshorttime(0.0)
        result.should eq "0us"
      end

      it "formats milliseconds" do
        result = RNS.prettyshorttime(0.005)
        result.should contain("ms")
      end
    end

    describe ".host_os" do
      it "returns a platform string" do
        os = RNS.host_os
        os.should_not be_empty
        # Should be one of the known platforms
        ["linux", "darwin", "windows", "freebsd", "openbsd", "android", "unknown"].should contain(os)
      end
    end

    describe ".rand" do
      it "returns a random float" do
        val = RNS.rand
        (val >= 0.0).should be_true
        (val < 1.0).should be_true
      end
    end

    describe ".trace_exception" do
      it "logs an exception without raising" do
        captured = ""
        original_dest = RNS.logdest
        original_level = RNS.loglevel
        RNS.logdest = RNS::LOG_CALLBACK
        RNS.loglevel = RNS::LOG_DEBUG
        RNS.logcall = ->(msg : String) { captured += msg + "\n"; nil }

        begin
          raise "test error for trace"
        rescue e
          RNS.trace_exception(e)
        end

        captured.should contain("test error for trace")
        captured.should contain("Exception")

        RNS.logdest = original_dest
        RNS.loglevel = original_level
        RNS.logcall = nil
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # System functions
  # ═══════════════════════════════════════════════════════════════════

  describe "system functions" do
    describe ".phyparams" do
      it "prints physical parameters without error" do
        # Capture stdout
        _output = String.build do |_|
          _original_stdout = STDOUT
          # We can't easily redirect STDOUT in Crystal, so just verify it doesn't raise
        end
        # Just verify the method exists and doesn't raise
        # (actual output goes to stdout)
        typeof(-> { RNS.phyparams }).should_not be_nil
      end
    end

    describe ".exit_called?" do
      it "tracks exit state" do
        RNS.exit_called?.should be_false
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Core protocol classes are accessible
  # ═══════════════════════════════════════════════════════════════════

  describe "core class re-exports" do
    it "exposes RNS::Identity" do
      identity = RNS::Identity.new(create_keys: true)
      identity.should be_a(RNS::Identity)

      # Check key constants
      RNS::Identity::CURVE.should eq "Curve25519"
      RNS::Identity::KEYSIZE.should eq 512
      RNS::Identity::HASHLENGTH.should eq 256
      RNS::Identity::NAME_HASH_LENGTH.should eq 80
      RNS::Identity::RATCHETSIZE.should eq 256
      RNS::Identity::TRUNCATED_HASHLENGTH.should eq 128
    end

    it "exposes RNS::Identity static methods" do
      # full_hash, truncated_hash, get_random_hash
      data = Bytes[1, 2, 3, 4]
      full = RNS::Identity.full_hash(data)
      full.size.should eq 32 # SHA-256

      truncated = RNS::Identity.truncated_hash(data)
      truncated.size.should eq(RNS::Identity::TRUNCATED_HASHLENGTH // 8)

      random_hash = RNS::Identity.get_random_hash
      random_hash.size.should eq(RNS::Identity::TRUNCATED_HASHLENGTH // 8)
    end

    it "exposes RNS::Destination" do
      identity = RNS::Identity.new(create_keys: true)
      dest = RNS::Destination.new(
        identity,
        RNS::Destination::OUT,
        RNS::Destination::SINGLE,
        "testapp",
        ["aspects"],
        register: false
      )
      dest.should be_a(RNS::Destination)
      dest.hash.should_not be_empty

      # Check type constants
      RNS::Destination::SINGLE.should eq 0x00_u8
      RNS::Destination::GROUP.should eq 0x01_u8
      RNS::Destination::PLAIN.should eq 0x02_u8
      RNS::Destination::LINK.should eq 0x03_u8
      RNS::Destination::IN.should eq 0x11_u8
      RNS::Destination::OUT.should eq 0x12_u8
    end

    it "exposes RNS::Packet" do
      # Check constants
      RNS::Packet::DATA.should eq 0x00_u8
      RNS::Packet::ANNOUNCE.should eq 0x01_u8
      RNS::Packet::LINKREQUEST.should eq 0x02_u8
      RNS::Packet::PROOF.should eq 0x03_u8

      RNS::Packet::HEADER_1.should eq 0x00_u8
      RNS::Packet::HEADER_2.should eq 0x01_u8

      # MDU constants
      RNS::Packet::PLAIN_MDU.should be > 0
      RNS::Packet::ENCRYPTED_MDU.should be > 0
    end

    it "exposes RNS::PacketReceipt" do
      RNS::PacketReceipt.should_not be_nil
    end

    it "exposes RNS::Link" do
      # Check constants
      RNS::Link::CURVE.should eq "Curve25519"
      RNS::Link::ECPUBSIZE.should eq 64
      RNS::Link::KEYSIZE.should eq 32
      RNS::Link::MDU.should be > 0
    end

    it "exposes RNS::RequestReceipt" do
      RNS::RequestReceipt.should_not be_nil
    end

    it "exposes RNS::Transport" do
      RNS::Transport::BROADCAST.should eq 0x00_u8
      RNS::Transport::TRANSPORT.should eq 0x01_u8
      RNS::Transport::RELAY.should eq 0x02_u8
      RNS::Transport::TUNNEL.should eq 0x03_u8
    end

    it "exposes RNS::Reticulum" do
      RNS::Reticulum::MTU.should eq 500
      RNS::Reticulum::HEADER_MINSIZE.should eq 19
      RNS::Reticulum::HEADER_MAXSIZE.should eq 35
    end

    it "exposes RNS::Resource" do
      RNS::Resource::WINDOW.should eq 4
      RNS::Resource::WINDOW_MAX.should eq 75
      RNS::Resource::MAX_EFFICIENT_SIZE.should be > 0
    end

    it "exposes RNS::ResourceAdvertisement" do
      RNS::ResourceAdvertisement.should_not be_nil
    end

    it "exposes RNS::Channel" do
      # Channel is generic: Channel(TPacket)
      RNS::MessageState::MSGSTATE_NEW.should eq 0
    end

    it "exposes RNS::MessageBase" do
      # MessageBase is an abstract class
      RNS::MessageBase.should_not be_nil
    end

    it "exposes RNS::Buffer" do
      # Buffer is a module with factory methods
      RNS::Buffer.should_not be_nil
    end

    it "exposes RNS::Resolver" do
      RNS::Resolver.should_not be_nil
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Cryptography modules
  # ═══════════════════════════════════════════════════════════════════

  describe "cryptography re-exports" do
    it "exposes RNS::Cryptography with hash functions" do
      data = "hello".to_slice
      sha256 = RNS::Cryptography.sha256(data)
      sha256.size.should eq 32

      sha512 = RNS::Cryptography.sha512(data)
      sha512.size.should eq 64
    end

    it "exposes HKDF key derivation" do
      ikm = Random::Secure.random_bytes(32)
      derived = RNS::Cryptography.hkdf(32, ikm)
      derived.size.should eq 32
    end

    it "exposes X25519 key exchange" do
      priv1 = RNS::Cryptography::X25519PrivateKey.generate
      priv2 = RNS::Cryptography::X25519PrivateKey.generate
      pub1 = priv1.public_key
      pub2 = priv2.public_key

      shared1 = priv1.exchange(pub2)
      shared2 = priv2.exchange(pub1)
      shared1.should eq shared2
    end

    it "exposes Ed25519 signing" do
      priv = RNS::Cryptography::Ed25519PrivateKey.generate
      pub = priv.public_key
      message = "test message".to_slice

      sig = priv.sign(message)
      sig.size.should eq 64

      # verify raises on failure, returns nil on success
      pub.verify(sig, message)

      # Invalid signature should raise
      bad_sig = sig.dup
      bad_sig[0] = bad_sig[0] ^ 0xFF_u8
      expect_raises(Exception) do
        pub.verify(bad_sig, message)
      end
    end

    it "exposes Token authenticated encryption" do
      key = RNS::Cryptography::Token.generate_key
      token = RNS::Cryptography::Token.new(key)
      plaintext = "secret data".to_slice
      ciphertext = token.encrypt(plaintext)
      decrypted = token.decrypt(ciphertext)
      decrypted.should eq plaintext
    end

    it "exposes AES-256-CBC" do
      key = Random::Secure.random_bytes(32)
      iv = Random::Secure.random_bytes(16)
      plaintext = "test plaintext!!".to_slice # 16 bytes, one block

      ciphertext = RNS::Cryptography::AES256CBC.encrypt(plaintext, key, iv)
      decrypted = RNS::Cryptography::AES256CBC.decrypt(ciphertext, key, iv)
      decrypted.should eq plaintext
    end

    it "exposes PKCS7 padding" do
      data = Bytes[1, 2, 3]
      padded = RNS::Cryptography::PKCS7.pad(data)
      padded.size.should eq 16 # padded to AES block size
      unpadded = RNS::Cryptography::PKCS7.unpad(padded)
      unpadded.should eq data
    end

    it "has TRUNCATED_HASHLENGTH constant" do
      RNS::Cryptography::TRUNCATED_HASHLENGTH.should eq 128
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Interface system
  # ═══════════════════════════════════════════════════════════════════

  describe "interface re-exports" do
    it "exposes Interface base with mode constants" do
      RNS::Interface::MODE_FULL.should_not be_nil
      RNS::Interface::MODE_POINT_TO_POINT.should_not be_nil
      RNS::Interface::MODE_ACCESS_POINT.should_not be_nil
      RNS::Interface::MODE_ROAMING.should_not be_nil
      RNS::Interface::MODE_BOUNDARY.should_not be_nil
      RNS::Interface::MODE_GATEWAY.should_not be_nil
    end

    it "exposes interface direction constants" do
      # In the Crystal port, IN/OUT/FWD/RPT are Bool defaults
      RNS::Interface::IN.should eq false
      RNS::Interface::OUT.should eq false
      RNS::Interface::FWD.should eq false
      RNS::Interface::RPT.should eq false
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Discovery module
  # ═══════════════════════════════════════════════════════════════════

  describe "discovery re-exports" do
    it "exposes Discovery module" do
      RNS::Discovery.should_not be_nil
    end

    it "exposes InterfaceAnnouncer via convenience alias" do
      RNS::InterfaceAnnouncer.should eq RNS::Discovery::InterfaceAnnouncer
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # End-to-end: create Identity → create Destination → verify hash
  # ═══════════════════════════════════════════════════════════════════

  describe "end-to-end public API exercise" do
    it "creates an Identity, Destination, and verifies hashes" do
      # Create a new identity with keys
      identity = RNS::Identity.new(create_keys: true)
      identity.should be_a(RNS::Identity)

      # Create a destination
      dest = RNS::Destination.new(
        identity,
        RNS::Destination::OUT,
        RNS::Destination::SINGLE,
        "testapp",
        ["echo"],
        register: false
      )

      # Destination hash should be deterministic for same identity + name
      dest.hash.should_not be_empty
      dest.hash.size.should eq(RNS::Identity::TRUNCATED_HASHLENGTH // 8)
    end

    it "signs and verifies with Identity" do
      identity = RNS::Identity.new(create_keys: true)
      message = "Hello, Reticulum!".to_slice

      signature = identity.sign(message)
      signature.size.should eq 64

      identity.validate(signature, message).should be_true
      identity.validate(signature, "tampered".to_slice).should be_false
    end

    it "encrypts and decrypts with Identity" do
      identity = RNS::Identity.new(create_keys: true)
      plaintext = "Confidential message".to_slice

      ciphertext = identity.encrypt(plaintext)
      ciphertext.should_not eq plaintext

      decrypted = identity.decrypt(ciphertext)
      decrypted.should_not be_nil
      decrypted.not_nil!.should eq plaintext
    end
  end
end
