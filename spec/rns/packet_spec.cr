require "../spec_helper"

describe RNS::Packet do
  # ─── Constants ───────────────────────────────────────────────────────
  describe "constants" do
    it "has DATA = 0x00" do
      RNS::Packet::DATA.should eq 0x00_u8
    end

    it "has ANNOUNCE = 0x01" do
      RNS::Packet::ANNOUNCE.should eq 0x01_u8
    end

    it "has LINKREQUEST = 0x02" do
      RNS::Packet::LINKREQUEST.should eq 0x02_u8
    end

    it "has PROOF = 0x03" do
      RNS::Packet::PROOF.should eq 0x03_u8
    end

    it "has HEADER_1 = 0x00" do
      RNS::Packet::HEADER_1.should eq 0x00_u8
    end

    it "has HEADER_2 = 0x01" do
      RNS::Packet::HEADER_2.should eq 0x01_u8
    end

    it "has correct context types" do
      RNS::Packet::NONE.should eq 0x00_u8
      RNS::Packet::RESOURCE.should eq 0x01_u8
      RNS::Packet::RESOURCE_ADV.should eq 0x02_u8
      RNS::Packet::RESOURCE_REQ.should eq 0x03_u8
      RNS::Packet::RESOURCE_HMU.should eq 0x04_u8
      RNS::Packet::RESOURCE_PRF.should eq 0x05_u8
      RNS::Packet::RESOURCE_ICL.should eq 0x06_u8
      RNS::Packet::RESOURCE_RCL.should eq 0x07_u8
      RNS::Packet::CACHE_REQUEST.should eq 0x08_u8
      RNS::Packet::REQUEST.should eq 0x09_u8
      RNS::Packet::RESPONSE.should eq 0x0A_u8
      RNS::Packet::PATH_RESPONSE.should eq 0x0B_u8
      RNS::Packet::COMMAND.should eq 0x0C_u8
      RNS::Packet::COMMAND_STATUS.should eq 0x0D_u8
      RNS::Packet::CHANNEL.should eq 0x0E_u8
      RNS::Packet::KEEPALIVE.should eq 0xFA_u8
      RNS::Packet::LINKIDENTIFY.should eq 0xFB_u8
      RNS::Packet::LINKCLOSE.should eq 0xFC_u8
      RNS::Packet::LINKPROOF.should eq 0xFD_u8
      RNS::Packet::LRRTT.should eq 0xFE_u8
      RNS::Packet::LRPROOF.should eq 0xFF_u8
    end

    it "has correct flag values" do
      RNS::Packet::FLAG_SET.should eq 0x01_u8
      RNS::Packet::FLAG_UNSET.should eq 0x00_u8
    end

    it "has correct MTU/MDU constants" do
      RNS::Packet::HEADER_MAXSIZE.should eq 35
      RNS::Packet::HEADER_MINSIZE.should eq 19
      RNS::Packet::MDU.should eq 464
      RNS::Packet::PLAIN_MDU.should eq 464
      RNS::Packet::ENCRYPTED_MDU.should eq 383
    end

    it "has TIMEOUT_PER_HOP = 6" do
      RNS::Packet::TIMEOUT_PER_HOP.should eq 6
    end
  end

  # ─── Reticulum constants (used by Packet) ────────────────────────────
  describe "Reticulum constants" do
    it "has MTU = 500" do
      RNS::Reticulum::MTU.should eq 500
    end

    it "has TRUNCATED_HASHLENGTH = 128" do
      RNS::Reticulum::TRUNCATED_HASHLENGTH.should eq 128
    end

    it "has HEADER_MAXSIZE = 35" do
      RNS::Reticulum::HEADER_MAXSIZE.should eq 35
    end

    it "has HEADER_MINSIZE = 19" do
      RNS::Reticulum::HEADER_MINSIZE.should eq 19
    end
  end

  # ─── Transport type constants ────────────────────────────────────────
  describe "Transport constants" do
    it "has BROADCAST = 0x00" do
      RNS::Transport::BROADCAST.should eq 0x00_u8
    end

    it "has TRANSPORT = 0x01" do
      RNS::Transport::TRANSPORT.should eq 0x01_u8
    end

    it "has RELAY = 0x02" do
      RNS::Transport::RELAY.should eq 0x02_u8
    end

    it "has TUNNEL = 0x03" do
      RNS::Transport::TUNNEL.should eq 0x03_u8
    end
  end

  # ─── Destination type constants ──────────────────────────────────────
  describe "Destination constants" do
    it "has SINGLE = 0x00" do
      RNS::Destination::SINGLE.should eq 0x00_u8
    end

    it "has GROUP = 0x01" do
      RNS::Destination::GROUP.should eq 0x01_u8
    end

    it "has PLAIN = 0x02" do
      RNS::Destination::PLAIN.should eq 0x02_u8
    end

    it "has LINK = 0x03" do
      RNS::Destination::LINK.should eq 0x03_u8
    end
  end

  # ─── Flag packing ───────────────────────────────────────────────────
  describe "#get_packed_flags" do
    it "packs HEADER_1, BROADCAST, SINGLE, DATA correctly" do
      # flags = (0 << 6) | (0 << 5) | (0 << 4) | (0 << 2) | 0 = 0x00
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::SINGLE
      )
      pkt = RNS::Packet.new(dest, Bytes[0x01, 0x02, 0x03])
      pkt.get_packed_flags.should eq 0x00_u8
    end

    it "packs HEADER_2, TRANSPORT, GROUP, ANNOUNCE correctly" do
      # flags = (1 << 6) | (0 << 5) | (1 << 4) | (1 << 2) | 1 = 0x55
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::GROUP
      )
      pkt = RNS::Packet.new(dest, Bytes[0x01],
        packet_type: RNS::Packet::ANNOUNCE,
        transport_type: RNS::Transport::TRANSPORT,
        header_type: RNS::Packet::HEADER_2,
        transport_id: RNS::Identity.get_random_hash
      )
      pkt.get_packed_flags.should eq 0x55_u8
    end

    it "packs HEADER_1, BROADCAST, PLAIN, LINKREQUEST correctly" do
      # flags = (0 << 6) | (0 << 5) | (0 << 4) | (2 << 2) | 2 = 0x0A
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::PLAIN
      )
      pkt = RNS::Packet.new(dest, Bytes[0x01],
        packet_type: RNS::Packet::LINKREQUEST
      )
      pkt.get_packed_flags.should eq 0x0A_u8
    end

    it "packs context_flag correctly" do
      # flags = (0 << 6) | (1 << 5) | (0 << 4) | (0 << 2) | 0 = 0x20
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::SINGLE
      )
      pkt = RNS::Packet.new(dest, Bytes[0x01],
        context_flag: RNS::Packet::FLAG_SET
      )
      pkt.get_packed_flags.should eq 0x20_u8
    end

    it "uses LINK type for LRPROOF context" do
      # LRPROOF forces destination type to LINK (0x03)
      # flags = (0 << 6) | (0 << 5) | (0 << 4) | (3 << 2) | 0 = 0x0C
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::SINGLE
      )
      pkt = RNS::Packet.new(dest, Bytes[0x01],
        context: RNS::Packet::LRPROOF
      )
      pkt.get_packed_flags.should eq 0x0C_u8
    end
  end

  # ─── Pack ────────────────────────────────────────────────────────────
  describe "#pack" do
    it "packs a HEADER_1 DATA packet with PLAIN destination (no encryption)" do
      dest_hash = RNS::Identity.get_random_hash
      dest = RNS::Destination::Stub.new(
        hash: dest_hash,
        type: RNS::Destination::PLAIN
      )
      payload = Bytes[0xDE, 0xAD, 0xBE, 0xEF]
      pkt = RNS::Packet.new(dest, payload)
      pkt.pack

      raw = pkt.raw.not_nil!
      # Header: flags(1) + hops(1) + dest_hash(16) + context(1) = 19 + payload(4) = 23
      raw.size.should eq 23

      # Verify flags byte
      raw[0].should eq 0x08_u8 # PLAIN(2) << 2 = 0x08

      # Verify hops
      raw[1].should eq 0x00_u8

      # Verify destination hash
      raw[2, 16].should eq dest_hash

      # Verify context byte
      raw[18].should eq RNS::Packet::NONE

      # Verify data (PLAIN destinations don't encrypt)
      raw[19, 4].should eq payload

      pkt.packed.should be_true
      pkt.packet_hash.should_not be_nil
    end

    it "packs a HEADER_1 ANNOUNCE packet (no encryption)" do
      dest_hash = RNS::Identity.get_random_hash
      dest = RNS::Destination::Stub.new(
        hash: dest_hash,
        type: RNS::Destination::SINGLE
      )
      payload = Random::Secure.random_bytes(64)
      pkt = RNS::Packet.new(dest, payload,
        packet_type: RNS::Packet::ANNOUNCE
      )
      pkt.pack

      raw = pkt.raw.not_nil!
      # flags(1) + hops(1) + dest_hash(16) + context(1) + payload(64) = 83
      raw.size.should eq 83
      # ANNOUNCE packets are not encrypted — data should be unchanged
      raw[19, 64].should eq payload
    end

    it "packs a HEADER_1 LINKREQUEST packet (no encryption)" do
      dest_hash = RNS::Identity.get_random_hash
      dest = RNS::Destination::Stub.new(
        hash: dest_hash,
        type: RNS::Destination::SINGLE
      )
      payload = Random::Secure.random_bytes(32)
      pkt = RNS::Packet.new(dest, payload,
        packet_type: RNS::Packet::LINKREQUEST
      )
      pkt.pack

      raw = pkt.raw.not_nil!
      raw[19, 32].should eq payload
    end

    it "packs a HEADER_1 RESOURCE context (no encryption by packet)" do
      dest_hash = RNS::Identity.get_random_hash
      dest = RNS::Destination::Stub.new(
        hash: dest_hash,
        type: RNS::Destination::SINGLE
      )
      payload = Random::Secure.random_bytes(50)
      pkt = RNS::Packet.new(dest, payload,
        context: RNS::Packet::RESOURCE
      )
      pkt.pack

      raw = pkt.raw.not_nil!
      raw[19, 50].should eq payload
    end

    it "packs a HEADER_1 KEEPALIVE context (no encryption)" do
      dest_hash = RNS::Identity.get_random_hash
      dest = RNS::Destination::Stub.new(
        hash: dest_hash,
        type: RNS::Destination::SINGLE
      )
      pkt = RNS::Packet.new(dest, Bytes.empty,
        context: RNS::Packet::KEEPALIVE
      )
      pkt.pack

      raw = pkt.raw.not_nil!
      # flags(1) + hops(1) + dest_hash(16) + context(1) = 19
      raw.size.should eq 19
      raw[18].should eq RNS::Packet::KEEPALIVE
    end

    it "packs a HEADER_1 CACHE_REQUEST context (no encryption)" do
      dest_hash = RNS::Identity.get_random_hash
      dest = RNS::Destination::Stub.new(
        hash: dest_hash,
        type: RNS::Destination::SINGLE
      )
      payload = Random::Secure.random_bytes(16)
      pkt = RNS::Packet.new(dest, payload,
        context: RNS::Packet::CACHE_REQUEST
      )
      pkt.pack

      raw = pkt.raw.not_nil!
      raw[19, 16].should eq payload
    end

    it "packs a HEADER_2 packet with transport_id" do
      dest_hash = RNS::Identity.get_random_hash
      transport_id = RNS::Identity.get_random_hash
      dest = RNS::Destination::Stub.new(
        hash: dest_hash,
        type: RNS::Destination::SINGLE
      )
      payload = Random::Secure.random_bytes(32)
      pkt = RNS::Packet.new(dest, payload,
        packet_type: RNS::Packet::ANNOUNCE,
        header_type: RNS::Packet::HEADER_2,
        transport_type: RNS::Transport::TRANSPORT,
        transport_id: transport_id
      )
      pkt.pack

      raw = pkt.raw.not_nil!
      # flags(1) + hops(1) + transport_id(16) + dest_hash(16) + context(1) + payload(32) = 67
      raw.size.should eq 67

      # Verify transport_id in header
      raw[2, 16].should eq transport_id
      # Verify dest_hash after transport_id
      raw[18, 16].should eq dest_hash
      # Verify context byte
      raw[34].should eq RNS::Packet::NONE
      # Verify payload
      raw[35, 32].should eq payload
    end

    it "raises on HEADER_2 without transport_id" do
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::SINGLE
      )
      pkt = RNS::Packet.new(dest, Bytes[0x01],
        header_type: RNS::Packet::HEADER_2
      )
      expect_raises(IO::Error, "transport ID") do
        pkt.pack
      end
    end

    it "raises when packed size exceeds MTU" do
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::PLAIN
      )
      # HEADER_1 header = 19 bytes, so payload > 481 bytes exceeds MTU of 500
      payload = Random::Secure.random_bytes(482)
      pkt = RNS::Packet.new(dest, payload)
      expect_raises(IO::Error, "exceeds MTU") do
        pkt.pack
      end
    end

    it "packs a PROOF with RESOURCE_PRF context (no encryption)" do
      dest_hash = RNS::Identity.get_random_hash
      dest = RNS::Destination::Stub.new(
        hash: dest_hash,
        type: RNS::Destination::SINGLE
      )
      payload = Random::Secure.random_bytes(64)
      pkt = RNS::Packet.new(dest, payload,
        packet_type: RNS::Packet::PROOF,
        context: RNS::Packet::RESOURCE_PRF
      )
      pkt.pack

      raw = pkt.raw.not_nil!
      raw[19, 64].should eq payload
    end

    it "packs a PROOF with LINK destination (no encryption)" do
      dest_hash = RNS::Identity.get_random_hash
      dest = RNS::Destination::Stub.new(
        hash: dest_hash,
        type: RNS::Destination::LINK
      )
      payload = Random::Secure.random_bytes(64)
      pkt = RNS::Packet.new(dest, payload,
        packet_type: RNS::Packet::PROOF
      )
      pkt.pack

      raw = pkt.raw.not_nil!
      raw[19, 64].should eq payload
    end

    it "encrypts data for SINGLE destination DATA packet" do
      identity = RNS::Identity.new
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::SINGLE,
        identity: identity
      )
      payload = Bytes[0x48, 0x65, 0x6C, 0x6C, 0x6F] # "Hello"
      pkt = RNS::Packet.new(dest, payload)
      pkt.pack

      raw = pkt.raw.not_nil!
      # Encrypted data should be larger than plaintext (ephemeral key + token overhead)
      ciphertext = raw[19..]
      ciphertext.size.should be > payload.size
      ciphertext.should_not eq payload
    end

    it "sets destination_hash on pack" do
      dest_hash = RNS::Identity.get_random_hash
      dest = RNS::Destination::Stub.new(
        hash: dest_hash,
        type: RNS::Destination::PLAIN
      )
      pkt = RNS::Packet.new(dest, Bytes[0x01])
      pkt.pack
      pkt.destination_hash.should eq dest_hash
    end

    it "computes packet_hash on pack" do
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::PLAIN
      )
      pkt = RNS::Packet.new(dest, Bytes[0x01, 0x02])
      pkt.pack
      pkt.packet_hash.should_not be_nil
      pkt.packet_hash.not_nil!.size.should eq 32 # SHA-256 full hash
    end
  end

  # ─── Unpack ──────────────────────────────────────────────────────────
  describe "#unpack" do
    it "unpacks a HEADER_1 PLAIN DATA packet" do
      # Construct raw bytes manually
      dest_hash = RNS::Identity.get_random_hash
      payload = Bytes[0xCA, 0xFE, 0xBA, 0xBE]
      flags = (RNS::Packet::HEADER_1.to_u8 << 6) |
              (RNS::Packet::FLAG_UNSET.to_u8 << 5) |
              (RNS::Transport::BROADCAST.to_u8 << 4) |
              (RNS::Destination::PLAIN.to_u8 << 2) |
              RNS::Packet::DATA.to_u8
      hops = 0x03_u8
      context = RNS::Packet::NONE

      raw = IO::Memory.new
      raw.write_byte(flags)
      raw.write_byte(hops)
      raw.write(dest_hash)
      raw.write_byte(context)
      raw.write(payload)

      pkt = RNS::Packet.new(nil, raw.to_slice)
      result = pkt.unpack
      result.should be_true

      pkt.header_type.should eq RNS::Packet::HEADER_1
      pkt.transport_type.should eq RNS::Transport::BROADCAST
      pkt.destination_type.should eq RNS::Destination::PLAIN
      pkt.packet_type.should eq RNS::Packet::DATA
      pkt.context_flag.should eq RNS::Packet::FLAG_UNSET
      pkt.hops.should eq 3
      pkt.destination_hash.should eq dest_hash
      pkt.context.should eq RNS::Packet::NONE
      pkt.data.should eq payload
      pkt.transport_id.should be_nil
      pkt.packed.should be_false
      pkt.packet_hash.should_not be_nil
    end

    it "unpacks a HEADER_2 ANNOUNCE packet" do
      dest_hash = RNS::Identity.get_random_hash
      transport_id = RNS::Identity.get_random_hash
      payload = Random::Secure.random_bytes(50)
      flags = (RNS::Packet::HEADER_2.to_u8 << 6) |
              (RNS::Packet::FLAG_UNSET.to_u8 << 5) |
              (RNS::Transport::TRANSPORT.to_u8 << 4) |
              (RNS::Destination::SINGLE.to_u8 << 2) |
              RNS::Packet::ANNOUNCE.to_u8
      hops = 0x05_u8
      context = RNS::Packet::NONE

      raw = IO::Memory.new
      raw.write_byte(flags)
      raw.write_byte(hops)
      raw.write(transport_id)
      raw.write(dest_hash)
      raw.write_byte(context)
      raw.write(payload)

      pkt = RNS::Packet.new(nil, raw.to_slice)
      result = pkt.unpack
      result.should be_true

      pkt.header_type.should eq RNS::Packet::HEADER_2
      pkt.transport_type.should eq RNS::Transport::TRANSPORT
      pkt.destination_type.should eq RNS::Destination::SINGLE
      pkt.packet_type.should eq RNS::Packet::ANNOUNCE
      pkt.hops.should eq 5
      pkt.transport_id.should eq transport_id
      pkt.destination_hash.should eq dest_hash
      pkt.data.should eq payload
    end

    it "returns false for malformed (too short) packets" do
      pkt = RNS::Packet.new(nil, Bytes[0x00])
      result = pkt.unpack
      result.should be_false
    end

    it "returns false for empty raw data" do
      pkt = RNS::Packet.new(nil, Bytes.empty)
      result = pkt.unpack
      result.should be_false
    end
  end

  # ─── Pack/Unpack roundtrip ──────────────────────────────────────────
  describe "pack/unpack roundtrip" do
    it "roundtrips a HEADER_1 PLAIN packet" do
      dest_hash = RNS::Identity.get_random_hash
      dest = RNS::Destination::Stub.new(
        hash: dest_hash,
        type: RNS::Destination::PLAIN
      )
      payload = Random::Secure.random_bytes(100)
      pkt1 = RNS::Packet.new(dest, payload)
      pkt1.pack

      pkt2 = RNS::Packet.new(nil, pkt1.raw.not_nil!)
      pkt2.unpack.should be_true

      pkt2.header_type.should eq RNS::Packet::HEADER_1
      pkt2.transport_type.should eq RNS::Transport::BROADCAST
      pkt2.destination_type.should eq RNS::Destination::PLAIN
      pkt2.packet_type.should eq RNS::Packet::DATA
      pkt2.destination_hash.should eq dest_hash
      pkt2.context.should eq RNS::Packet::NONE
      pkt2.data.should eq payload
    end

    it "roundtrips a HEADER_2 ANNOUNCE packet" do
      dest_hash = RNS::Identity.get_random_hash
      transport_id = RNS::Identity.get_random_hash
      dest = RNS::Destination::Stub.new(
        hash: dest_hash,
        type: RNS::Destination::SINGLE
      )
      payload = Random::Secure.random_bytes(64)
      pkt1 = RNS::Packet.new(dest, payload,
        packet_type: RNS::Packet::ANNOUNCE,
        header_type: RNS::Packet::HEADER_2,
        transport_type: RNS::Transport::TRANSPORT,
        transport_id: transport_id
      )
      pkt1.pack

      pkt2 = RNS::Packet.new(nil, pkt1.raw.not_nil!)
      pkt2.unpack.should be_true

      pkt2.header_type.should eq RNS::Packet::HEADER_2
      pkt2.transport_type.should eq RNS::Transport::TRANSPORT
      pkt2.destination_type.should eq RNS::Destination::SINGLE
      pkt2.packet_type.should eq RNS::Packet::ANNOUNCE
      pkt2.transport_id.should eq transport_id
      pkt2.destination_hash.should eq dest_hash
      pkt2.data.should eq payload
    end

    it "preserves packet hash across pack/unpack" do
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::PLAIN
      )
      pkt1 = RNS::Packet.new(dest, Random::Secure.random_bytes(50))
      pkt1.pack

      pkt2 = RNS::Packet.new(nil, pkt1.raw.not_nil!)
      pkt2.unpack.should be_true

      pkt1.packet_hash.should eq pkt2.packet_hash
    end

    it "roundtrips 100 random PLAIN packets" do
      100.times do
        dest_hash = RNS::Identity.get_random_hash
        dest = RNS::Destination::Stub.new(
          hash: dest_hash,
          type: RNS::Destination::PLAIN
        )
        payload_size = rand(0..RNS::Packet::PLAIN_MDU)
        payload = Random::Secure.random_bytes(payload_size)
        pkt1 = RNS::Packet.new(dest, payload)
        pkt1.pack

        pkt2 = RNS::Packet.new(nil, pkt1.raw.not_nil!)
        pkt2.unpack.should be_true
        pkt2.destination_hash.should eq dest_hash
        pkt2.data.should eq payload
        pkt1.packet_hash.should eq pkt2.packet_hash
      end
    end
  end

  # ─── Hash computation ───────────────────────────────────────────────
  describe "#get_hash and #get_hashable_part" do
    it "computes hash from hashable part (HEADER_1)" do
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::PLAIN
      )
      pkt = RNS::Packet.new(dest, Bytes[0x01, 0x02, 0x03])
      pkt.pack

      hashable = pkt.get_hashable_part
      # Hashable part: masked flags byte (lower nibble only) + raw[2:]
      hashable[0].should eq(pkt.raw.not_nil![0] & 0x0F_u8)
      hashable[1..].should eq pkt.raw.not_nil![2..]

      pkt.get_hash.should eq RNS::Identity.full_hash(hashable)
    end

    it "excludes transport_id from hashable part (HEADER_2)" do
      dest_hash = RNS::Identity.get_random_hash
      transport_id = RNS::Identity.get_random_hash
      dest = RNS::Destination::Stub.new(
        hash: dest_hash,
        type: RNS::Destination::SINGLE
      )
      pkt = RNS::Packet.new(dest, Bytes[0x01],
        packet_type: RNS::Packet::ANNOUNCE,
        header_type: RNS::Packet::HEADER_2,
        transport_type: RNS::Transport::TRANSPORT,
        transport_id: transport_id
      )
      pkt.pack

      hashable = pkt.get_hashable_part
      raw = pkt.raw.not_nil!
      dst_len = RNS::Identity::TRUNCATED_HASHLENGTH // 8

      # For HEADER_2: skip flags(1) + hops(1) + transport_id(16) = first 18 bytes
      # hashable = masked flags + raw[18:]
      hashable[0].should eq(raw[0] & 0x0F_u8)
      hashable[1..].should eq raw[(dst_len + 2)..]
    end

    it "produces different hashes for different payloads" do
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::PLAIN
      )
      pkt1 = RNS::Packet.new(dest, Bytes[0x01])
      pkt1.pack
      pkt2 = RNS::Packet.new(dest, Bytes[0x02])
      pkt2.pack

      pkt1.packet_hash.should_not eq pkt2.packet_hash
    end

    it "produces same hash regardless of header type (transport stripped)" do
      dest_hash = RNS::Identity.get_random_hash
      transport_id = RNS::Identity.get_random_hash
      payload = Random::Secure.random_bytes(32)

      dest = RNS::Destination::Stub.new(
        hash: dest_hash,
        type: RNS::Destination::SINGLE
      )

      # HEADER_1 packet
      pkt1 = RNS::Packet.new(dest, payload,
        packet_type: RNS::Packet::ANNOUNCE
      )
      pkt1.pack

      # HEADER_2 packet with same payload and destination
      pkt2 = RNS::Packet.new(dest, payload,
        packet_type: RNS::Packet::ANNOUNCE,
        header_type: RNS::Packet::HEADER_2,
        transport_type: RNS::Transport::TRANSPORT,
        transport_id: transport_id
      )
      pkt2.pack

      # Hashes should match because transport info is stripped from hashable part
      pkt1.packet_hash.should eq pkt2.packet_hash
    end
  end

  # ─── Truncated hash ─────────────────────────────────────────────────
  describe "#get_truncated_hash" do
    it "returns first 16 bytes of full hash" do
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::PLAIN
      )
      pkt = RNS::Packet.new(dest, Bytes[0x01])
      pkt.pack

      truncated = pkt.get_truncated_hash
      truncated.size.should eq 16
      truncated.should eq pkt.get_hash[0, 16]
    end
  end

  # ─── Constructor from raw ───────────────────────────────────────────
  describe "constructor from raw" do
    it "creates packet from raw bytes (nil destination)" do
      raw = Random::Secure.random_bytes(50)
      pkt = RNS::Packet.new(nil, raw)
      pkt.raw.should eq raw
      pkt.packed.should be_true
      pkt.from_packed.should be_true
      pkt.create_receipt.should be_false
    end
  end

  # ─── Constructor with destination ───────────────────────────────────
  describe "constructor with destination" do
    it "initializes fields correctly" do
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::SINGLE
      )
      payload = Bytes[0x01, 0x02]
      pkt = RNS::Packet.new(dest, payload)

      pkt.header_type.should eq RNS::Packet::HEADER_1
      pkt.packet_type.should eq RNS::Packet::DATA
      pkt.transport_type.should eq RNS::Transport::BROADCAST
      pkt.context.should eq RNS::Packet::NONE
      pkt.context_flag.should eq RNS::Packet::FLAG_UNSET
      pkt.hops.should eq 0
      pkt.data.should eq payload
      pkt.raw.should be_nil
      pkt.packed.should be_false
      pkt.sent.should be_false
      pkt.create_receipt.should be_true
      pkt.receipt.should be_nil
      pkt.from_packed.should be_false
      pkt.sent_at.should be_nil
      pkt.packet_hash.should be_nil
      pkt.ratchet_id.should be_nil
      pkt.rssi.should be_nil
      pkt.snr.should be_nil
      pkt.q.should be_nil
    end

    it "uses default MTU for non-LINK destination" do
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::SINGLE
      )
      pkt = RNS::Packet.new(dest, Bytes[0x01])
      pkt.mtu.should eq RNS::Reticulum::MTU
    end
  end

  # ─── LRPROOF context ────────────────────────────────────────────────
  describe "LRPROOF context" do
    it "uses link_id for destination hash in header" do
      link_id = RNS::Identity.get_random_hash
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::SINGLE,
        link_id: link_id
      )
      payload = Random::Secure.random_bytes(32)
      pkt = RNS::Packet.new(dest, payload,
        context: RNS::Packet::LRPROOF
      )
      pkt.pack

      raw = pkt.raw.not_nil!
      # For LRPROOF, header uses link_id instead of dest hash
      raw[2, 16].should eq link_id
      # Data is not encrypted for LRPROOF
      raw[19, 32].should eq payload
    end
  end

  # ─── PacketReceipt ──────────────────────────────────────────────────
  describe RNS::PacketReceipt do
    describe "constants" do
      it "has correct status constants" do
        RNS::PacketReceipt::FAILED.should eq 0x00_u8
        RNS::PacketReceipt::SENT.should eq 0x01_u8
        RNS::PacketReceipt::DELIVERED.should eq 0x02_u8
        RNS::PacketReceipt::CULLED.should eq 0xFF_u8
      end

      it "has correct proof length constants" do
        # EXPL_LENGTH = HASHLENGTH/8 + SIGLENGTH/8 = 32 + 64 = 96
        RNS::PacketReceipt::EXPL_LENGTH.should eq 96
        # IMPL_LENGTH = SIGLENGTH/8 = 64
        RNS::PacketReceipt::IMPL_LENGTH.should eq 64
      end
    end

    describe "#initialize" do
      it "creates a receipt from a packed packet" do
        dest = RNS::Destination::Stub.new(
          hash: RNS::Identity.get_random_hash,
          type: RNS::Destination::PLAIN
        )
        pkt = RNS::Packet.new(dest, Bytes[0x01, 0x02])
        pkt.pack

        receipt = RNS::PacketReceipt.new(pkt)
        receipt.hash.should eq pkt.get_hash
        receipt.truncated_hash.should eq pkt.get_truncated_hash
        receipt.sent.should be_true
        receipt.sent_at.should_not be_nil
        receipt.proved.should be_false
        receipt.status.should eq RNS::PacketReceipt::SENT
        receipt.concluded_at.should be_nil
        receipt.proof_packet.should be_nil
      end
    end

    describe "#get_status" do
      it "returns current status" do
        dest = RNS::Destination::Stub.new(
          hash: RNS::Identity.get_random_hash,
          type: RNS::Destination::PLAIN
        )
        pkt = RNS::Packet.new(dest, Bytes[0x01])
        pkt.pack
        receipt = RNS::PacketReceipt.new(pkt)
        receipt.get_status.should eq RNS::PacketReceipt::SENT
      end
    end

    describe "#set_timeout" do
      it "sets the timeout value" do
        dest = RNS::Destination::Stub.new(
          hash: RNS::Identity.get_random_hash,
          type: RNS::Destination::PLAIN
        )
        pkt = RNS::Packet.new(dest, Bytes[0x01])
        pkt.pack
        receipt = RNS::PacketReceipt.new(pkt)
        receipt.set_timeout(30.0)
        receipt.timeout.should eq 30.0
      end
    end

    describe "#set_delivery_callback" do
      it "sets the delivery callback" do
        dest = RNS::Destination::Stub.new(
          hash: RNS::Identity.get_random_hash,
          type: RNS::Destination::PLAIN
        )
        pkt = RNS::Packet.new(dest, Bytes[0x01])
        pkt.pack
        receipt = RNS::PacketReceipt.new(pkt)

        called = false
        receipt.set_delivery_callback(->(r : RNS::PacketReceipt) { called = true; nil })
        receipt.callbacks.delivery.should_not be_nil
      end
    end

    describe "#set_timeout_callback" do
      it "sets the timeout callback" do
        dest = RNS::Destination::Stub.new(
          hash: RNS::Identity.get_random_hash,
          type: RNS::Destination::PLAIN
        )
        pkt = RNS::Packet.new(dest, Bytes[0x01])
        pkt.pack
        receipt = RNS::PacketReceipt.new(pkt)

        receipt.set_timeout_callback(->(r : RNS::PacketReceipt) { nil })
        receipt.callbacks.timeout.should_not be_nil
      end
    end

    describe "#get_rtt" do
      it "computes RTT from sent_at and concluded_at" do
        dest = RNS::Destination::Stub.new(
          hash: RNS::Identity.get_random_hash,
          type: RNS::Destination::PLAIN
        )
        pkt = RNS::Packet.new(dest, Bytes[0x01])
        pkt.pack
        receipt = RNS::PacketReceipt.new(pkt)

        # Simulate completion
        receipt.concluded_at = Time.utc.to_unix_f + 1.5
        rtt = receipt.get_rtt
        rtt.should be > 0.0
      end
    end

    describe "#is_timed_out?" do
      it "returns false for fresh receipt with reasonable timeout" do
        dest = RNS::Destination::Stub.new(
          hash: RNS::Identity.get_random_hash,
          type: RNS::Destination::PLAIN
        )
        pkt = RNS::Packet.new(dest, Bytes[0x01])
        pkt.pack
        receipt = RNS::PacketReceipt.new(pkt)
        receipt.set_timeout(60.0)
        receipt.is_timed_out?.should be_false
      end

      it "returns true when timeout has elapsed" do
        dest = RNS::Destination::Stub.new(
          hash: RNS::Identity.get_random_hash,
          type: RNS::Destination::PLAIN
        )
        pkt = RNS::Packet.new(dest, Bytes[0x01])
        pkt.pack
        receipt = RNS::PacketReceipt.new(pkt)
        # Set sent_at to past and short timeout to ensure expiry
        receipt.sent_at = Time.utc.to_unix_f - 1.0
        receipt.set_timeout(0.0)
        receipt.is_timed_out?.should be_true
      end
    end

    describe "#check_timeout" do
      it "marks FAILED when timed out" do
        dest = RNS::Destination::Stub.new(
          hash: RNS::Identity.get_random_hash,
          type: RNS::Destination::PLAIN
        )
        pkt = RNS::Packet.new(dest, Bytes[0x01])
        pkt.pack
        receipt = RNS::PacketReceipt.new(pkt)
        receipt.sent_at = Time.utc.to_unix_f - 1.0
        receipt.set_timeout(0.0)
        receipt.check_timeout
        receipt.status.should eq RNS::PacketReceipt::FAILED
        receipt.concluded_at.should_not be_nil
      end

      it "marks CULLED when timeout is -1" do
        dest = RNS::Destination::Stub.new(
          hash: RNS::Identity.get_random_hash,
          type: RNS::Destination::PLAIN
        )
        pkt = RNS::Packet.new(dest, Bytes[0x01])
        pkt.pack
        receipt = RNS::PacketReceipt.new(pkt)
        receipt.sent_at = Time.utc.to_unix_f - 1.0
        receipt.set_timeout(-1.0)
        receipt.check_timeout
        receipt.status.should eq RNS::PacketReceipt::CULLED
      end

      it "does not change status if not timed out" do
        dest = RNS::Destination::Stub.new(
          hash: RNS::Identity.get_random_hash,
          type: RNS::Destination::PLAIN
        )
        pkt = RNS::Packet.new(dest, Bytes[0x01])
        pkt.pack
        receipt = RNS::PacketReceipt.new(pkt)
        receipt.set_timeout(60.0)
        receipt.check_timeout
        receipt.status.should eq RNS::PacketReceipt::SENT
      end

      it "calls timeout callback on failure" do
        dest = RNS::Destination::Stub.new(
          hash: RNS::Identity.get_random_hash,
          type: RNS::Destination::PLAIN
        )
        pkt = RNS::Packet.new(dest, Bytes[0x01])
        pkt.pack
        receipt = RNS::PacketReceipt.new(pkt)
        receipt.sent_at = Time.utc.to_unix_f - 1.0
        receipt.set_timeout(0.0)

        callback_called = false
        receipt.set_timeout_callback(->(r : RNS::PacketReceipt) { callback_called = true; nil })
        receipt.check_timeout

        # Give the spawned fiber time to run
        sleep 50.milliseconds
        callback_called.should be_true
      end
    end
  end

  # ─── ProofDestination ───────────────────────────────────────────────
  describe RNS::ProofDestination do
    it "creates with truncated hash of packet" do
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::PLAIN
      )
      pkt = RNS::Packet.new(dest, Bytes[0x01, 0x02])
      pkt.pack

      proof_dest = RNS::ProofDestination.new(pkt)
      expected_hash = pkt.get_hash[0, RNS::Reticulum::TRUNCATED_HASHLENGTH // 8]
      proof_dest.hash.should eq expected_hash
      proof_dest.type.should eq RNS::Destination::SINGLE
    end

    it "encrypt returns plaintext unchanged" do
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::PLAIN
      )
      pkt = RNS::Packet.new(dest, Bytes[0x01])
      pkt.pack

      proof_dest = RNS::ProofDestination.new(pkt)
      data = Bytes[0xDE, 0xAD]
      proof_dest.encrypt(data).should eq data
    end
  end

  # ─── MTU boundary tests ─────────────────────────────────────────────
  describe "MTU boundary" do
    it "accepts maximum payload that fits within MTU" do
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::PLAIN
      )
      # HEADER_1 header = 19 bytes, so max payload is MTU - 19 = 481
      max_payload = RNS::Reticulum::MTU - RNS::Packet::HEADER_MINSIZE
      payload = Random::Secure.random_bytes(max_payload)
      pkt = RNS::Packet.new(dest, payload)
      pkt.pack # Should not raise
      pkt.raw.not_nil!.size.should eq RNS::Reticulum::MTU
    end

    it "accepts empty payload" do
      dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.get_random_hash,
        type: RNS::Destination::PLAIN
      )
      pkt = RNS::Packet.new(dest, Bytes.empty)
      pkt.pack # Should not raise
      # Header only: flags(1) + hops(1) + dest_hash(16) + context(1) = 19
      pkt.raw.not_nil!.size.should eq 19
    end
  end
end
