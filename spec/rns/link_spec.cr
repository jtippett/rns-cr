require "../spec_helper"

# Helper to create an IN SINGLE destination for link testing
private def create_in_destination(app_name = "test", aspects = ["link"]) : RNS::Destination
  identity = RNS::Identity.new
  RNS::Destination.new(identity, RNS::Destination::IN, RNS::Destination::SINGLE,
    app_name, aspects, register: false)
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
      link.set_link_established_callback(->(l : RNS::Link) { nil })
      link.callbacks.link_established.should_not be_nil
    end

    it "calls link_closed on teardown" do
      owner = create_in_destination
      peer_prv = RNS::Cryptography::X25519PrivateKey.generate
      peer_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
      closed = false
      link = RNS::Link.new(owner: owner, peer_pub_bytes: peer_prv.public_key.public_bytes,
        peer_sig_pub_bytes: peer_sig_prv.public_key.public_bytes,
        closed_callback: ->(l : RNS::Link) { closed = true; nil })
      link.teardown
      closed.should be_true
    end

    it "sets packet callback" do
      link = create_handshaken_link
      link.set_packet_callback(->(d : Bytes, p : RNS::Packet) { nil })
      link.callbacks.packet.should_not be_nil
    end

    it "sets remote_identified callback" do
      link = create_handshaken_link
      link.set_remote_identified_callback(->(l : RNS::Link, i : RNS::Identity) { nil })
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
  pending "LinkChannelOutlet wraps a link" { }
  pending "LinkChannelOutlet reports mdu" { }
  pending "LinkChannelOutlet reports rtt" { }
  pending "LinkChannelOutlet is_usable when ACTIVE" { }
  pending "LinkChannelOutlet get_packet_id returns hash" { }

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
        response_callback: ->(r : RNS::RequestReceipt) { got_response = true; nil })
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
  end
end
