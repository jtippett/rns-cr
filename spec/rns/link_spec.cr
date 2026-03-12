require "../spec_helper"

# Helper to create an IN SINGLE destination for link testing
private def create_in_destination(app_name = "test", aspects = ["link"]) : RNS::Destination
  identity = RNS::Identity.new
  RNS::Destination.new(identity, RNS::Destination::IN, RNS::Destination::SINGLE,
    app_name, aspects, register: false)
end

# Helper to create a Resource with a specific hash for testing resource management
private def create_test_resource(link : RNS::Link, hash : Bytes? = nil) : RNS::Resource
  resource = RNS::Resource.new(nil, link, advertise: false)
  resource.hash = hash || Random::Secure.random_bytes(32)
  resource
end

# Helper to create a responder link with fake link_id and completed handshake
private def create_handshaken_link
  owner = create_in_destination
  peer_prv = RNS::Cryptography::X25519PrivateKey.generate
  peer_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
  link = RNS::Link.new(owner: owner, peer_pub_bytes: peer_prv.public_key.public_bytes,
    peer_sig_pub_bytes: peer_sig_prv.public_key.public_bytes)
  fake_id = RNS::Identity.truncated_hash(Random::Secure.random_bytes(32))
  link.set_link_id_bytes(fake_id)
  link.do_handshake
  link
end

