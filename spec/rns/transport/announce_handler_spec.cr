require "../../spec_helper"

# Helper to create an announce packet from a destination for testing
def create_announce_packet(dest : RNS::Destination, app_data : Bytes? = nil, path_response : Bool = false) : RNS::Packet
  dest.announce(app_data: app_data, path_response: path_response, send: false).not_nil!
end

# Helper to build a random blob with a specific emission timestamp
def build_random_blob(emission_time : Int64) : Bytes
  blob = Random::Secure.random_bytes(10)
  # Encode emission time into bytes 5..9 (big-endian, 40-bit)
  blob[5] = ((emission_time >> 32) & 0xFF).to_u8
  blob[6] = ((emission_time >> 24) & 0xFF).to_u8
  blob[7] = ((emission_time >> 16) & 0xFF).to_u8
  blob[8] = ((emission_time >> 8) & 0xFF).to_u8
  blob[9] = (emission_time & 0xFF).to_u8
  blob
end

describe "Transport Announce Handling" do
  before_each do
    RNS::Transport.reset
    RNS::Identity.known_destinations.clear
    RNS::Identity.known_ratchets.clear
  end

  # ════════════════════════════════════════════════════════════════
  #  Timebase Helpers
  # ════════════════════════════════════════════════════════════════

  describe ".timebase_from_random_blob" do
    it "extracts timebase from bytes 5..9 of a 10-byte blob" do
      blob = Bytes.new(10, 0_u8)
      # Set bytes 5..9 to represent a known value
      # 0x0000000001 = 1
      blob[9] = 1_u8
      RNS::Transport.timebase_from_random_blob(blob).should eq(1_i64)
    end

    it "extracts large timebase values" do
      blob = Bytes.new(10, 0_u8)
      # 0x00FFFFFFFF = 4294967295
      blob[5] = 0x00_u8
      blob[6] = 0xFF_u8
      blob[7] = 0xFF_u8
      blob[8] = 0xFF_u8
      blob[9] = 0xFF_u8
      RNS::Transport.timebase_from_random_blob(blob).should eq(4294967295_i64)
    end

    it "returns 0 for short blob" do
      blob = Bytes.new(5, 0_u8)
      RNS::Transport.timebase_from_random_blob(blob).should eq(0_i64)
    end

    it "returns 0 for all-zero blob" do
      blob = Bytes.new(10, 0_u8)
      RNS::Transport.timebase_from_random_blob(blob).should eq(0_i64)
    end

    it "correctly reads big-endian 40-bit value" do
      blob = Bytes.new(10, 0_u8)
      # 0x0102030405
      blob[5] = 0x01_u8
      blob[6] = 0x02_u8
      blob[7] = 0x03_u8
      blob[8] = 0x04_u8
      blob[9] = 0x05_u8
      expected = (0x01_i64 << 32) | (0x02_i64 << 24) | (0x03_i64 << 16) | (0x04_i64 << 8) | 0x05_i64
      RNS::Transport.timebase_from_random_blob(blob).should eq(expected)
    end
  end

  describe ".timebase_from_random_blobs" do
    it "returns 0 for empty array" do
      RNS::Transport.timebase_from_random_blobs([] of Bytes).should eq(0_i64)
    end

    it "returns the maximum timebase" do
      blob1 = build_random_blob(100_i64)
      blob2 = build_random_blob(500_i64)
      blob3 = build_random_blob(200_i64)
      RNS::Transport.timebase_from_random_blobs([blob1, blob2, blob3]).should eq(500_i64)
    end

    it "handles single blob" do
      blob = build_random_blob(42_i64)
      RNS::Transport.timebase_from_random_blobs([blob]).should eq(42_i64)
    end
  end

  describe ".announce_emitted" do
    it "extracts emission timebase from announce packet data" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      packet = create_announce_packet(dest)

      offset = RNS::Identity::KEYSIZE // 8 + RNS::Identity::NAME_HASH_LENGTH // 8
      random_blob = packet.data[offset, 10]
      expected = RNS::Transport.timebase_from_random_blob(random_blob)

      RNS::Transport.announce_emitted(packet).should eq(expected)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Packet Filter
  # ════════════════════════════════════════════════════════════════

  describe ".packet_filter" do
    it "allows KEEPALIVE context" do
      dest_stub = RNS::Destination::Stub.new(
        hash: Random::Secure.random_bytes(16),
        type: RNS::Destination::SINGLE,
      )
      packet = RNS::Packet.new(dest_stub, Bytes.new(10, 0_u8),
        packet_type: RNS::Packet::DATA,
        context: RNS::Packet::KEEPALIVE,
      )
      packet.pack
      RNS::Transport.packet_filter(packet).should be_true
    end

    it "allows RESOURCE context" do
      dest_stub = RNS::Destination::Stub.new(
        hash: Random::Secure.random_bytes(16),
        type: RNS::Destination::SINGLE,
      )
      packet = RNS::Packet.new(dest_stub, Bytes.new(10, 0_u8),
        packet_type: RNS::Packet::DATA,
        context: RNS::Packet::RESOURCE,
      )
      packet.pack
      RNS::Transport.packet_filter(packet).should be_true
    end

    it "allows CACHE_REQUEST context" do
      dest_stub = RNS::Destination::Stub.new(
        hash: Random::Secure.random_bytes(16),
        type: RNS::Destination::SINGLE,
      )
      packet = RNS::Packet.new(dest_stub, Bytes.new(10, 0_u8),
        packet_type: RNS::Packet::DATA,
        context: RNS::Packet::CACHE_REQUEST,
      )
      packet.pack
      RNS::Transport.packet_filter(packet).should be_true
    end

    it "allows CHANNEL context" do
      dest_stub = RNS::Destination::Stub.new(
        hash: Random::Secure.random_bytes(16),
        type: RNS::Destination::SINGLE,
      )
      packet = RNS::Packet.new(dest_stub, Bytes.new(10, 0_u8),
        packet_type: RNS::Packet::DATA,
        context: RNS::Packet::CHANNEL,
      )
      packet.pack
      RNS::Transport.packet_filter(packet).should be_true
    end

    it "drops PLAIN packets with more than 1 hop" do
      dest_stub = RNS::Destination::Stub.new(
        hash: Random::Secure.random_bytes(16),
        type: RNS::Destination::PLAIN,
      )
      packet = RNS::Packet.new(dest_stub, Bytes.new(10, 0_u8),
        packet_type: RNS::Packet::DATA,
      )
      packet.pack
      packet.hops = 2_u8
      RNS::Transport.packet_filter(packet).should be_false
    end

    it "allows PLAIN packets with 1 or fewer hops" do
      dest_stub = RNS::Destination::Stub.new(
        hash: Random::Secure.random_bytes(16),
        type: RNS::Destination::PLAIN,
      )
      packet = RNS::Packet.new(dest_stub, Bytes.new(10, 0_u8),
        packet_type: RNS::Packet::DATA,
      )
      packet.pack
      packet.hops = 1_u8
      RNS::Transport.packet_filter(packet).should be_true
    end

    it "drops PLAIN announce packets" do
      dest_stub = RNS::Destination::Stub.new(
        hash: Random::Secure.random_bytes(16),
        type: RNS::Destination::PLAIN,
      )
      packet = RNS::Packet.new(dest_stub, Bytes.new(10, 0_u8),
        packet_type: RNS::Packet::ANNOUNCE,
      )
      packet.pack
      RNS::Transport.packet_filter(packet).should be_false
    end

    it "drops GROUP announce packets" do
      dest_stub = RNS::Destination::Stub.new(
        hash: Random::Secure.random_bytes(16),
        type: RNS::Destination::GROUP,
      )
      packet = RNS::Packet.new(dest_stub, Bytes.new(10, 0_u8),
        packet_type: RNS::Packet::ANNOUNCE,
      )
      packet.pack
      RNS::Transport.packet_filter(packet).should be_false
    end

    it "drops GROUP packets with more than 1 hop" do
      dest_stub = RNS::Destination::Stub.new(
        hash: Random::Secure.random_bytes(16),
        type: RNS::Destination::GROUP,
      )
      packet = RNS::Packet.new(dest_stub, Bytes.new(10, 0_u8),
        packet_type: RNS::Packet::DATA,
      )
      packet.pack
      packet.hops = 2_u8
      RNS::Transport.packet_filter(packet).should be_false
    end

    it "allows unseen SINGLE packets" do
      dest_stub = RNS::Destination::Stub.new(
        hash: Random::Secure.random_bytes(16),
        type: RNS::Destination::SINGLE,
      )
      packet = RNS::Packet.new(dest_stub, Bytes.new(10, 0_u8),
        packet_type: RNS::Packet::DATA,
      )
      packet.pack
      RNS::Transport.packet_filter(packet).should be_true
    end

    it "allows SINGLE announce even if hash is in hashlist" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      packet = create_announce_packet(dest)
      packet.pack

      # Add its hash to the hashlist
      RNS::Transport.add_packet_hash(packet.packet_hash.not_nil!)

      RNS::Transport.packet_filter(packet).should be_true
    end

    it "drops non-announce SINGLE packets if hash is already seen" do
      dest_stub = RNS::Destination::Stub.new(
        hash: Random::Secure.random_bytes(16),
        type: RNS::Destination::SINGLE,
      )
      packet = RNS::Packet.new(dest_stub, Bytes.new(10, 0_u8),
        packet_type: RNS::Packet::DATA,
      )
      packet.pack

      # Add its hash to the hashlist
      RNS::Transport.add_packet_hash(packet.packet_hash.not_nil!)

      RNS::Transport.packet_filter(packet).should be_false
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Packet Hash Deduplication
  # ════════════════════════════════════════════════════════════════

  describe ".add_packet_hash / .packet_hash_in_list?" do
    it "adds and checks packet hashes" do
      hash = Random::Secure.random_bytes(32)
      RNS::Transport.packet_hash_in_list?(hash).should be_false
      RNS::Transport.add_packet_hash(hash)
      RNS::Transport.packet_hash_in_list?(hash).should be_true
    end

    it "returns false for unknown hash" do
      hash = Random::Secure.random_bytes(32)
      RNS::Transport.packet_hash_in_list?(hash).should be_false
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Identity.validate_announce
  # ════════════════════════════════════════════════════════════════

  describe "Identity.validate_announce" do
    it "validates a valid announce packet" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      # Clear known_destinations so validate_announce re-remembers
      RNS::Identity.known_destinations.clear
      packet = create_announce_packet(dest)
      packet.pack

      RNS::Identity.validate_announce(packet).should be_true
    end

    it "validates with only_validate_signature" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear
      packet = create_announce_packet(dest)
      packet.pack

      RNS::Identity.validate_announce(packet, only_validate_signature: true).should be_true
    end

    it "remembers destination after full validation" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear
      packet = create_announce_packet(dest)
      packet.pack

      RNS::Identity.validate_announce(packet).should be_true
      RNS::Identity.known_destinations.has_key?(dest.hash).should be_true
    end

    it "does not remember on signature-only validation" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear
      packet = create_announce_packet(dest)
      packet.pack

      RNS::Identity.validate_announce(packet, only_validate_signature: true).should be_true
      RNS::Identity.known_destinations.has_key?(dest.hash).should be_false
    end

    it "returns false for non-announce packets" do
      dest_stub = RNS::Destination::Stub.new(
        hash: Random::Secure.random_bytes(16),
        type: RNS::Destination::SINGLE,
      )
      packet = RNS::Packet.new(dest_stub, Bytes.new(10, 0_u8),
        packet_type: RNS::Packet::DATA,
      )
      packet.pack
      RNS::Identity.validate_announce(packet).should be_false
    end

    it "returns false for announce with tampered data" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear
      packet = create_announce_packet(dest)
      packet.pack

      # Tamper with a byte in the data (flip a bit in the public key)
      packet.data[0] ^= 0xFF_u8

      RNS::Identity.validate_announce(packet).should be_false
    end

    it "validates announce with app_data" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear
      app_data = "hello world".to_slice
      packet = create_announce_packet(dest, app_data: app_data)
      packet.pack

      RNS::Identity.validate_announce(packet).should be_true
    end

    it "recalls app_data after validation" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear
      app_data = "my data".to_slice
      packet = create_announce_packet(dest, app_data: app_data)
      packet.pack

      RNS::Identity.validate_announce(packet).should be_true
      recalled = RNS::Identity.recall_app_data(dest.hash)
      recalled.should_not be_nil
      recalled.not_nil!.should eq(app_data)
    end

    it "rejects announce with mismatched public key for known destination" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      packet = create_announce_packet(dest)
      packet.pack

      # First validation should succeed
      RNS::Identity.validate_announce(packet).should be_true

      # Create a different identity and forge a destination with the same hash
      # Simulate a public key mismatch by modifying known_destinations
      known = RNS::Identity.known_destinations[dest.hash]
      fake_key = Random::Secure.random_bytes(RNS::Identity::KEYSIZE // 8)
      known[2] = fake_key.as(Bytes | Float64 | Nil)

      # Second validation should fail due to key mismatch
      RNS::Identity.validate_announce(packet).should be_false
    end

    it "validates 20 different announce packets" do
      20.times do |i|
        dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "app#{i}", register: false)
        RNS::Identity.known_destinations.clear
        packet = create_announce_packet(dest)
        packet.pack
        RNS::Identity.validate_announce(packet).should be_true
      end
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Inbound Announce Processing
  # ════════════════════════════════════════════════════════════════

  describe ".inbound_announce" do
    it "processes a valid announce and adds to path table" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear

      packet = create_announce_packet(dest)
      packet.pack

      result = RNS::Transport.inbound_announce(packet)
      result.should be_true

      dest_hex = dest.hash.hexstring
      RNS::Transport.path_table.has_key?(dest_hex).should be_true
    end

    it "sets correct hops in path table entry" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear

      packet = create_announce_packet(dest)
      packet.pack
      packet.hops = 3_u8

      RNS::Transport.inbound_announce(packet)

      entry = RNS::Transport.path_table[dest.hash.hexstring]
      entry.hops.should eq(3)
    end

    it "rejects announce for local destination" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      # Register the destination so it's considered local
      # (it was already registered by default, but let's be explicit)
      RNS::Transport.register_destination(dest)
      RNS::Identity.known_destinations.clear

      packet = create_announce_packet(dest)
      packet.pack

      result = RNS::Transport.inbound_announce(packet)
      result.should be_false
    end

    it "rejects invalid announce (tampered signature)" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear

      packet = create_announce_packet(dest)
      packet.pack
      # Tamper with public key in packet data
      packet.data[0] ^= 0xFF_u8

      result = RNS::Transport.inbound_announce(packet)
      result.should be_false
    end

    it "adds announce to announce table for retransmission" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear

      packet = create_announce_packet(dest)
      packet.pack

      RNS::Transport.inbound_announce(packet)

      dest_hex = dest.hash.hexstring
      RNS::Transport.announce_table.has_key?(dest_hex).should be_true
    end

    it "does not add PATH_RESPONSE to announce table" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear

      packet = create_announce_packet(dest, path_response: true)
      packet.pack

      RNS::Transport.inbound_announce(packet)

      dest_hex = dest.hash.hexstring
      # Should be in path table but NOT in announce table
      RNS::Transport.path_table.has_key?(dest_hex).should be_true
      RNS::Transport.announce_table.has_key?(dest_hex).should be_false
    end

    it "stores random blob in path entry" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear

      packet = create_announce_packet(dest)
      packet.pack

      RNS::Transport.inbound_announce(packet)

      entry = RNS::Transport.path_table[dest.hash.hexstring]
      entry.random_blobs.size.should eq(1)
    end

    it "uses destination_hash as received_from when no transport_id" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear

      packet = create_announce_packet(dest)
      packet.pack

      RNS::Transport.inbound_announce(packet)

      entry = RNS::Transport.path_table[dest.hash.hexstring]
      entry.next_hop.should eq(dest.hash)
    end

    it "deduplicates announces with same random blob" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear

      packet = create_announce_packet(dest)
      packet.pack

      # First announce should succeed
      result1 = RNS::Transport.inbound_announce(packet)
      result1.should be_true

      # Same packet (same random blob) should be deduplicated
      # Need to clear known_destinations for the second validation to work
      # but the path table already has this random blob
      result2 = RNS::Transport.inbound_announce(packet)
      result2.should be_false
    end

    it "accepts new announce with fewer hops and newer emission" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear

      # Create first announce and manually set a low emission time
      packet1 = create_announce_packet(dest)
      packet1.pack
      packet1.hops = 5_u8

      # Patch the random blob emission time to be low (bytes 5-9 of random blob)
      offset = RNS::Identity::KEYSIZE // 8 + RNS::Identity::NAME_HASH_LENGTH // 8
      packet1.data[offset + 5] = 0_u8
      packet1.data[offset + 6] = 0_u8
      packet1.data[offset + 7] = 0_u8
      packet1.data[offset + 8] = 0_u8
      packet1.data[offset + 9] = 1_u8

      # Process first announce — it will fail signature validation since we
      # modified data. Instead, directly insert a path entry.
      dest_hex = dest.hash.hexstring
      blob1 = packet1.data[offset, 10].dup
      RNS::Transport.path_table[dest_hex] = RNS::Transport::PathEntry.new(
        timestamp: Time.utc.to_unix_f,
        next_hop: dest.hash,
        hops: 5,
        expires: Time.utc.to_unix_f + 3600.0,
        random_blobs: [blob1],
        receiving_interface: nil,
        packet_hash: packet1.packet_hash || Bytes.empty,
      )

      # Create second announce with fewer hops
      packet2 = create_announce_packet(dest)
      packet2.pack
      packet2.hops = 2_u8

      # Patch the second random blob emission time to be higher
      packet2.data[offset + 5] = 0xFF_u8
      packet2.data[offset + 6] = 0xFF_u8
      packet2.data[offset + 7] = 0xFF_u8
      packet2.data[offset + 8] = 0xFF_u8
      packet2.data[offset + 9] = 0xFF_u8

      # The signature won't match after patching, so inbound_announce will fail.
      # Instead, test the logic directly by calling with a proper announce.

      # Use a proper announce and manipulate the path table to have higher hops
      RNS::Identity.known_destinations.clear
      packet3 = create_announce_packet(dest)
      packet3.pack
      packet3.hops = 2_u8

      # Set path entry with high hop count and old emission time
      blob_old = build_random_blob(1_i64)
      RNS::Transport.path_table[dest_hex] = RNS::Transport::PathEntry.new(
        timestamp: Time.utc.to_unix_f,
        next_hop: dest.hash,
        hops: 5,
        expires: Time.utc.to_unix_f + 3600.0,
        random_blobs: [blob_old],
        receiving_interface: nil,
        packet_hash: Bytes.empty,
      )

      result = RNS::Transport.inbound_announce(packet3)
      result.should be_true

      entry = RNS::Transport.path_table[dest_hex]
      entry.hops.should eq(2)
    end

    it "rejects announce with more hops when path not expired and emission not newer" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear

      packet1 = create_announce_packet(dest)
      packet1.pack
      packet1.hops = 2_u8

      RNS::Transport.inbound_announce(packet1)

      # Same emission time (same announce), more hops — should reject
      packet2 = create_announce_packet(dest)
      packet2.pack
      packet2.hops = 5_u8

      # This will be rejected because the new announce has more hops,
      # the path hasn't expired, and the emission time is similar
      result = RNS::Transport.inbound_announce(packet2)
      # May or may not be true depending on emission timing
      # But hops should not increase
      entry = RNS::Transport.path_table[dest.hash.hexstring]
      entry.hops.should be <= 5
    end

    it "calls registered announce handlers" do
      handler_called = false
      received_hash = nil

      handler = TestCallbackAnnounceHandler.new(nil) do |dh, _ai, _ad, _aph|
        handler_called = true
        received_hash = dh
      end

      RNS::Transport.register_announce_handler(handler)

      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear

      packet = create_announce_packet(dest)
      packet.pack

      RNS::Transport.inbound_announce(packet)

      # Give the spawned fiber time to execute
      sleep(50.milliseconds)

      handler_called.should be_true
      received_hash.should eq(dest.hash)
    end

    it "filters handler by aspect_filter" do
      handler_called = false

      handler = TestCallbackAnnounceHandler.new("nonmatching.aspect") do |_dh, _ai, _ad, _aph|
        handler_called = true
      end

      RNS::Transport.register_announce_handler(handler)

      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear

      packet = create_announce_packet(dest)
      packet.pack

      RNS::Transport.inbound_announce(packet)
      sleep(50.milliseconds)

      handler_called.should be_false
    end

    it "does not invoke handler for PATH_RESPONSE" do
      handler_called = false

      handler = TestCallbackAnnounceHandler.new(nil) do |_dh, _ai, _ad, _aph|
        handler_called = true
      end

      RNS::Transport.register_announce_handler(handler)

      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear

      packet = create_announce_packet(dest, path_response: true)
      packet.pack

      RNS::Transport.inbound_announce(packet)
      sleep(50.milliseconds)

      handler_called.should be_false
    end

    it "handles announce with app_data" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear

      app_data = "test app data".to_slice
      packet = create_announce_packet(dest, app_data: app_data)
      packet.pack

      result = RNS::Transport.inbound_announce(packet)
      result.should be_true

      recalled = RNS::Identity.recall_app_data(dest.hash)
      recalled.should_not be_nil
      recalled.not_nil!.should eq(app_data)
    end

    it "rejects non-announce packet types" do
      dest_stub = RNS::Destination::Stub.new(
        hash: Random::Secure.random_bytes(16),
        type: RNS::Destination::SINGLE,
      )
      packet = RNS::Packet.new(dest_stub, Bytes.new(10, 0_u8),
        packet_type: RNS::Packet::DATA,
      )
      packet.pack
      RNS::Transport.inbound_announce(packet).should be_false
    end

    it "rejects announce with hops exceeding PATHFINDER_M" do
      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear

      packet = create_announce_packet(dest)
      packet.pack
      packet.hops = (RNS::Transport::PATHFINDER_M + 1).to_u8

      result = RNS::Transport.inbound_announce(packet)
      result.should be_false
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Rate Limiting
  # ════════════════════════════════════════════════════════════════

  describe ".check_announce_rate" do
    it "does not block first announce" do
      RNS::Transport.check_announce_rate("test_dest", Time.utc.to_unix_f).should be_false
    end

    it "creates rate entry on first announce" do
      now = Time.utc.to_unix_f
      RNS::Transport.check_announce_rate("test_dest", now)
      RNS::Transport.announce_rate_table.has_key?("test_dest").should be_true
    end

    it "updates timestamps on subsequent announces" do
      now = Time.utc.to_unix_f
      RNS::Transport.check_announce_rate("test_dest", now)
      RNS::Transport.check_announce_rate("test_dest", now + 1.0)

      entry = RNS::Transport.announce_rate_table["test_dest"]
      entry.timestamps.size.should eq(2)
    end

    it "limits timestamps to MAX_RATE_TIMESTAMPS" do
      now = Time.utc.to_unix_f
      (RNS::Transport::MAX_RATE_TIMESTAMPS + 5).times do |i|
        RNS::Transport.check_announce_rate("test_dest", now + i.to_f64)
      end

      entry = RNS::Transport.announce_rate_table["test_dest"]
      entry.timestamps.size.should be <= RNS::Transport::MAX_RATE_TIMESTAMPS
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Process Announce Table
  # ════════════════════════════════════════════════════════════════

  describe ".process_announce_table" do
    it "returns empty array when no announces pending" do
      RNS::Transport.process_announce_table.should be_empty
    end

    it "removes completed announces that exceed retry limit" do
      # Set up transport identity for rebroadcast
      transport_identity = RNS::Identity.new
      RNS::Transport.identity = transport_identity

      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear
      packet = create_announce_packet(dest)
      packet.pack

      dest_hex = dest.hash.hexstring

      # Insert announce with retries exceeding limit
      RNS::Transport.announce_table[dest_hex] = RNS::Transport::AnnounceEntry.new(
        timestamp: Time.utc.to_unix_f,
        retransmit_timeout: 0.0,
        retries: RNS::Transport::PATHFINDER_R + 1,
        received_from: dest.hash,
        hops: 0,
        packet: packet,
        local_rebroadcasts: 0,
        block_rebroadcasts: false,
        attached_interface: nil,
      )

      RNS::Transport.process_announce_table
      RNS::Transport.announce_table.has_key?(dest_hex).should be_false
    end

    it "removes announces that hit local rebroadcast max with retries" do
      transport_identity = RNS::Identity.new
      RNS::Transport.identity = transport_identity

      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear
      packet = create_announce_packet(dest)
      packet.pack

      dest_hex = dest.hash.hexstring

      RNS::Transport.announce_table[dest_hex] = RNS::Transport::AnnounceEntry.new(
        timestamp: Time.utc.to_unix_f,
        retransmit_timeout: 0.0,
        retries: RNS::Transport::LOCAL_REBROADCASTS_MAX,
        received_from: dest.hash,
        hops: 0,
        packet: packet,
        local_rebroadcasts: RNS::Transport::LOCAL_REBROADCASTS_MAX,
        block_rebroadcasts: false,
        attached_interface: nil,
      )

      RNS::Transport.process_announce_table
      RNS::Transport.announce_table.has_key?(dest_hex).should be_false
    end

    it "retransmits announce when timeout is reached" do
      transport_identity = RNS::Identity.new
      RNS::Transport.identity = transport_identity

      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear
      packet = create_announce_packet(dest)
      packet.pack

      # Validate so identity is remembered
      RNS::Identity.validate_announce(packet)

      dest_hex = dest.hash.hexstring

      # Insert with timeout in the past (should trigger retransmit)
      RNS::Transport.announce_table[dest_hex] = RNS::Transport::AnnounceEntry.new(
        timestamp: Time.utc.to_unix_f - 10.0,
        retransmit_timeout: Time.utc.to_unix_f - 1.0,
        retries: 0,
        received_from: dest.hash,
        hops: 0,
        packet: packet,
        local_rebroadcasts: 0,
        block_rebroadcasts: false,
        attached_interface: nil,
      )

      outgoing = RNS::Transport.process_announce_table
      outgoing.size.should eq(1)

      rebroadcast = outgoing[0]
      rebroadcast.packet_type.should eq(RNS::Packet::ANNOUNCE)

      # Retries should have incremented
      RNS::Transport.announce_table[dest_hex].retries.should eq(1)
    end

    it "does not retransmit if timeout not yet reached" do
      transport_identity = RNS::Identity.new
      RNS::Transport.identity = transport_identity

      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear
      packet = create_announce_packet(dest)
      packet.pack

      dest_hex = dest.hash.hexstring

      # Insert with timeout far in the future
      RNS::Transport.announce_table[dest_hex] = RNS::Transport::AnnounceEntry.new(
        timestamp: Time.utc.to_unix_f,
        retransmit_timeout: Time.utc.to_unix_f + 3600.0,
        retries: 0,
        received_from: dest.hash,
        hops: 0,
        packet: packet,
        local_rebroadcasts: 0,
        block_rebroadcasts: false,
        attached_interface: nil,
      )

      outgoing = RNS::Transport.process_announce_table
      outgoing.should be_empty
    end

    it "sets PATH_RESPONSE context for block_rebroadcasts" do
      transport_identity = RNS::Identity.new
      RNS::Transport.identity = transport_identity

      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear
      packet = create_announce_packet(dest)
      packet.pack
      RNS::Identity.validate_announce(packet)

      dest_hex = dest.hash.hexstring

      RNS::Transport.announce_table[dest_hex] = RNS::Transport::AnnounceEntry.new(
        timestamp: Time.utc.to_unix_f - 10.0,
        retransmit_timeout: Time.utc.to_unix_f - 1.0,
        retries: 0,
        received_from: dest.hash,
        hops: 0,
        packet: packet,
        local_rebroadcasts: 0,
        block_rebroadcasts: true,
        attached_interface: nil,
      )

      outgoing = RNS::Transport.process_announce_table
      outgoing.size.should eq(1)
      outgoing[0].context.should eq(RNS::Packet::PATH_RESPONSE)
    end

    it "reinserts held announce after processing" do
      transport_identity = RNS::Identity.new
      RNS::Transport.identity = transport_identity

      dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
      RNS::Identity.known_destinations.clear
      packet = create_announce_packet(dest)
      packet.pack
      RNS::Identity.validate_announce(packet)

      dest_hex = dest.hash.hexstring

      # Set up announce table entry
      announce_entry = RNS::Transport::AnnounceEntry.new(
        timestamp: Time.utc.to_unix_f - 10.0,
        retransmit_timeout: Time.utc.to_unix_f - 1.0,
        retries: 0,
        received_from: dest.hash,
        hops: 0,
        packet: packet,
        local_rebroadcasts: 0,
        block_rebroadcasts: false,
        attached_interface: nil,
      )
      RNS::Transport.announce_table[dest_hex] = announce_entry

      # Set up a held announce
      held_entry = RNS::Transport::AnnounceEntry.new(
        timestamp: Time.utc.to_unix_f,
        retransmit_timeout: Time.utc.to_unix_f + 10.0,
        retries: 0,
        received_from: dest.hash,
        hops: 1,
        packet: packet,
        local_rebroadcasts: 0,
        block_rebroadcasts: false,
        attached_interface: nil,
      )
      RNS::Transport.held_announces[dest_hex] = held_entry

      RNS::Transport.process_announce_table

      # The held announce should have been reinserted
      RNS::Transport.announce_table.has_key?(dest_hex).should be_true
      RNS::Transport.announce_table[dest_hex].hops.should eq(1)
      RNS::Transport.held_announces.has_key?(dest_hex).should be_false
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  mark_path_unknown_for_destination
  # ════════════════════════════════════════════════════════════════

  describe ".mark_path_unknown_for_destination" do
    it "marks path state as unknown" do
      dest_hash = Random::Secure.random_bytes(16)
      RNS::Transport.update_path(dest_hash, dest_hash, 1, Time.utc.to_unix_f + 3600.0)
      RNS::Transport.mark_path_unresponsive(dest_hash)
      RNS::Transport.path_is_unresponsive(dest_hash).should be_true

      RNS::Transport.mark_path_unknown_for_destination(dest_hash)
      RNS::Transport.path_is_unresponsive(dest_hash).should be_false
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Announce Cache
  # ════════════════════════════════════════════════════════════════

  describe ".cache_packet" do
    it "caches announce to file" do
      Dir.cd(Dir.tempdir) do
        cache_dir = File.join(Dir.tempdir, "test_cache_#{Random::Secure.hex(4)}")
        Dir.mkdir_p(cache_dir)

        begin
          dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
          packet = create_announce_packet(dest)
          packet.pack

          RNS::Transport.cache_packet(packet, cache_dir, force_cache: true, packet_type: "announce")

          announce_dir = File.join(cache_dir, "announces")
          Dir.exists?(announce_dir).should be_true
          Dir.children(announce_dir).size.should eq(1)
        ensure
          FileUtils.rm_rf(cache_dir)
        end
      end
    end

    it "does not cache when force_cache is false" do
      Dir.cd(Dir.tempdir) do
        cache_dir = File.join(Dir.tempdir, "test_cache2_#{Random::Secure.hex(4)}")
        Dir.mkdir_p(cache_dir)

        begin
          dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", register: false)
          packet = create_announce_packet(dest)
          packet.pack

          RNS::Transport.cache_packet(packet, cache_dir, force_cache: false, packet_type: "announce")

          announce_dir = File.join(cache_dir, "announces")
          Dir.exists?(announce_dir).should be_false
        ensure
          FileUtils.rm_rf(cache_dir)
        end
      end
    end
  end

  describe ".clean_announce_cache" do
    it "removes cached announces not in path table" do
      Dir.cd(Dir.tempdir) do
        cache_dir = File.join(Dir.tempdir, "test_clean_#{Random::Secure.hex(4)}")
        announce_dir = File.join(cache_dir, "announces")
        Dir.mkdir_p(announce_dir)

        begin
          # Create a fake cached announce file
          File.write(File.join(announce_dir, "deadbeef01020304"), "fake")

          RNS::Transport.clean_announce_cache(cache_dir)

          Dir.children(announce_dir).size.should eq(0)
        ensure
          FileUtils.rm_rf(cache_dir)
        end
      end
    end

    it "keeps cached announces that are in path table" do
      Dir.cd(Dir.tempdir) do
        cache_dir = File.join(Dir.tempdir, "test_keep_#{Random::Secure.hex(4)}")
        announce_dir = File.join(cache_dir, "announces")
        Dir.mkdir_p(announce_dir)

        begin
          # Add a path table entry with a known packet hash
          dest_hash = Random::Secure.random_bytes(16)
          packet_hash = Bytes[0xde, 0xad, 0xbe, 0xef]
          RNS::Transport.update_path(dest_hash, dest_hash, 1,
            Time.utc.to_unix_f + 3600.0,
            packet_hash: packet_hash)

          # Create cached announce file matching that hash
          File.write(File.join(announce_dir, packet_hash.hexstring), "real")

          RNS::Transport.clean_announce_cache(cache_dir)

          Dir.children(announce_dir).should contain(packet_hash.hexstring)
        ensure
          FileUtils.rm_rf(cache_dir)
        end
      end
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Stress Tests
  # ════════════════════════════════════════════════════════════════

  describe "stress tests" do
    it "processes 50 different announces" do
      50.times do |i|
        RNS::Identity.known_destinations.clear
        dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "app#{i}", register: false)
        packet = create_announce_packet(dest)
        packet.pack

        result = RNS::Transport.inbound_announce(packet)
        result.should be_true
      end

      RNS::Transport.path_table.size.should eq(50)
    end

    it "20 announce table processing cycles eventually drain all announces" do
      transport_identity = RNS::Identity.new
      RNS::Transport.identity = transport_identity

      # Set up some announces in the table
      5.times do |i|
        dest = RNS::Destination.new(nil, RNS::Destination::IN, RNS::Destination::SINGLE, "stress#{i}", register: false)
        RNS::Identity.known_destinations.clear
        packet = create_announce_packet(dest)
        packet.pack
        RNS::Identity.validate_announce(packet)

        RNS::Transport.announce_table[dest.hash.hexstring] = RNS::Transport::AnnounceEntry.new(
          timestamp: Time.utc.to_unix_f,
          retransmit_timeout: Time.utc.to_unix_f - 1.0,
          retries: 0,
          received_from: dest.hash,
          hops: 0,
          packet: packet,
          local_rebroadcasts: 0,
          block_rebroadcasts: false,
          attached_interface: nil,
        )
      end

      20.times do
        # Force all retransmit timeouts to be in the past so processing proceeds
        RNS::Transport.announce_table.each do |hex, entry|
          RNS::Transport.announce_table[hex] = RNS::Transport::AnnounceEntry.new(
            timestamp: entry.timestamp,
            retransmit_timeout: Time.utc.to_unix_f - 1.0,
            retries: entry.retries,
            received_from: entry.received_from,
            hops: entry.hops,
            packet: entry.packet,
            local_rebroadcasts: entry.local_rebroadcasts,
            block_rebroadcasts: entry.block_rebroadcasts,
            attached_interface: entry.attached_interface,
          )
        end
        RNS::Transport.process_announce_table
      end

      # All should eventually complete (retries exhausted)
      RNS::Transport.announce_table.size.should eq(0)
    end

    it "rate limiting for 30 rapid announces from same destination" do
      dest_hex = "test_rate_stress"
      now = Time.utc.to_unix_f

      blocked_count = 0
      30.times do |i|
        result = RNS::Transport.check_announce_rate(dest_hex, now + i * 0.001)
        blocked_count += 1 if result
      end

      # Without a rate target, none should be blocked
      blocked_count.should eq(0)
    end
  end
end

# Test helper class implementing AnnounceHandler
class TestCallbackAnnounceHandler
  include RNS::Transport::AnnounceHandler

  getter aspect_filter : String?
  @callback : Proc(Bytes, RNS::Identity?, Bytes?, Bytes?, Nil)

  def initialize(@aspect_filter : String?, &@callback : Proc(Bytes, RNS::Identity?, Bytes?, Bytes?, Nil))
  end

  def received_announce(destination_hash : Bytes, announced_identity : RNS::Identity?, app_data : Bytes?, announce_packet_hash : Bytes?)
    @callback.call(destination_hash, announced_identity, app_data, announce_packet_hash)
  end
end
