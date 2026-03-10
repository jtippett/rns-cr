require "../../spec_helper"
require "file_utils"

# Integration test: Announce processing through the full stack
# Tests: Identity creation → Destination creation → Announce generation →
#         Transport inbound processing → Path table population → Handler callbacks

private ANNOUNCE_APP_NAME = "integrationtest"

# Concrete AnnounceHandler implementation for testing.
# AnnounceHandler is a module with abstract methods, so we must subclass it.
class TestAnnounceHandler
  include RNS::Transport::AnnounceHandler

  getter aspect_filter : String? = nil
  getter calls : Array({Bytes, RNS::Identity?, Bytes?, Bytes?}) = [] of {Bytes, RNS::Identity?, Bytes?, Bytes?}

  def initialize(@aspect_filter : String? = nil)
  end

  def received_announce(destination_hash : Bytes, announced_identity : RNS::Identity?, app_data : Bytes?, announce_packet_hash : Bytes?)
    @calls << {destination_hash, announced_identity, app_data, announce_packet_hash}
  end
end

private def start_announce_transport(transport_enabled : Bool = false)
  dir = Dir.tempdir + "/rns_integration_announce_#{Random::Secure.hex(4)}"
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

private def cleanup_announce_dir(dir : String)
  RNS::Transport.stop_job_loop
  FileUtils.rm_rf(dir) if Dir.exists?(dir)
end

# Pack an announce packet (needed because announce(send: false) returns an
# unpacked packet; pack() populates raw and destination_hash).
private def pack_announce(dest : RNS::Destination) : RNS::Packet
  packet = dest.announce(send: false).not_nil!
  packet.pack
  packet
end

# Feed a packed announce packet through Transport.inbound.
# Returns the packet so callers can also use it directly via inbound_announce.
private def feed_inbound(dest : RNS::Destination, app_data : Bytes? = nil) : RNS::Packet
  packet = if app_data
             p = dest.announce(app_data: app_data, send: false).not_nil!
             p.pack
             p
           else
             pack_announce(dest)
           end
  raw = packet.raw.not_nil!
  RNS::Transport.inbound(raw)
  packet
end