describe RNS::Link do
  before_each do
    RNS::Transport.reset
    # Register a dummy interface hash so Transport.outbound can
    # broadcast packets in unit tests (no real I/O occurs).
    RNS::Transport.interfaces << Random::Secure.random_bytes(32)
  end

  # ────────────────────────────────────────────────────────────────────
  #  Constants
  # ────────────────────────────────────────────────────────────────────

  describe "constants" do
    it "defines curve and key size constants" do
      RNS::Link::CURVE.should eq "Curve25519"
      RNS::Link::ECPUBSIZE.should eq 64
      RNS::Link::KEYSIZE.should eq 32
    end

    it "defines MDU" do
      RNS::Link::MDU.should be > 0
      RNS::Link::MDU.should be < RNS::Reticulum::MTU
    end

    it "defines timing constants" do
      RNS::Link::ESTABLISHMENT_TIMEOUT_PER_HOP.should eq 6.0
      RNS::Link::LINK_MTU_SIZE.should eq 3
      RNS::Link::TRAFFIC_TIMEOUT_MIN_MS.should eq 5
      RNS::Link::TRAFFIC_TIMEOUT_FACTOR.should eq 6
      RNS::Link::KEEPALIVE_MAX_RTT.should eq 1.75
      RNS::Link::KEEPALIVE_TIMEOUT_FACTOR.should eq 4
      RNS::Link::STALE_GRACE.should eq 5.0
      RNS::Link::KEEPALIVE_MAX.should eq 360.0
      RNS::Link::KEEPALIVE_MIN.should eq 5.0
      RNS::Link::KEEPALIVE.should eq 360.0
      RNS::Link::STALE_FACTOR.should eq 2
      RNS::Link::STALE_TIME.should eq 720.0
      RNS::Link::WATCHDOG_MAX_SLEEP.should eq 5.0
    end

    it "defines link states" do
      RNS::Link::PENDING.should eq 0x00_u8
      RNS::Link::HANDSHAKE.should eq 0x01_u8
      RNS::Link::ACTIVE.should eq 0x02_u8
      RNS::Link::STALE.should eq 0x03_u8
      RNS::Link::CLOSED.should eq 0x04_u8
    end

    it "defines teardown reasons" do
      RNS::Link::TIMEOUT.should eq 0x01_u8
      RNS::Link::INITIATOR_CLOSED.should eq 0x02_u8
      RNS::Link::DESTINATION_CLOSED.should eq 0x03_u8
    end

    it "defines resource strategies" do
      RNS::Link::ACCEPT_NONE.should eq 0x00_u8
      RNS::Link::ACCEPT_APP.should eq 0x01_u8
      RNS::Link::ACCEPT_ALL.should eq 0x02_u8
      RNS::Link::RESOURCE_STRATEGIES.should eq [0x00_u8, 0x01_u8, 0x02_u8]
    end

    it "defines encryption modes" do
      RNS::Link::MODE_AES128_CBC.should eq 0x00_u8
      RNS::Link::MODE_AES256_CBC.should eq 0x01_u8
      RNS::Link::MODE_AES256_GCM.should eq 0x02_u8
      RNS::Link::MODE_DEFAULT.should eq RNS::Link::MODE_AES256_CBC
      RNS::Link::ENABLED_MODES.should eq [RNS::Link::MODE_AES256_CBC]
    end

    it "defines mode descriptions" do
      RNS::Link::MODE_DESCRIPTIONS[RNS::Link::MODE_AES128_CBC].should eq "AES_128_CBC"
      RNS::Link::MODE_DESCRIPTIONS[RNS::Link::MODE_AES256_CBC].should eq "AES_256_CBC"
    end

    it "defines byte masks" do
      RNS::Link::MTU_BYTEMASK.should eq 0x1FFFFF_u32
      RNS::Link::MODE_BYTEMASK.should eq 0xE0_u8
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Signalling bytes
  # ────────────────────────────────────────────────────────────────────

  describe ".signalling_bytes" do
    it "produces 3 bytes" do
      sb = RNS::Link.signalling_bytes(500_u32, RNS::Link::MODE_AES256_CBC)
      sb.size.should eq 3
    end

    it "encodes MTU in lower bits" do
      sb = RNS::Link.signalling_bytes(500_u32, RNS::Link::MODE_AES256_CBC)
      mtu = ((sb[0].to_u32 << 16) + (sb[1].to_u32 << 8) + sb[2].to_u32) & RNS::Link::MTU_BYTEMASK.to_u32
      mtu.should eq 500
    end

    it "encodes mode in upper bits" do
      sb = RNS::Link.signalling_bytes(500_u32, RNS::Link::MODE_AES256_CBC)
      mode = sb[0] >> 5
      mode.should eq RNS::Link::MODE_AES256_CBC
    end

    it "raises for unsupported mode" do
      expect_raises(RNS::TypeError) do
        RNS::Link.signalling_bytes(500_u32, RNS::Link::MODE_AES128_CBC)
      end
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Responder construction
  # ────────────────────────────────────────────────────────────────────

  describe "responder construction" do
    it "creates a responder link with owner" do
      owner = create_in_destination
      peer_prv = RNS::Cryptography::X25519PrivateKey.generate
      peer_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate

      link = RNS::Link.new(owner: owner, peer_pub_bytes: peer_prv.public_key.public_bytes,
        peer_sig_pub_bytes: peer_sig_prv.public_key.public_bytes)
      link.initiator?.should be_false
      link.status.should eq RNS::Link::PENDING
      link.type.should eq RNS::Destination::LINK
      link.mode.should eq RNS::Link::MODE_DEFAULT
    end

    it "generates X25519 public key bytes" do
      owner = create_in_destination
      peer_prv = RNS::Cryptography::X25519PrivateKey.generate
      peer_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate

      link = RNS::Link.new(owner: owner, peer_pub_bytes: peer_prv.public_key.public_bytes,
        peer_sig_pub_bytes: peer_sig_prv.public_key.public_bytes)
      link.pub_bytes.should_not be_nil
      link.pub_bytes.not_nil!.size.should eq 32
    end

    it "initializes default state" do
      owner = create_in_destination
      peer_prv = RNS::Cryptography::X25519PrivateKey.generate
      peer_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate

      link = RNS::Link.new(owner: owner, peer_pub_bytes: peer_prv.public_key.public_bytes,
        peer_sig_pub_bytes: peer_sig_prv.public_key.public_bytes)
      link.rtt.should be_nil
      link.mtu.should eq RNS::Reticulum::MTU
      link.last_inbound.should eq 0.0
      link.last_outbound.should eq 0.0
      link.tx.should eq 0
      link.rx.should eq 0
      link.resource_strategy.should eq RNS::Link::ACCEPT_NONE
      link.activated_at.should be_nil
      link.teardown_reason.should be_nil
      link.pending_requests.empty?.should be_true
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  ECDH handshake
  # ────────────────────────────────────────────────────────────────────

  describe "ECDH handshake" do
    it "produces matching derived keys on both sides" do
      owner = create_in_destination
      init_prv = RNS::Cryptography::X25519PrivateKey.generate
      init_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate

      resp_link = RNS::Link.new(owner: owner,
        peer_pub_bytes: init_prv.public_key.public_bytes,
        peer_sig_pub_bytes: init_sig_prv.public_key.public_bytes)
      fake_link_id = RNS::Identity.truncated_hash(Random::Secure.random_bytes(32))
      resp_link.set_link_id_bytes(fake_link_id)
      resp_link.do_handshake
      resp_link.status.should eq RNS::Link::HANDSHAKE
      resp_derived = resp_link.derived_key.not_nil!

      resp_pub_bytes = resp_link.pub_bytes.not_nil!
      init_shared = init_prv.exchange(RNS::Cryptography::X25519PublicKey.from_public_bytes(resp_pub_bytes))
      init_derived = RNS::Cryptography.hkdf(length: 64, derive_from: init_shared, salt: fake_link_id, context: nil)
      init_derived.should eq resp_derived
    end

    it "rejects handshake in non-PENDING state" do
      owner = create_in_destination
      peer_prv = RNS::Cryptography::X25519PrivateKey.generate
      peer_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate

      link = RNS::Link.new(owner: owner, peer_pub_bytes: peer_prv.public_key.public_bytes,
        peer_sig_pub_bytes: peer_sig_prv.public_key.public_bytes)
      link.set_link_id_bytes(RNS::Identity.truncated_hash(Random::Secure.random_bytes(32)))
      link.do_handshake
      link.status.should eq RNS::Link::HANDSHAKE
      link.do_handshake # No-op
      link.status.should eq RNS::Link::HANDSHAKE
    end

    it "derives 64-byte key for AES256-CBC mode" do
      link = create_handshaken_link
      link.derived_key.not_nil!.size.should eq 64
    end

    it "produces different keys for different link IDs" do
      owner = create_in_destination
      peer_prv = RNS::Cryptography::X25519PrivateKey.generate
      peer_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate

      link1 = RNS::Link.new(owner: owner, peer_pub_bytes: peer_prv.public_key.public_bytes,
        peer_sig_pub_bytes: peer_sig_prv.public_key.public_bytes)
      link2 = RNS::Link.new(owner: owner, peer_pub_bytes: peer_prv.public_key.public_bytes,
        peer_sig_pub_bytes: peer_sig_prv.public_key.public_bytes)

      link1.set_link_id_bytes(RNS::Identity.truncated_hash(Random::Secure.random_bytes(32)))
      link2.set_link_id_bytes(RNS::Identity.truncated_hash(Random::Secure.random_bytes(32)))
      link1.do_handshake
      link2.do_handshake
      link1.derived_key.not_nil!.should_not eq link2.derived_key.not_nil!
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Encrypt / Decrypt roundtrip
  # ────────────────────────────────────────────────────────────────────

  describe "encrypt/decrypt" do
    it "roundtrips data" do
      link = create_handshaken_link
      pt = "Hello, encrypted link!".to_slice
      ct = link.encrypt_data(pt)
      ct.should_not eq pt
      link.decrypt_data(ct).not_nil!.should eq pt
    end

    it "both sides can encrypt/decrypt each other's data" do
      owner = create_in_destination
      init_prv = RNS::Cryptography::X25519PrivateKey.generate
      init_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate

      resp_link = RNS::Link.new(owner: owner,
        peer_pub_bytes: init_prv.public_key.public_bytes,
        peer_sig_pub_bytes: init_sig_prv.public_key.public_bytes)
      fake_link_id = RNS::Identity.truncated_hash(Random::Secure.random_bytes(32))
      resp_link.set_link_id_bytes(fake_link_id)
      resp_link.do_handshake

      resp_pub_bytes = resp_link.pub_bytes.not_nil!
      init_shared = init_prv.exchange(RNS::Cryptography::X25519PublicKey.from_public_bytes(resp_pub_bytes))
      init_derived = RNS::Cryptography.hkdf(length: 64, derive_from: init_shared, salt: fake_link_id, context: nil)

      init_token = RNS::Cryptography::Token.new(init_derived)
      resp_token = RNS::Cryptography::Token.new(resp_link.derived_key.not_nil!)

      msg1 = "From initiator".to_slice
      resp_token.decrypt(init_token.encrypt(msg1)).should eq msg1

      msg2 = "From responder".to_slice
      init_token.decrypt(resp_token.encrypt(msg2)).should eq msg2
    end

    it "encrypts empty data" do
      link = create_handshaken_link
      ct = link.encrypt_data(Bytes.empty)
      link.decrypt_data(ct).not_nil!.should eq Bytes.empty
    end

    it "produces different ciphertext for same plaintext" do
      link = create_handshaken_link
      pt = "Same message".to_slice
      link.encrypt_data(pt).should_not eq link.encrypt_data(pt)
    end

    it "returns nil for tampered ciphertext" do
      link = create_handshaken_link
      ct = link.encrypt_data("test".to_slice)
      ct[ct.size // 2] ^= 0xFF_u8
      link.decrypt_data(ct).should be_nil
    end

    it "100 random roundtrips" do
      link = create_handshaken_link
      100.times do
        data = Random::Secure.random_bytes(Random::Secure.rand(1..256))
        link.decrypt_data(link.encrypt_data(data)).not_nil!.should eq data
      end
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Sign / Validate
  # ────────────────────────────────────────────────────────────────────

  describe "sign/validate" do
    it "signs with link ephemeral key and produces 64-byte signature" do
      link = create_handshaken_link
      link.sign("test".to_slice).size.should eq 64
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  State transitions
  # ────────────────────────────────────────────────────────────────────

  describe "state transitions" do
    it "starts as PENDING" do
      owner = create_in_destination
      peer_prv = RNS::Cryptography::X25519PrivateKey.generate
      peer_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
      link = RNS::Link.new(owner: owner, peer_pub_bytes: peer_prv.public_key.public_bytes,
        peer_sig_pub_bytes: peer_sig_prv.public_key.public_bytes)
      link.status.should eq RNS::Link::PENDING
    end

    it "HANDSHAKE after do_handshake" do
      link = create_handshaken_link
      link.status.should eq RNS::Link::HANDSHAKE
    end

    it "CLOSED on teardown" do
      link = create_handshaken_link
      link.teardown
      link.status.should eq RNS::Link::CLOSED
    end

    it "sets teardown_reason" do
      link = create_handshaken_link
      link.teardown
      link.teardown_reason.should eq RNS::Link::DESTINATION_CLOSED
    end

    it "purges keys on link_closed" do
      link = create_handshaken_link
      link.teardown
      link.prv_key.should be_nil
      link.pub_key.should be_nil
      link.shared_key.should be_nil
      link.derived_key.should be_nil
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Timing helpers
  # ────────────────────────────────────────────────────────────────────

  describe "timing helpers" do
    it "tracks outbound timestamps" do
      link = create_handshaken_link
      link.last_outbound.should eq 0.0
      link.had_outbound
      link.last_outbound.should be > 0
      link.last_data.should be > 0
    end

    it "tracks keepalive vs data" do
      link = create_handshaken_link
      link.had_outbound(is_keepalive: true)
      link.last_keepalive.should be > 0
      link.last_data.should eq 0.0
    end

    it "reports no_inbound_for" do
      link = create_handshaken_link
      link.no_inbound_for.should be >= 0
    end

    it "get_age nil when not activated" do
      link = create_handshaken_link
      link.get_age.should be_nil
    end

    it "get_age positive when activated" do
      link = create_handshaken_link
      link.activated_at = Time.utc.to_unix_f
      link.get_age.not_nil!.should be >= 0
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Keepalive
  # ────────────────────────────────────────────────────────────────────

  describe "keepalive" do
    it "updates from RTT" do
      link = create_handshaken_link
      link.rtt = 0.5
      link.update_keepalive
      link.keepalive.should be >= RNS::Link::KEEPALIVE_MIN
      link.keepalive.should be <= RNS::Link::KEEPALIVE_MAX
    end

    it "clamps to min for fast RTT" do
      link = create_handshaken_link
      link.rtt = 0.001
      link.update_keepalive
      link.keepalive.should eq RNS::Link::KEEPALIVE_MIN
    end

    it "clamps to max for slow RTT" do
      link = create_handshaken_link
      link.rtt = 100.0
      link.update_keepalive
      link.keepalive.should eq RNS::Link::KEEPALIVE_MAX
    end

    it "sets stale_time = keepalive * STALE_FACTOR" do
      link = create_handshaken_link
      link.rtt = 1.0
      link.update_keepalive
      link.stale_time.should eq link.keepalive * RNS::Link::STALE_FACTOR
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Callbacks
  # ────────────────────────────────────────────────────────────────────

  describe "callbacks" do
    it "sets link_established" do
      link = create_handshaken_link
      link.set_link_established_callback(->(_l : RNS::Link) { nil })
      link.callbacks.link_established.should_not be_nil
    end

    it "calls link_closed on teardown" do
      owner = create_in_destination
      peer_prv = RNS::Cryptography::X25519PrivateKey.generate
      peer_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
      closed = false
      link = RNS::Link.new(owner: owner, peer_pub_bytes: peer_prv.public_key.public_bytes,
        peer_sig_pub_bytes: peer_sig_prv.public_key.public_bytes,
        closed_callback: ->(_l : RNS::Link) { closed = true; nil })
      link.teardown
      closed.should be_true
    end

    it "sets packet callback" do
      link = create_handshaken_link
      link.set_packet_callback(->(_d : Bytes, _p : RNS::Packet) { nil })
      link.callbacks.packet.should_not be_nil
    end

    it "sets remote_identified callback" do
      link = create_handshaken_link
      link.set_remote_identified_callback(->(_l : RNS::Link, _i : RNS::Identity) { nil })
      link.callbacks.remote_identified.should_not be_nil
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Resource strategy
  # ────────────────────────────────────────────────────────────────────

  describe "resource strategy" do
    it "defaults to ACCEPT_NONE" do
      link = create_handshaken_link
      link.resource_strategy.should eq RNS::Link::ACCEPT_NONE
    end

    it "can be set to ACCEPT_ALL" do
      link = create_handshaken_link
      link.set_resource_strategy(RNS::Link::ACCEPT_ALL)
      link.resource_strategy.should eq RNS::Link::ACCEPT_ALL
    end

    it "raises for unsupported strategy" do
      link = create_handshaken_link
      expect_raises(RNS::TypeError) { link.set_resource_strategy(0xFF_u8) }
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Phy stats
  # ────────────────────────────────────────────────────────────────────

  describe "phy stats" do
    it "returns nil when not tracking" do
      link = create_handshaken_link
      link.rssi = -80.0
      link.get_rssi.should be_nil
    end

    it "returns values when tracking" do
      link = create_handshaken_link
      link.track_phy_stats(true)
      link.rssi = -80.0
      link.snr = 10.5
      link.q = 0.95
      link.get_rssi.should eq -80.0
      link.get_snr.should eq 10.5
      link.get_q.should eq 0.95
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Status-gated getters
  # ────────────────────────────────────────────────────────────────────

  describe "status-gated getters" do
    it "nil when not active" do
      link = create_handshaken_link
      link.get_mtu.should be_nil
      link.get_mdu.should be_nil
      link.get_expected_rate.should be_nil
    end

    it "values when active" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      link.get_mtu.should eq RNS::Reticulum::MTU
      link.get_mdu.should_not be_nil
    end

    it "establishment rate in bits/sec" do
      link = create_handshaken_link
      link.establishment_rate = 100.0
      link.get_establishment_rate.should eq 800.0
    end

    it "nil establishment rate when unset" do
      link = create_handshaken_link
      link.get_establishment_rate.should be_nil
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  DestinationInterface / LinkLike compliance
  # ────────────────────────────────────────────────────────────────────

  describe "DestinationInterface" do
    it "implements hash, type, encrypt" do
      link = create_handshaken_link
      link.hash.size.should eq 16
      link.type.should eq RNS::Destination::LINK
      link.encrypt("test".to_slice).size.should be > 4
    end

    it "can be used as Packet destination" do
      link = create_handshaken_link
      packet = RNS::Packet.new(link, "hello".to_slice, context: RNS::Packet::KEEPALIVE)
      packet.destination.should_not be_nil
    end
  end

  describe "LinkLike compliance" do
    it "implements all methods" do
      link = create_handshaken_link
      link.link_id.should be_a(Bytes)
      link.initiator?.should be_a(Bool)
      link.status.should be_a(UInt8)
      link.destination_hash.should be_a(Bytes)
      link.expected_hops.should be_a(Int32)
    end

    it "can be assigned to LinkLike" do
      link = create_handshaken_link
      link_like : RNS::LinkLike = link
      link_like.status.should eq RNS::Link::HANDSHAKE
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  link_id_from_lr_packet
  # ────────────────────────────────────────────────────────────────────

  describe ".link_id_from_lr_packet" do
    it "produces 16-byte truncated hash" do
      dest = create_in_destination
      data = Random::Secure.random_bytes(64)
      pkt = RNS::Packet.new(dest, data, packet_type: RNS::Packet::LINKREQUEST)
      pkt.pack
      RNS::Link.link_id_from_lr_packet(pkt).size.should eq 16
    end

    it "strips signalling bytes from hash" do
      dest = create_in_destination
      base = Random::Secure.random_bytes(64)
      data_with = Bytes.new(67)
      base.copy_to(data_with)
      data_with[64] = 0x20_u8; data_with[65] = 0x01_u8; data_with[66] = 0xF4_u8

      pkt1 = RNS::Packet.new(dest, base, packet_type: RNS::Packet::LINKREQUEST)
      pkt1.pack
      pkt2 = RNS::Packet.new(dest, data_with, packet_type: RNS::Packet::LINKREQUEST)
      pkt2.pack

      RNS::Link.link_id_from_lr_packet(pkt1).should eq RNS::Link.link_id_from_lr_packet(pkt2)
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  MTU/mode from packets
  # ────────────────────────────────────────────────────────────────────

  describe "MTU/mode extraction" do
    it "extracts MTU from LR packet" do
      dest = create_in_destination
      sb = RNS::Link.signalling_bytes(500_u32, RNS::Link::MODE_AES256_CBC)
      data = Bytes.new(67)
      Random::Secure.random_bytes(64).copy_to(data)
      sb.copy_to(data + 64)
      pkt = RNS::Packet.new(dest, data, packet_type: RNS::Packet::LINKREQUEST)
      RNS::Link.mtu_from_lr_packet(pkt).should eq 500
    end

    it "nil for wrong size" do
      dest = create_in_destination
      pkt = RNS::Packet.new(dest, Random::Secure.random_bytes(50), packet_type: RNS::Packet::LINKREQUEST)
      RNS::Link.mtu_from_lr_packet(pkt).should be_nil
    end

    it "extracts mode from LR packet" do
      dest = create_in_destination
      sb = RNS::Link.signalling_bytes(500_u32, RNS::Link::MODE_AES256_CBC)
      data = Bytes.new(67)
      Random::Secure.random_bytes(64).copy_to(data)
      sb.copy_to(data + 64)
      pkt = RNS::Packet.new(dest, data, packet_type: RNS::Packet::LINKREQUEST)
      RNS::Link.mode_from_lr_packet(pkt).should eq RNS::Link::MODE_AES256_CBC
    end

    it "defaults mode for short packet" do
      dest = create_in_destination
      pkt = RNS::Packet.new(dest, Random::Secure.random_bytes(64), packet_type: RNS::Packet::LINKREQUEST)
      RNS::Link.mode_from_lr_packet(pkt).should eq RNS::Link::MODE_DEFAULT
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  validate_request
  # ────────────────────────────────────────────────────────────────────

  describe ".validate_request" do
    it "creates link from valid data" do
      owner = create_in_destination
      init_prv = RNS::Cryptography::X25519PrivateKey.generate
      init_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
      rd = Bytes.new(64)
      init_prv.public_key.public_bytes.copy_to(rd)
      init_sig_prv.public_key.public_bytes.copy_to(rd + 32)
      pkt = RNS::Packet.new(owner, rd, packet_type: RNS::Packet::LINKREQUEST)
      pkt.pack

      link = RNS::Link.validate_request(owner, rd, pkt)
      link.should_not be_nil
      l = link.not_nil!
      l.initiator?.should be_false
      l.status.should eq RNS::Link::HANDSHAKE
      l.link_id.size.should eq 16
    end

    it "nil for invalid size" do
      owner = create_in_destination
      d = Random::Secure.random_bytes(50)
      pkt = RNS::Packet.new(owner, d, packet_type: RNS::Packet::LINKREQUEST)
      pkt.pack
      RNS::Link.validate_request(owner, d, pkt).should be_nil
    end

    it "accepts with signalling bytes" do
      owner = create_in_destination
      init_prv = RNS::Cryptography::X25519PrivateKey.generate
      init_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
      sb = RNS::Link.signalling_bytes(500_u32, RNS::Link::MODE_AES256_CBC)
      rd = Bytes.new(67)
      init_prv.public_key.public_bytes.copy_to(rd)
      init_sig_prv.public_key.public_bytes.copy_to(rd + 32)
      sb.copy_to(rd + 64)
      pkt = RNS::Packet.new(owner, rd, packet_type: RNS::Packet::LINKREQUEST)
      pkt.pack
      RNS::Link.validate_request(owner, rd, pkt).should_not be_nil
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Full 3-step handshake simulation
  # ────────────────────────────────────────────────────────────────────

  describe "full handshake simulation" do
    it "both sides derive matching keys" do
      owner = create_in_destination
      init_prv = RNS::Cryptography::X25519PrivateKey.generate
      init_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
      rd = Bytes.new(64)
      init_prv.public_key.public_bytes.copy_to(rd)
      init_sig_prv.public_key.public_bytes.copy_to(rd + 32)
      pkt = RNS::Packet.new(owner, rd, packet_type: RNS::Packet::LINKREQUEST)
      pkt.pack

      resp = RNS::Link.validate_request(owner, rd, pkt).not_nil!
      link_id = resp.link_id
      resp_derived = resp.derived_key.not_nil!
      resp_pub = resp.pub_bytes.not_nil!

      init_shared = init_prv.exchange(RNS::Cryptography::X25519PublicKey.from_public_bytes(resp_pub))
      init_derived = RNS::Cryptography.hkdf(length: 64, derive_from: init_shared, salt: link_id, context: nil)
      init_derived.should eq resp_derived

      # Both can encrypt/decrypt
      it = RNS::Cryptography::Token.new(init_derived)
      rt = RNS::Cryptography::Token.new(resp_derived)
      msg = "Handshake test".to_slice
      rt.decrypt(it.encrypt(msg)).should eq msg
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Identify
  # ────────────────────────────────────────────────────────────────────

  describe "identify" do
    it "no-op if not initiator" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      link.identify(RNS::Identity.new) # Should not crash
    end

    it "no-op if not ACTIVE" do
      link = create_handshaken_link
      link.set_initiator(true)
      link.identify(RNS::Identity.new) # Status is HANDSHAKE
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  MDU, to_s, get_mode, get_remote_identity
  # ────────────────────────────────────────────────────────────────────

  describe "update_mdu" do
    it "recalculates from MTU" do
      link = create_handshaken_link
      old_mdu = link.mdu
      link.mtu = 1000
      link.update_mdu
      link.mdu.should be > old_mdu
    end
  end

  describe "to_s" do
    it "returns prettyhexrep of link_id" do
      link = create_handshaken_link
      link.to_s.should eq RNS.prettyhexrep(link.link_id)
    end
  end

  describe "get_mode" do
    it "returns current mode" do
      link = create_handshaken_link
      link.get_mode.should eq RNS::Link::MODE_AES256_CBC
    end
  end

  describe "get_remote_identity" do
    it "nil when not identified" do
      link = create_handshaken_link
      link.get_remote_identity.should be_nil
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  LinkChannelOutlet
  # ────────────────────────────────────────────────────────────────────

  # LinkChannelOutlet tests temporarily disabled due to Crystal codegen bug
  # with non-generic class inheriting from generic class instantiation.
  # See: https://github.com/crystal-lang/issues
  describe "LinkChannelOutlet" do
    it "wraps a link" do
      link = create_handshaken_link
      outlet = RNS::LinkChannelOutlet.new(link)
      outlet.link.should eq link
    end

    it "reports mdu" do
      link = create_handshaken_link
      outlet = RNS::LinkChannelOutlet.new(link)
      outlet.mdu.should eq link.mdu
    end

    it "reports rtt" do
      link = create_handshaken_link
      outlet = RNS::LinkChannelOutlet.new(link)
      outlet.rtt.should eq(link.rtt || 0.0)
    end

    it "is_usable when ACTIVE" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      outlet = RNS::LinkChannelOutlet.new(link)
      outlet.is_usable.should be_true
    end

    it "not usable when CLOSED" do
      link = create_handshaken_link
      link.status = RNS::Link::CLOSED
      outlet = RNS::LinkChannelOutlet.new(link)
      outlet.is_usable.should be_false
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  RequestReceipt
  # ────────────────────────────────────────────────────────────────────

  describe RNS::RequestReceipt do
    it "defines status constants" do
      RNS::RequestReceipt::FAILED.should eq 0x00_u8
      RNS::RequestReceipt::SENT.should eq 0x01_u8
      RNS::RequestReceipt::DELIVERED.should eq 0x02_u8
      RNS::RequestReceipt::RECEIVING.should eq 0x03_u8
      RNS::RequestReceipt::READY.should eq 0x04_u8
    end

    it "starts SENT and not concluded" do
      link = create_handshaken_link
      pkt = RNS::Packet.new(link, "test".to_slice, context: RNS::Packet::KEEPALIVE)
      pkt.pack
      pr = RNS::PacketReceipt.new(pkt)
      rr = RNS::RequestReceipt.new(link: link, packet_receipt: pr, timeout: 10.0)
      rr.get_status.should eq RNS::RequestReceipt::SENT
      rr.concluded?.should be_false
    end

    it "transitions to READY on response" do
      link = create_handshaken_link
      pkt = RNS::Packet.new(link, "test".to_slice, context: RNS::Packet::KEEPALIVE)
      pkt.pack
      pr = RNS::PacketReceipt.new(pkt)
      got_response = false
      rr = RNS::RequestReceipt.new(link: link, packet_receipt: pr, timeout: 10.0,
        response_callback: ->(_r : RNS::RequestReceipt) { got_response = true; nil })
      rr.response_received(MessagePack::Any.new("resp"))
      rr.get_status.should eq RNS::RequestReceipt::READY
      rr.concluded?.should be_true
      rr.get_progress.should eq 1.0
      got_response.should be_true
    end

    it "added to link pending_requests" do
      link = create_handshaken_link
      pkt = RNS::Packet.new(link, "test".to_slice, context: RNS::Packet::KEEPALIVE)
      pkt.pack
      pr = RNS::PacketReceipt.new(pkt)
      rr = RNS::RequestReceipt.new(link: link, packet_receipt: pr, timeout: 10.0)
      link.pending_requests.should contain(rr)
    end

    it "get_response nil when not READY" do
      link = create_handshaken_link
      pkt = RNS::Packet.new(link, "test".to_slice, context: RNS::Packet::KEEPALIVE)
      pkt.pack
      pr = RNS::PacketReceipt.new(pkt)
      rr = RNS::RequestReceipt.new(link: link, packet_receipt: pr, timeout: 10.0)
      rr.get_response.should be_nil
    end

    it "get_response returns data when READY" do
      link = create_handshaken_link
      pkt = RNS::Packet.new(link, "test".to_slice, context: RNS::Packet::KEEPALIVE)
      pkt.pack
      pr = RNS::PacketReceipt.new(pkt)
      rr = RNS::RequestReceipt.new(link: link, packet_receipt: pr, timeout: 10.0)
      rr.response_received(MessagePack::Any.new("data"))
      rr.get_response.should_not be_nil
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Callback classes
  # ────────────────────────────────────────────────────────────────────

  describe RNS::RequestReceiptCallbacks do
    it "initializes nil" do
      c = RNS::RequestReceiptCallbacks.new
      c.response.should be_nil
      c.failed.should be_nil
      c.progress.should be_nil
    end
  end

  describe RNS::LinkCallbacks do
    it "initializes nil" do
      c = RNS::LinkCallbacks.new
      c.link_established.should be_nil
      c.link_closed.should be_nil
      c.packet.should be_nil
      c.remote_identified.should be_nil
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  send() convenience method
  # ────────────────────────────────────────────────────────────────────

  describe "send" do
    it "creates and returns a packet" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      pkt = link.send("hello".to_slice)
      pkt.should_not be_nil
    end

    it "increments tx and txbytes" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      link.tx.should eq 0
      link.txbytes.should eq 0
      link.send("test".to_slice)
      link.tx.should eq 1
      link.txbytes.should eq 4
    end

    it "returns nil when CLOSED" do
      link = create_handshaken_link
      link.status = RNS::Link::CLOSED
      link.send("hello".to_slice).should be_nil
    end

    it "updates last_outbound" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      link.last_outbound.should eq 0.0
      link.send("data".to_slice)
      link.last_outbound.should be > 0
    end

    it "accepts packet_type and context" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      pkt = link.send(Bytes[0xFF], packet_type: RNS::Packet::DATA, context: RNS::Packet::KEEPALIVE)
      pkt.should_not be_nil
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Resource management
  # ────────────────────────────────────────────────────────────────────

  describe "resource management" do
    it "registers and tracks outgoing resources" do
      link = create_handshaken_link
      resource = create_test_resource(link)
      link.register_outgoing_resource(resource)
      link.outgoing_resources.size.should eq 1
      link.ready_for_new_resource?.should be_false
    end

    it "registers and tracks incoming resources" do
      link = create_handshaken_link
      hash = Random::Secure.random_bytes(32)
      resource = create_test_resource(link, hash)
      link.register_incoming_resource(resource)
      link.incoming_resources.size.should eq 1
      link.has_incoming_resource?(hash).should be_true
    end

    it "has_incoming_resource? false for unknown hash" do
      link = create_handshaken_link
      link.has_incoming_resource?(Random::Secure.random_bytes(32)).should be_false
    end

    it "cancels outgoing resource" do
      link = create_handshaken_link
      resource = create_test_resource(link)
      link.register_outgoing_resource(resource)
      link.cancel_outgoing_resource(resource.hash)
      link.outgoing_resources.empty?.should be_true
      link.ready_for_new_resource?.should be_true
    end

    it "cancels incoming resource" do
      link = create_handshaken_link
      resource = create_test_resource(link)
      link.register_incoming_resource(resource)
      link.cancel_incoming_resource(resource.hash)
      link.incoming_resources.empty?.should be_true
    end

    it "ready_for_new_resource? true when empty" do
      link = create_handshaken_link
      link.ready_for_new_resource?.should be_true
    end

    it "resource_concluded updates expected_rate for incoming" do
      link = create_handshaken_link
      resource = create_test_resource(link)
      link.register_incoming_resource(resource)
      started = Time.utc.to_unix_f - 1.0
      link.resource_concluded(resource, 8000_i64, started, window: 10, eifr: 1000.0, incoming: true)
      link.incoming_resources.empty?.should be_true
      link.expected_rate.should_not be_nil
      link.expected_rate.not_nil!.should be > 0
      link.get_last_resource_window.should eq 10
      link.get_last_resource_eifr.should eq 1000.0
    end

    it "resource_concluded updates expected_rate for outgoing" do
      link = create_handshaken_link
      resource = create_test_resource(link)
      link.register_outgoing_resource(resource)
      started = Time.utc.to_unix_f - 0.5
      link.resource_concluded(resource, 4000_i64, started, incoming: false)
      link.outgoing_resources.empty?.should be_true
      link.expected_rate.not_nil!.should be > 0
    end

    it "clears resources on link_closed" do
      link = create_handshaken_link
      link.register_incoming_resource(create_test_resource(link))
      link.register_outgoing_resource(create_test_resource(link))
      link.link_closed
      link.incoming_resources.empty?.should be_true
      link.outgoing_resources.empty?.should be_true
    end

    it "get_last_resource_window/eifr nil initially" do
      link = create_handshaken_link
      link.get_last_resource_window.should be_nil
      link.get_last_resource_eifr.should be_nil
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Resource callback setters
  # ────────────────────────────────────────────────────────────────────

  describe "resource callbacks" do
    it "sets resource callback" do
      link = create_handshaken_link
      link.set_resource_callback(->(_adv : RNS::ResourceAdvertisement) { true })
      link.callbacks.resource.should_not be_nil
    end

    it "sets resource_started callback" do
      link = create_handshaken_link
      link.set_resource_started_callback(->(_resource : RNS::Resource) { nil })
      link.callbacks.resource_started.should_not be_nil
    end

    it "sets resource_concluded callback" do
      link = create_handshaken_link
      link.set_resource_concluded_callback(->(_resource : RNS::Resource) { nil })
      link.callbacks.resource_concluded.should_not be_nil
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Keepalive timing (Task 5.3)
  # ────────────────────────────────────────────────────────────────────

  describe "keepalive timing" do
    it "keepalive formula: rtt * (KEEPALIVE_MAX / KEEPALIVE_MAX_RTT)" do
      link = create_handshaken_link
      link.rtt = 1.0
      link.update_keepalive
      expected = Math.max(Math.min(1.0 * (RNS::Link::KEEPALIVE_MAX / RNS::Link::KEEPALIVE_MAX_RTT), RNS::Link::KEEPALIVE_MAX), RNS::Link::KEEPALIVE_MIN)
      link.keepalive.should eq expected
    end

    it "stale_time tracks keepalive * STALE_FACTOR" do
      link = create_handshaken_link
      [0.001, 0.1, 0.5, 1.0, 5.0, 100.0].each do |rtt|
        link.rtt = rtt
        link.update_keepalive
        link.stale_time.should eq link.keepalive * RNS::Link::STALE_FACTOR
      end
    end

    it "scales keepalive proportionally for medium RTT" do
      link = create_handshaken_link
      link.rtt = 0.5
      link.update_keepalive
      ka = link.keepalive
      ka.should be > RNS::Link::KEEPALIVE_MIN
      ka.should be < RNS::Link::KEEPALIVE_MAX
    end

    it "send_keepalive marks last_keepalive" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      link.last_keepalive.should eq 0.0
      link.send_keepalive
      link.last_keepalive.should be > 0
    end

    it "send_keepalive does not update last_data" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      link.send_keepalive
      link.last_data.should eq 0.0
    end

    it "had_outbound with is_keepalive=true only updates keepalive timestamp" do
      link = create_handshaken_link
      link.had_outbound(is_keepalive: true)
      link.last_keepalive.should be > 0
      link.last_data.should eq 0.0
    end

    it "had_outbound with is_keepalive=false updates data timestamp" do
      link = create_handshaken_link
      link.had_outbound(is_keepalive: false)
      link.last_data.should be > 0
      link.last_keepalive.should eq 0.0
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Stale detection (Task 5.3)
  # ────────────────────────────────────────────────────────────────────

  describe "stale detection" do
    it "STALE_FACTOR is 2" do
      RNS::Link::STALE_FACTOR.should eq 2
    end

    it "STALE_TIME is KEEPALIVE * STALE_FACTOR" do
      RNS::Link::STALE_TIME.should eq RNS::Link::KEEPALIVE * RNS::Link::STALE_FACTOR
    end

    it "default stale_time is 720.0 seconds" do
      link = create_handshaken_link
      link.stale_time.should eq 720.0
    end

    it "stale detection adjusts with RTT" do
      link = create_handshaken_link
      link.rtt = 0.1
      link.update_keepalive
      link.stale_time.should be < RNS::Link::STALE_TIME
      link.stale_time.should eq link.keepalive * RNS::Link::STALE_FACTOR
    end

    it "STALE reverts to ACTIVE on inbound" do
      link = create_handshaken_link
      link.status = RNS::Link::STALE
      # Simulate receive restoring ACTIVE
      link.status = RNS::Link::ACTIVE if link.status == RNS::Link::STALE
      link.status.should eq RNS::Link::ACTIVE
    end

    it "inactive_for reflects minimum of inbound/outbound" do
      link = create_handshaken_link
      link.activated_at = Time.utc.to_unix_f
      sleep 0.01.seconds
      link.had_outbound
      # outbound is recent, inbound is from activation
      link.inactive_for.should be < 1.0
    end

    it "no_data_for tracks last data exchange" do
      link = create_handshaken_link
      link.had_outbound # updates last_data
      sleep 0.01.seconds
      link.no_data_for.should be >= 0.01
      link.no_data_for.should be < 1.0
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Teardown (Task 5.3)
  # ────────────────────────────────────────────────────────────────────

  describe "teardown" do
    it "sets CLOSED status" do
      link = create_handshaken_link
      link.teardown
      link.status.should eq RNS::Link::CLOSED
    end

    it "sets DESTINATION_CLOSED reason for responder" do
      link = create_handshaken_link
      link.initiator?.should be_false
      link.teardown
      link.teardown_reason.should eq RNS::Link::DESTINATION_CLOSED
    end

    it "sets INITIATOR_CLOSED reason for initiator" do
      link = create_handshaken_link
      link.set_initiator(true)
      link.status = RNS::Link::ACTIVE
      link.teardown
      link.teardown_reason.should eq RNS::Link::INITIATOR_CLOSED
    end

    it "purges all crypto keys" do
      link = create_handshaken_link
      link.derived_key.should_not be_nil
      link.teardown
      link.prv_key.should be_nil
      link.pub_key.should be_nil
      link.pub_bytes.should be_nil
      link.shared_key.should be_nil
      link.derived_key.should be_nil
    end

    it "clears incoming and outgoing resources" do
      link = create_handshaken_link
      link.register_incoming_resource(create_test_resource(link))
      link.register_outgoing_resource(create_test_resource(link))
      link.teardown
      link.incoming_resources.empty?.should be_true
      link.outgoing_resources.empty?.should be_true
    end

    it "calls link_closed callback" do
      owner = create_in_destination
      peer_prv = RNS::Cryptography::X25519PrivateKey.generate
      peer_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
      closed_link : RNS::Link? = nil
      link = RNS::Link.new(owner: owner, peer_pub_bytes: peer_prv.public_key.public_bytes,
        peer_sig_pub_bytes: peer_sig_prv.public_key.public_bytes,
        closed_callback: ->(l : RNS::Link) { closed_link = l; nil })
      link.teardown
      closed_link.should eq link
    end

    it "teardown_packet with matching link_id closes link" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      encrypted_lid = link.encrypt_data(link.link_id)
      fake_pkt = RNS::Packet.new(link, encrypted_lid, context: RNS::Packet::LINKCLOSE)
      link.teardown_packet(fake_pkt)
      link.status.should eq RNS::Link::CLOSED
    end

    it "teardown_packet with wrong data does not close" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      fake_pkt = RNS::Packet.new(link, "not-the-link-id".to_slice, context: RNS::Packet::LINKCLOSE)
      link.teardown_packet(fake_pkt)
      link.status.should eq RNS::Link::ACTIVE
    end

    it "teardown_packet sets reverse teardown reason for initiator" do
      link = create_handshaken_link
      link.set_initiator(true)
      link.status = RNS::Link::ACTIVE
      encrypted_lid = link.encrypt_data(link.link_id)
      fake_pkt = RNS::Packet.new(link, encrypted_lid, context: RNS::Packet::LINKCLOSE)
      link.teardown_packet(fake_pkt)
      link.teardown_reason.should eq RNS::Link::DESTINATION_CLOSED
    end

    it "does not send teardown packet if PENDING" do
      link = create_handshaken_link
      link.status = RNS::Link::PENDING
      link.teardown
      link.status.should eq RNS::Link::CLOSED
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  RTT computation (Task 5.3)
  # ────────────────────────────────────────────────────────────────────

  describe "RTT computation" do
    it "rtt nil initially" do
      link = create_handshaken_link
      link.rtt.should be_nil
    end

    it "keepalive updates from RTT" do
      link = create_handshaken_link
      link.rtt = 0.5
      link.update_keepalive
      expected_ka = Math.max(Math.min(0.5 * (RNS::Link::KEEPALIVE_MAX / RNS::Link::KEEPALIVE_MAX_RTT), RNS::Link::KEEPALIVE_MAX), RNS::Link::KEEPALIVE_MIN)
      link.keepalive.should be_close(expected_ka, 0.001)
    end

    it "establishment_rate computed from cost/rtt" do
      link = create_handshaken_link
      link.establishment_cost = 200
      link.rtt = 0.5
      link.establishment_rate = link.establishment_cost.to_f64 / link.rtt.not_nil!
      link.establishment_rate.should eq 400.0
      link.get_establishment_rate.should eq 3200.0 # bits/sec
    end

    it "RTT affects keepalive range" do
      link = create_handshaken_link
      # Very fast RTT → minimum keepalive
      link.rtt = 0.001
      link.update_keepalive
      link.keepalive.should eq RNS::Link::KEEPALIVE_MIN

      # Very slow RTT → maximum keepalive
      link.rtt = 100.0
      link.update_keepalive
      link.keepalive.should eq RNS::Link::KEEPALIVE_MAX
    end

    it "RTT available via rtt property" do
      link = create_handshaken_link
      link.rtt = 1.234
      link.rtt.should eq 1.234
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Receive packet dispatch (Task 5.3)
  # ────────────────────────────────────────────────────────────────────

  describe "receive" do
    it "ignores packets when CLOSED" do
      link = create_handshaken_link
      link.status = RNS::Link::CLOSED
      before_rx = link.rx
      pkt = RNS::Packet.new(link, "test".to_slice, context: RNS::Packet::NONE)
      link.receive(pkt)
      link.rx.should eq before_rx
    end

    it "increments rx and rxbytes" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      pkt = RNS::Packet.new(link, "data".to_slice, context: RNS::Packet::KEEPALIVE)
      link.receive(pkt)
      link.rx.should eq 1
      link.rxbytes.should eq 4
    end

    it "updates last_inbound on receive" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      link.last_inbound.should eq 0.0
      pkt = RNS::Packet.new(link, "data".to_slice, context: RNS::Packet::KEEPALIVE)
      link.receive(pkt)
      link.last_inbound.should be > 0
    end

    it "STALE -> ACTIVE on receive" do
      link = create_handshaken_link
      link.status = RNS::Link::STALE
      pkt = RNS::Packet.new(link, "data".to_slice, context: RNS::Packet::KEEPALIVE)
      link.receive(pkt)
      link.status.should eq RNS::Link::ACTIVE
    end

    it "keepalive does not update last_data" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      pkt = RNS::Packet.new(link, Bytes[0xFF], context: RNS::Packet::KEEPALIVE)
      link.receive(pkt)
      link.last_data.should eq 0.0
    end

    it "non-keepalive updates last_data" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      pkt = RNS::Packet.new(link, "data".to_slice, context: RNS::Packet::LRRTT)
      pkt.packet_type = RNS::Packet::DATA
      link.receive(pkt)
      link.last_data.should be > 0
    end

    it "LINKCLOSE via receive tears down" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      encrypted_lid = link.encrypt_data(link.link_id)
      pkt = RNS::Packet.new(link, encrypted_lid, context: RNS::Packet::LINKCLOSE)
      pkt.packet_type = RNS::Packet::DATA
      link.receive(pkt)
      link.status.should eq RNS::Link::CLOSED
    end

    it "responder sends keepalive response for 0xFF" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      pkt = RNS::Packet.new(link, Bytes[0xFF], context: RNS::Packet::KEEPALIVE)
      pkt.packet_type = RNS::Packet::DATA
      link.receive(pkt)
      # Responder sends 0xFE back, which updates last_outbound
      link.last_outbound.should be > 0
    end

    it "initiator ignores own keepalive 0xFF" do
      link = create_handshaken_link
      link.set_initiator(true)
      link.status = RNS::Link::ACTIVE
      pkt = RNS::Packet.new(link, Bytes[0xFF], context: RNS::Packet::KEEPALIVE)
      pkt.packet_type = RNS::Packet::DATA
      before_rx = link.rx
      link.receive(pkt)
      # Initiator skips its own keepalive
      link.rx.should eq before_rx
    end

    it "unlocks watchdog after receive" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      pkt = RNS::Packet.new(link, "data".to_slice, context: RNS::Packet::KEEPALIVE)
      link.receive(pkt)
      # watchdog_lock should be false after receive completes
      # (internal state, verified by the fact receive doesn't deadlock)
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  handle_request dispatch (Task 5.3)
  # ────────────────────────────────────────────────────────────────────

  describe "handle_request" do
    it "dispatches to registered request handler with ALLOW_ALL" do
      owner = create_in_destination
      peer_prv = RNS::Cryptography::X25519PrivateKey.generate
      peer_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
      link = RNS::Link.new(owner: owner,
        peer_pub_bytes: peer_prv.public_key.public_bytes,
        peer_sig_pub_bytes: peer_sig_prv.public_key.public_bytes)
      link.set_link_id_bytes(RNS::Identity.truncated_hash(Random::Secure.random_bytes(32)))
      link.do_handshake
      link.status = RNS::Link::ACTIVE
      link.set_destination(owner) # Set destination for request handler lookup

      received_path = ""
      owner.register_request_handler("/test",
        ->(path : String, _data : Bytes?, _req_id : Bytes, _link_id : Bytes, _identity : RNS::Identity?, _requested_at : Float64) {
          received_path = path
          "response".to_slice.as(Bytes?)
        },
        RNS::Destination::ALLOW_ALL)

      path_hash = RNS::Identity.truncated_hash("/test".to_slice)
      unpacked = [
        MessagePack::Any.new(Time.utc.to_unix_f.as(MessagePack::Type)),
        MessagePack::Any.new(path_hash.as(MessagePack::Type)),
        MessagePack::Any.new(nil.as(MessagePack::Type)),
      ] of MessagePack::Any

      request_id = Random::Secure.random_bytes(16)
      link.handle_request(request_id, unpacked)
      received_path.should eq "/test"
    end

    it "rejects request with ALLOW_NONE" do
      owner = create_in_destination
      peer_prv = RNS::Cryptography::X25519PrivateKey.generate
      peer_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
      link = RNS::Link.new(owner: owner,
        peer_pub_bytes: peer_prv.public_key.public_bytes,
        peer_sig_pub_bytes: peer_sig_prv.public_key.public_bytes)
      link.set_link_id_bytes(RNS::Identity.truncated_hash(Random::Secure.random_bytes(32)))
      link.do_handshake
      link.status = RNS::Link::ACTIVE
      link.set_destination(owner)

      called = false
      owner.register_request_handler("/blocked",
        ->(_path : String, _data : Bytes?, _req_id : Bytes, _link_id : Bytes, _identity : RNS::Identity?, _requested_at : Float64) {
          called = true
          nil.as(Bytes?)
        },
        RNS::Destination::ALLOW_NONE)

      path_hash = RNS::Identity.truncated_hash("/blocked".to_slice)
      unpacked = [
        MessagePack::Any.new(Time.utc.to_unix_f.as(MessagePack::Type)),
        MessagePack::Any.new(path_hash.as(MessagePack::Type)),
        MessagePack::Any.new(nil.as(MessagePack::Type)),
      ] of MessagePack::Any

      link.handle_request(Random::Secure.random_bytes(16), unpacked)
      called.should be_false
    end

    it "no-op when not ACTIVE" do
      link = create_handshaken_link
      link.status = RNS::Link::HANDSHAKE
      unpacked = [
        MessagePack::Any.new(0.0.as(MessagePack::Type)),
        MessagePack::Any.new(Bytes.new(16).as(MessagePack::Type)),
        MessagePack::Any.new(nil.as(MessagePack::Type)),
      ] of MessagePack::Any
      link.handle_request(Bytes.new(16), unpacked) # should not raise
    end

    it "no-op for unregistered path" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      unpacked = [
        MessagePack::Any.new(0.0.as(MessagePack::Type)),
        MessagePack::Any.new(Random::Secure.random_bytes(16).as(MessagePack::Type)),
        MessagePack::Any.new(nil.as(MessagePack::Type)),
      ] of MessagePack::Any
      link.handle_request(Bytes.new(16), unpacked) # should not raise
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  RequestReceipt resource methods (Task 5.3)
  # ────────────────────────────────────────────────────────────────────

  describe "RequestReceipt resource methods" do
    it "request_resource_concluded transitions to DELIVERED on success" do
      link = create_handshaken_link
      pkt = RNS::Packet.new(link, "test".to_slice, context: RNS::Packet::KEEPALIVE)
      pkt.pack
      pr = RNS::PacketReceipt.new(pkt)
      rr = RNS::RequestReceipt.new(link: link, packet_receipt: pr, timeout: 10.0)
      rr.request_resource_concluded(0x00_u8, 0x00_u8) # success
      rr.status.should eq RNS::RequestReceipt::DELIVERED
    end

    it "request_resource_concluded transitions to FAILED on failure" do
      link = create_handshaken_link
      pkt = RNS::Packet.new(link, "test".to_slice, context: RNS::Packet::KEEPALIVE)
      pkt.pack
      pr = RNS::PacketReceipt.new(pkt)
      failed = false
      rr = RNS::RequestReceipt.new(link: link, packet_receipt: pr, timeout: 10.0,
        failed_callback: ->(_r : RNS::RequestReceipt) { failed = true; nil })
      rr.request_resource_concluded(0xFF_u8, 0x00_u8) # failure
      rr.status.should eq RNS::RequestReceipt::FAILED
      failed.should be_true
    end

    it "response_resource_progress updates progress and status" do
      link = create_handshaken_link
      pkt = RNS::Packet.new(link, "test".to_slice, context: RNS::Packet::KEEPALIVE)
      pkt.pack
      pr = RNS::PacketReceipt.new(pkt)
      progress_val = 0.0
      rr = RNS::RequestReceipt.new(link: link, packet_receipt: pr, timeout: 10.0,
        progress_callback: ->(r : RNS::RequestReceipt) { progress_val = r.progress; nil })
      rr.response_resource_progress(0.5)
      rr.status.should eq RNS::RequestReceipt::RECEIVING
      rr.progress.should eq 0.5
      progress_val.should eq 0.5
    end

    it "response_resource_progress ignores when FAILED" do
      link = create_handshaken_link
      pkt = RNS::Packet.new(link, "test".to_slice, context: RNS::Packet::KEEPALIVE)
      pkt.pack
      pr = RNS::PacketReceipt.new(pkt)
      rr = RNS::RequestReceipt.new(link: link, packet_receipt: pr, timeout: 10.0)
      rr.status = RNS::RequestReceipt::FAILED
      rr.response_resource_progress(0.5)
      rr.progress.should eq 0.0 # unchanged
    end

    it "response_resource_progress marks packet_receipt delivered" do
      link = create_handshaken_link
      pkt = RNS::Packet.new(link, "test".to_slice, context: RNS::Packet::KEEPALIVE)
      pkt.pack
      pr = RNS::PacketReceipt.new(pkt)
      rr = RNS::RequestReceipt.new(link: link, packet_receipt: pr, timeout: 10.0)
      rr.response_resource_progress(0.3)
      pr.status.should eq RNS::PacketReceipt::DELIVERED
      pr.proved.should be_true
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Watchdog behavior (Task 5.3)
  # ────────────────────────────────────────────────────────────────────

  describe "watchdog" do
    it "times out PENDING link after establishment_timeout" do
      owner = create_in_destination
      peer_prv = RNS::Cryptography::X25519PrivateKey.generate
      peer_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
      link = RNS::Link.new(owner: owner,
        peer_pub_bytes: peer_prv.public_key.public_bytes,
        peer_sig_pub_bytes: peer_sig_prv.public_key.public_bytes)
      link.set_link_id_bytes(RNS::Identity.truncated_hash(Random::Secure.random_bytes(32)))
      link.request_time = Time.utc.to_unix_f - 100.0 # Way past timeout
      link.establishment_timeout = 1.0
      link.status.should eq RNS::Link::PENDING

      link.start_watchdog
      sleep 0.1.seconds # Let watchdog run
      link.status.should eq RNS::Link::CLOSED
      link.teardown_reason.should eq RNS::Link::TIMEOUT
    end

    it "times out HANDSHAKE link after establishment_timeout" do
      link = create_handshaken_link
      link.request_time = Time.utc.to_unix_f - 100.0
      link.establishment_timeout = 1.0
      link.status.should eq RNS::Link::HANDSHAKE

      link.start_watchdog
      sleep 0.1.seconds
      link.status.should eq RNS::Link::CLOSED
      link.teardown_reason.should eq RNS::Link::TIMEOUT
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Prove packet (Task 5.3)
  # ────────────────────────────────────────────────────────────────────

  describe "prove_packet" do
    it "creates a proof with packet_hash + signature" do
      link = create_handshaken_link
      link.status = RNS::Link::ACTIVE
      pkt = RNS::Packet.new(link, "data".to_slice, context: RNS::Packet::NONE)
      pkt.pack
      # prove_packet should not raise
      link.prove_packet(pkt)
      link.last_outbound.should be > 0
    end
  end

  # ────────────────────────────────────────────────────────────────────
  #  Stress tests
  # ────────────────────────────────────────────────────────────────────

  describe "stress" do
    it "20 handshakes with valid encryption" do
      20.times do
        link = create_handshaken_link
        msg = Random::Secure.random_bytes(Random::Secure.rand(1..200))
        link.decrypt_data(link.encrypt_data(msg)).not_nil!.should eq msg
      end
    end

    it "10 validate_request calls" do
      10.times do
        owner = create_in_destination
        init_prv = RNS::Cryptography::X25519PrivateKey.generate
        init_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
        rd = Bytes.new(64)
        init_prv.public_key.public_bytes.copy_to(rd)
        init_sig_prv.public_key.public_bytes.copy_to(rd + 32)
        pkt = RNS::Packet.new(owner, rd, packet_type: RNS::Packet::LINKREQUEST)
        pkt.pack
        RNS::Link.validate_request(owner, rd, pkt).not_nil!.status.should eq RNS::Link::HANDSHAKE
      end
    end

    it "50 resource register/conclude cycles" do
      link = create_handshaken_link
      50.times do
        resource = create_test_resource(link)
        link.register_incoming_resource(resource)
        link.resource_concluded(resource, Random::Secure.rand(100_i64..10000_i64), Time.utc.to_unix_f - 0.5, incoming: true)
      end
      link.incoming_resources.empty?.should be_true
      link.expected_rate.not_nil!.should be > 0
    end

    it "concurrent link creation" do
      10.times do
        owner = create_in_destination
        peer_prv = RNS::Cryptography::X25519PrivateKey.generate
        peer_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
        link = RNS::Link.new(owner: owner,
          peer_pub_bytes: peer_prv.public_key.public_bytes,
          peer_sig_pub_bytes: peer_sig_prv.public_key.public_bytes)
        link.initiator?.should be_false
        link.status.should eq RNS::Link::PENDING
      end
    end
  end
end
