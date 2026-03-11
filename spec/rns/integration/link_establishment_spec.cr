require "../../spec_helper"

# Integration test: Link establishment through the full stack

private LINK_APP_NAME = "linktest"

private def start_link_transport(transport_enabled : Bool = false)
  dir = Dir.tempdir + "/rns_integration_link_#{Random::Secure.hex(4)}"
  Dir.mkdir_p(dir)
  owner = RNS::Transport::OwnerRef.new(
    is_connected_to_shared_instance: false,
    storage_path: dir,
    cache_path: dir,
    transport_enabled: transport_enabled,
  )
  RNS::Transport.start(owner)
  dir
end

private def cleanup_link_dir(dir : String)
  RNS::Transport.stop_job_loop
  FileUtils.rm_rf(dir) if Dir.exists?(dir)
end

private def create_link_dest(identity : RNS::Identity, aspects = ["echo"]) : RNS::Destination
  RNS::Destination.new(identity, RNS::Destination::IN, RNS::Destination::SINGLE,
    LINK_APP_NAME, aspects, register: false)
end

# Helper: set up a responder link via validate_request, returning {link, init_prv}
private def setup_responder_link(server_dest : RNS::Destination)
  init_prv = RNS::Cryptography::X25519PrivateKey.generate
  init_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate

  request_data = Bytes.new(RNS::Link::ECPUBSIZE)
  init_prv.public_key.public_bytes.copy_to(request_data)
  init_sig_prv.public_key.public_bytes.copy_to(request_data + 32)

  pkt = RNS::Packet.new(server_dest, request_data, packet_type: RNS::Packet::LINKREQUEST)
  pkt.pack

  resp = RNS::Link.validate_request(server_dest, request_data, pkt).not_nil!
  {resp, init_prv}
end