describe "Integration: Announce" do
  before_each do
    RNS::Transport.reset
    RNS::Identity.known_destinations.clear
    RNS::Identity.known_ratchets.clear
  end

  describe "Identity and Destination creation" do
    it "creates an Identity with valid keys" do
      id = RNS::Identity.new
      id.hash.should_not be_nil
      id.hexhash.should_not be_nil
      id.get_public_key.size.should eq(RNS::Identity::KEYSIZE // 8)
      id.get_private_key.size.should eq(RNS::Identity::KEYSIZE // 8)
    end

    it "creates a Destination from an Identity" do
      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
      dest.hash.size.should eq(RNS::Reticulum::TRUNCATED_HASHLENGTH // 8)
      dest.hexhash.size.should eq(RNS::Reticulum::TRUNCATED_HASHLENGTH // 4)
      dest.type.should eq(RNS::Destination::SINGLE)
      dest.direction.should eq(RNS::Destination::IN)
      dest.identity.should eq(id)
    end

    it "registers Destination with Transport when register=true" do
      dir = start_announce_transport
      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME)
      RNS::Transport.destinations.should contain(dest)
      cleanup_announce_dir(dir)
    end

    it "computes destination hash from app_name + identity hash" do
      id = RNS::Identity.new
      dest1 = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
      dest2 = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
      dest1.hash.should eq(dest2.hash)
    end

    it "different identities produce different destination hashes" do
      id1 = RNS::Identity.new
      id2 = RNS::Identity.new
      dest1 = RNS::Destination.new(id1, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
      dest2 = RNS::Destination.new(id2, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
      dest1.hash.should_not eq(dest2.hash)
    end

    it "different app_names produce different hashes for same identity" do
      id = RNS::Identity.new
      dest1 = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, "appone", register: false)
      dest2 = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, "apptwo", register: false)
      dest1.hash.should_not eq(dest2.hash)
    end
  end

  describe "Announce generation" do
    it "generates a valid announce packet" do
      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
      packet = dest.announce(send: false)
      packet.should_not be_nil
      pkt = packet.not_nil!
      pkt.packet_type.should eq(RNS::Packet::ANNOUNCE)
      # Pack the packet so raw and destination_hash are populated
      pkt.pack
      pkt.packed.should be_true
      pkt.raw.should_not be_nil
    end

    it "generates announce with app_data" do
      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
      app_data = "Hello RNS".to_slice
      packet = dest.announce(app_data: app_data, send: false)
      packet.should_not be_nil
    end

    it "validates its own announce" do
      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
      packet = pack_announce(dest)
      RNS::Identity.validate_announce(packet).should be_true
    end

    it "validates announce with app_data" do
      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
      app_data = "Test application data: 123".to_slice
      packet = dest.announce(app_data: app_data, send: false).not_nil!
      packet.pack
      RNS::Identity.validate_announce(packet).should be_true
    end

    it "rejects tampered announce data" do
      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
      packet = pack_announce(dest)

      raw = packet.raw.not_nil!
      # Tamper with a byte in the middle of the packet data
      if raw.size > 20
        raw[20] = raw[20] ^ 0xFF_u8
      end

      tampered = RNS::Packet.new(nil, raw)
      tampered.unpack
      RNS::Identity.validate_announce(tampered).should be_false
    end

    it "only IN SINGLE destinations can announce" do
      id = RNS::Identity.new
      dest_out = RNS::Destination.new(id, RNS::Destination::OUT, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
      expect_raises(RNS::TypeError) { dest_out.announce(send: false) }
    end

    it "generates different announce hashes each time due to random_hash" do
      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
      pkt1 = pack_announce(dest)
      pkt2 = pack_announce(dest)
      pkt1.packet_hash.should_not eq(pkt2.packet_hash)
    end
  end

  describe "Transport announce processing" do
    it "processes inbound announce and populates path table" do
      dir = start_announce_transport(transport_enabled: true)
      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
      packet = pack_announce(dest)
      RNS::Transport.inbound_announce(packet)
      RNS::Transport.has_path(dest.hash).should be_true
      RNS::Transport.hops_to(dest.hash).should eq(0)
      cleanup_announce_dir(dir)
    end

    it "remembers identity after announce processing" do
      dir = start_announce_transport(transport_enabled: true)
      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
      packet = pack_announce(dest)
      RNS::Transport.inbound_announce(packet)
      recalled = RNS::Identity.recall(dest.hash)
      recalled.should_not be_nil
      recalled.not_nil!.get_public_key.should eq(id.get_public_key)
      cleanup_announce_dir(dir)
    end

    it "recalls app_data from announce" do
      dir = start_announce_transport(transport_enabled: true)
      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
      app_data = "integration test data".to_slice
      packet = dest.announce(app_data: app_data, send: false).not_nil!
      packet.pack
      RNS::Transport.inbound_announce(packet)
      recalled_data = RNS::Identity.recall_app_data(dest.hash)
      recalled_data.should_not be_nil
      String.new(recalled_data.not_nil!).should eq("integration test data")
      cleanup_announce_dir(dir)
    end

    it "rejects announce for locally registered destination" do
      dir = start_announce_transport(transport_enabled: true)
      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME)
      packet = pack_announce(dest)
      before_count = RNS::Transport.path_table.size
      RNS::Transport.inbound_announce(packet)
      RNS::Transport.path_table.size.should eq(before_count)
      cleanup_announce_dir(dir)
    end

    it "registers and deregisters announce handlers" do
      dir = start_announce_transport(transport_enabled: true)

      handler = TestAnnounceHandler.new(aspect_filter: nil)
      RNS::Transport.register_announce_handler(handler)
      RNS::Transport.announce_handlers.size.should eq(1)
      RNS::Transport.announce_handlers.first.should eq(handler)

      handler2 = TestAnnounceHandler.new(aspect_filter: "some.filter")
      RNS::Transport.register_announce_handler(handler2)
      RNS::Transport.announce_handlers.size.should eq(2)

      RNS::Transport.deregister_announce_handler(handler)
      RNS::Transport.announce_handlers.size.should eq(1)
      RNS::Transport.announce_handlers.first.should eq(handler2)

      cleanup_announce_dir(dir)
    end

    it "inbound_announce populates path table and stores identity" do
      dir = start_announce_transport(transport_enabled: true)

      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, ["announcetest"], register: false)
      app_data = "handler test".to_slice
      packet = dest.announce(app_data: app_data, send: false).not_nil!
      packet.pack

      RNS::Transport.inbound_announce(packet)

      # inbound_announce populates path table synchronously
      RNS::Transport.path_table.has_key?(dest.hash.hexstring).should be_true

      # validate_announce stores the identity via Identity.remember
      recalled = RNS::Identity.recall(dest.hash)
      recalled.should_not be_nil

      # Recalled app_data should match
      recalled_app_data = RNS::Identity.recall_app_data(dest.hash)
      recalled_app_data.should_not be_nil
      String.new(recalled_app_data.not_nil!).should eq("handler test")

      cleanup_announce_dir(dir)
    end

    it "processes full inbound pipeline via Transport.inbound" do
      dir = start_announce_transport(transport_enabled: true)
      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
      packet = pack_announce(dest)
      raw = packet.raw.not_nil!
      RNS::Transport.inbound(raw)
      RNS::Transport.has_path(dest.hash).should be_true
      cleanup_announce_dir(dir)
    end
  end

  describe "Multiple announces" do
    it "processes announces from multiple identities" do
      dir = start_announce_transport(transport_enabled: true)
      destinations = Array(RNS::Destination).new
      10.times do
        id = RNS::Identity.new
        dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
        packet = pack_announce(dest)
        RNS::Transport.inbound_announce(packet)
        destinations << dest
      end
      destinations.each do |dest|
        RNS::Transport.has_path(dest.hash).should be_true
        RNS::Identity.recall(dest.hash).should_not be_nil
      end
      cleanup_announce_dir(dir)
    end

    it "deduplicates announce with same random blob" do
      dir = start_announce_transport(transport_enabled: true)
      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
      packet = pack_announce(dest)
      RNS::Transport.inbound_announce(packet)
      before_table = RNS::Transport.announce_table.size
      # Processing the same packet again should not add a new entry
      RNS::Transport.inbound_announce(packet)
      RNS::Transport.announce_table.size.should eq(before_table)
      cleanup_announce_dir(dir)
    end
  end

  describe "Announce with aspects" do
    it "destination name includes aspects" do
      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, ["service", "echo"], register: false)
      dest.name.should contain("#{ANNOUNCE_APP_NAME}.service.echo")
    end

    it "destination hash is consistent for same identity and aspects" do
      id = RNS::Identity.new
      d1 = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, ["svc"], register: false)
      d2 = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, ["svc"], register: false)
      d1.hash.should eq(d2.hash)
    end
  end

  describe "End-to-end announce flow" do
    it "full cycle: create, announce, validate, remember, recall" do
      dir = start_announce_transport(transport_enabled: true)
      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, ["echo"], register: false)
      app_data = "Echo Service v1.0".to_slice
      packet = dest.announce(app_data: app_data, send: false).not_nil!
      packet.pack
      RNS::Identity.validate_announce(packet).should be_true
      RNS::Transport.inbound_announce(packet)

      RNS::Transport.has_path(dest.hash).should be_true

      recalled_id = RNS::Identity.recall(dest.hash)
      recalled_id.should_not be_nil
      recalled_id.not_nil!.get_public_key.should eq(id.get_public_key)

      recalled_data = RNS::Identity.recall_app_data(dest.hash)
      recalled_data.should_not be_nil
      String.new(recalled_data.not_nil!).should eq("Echo Service v1.0")

      dest_out = RNS::Destination.new(recalled_id.not_nil!, RNS::Destination::OUT, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, ["echo"], register: false)
      dest_out.hash.should eq(dest.hash)
      cleanup_announce_dir(dir)
    end
  end

  describe "Stress tests" do
    it "processes 50 announces from different identities" do
      dir = start_announce_transport(transport_enabled: true)
      50.times do |i|
        id = RNS::Identity.new
        dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, ["stress#{i}"], register: false)
        app_data = "stress_data_#{i}".to_slice
        packet = dest.announce(app_data: app_data, send: false).not_nil!
        packet.pack
        RNS::Identity.validate_announce(packet).should be_true
        RNS::Transport.inbound_announce(packet)
      end
      RNS::Transport.path_table.size.should eq(50)
      cleanup_announce_dir(dir)
    end

    it "validates 100 announces with random app_data" do
      100.times do
        id = RNS::Identity.new
        dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, ANNOUNCE_APP_NAME, register: false)
        app_data = Random::Secure.random_bytes(Random.rand(0..200))
        packet = dest.announce(app_data: app_data, send: false).not_nil!
        packet.pack
        RNS::Identity.validate_announce(packet).should be_true
      end
    end
  end
end