describe "Integration: Link Establishment" do
  before_each do
    RNS::Transport.reset
    RNS::Identity.known_destinations.clear
    RNS::Identity.known_ratchets.clear
  end

  describe "3-step ECDH handshake" do
    it "initiator and responder derive matching shared keys" do
      server_identity = RNS::Identity.new
      server_dest = create_link_dest(server_identity)
      resp, init_prv = setup_responder_link(server_dest)

      resp_derived = resp.derived_key.not_nil!
      init_shared = init_prv.exchange(RNS::Cryptography::X25519PublicKey.from_public_bytes(resp.pub_bytes.not_nil!))
      init_derived = RNS::Cryptography.hkdf(length: 64, derive_from: init_shared, salt: resp.link_id, context: nil)

      init_derived.should eq(resp_derived)
    end

    it "derived keys enable bidirectional encryption" do
      server_identity = RNS::Identity.new
      server_dest = create_link_dest(server_identity)
      resp, init_prv = setup_responder_link(server_dest)

      resp_derived = resp.derived_key.not_nil!
      init_shared = init_prv.exchange(RNS::Cryptography::X25519PublicKey.from_public_bytes(resp.pub_bytes.not_nil!))
      init_derived = RNS::Cryptography.hkdf(length: 64, derive_from: init_shared, salt: resp.link_id, context: nil)

      init_token = RNS::Cryptography::Token.new(init_derived)
      resp_token = RNS::Cryptography::Token.new(resp_derived)

      msg1 = "Hello from initiator".to_slice
      resp_token.decrypt(init_token.encrypt(msg1)).should eq(msg1)

      msg2 = "Hello from responder".to_slice
      init_token.decrypt(resp_token.encrypt(msg2)).should eq(msg2)
    end

    it "handles link request with MTU signalling bytes" do
      server_identity = RNS::Identity.new
      server_dest = create_link_dest(server_identity)

      init_prv = RNS::Cryptography::X25519PrivateKey.generate
      init_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
      signalling = RNS::Link.signalling_bytes(RNS::Reticulum::MTU.to_u32, RNS::Link::MODE_AES256_CBC)

      request_data = Bytes.new(RNS::Link::ECPUBSIZE + signalling.size)
      init_prv.public_key.public_bytes.copy_to(request_data)
      init_sig_prv.public_key.public_bytes.copy_to(request_data + 32)
      signalling.copy_to(request_data + RNS::Link::ECPUBSIZE)

      pkt = RNS::Packet.new(server_dest, request_data, packet_type: RNS::Packet::LINKREQUEST)
      pkt.pack

      resp = RNS::Link.validate_request(server_dest, request_data, pkt)
      resp.should_not be_nil
      resp.not_nil!.mtu.should eq(RNS::Reticulum::MTU)
    end
  end

  describe "Link proof verification" do
    it "initiator creates pending link with valid link_id" do
      dir = start_link_transport
      server_identity = RNS::Identity.new
      server_dest = create_link_dest(server_identity)

      RNS::Identity.remember(
        Random::Secure.random_bytes(16), server_dest.hash,
        server_identity.get_public_key, nil
      )

      client_link = RNS::Link.new(destination: server_dest)
      client_link.status.should eq(RNS::Link::PENDING)
      client_link.initiator?.should be_true
      client_link.link_id.size.should eq(RNS::Reticulum::TRUNCATED_HASHLENGTH // 8)
      cleanup_link_dir(dir)
    end

    it "responder enters HANDSHAKE state after validate_request" do
      server_identity = RNS::Identity.new
      server_dest = create_link_dest(server_identity)
      resp, _ = setup_responder_link(server_dest)
      resp.status.should eq(RNS::Link::HANDSHAKE)
    end
  end

  describe "Link encrypt/decrypt via established link" do
    it "responder link can encrypt and decrypt" do
      server_identity = RNS::Identity.new
      server_dest = create_link_dest(server_identity)
      resp, _ = setup_responder_link(server_dest)

      msg = "Encrypted test message over link".to_slice
      encrypted = resp.encrypt_data(msg)
      encrypted.should_not eq(msg)
      decrypted = resp.decrypt_data(encrypted)
      decrypted.not_nil!.should eq(msg)
    end

    it "encrypt/decrypt roundtrip with various payload sizes" do
      server_identity = RNS::Identity.new
      server_dest = create_link_dest(server_identity)
      resp, _ = setup_responder_link(server_dest)

      [1, 16, 32, 64, 128, 256, 383].each do |size|
        data = Random::Secure.random_bytes(size)
        encrypted = resp.encrypt_data(data)
        decrypted = resp.decrypt_data(encrypted)
        decrypted.not_nil!.should eq(data)
      end
    end
  end

  describe "Link registration with Transport" do
    it "initiator link registers as pending" do
      dir = start_link_transport
      server_identity = RNS::Identity.new
      server_dest = create_link_dest(server_identity)
      link = RNS::Link.new(destination: server_dest)
      RNS::Transport.pending_links.should contain(link)
      cleanup_link_dir(dir)
    end

    it "responder link registers after validate_request" do
      dir = start_link_transport
      server_identity = RNS::Identity.new
      server_dest = create_link_dest(server_identity)
      resp, _ = setup_responder_link(server_dest)
      RNS::Transport.active_links.size.should be >= 1
      cleanup_link_dir(dir)
    end
  end

  describe "Link state transitions" do
    it "link starts PENDING, moves to HANDSHAKE, then can be set ACTIVE" do
      server_identity = RNS::Identity.new
      server_dest = create_link_dest(server_identity)
      resp, _ = setup_responder_link(server_dest)
      resp.status.should eq(RNS::Link::HANDSHAKE)
      resp.status = RNS::Link::ACTIVE
      resp.status.should eq(RNS::Link::ACTIVE)
    end

    it "teardown sets link CLOSED" do
      server_identity = RNS::Identity.new
      server_dest = create_link_dest(server_identity)
      resp, _ = setup_responder_link(server_dest)
      resp.status = RNS::Link::ACTIVE
      resp.teardown
      resp.status.should eq(RNS::Link::CLOSED)
    end
  end

  describe "Data transfer over established link" do
    it "sends data packets with link encryption" do
      server_identity = RNS::Identity.new
      server_dest = create_link_dest(server_identity)
      resp, _ = setup_responder_link(server_dest)
      resp.status = RNS::Link::ACTIVE

      data = "Test data over link".to_slice
      result = resp.send(data)
      result.should_not be_nil
      resp.tx.should eq(1)
      resp.txbytes.should be > 0
    end

    it "multiple messages maintain counters" do
      server_identity = RNS::Identity.new
      server_dest = create_link_dest(server_identity)
      resp, _ = setup_responder_link(server_dest)
      resp.status = RNS::Link::ACTIVE

      10.times do |i|
        resp.send("Message #{i}".to_slice)
      end
      resp.tx.should eq(10)
      resp.txbytes.should be > 0
    end
  end

  describe "Link callbacks" do
    it "established callback is set" do
      server_identity = RNS::Identity.new
      server_dest = create_link_dest(server_identity)
      link = RNS::Link.new(destination: server_dest, established_callback: ->(_l : RNS::Link) { })
      link.callbacks.link_established.should_not be_nil
    end

    it "closed callback is set" do
      server_identity = RNS::Identity.new
      server_dest = create_link_dest(server_identity)
      link = RNS::Link.new(destination: server_dest, closed_callback: ->(_l : RNS::Link) { })
      link.callbacks.link_closed.should_not be_nil
    end
  end

  describe "Stress tests" do
    it "establishes 20 independent links with matching derived keys" do
      20.times do
        server_identity = RNS::Identity.new
        server_dest = create_link_dest(server_identity)
        resp, init_prv = setup_responder_link(server_dest)

        resp_derived = resp.derived_key.not_nil!
        init_shared = init_prv.exchange(RNS::Cryptography::X25519PublicKey.from_public_bytes(resp.pub_bytes.not_nil!))
        init_derived = RNS::Cryptography.hkdf(length: 64, derive_from: init_shared, salt: resp.link_id, context: nil)
        init_derived.should eq(resp_derived)
      end
    end

    it "encrypts and decrypts 100 random payloads over link" do
      server_identity = RNS::Identity.new
      server_dest = create_link_dest(server_identity)
      resp, _ = setup_responder_link(server_dest)

      100.times do
        size = Random.rand(1..RNS::Link::MDU)
        data = Random::Secure.random_bytes(size)
        encrypted = resp.encrypt_data(data)
        decrypted = resp.decrypt_data(encrypted)
        decrypted.not_nil!.should eq(data)
      end
    end
  end
end
