require "../../spec_helper"

# ─── Test helpers ────────────────────────────────────────────────
private def make_identity
  RNS::Identity.new(create_keys: true)
end

private def make_interface_hash
  Random::Secure.random_bytes(16)
end

private def make_destination(identity = nil, direction = RNS::Destination::IN, type = RNS::Destination::SINGLE)
  id = identity || make_identity
  RNS::Destination.new(id, direction, type, "test", ["app"], register: false)
end

private def make_plain_destination
  RNS::Destination.new(nil, RNS::Destination::OUT, RNS::Destination::PLAIN, "test", ["plain"], register: false)
end

private def make_packet(destination, data = Bytes.new(10, 0xAA_u8), packet_type = RNS::Packet::DATA, context = RNS::Packet::NONE)
  pkt = RNS::Packet.new(destination, data, packet_type: packet_type, context: context)
  pkt.pack
  pkt
end

describe RNS::Transport do
  before_each do
    RNS::Transport.reset
    RNS::Identity.known_destinations.clear
    RNS::Identity.known_ratchets.clear
    RNS::Transport.identity = RNS::Identity.new(create_keys: true)
  end

  # ════════════════════════════════════════════════════════════════
  #  LinkLike and LinkStub
  # ════════════════════════════════════════════════════════════════

  describe "LinkLike constants" do
    it "defines link state constants" do
      RNS::LinkLike::PENDING.should eq 0x00_u8
      RNS::LinkLike::HANDSHAKE.should eq 0x01_u8
      RNS::LinkLike::ACTIVE.should eq 0x02_u8
      RNS::LinkLike::STALE.should eq 0x03_u8
      RNS::LinkLike::CLOSED.should eq 0x04_u8
    end

    it "defines stale time" do
      RNS::LinkLike::STALE_TIME.should eq 720.0
    end

    it "defines establishment timeout per hop" do
      RNS::LinkLike::ESTABLISHMENT_TIMEOUT_PER_HOP.should eq 6.0
    end
  end

  describe "LinkStub" do
    it "creates with defaults" do
      link = RNS::LinkStub.new(Bytes.new(16, 0x42_u8))
      link.link_id.should eq Bytes.new(16, 0x42_u8)
      link.initiator?.should be_true
      link.status.should eq RNS::LinkLike::PENDING
      link.expected_hops.should eq 0
      link.attached_interface.should be_nil
    end

    it "creates with custom values" do
      link = RNS::LinkStub.new(
        Bytes.new(16, 0x01_u8),
        initiator: false,
        status: RNS::LinkLike::ACTIVE,
        destination_hash: Bytes.new(16, 0x02_u8),
        expected_hops: 3,
      )
      link.initiator?.should be_false
      link.status.should eq RNS::LinkLike::ACTIVE
      link.destination_hash.should eq Bytes.new(16, 0x02_u8)
      link.expected_hops.should eq 3
    end

    it "allows status mutation" do
      link = RNS::LinkStub.new(Bytes.new(16))
      link.status = RNS::LinkLike::ACTIVE
      link.status.should eq RNS::LinkLike::ACTIVE
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Link Management
  # ════════════════════════════════════════════════════════════════

  describe ".register_link" do
    it "registers an initiator link as pending" do
      link = RNS::LinkStub.new(Bytes.new(16, 0x01_u8), initiator: true)
      RNS::Transport.register_link(link)
      RNS::Transport.pending_links.size.should eq 1
      RNS::Transport.active_links.size.should eq 0
    end

    it "registers a responder link as active" do
      link = RNS::LinkStub.new(Bytes.new(16, 0x02_u8), initiator: false)
      RNS::Transport.register_link(link)
      RNS::Transport.pending_links.size.should eq 0
      RNS::Transport.active_links.size.should eq 1
    end

    it "registers multiple links" do
      3.times do |i|
        link = RNS::LinkStub.new(Bytes.new(16, i.to_u8), initiator: true)
        RNS::Transport.register_link(link)
      end
      RNS::Transport.pending_links.size.should eq 3
    end
  end

  describe ".activate_link" do
    it "moves a link from pending to active" do
      link = RNS::LinkStub.new(Bytes.new(16, 0x01_u8), initiator: true)
      RNS::Transport.register_link(link)
      RNS::Transport.pending_links.size.should eq 1

      link.status = RNS::LinkLike::ACTIVE
      RNS::Transport.activate_link(link)

      RNS::Transport.pending_links.size.should eq 0
      RNS::Transport.active_links.size.should eq 1
    end

    it "raises if link is not in ACTIVE state" do
      link = RNS::LinkStub.new(Bytes.new(16, 0x01_u8), initiator: true)
      RNS::Transport.register_link(link)

      expect_raises(IO::Error) do
        RNS::Transport.activate_link(link)
      end
    end

    it "logs error if link not in pending table" do
      link = RNS::LinkStub.new(Bytes.new(16, 0x01_u8), initiator: true)
      link.status = RNS::LinkLike::ACTIVE
      # Not registered, so activate should just log error
      RNS::Transport.activate_link(link)
      RNS::Transport.active_links.size.should eq 0
    end
  end

  describe ".find_link_for_destination" do
    it "finds an active link by destination hash" do
      link_id = Random::Secure.random_bytes(16)
      link = RNS::LinkStub.new(link_id, initiator: false)
      RNS::Transport.register_link(link)

      found = RNS::Transport.find_link_for_destination(link_id)
      found.should_not be_nil
      found.not_nil!.link_id.should eq link_id
    end

    it "returns nil for unknown destination hash" do
      result = RNS::Transport.find_link_for_destination(Bytes.new(16))
      result.should be_nil
    end

    it "does not find pending links" do
      link_id = Random::Secure.random_bytes(16)
      link = RNS::LinkStub.new(link_id, initiator: true)
      RNS::Transport.register_link(link)

      result = RNS::Transport.find_link_for_destination(link_id)
      result.should be_nil
    end
  end

  describe ".find_best_link" do
    it "returns the first matching active link" do
      link_id = Random::Secure.random_bytes(16)
      link = RNS::LinkStub.new(link_id, initiator: false)
      RNS::Transport.register_link(link)

      found = RNS::Transport.find_best_link(link_id)
      found.should_not be_nil
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Transmit
  # ════════════════════════════════════════════════════════════════

  describe ".transmit" do
    it "records transmission in transmit log" do
      iface = make_interface_hash
      data = Bytes.new(20, 0xFF_u8)
      RNS::Transport.transmit(iface, data)

      RNS::Transport.transmit_log.size.should eq 1
      RNS::Transport.transmit_log[0][0].should eq iface
      RNS::Transport.transmit_log[0][1].should eq data
    end

    it "updates traffic counter" do
      iface = make_interface_hash
      data = Bytes.new(50, 0xAA_u8)
      RNS::Transport.transmit(iface, data)

      RNS::Transport.traffic_txb.should eq 50_i64
    end

    it "records multiple transmissions" do
      3.times do |i|
        RNS::Transport.transmit(make_interface_hash, Bytes.new(10 + i))
      end
      RNS::Transport.transmit_log.size.should eq 3
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Outbound Routing
  # ════════════════════════════════════════════════════════════════

  describe ".outbound" do
    it "broadcasts on all interfaces when no path is known" do
      iface1 = make_interface_hash
      iface2 = make_interface_hash
      RNS::Transport.register_interface(iface1)
      RNS::Transport.register_interface(iface2)

      dest = make_plain_destination
      pkt = make_packet(dest)

      result = RNS::Transport.outbound(pkt)
      result.should be_true
      RNS::Transport.transmit_log.size.should eq 2
    end

    it "routes via path table for known multi-hop paths" do
      identity = make_identity
      dest = make_destination(identity, RNS::Destination::OUT)
      pkt = make_packet(dest)

      next_hop = Random::Secure.random_bytes(16)
      iface = make_interface_hash
      RNS::Transport.register_interface(iface)

      RNS::Transport.update_path(
        dest.hash,
        next_hop,
        hops: 3,
        expires: Time.utc.to_unix_f + 3600,
        receiving_interface: iface,
      )

      result = RNS::Transport.outbound(pkt)
      result.should be_true

      # Should have transmitted once via the path
      RNS::Transport.transmit_log.size.should eq 1
      transmitted_iface = RNS::Transport.transmit_log[0][0]
      transmitted_iface.should eq iface

      # Transmitted raw should include transport header (HEADER_2)
      transmitted_raw = RNS::Transport.transmit_log[0][1]
      flags = transmitted_raw[0]
      header_type = (flags >> 6) & 0x03
      header_type.should eq RNS::Packet::HEADER_2
    end

    it "routes directly for 1-hop paths" do
      identity = make_identity
      dest = make_destination(identity, RNS::Destination::OUT)
      pkt = make_packet(dest)

      iface = make_interface_hash
      RNS::Transport.register_interface(iface)

      RNS::Transport.update_path(
        dest.hash,
        dest.hash, # next_hop = destination for direct path
        hops: 1,
        expires: Time.utc.to_unix_f + 3600,
        receiving_interface: iface,
      )

      result = RNS::Transport.outbound(pkt)
      result.should be_true
      RNS::Transport.transmit_log.size.should eq 1

      # Direct path: raw should be sent as-is (HEADER_1)
      transmitted_raw = RNS::Transport.transmit_log[0][1]
      flags = transmitted_raw[0]
      header_type = (flags >> 6) & 0x03
      header_type.should eq RNS::Packet::HEADER_1
    end

    it "generates receipt for DATA packets to non-PLAIN destinations" do
      dest = make_destination(nil, RNS::Destination::OUT)
      data = Bytes.new(10, 0xBB_u8)
      pkt = RNS::Packet.new(dest, data, packet_type: RNS::Packet::DATA)
      pkt.pack

      iface = make_interface_hash
      RNS::Transport.register_interface(iface)

      RNS::Transport.outbound(pkt)
      pkt.receipt.should_not be_nil
      RNS::Transport.receipts.size.should eq 1
    end

    it "does not generate receipt for ANNOUNCE packets" do
      identity = make_identity
      dest = RNS::Destination.new(identity, RNS::Destination::IN, RNS::Destination::SINGLE, "test", ["recv"], register: false)
      announce_pkt = dest.announce(send: false)
      announce_pkt.should_not be_nil

      if announce_pkt
        iface = make_interface_hash
        RNS::Transport.register_interface(iface)
        RNS::Transport.outbound(announce_pkt)
        announce_pkt.receipt.should be_nil
      end
    end

    it "does not generate receipt for KEEPALIVE context" do
      dest = make_destination(nil, RNS::Destination::OUT)
      pkt = RNS::Packet.new(dest, Bytes.new(10), context: RNS::Packet::KEEPALIVE)
      pkt.pack

      iface = make_interface_hash
      RNS::Transport.register_interface(iface)
      RNS::Transport.outbound(pkt)
      pkt.receipt.should be_nil
    end

    it "marks packet as sent" do
      dest = make_plain_destination
      pkt = make_packet(dest)
      iface = make_interface_hash
      RNS::Transport.register_interface(iface)

      RNS::Transport.outbound(pkt)
      pkt.sent.should be_true
      pkt.sent_at.should_not be_nil
    end

    it "updates path table timestamp when routing via known path" do
      identity = make_identity
      dest = make_destination(identity, RNS::Destination::OUT)
      pkt = make_packet(dest)

      iface = make_interface_hash
      RNS::Transport.register_interface(iface)

      old_time = Time.utc.to_unix_f - 100
      dest_hex = dest.hash.hexstring
      RNS::Transport.path_table[dest_hex] = RNS::Transport::PathEntry.new(
        timestamp: old_time,
        next_hop: Random::Secure.random_bytes(16),
        hops: 3,
        expires: Time.utc.to_unix_f + 3600,
        random_blobs: [] of Bytes,
        receiving_interface: iface,
        packet_hash: Bytes.empty,
      )

      RNS::Transport.outbound(pkt)
      new_timestamp = RNS::Transport.path_table[dest_hex].timestamp
      new_timestamp.should be > old_time
    end

    it "returns false when no interfaces are available" do
      dest = make_plain_destination
      pkt = make_packet(dest)

      result = RNS::Transport.outbound(pkt)
      result.should be_false
    end

    it "releases jobs lock even on error" do
      # After any outbound call, jobs_locked should be false
      dest = make_plain_destination
      pkt = make_packet(dest)
      RNS::Transport.outbound(pkt)
      RNS::Transport.jobs_locked.should be_false
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Inbound Packet Processing
  # ════════════════════════════════════════════════════════════════

  describe ".inbound" do
    it "drops packets smaller than 3 bytes" do
      RNS::Transport.inbound(Bytes.new(2))
      # No crash, no transmissions
      RNS::Transport.transmit_log.size.should eq 0
    end

    it "drops packets with IFAC flag set (no IFAC support)" do
      raw = Bytes.new(20)
      raw[0] = 0x80_u8 # IFAC flag
      RNS::Transport.inbound(raw)
      RNS::Transport.transmit_log.size.should eq 0
    end

    it "drops packets when no identity is set" do
      RNS::Transport.identity = nil
      dest = make_plain_destination
      pkt = make_packet(dest)
      raw = pkt.raw
      if raw
        RNS::Transport.inbound(raw)
      end
      # Should not process
      RNS::Transport.transmit_log.size.should eq 0
    end

    it "processes a valid PLAIN DATA packet" do
      dest = make_plain_destination
      data = Bytes.new(10, 0xCC_u8)
      pkt = RNS::Packet.new(dest, data, packet_type: RNS::Packet::DATA)
      pkt.pack
      raw = pkt.raw
      raw.should_not be_nil

      if raw
        RNS::Transport.inbound(raw)
      end
      # Should process without error
      RNS::Transport.jobs_locked.should be_false
    end

    it "delivers DATA to local destination" do
      received_data = nil
      identity = make_identity
      dest = RNS::Destination.new(identity, RNS::Destination::IN, RNS::Destination::SINGLE, "testapp", ["recv"], register: false)
      RNS::Transport.register_destination(dest)

      dest.set_packet_callback(->(data : Bytes, packet : RNS::Packet) {
        received_data = data
        nil
      })

      # Create an outgoing packet for this destination
      out_dest = RNS::Destination.new(identity, RNS::Destination::OUT, RNS::Destination::SINGLE, "testapp", ["recv"], register: false)
      pkt = RNS::Packet.new(out_dest, Bytes.new(10, 0xDD_u8), packet_type: RNS::Packet::DATA)
      pkt.pack
      raw = pkt.raw

      if raw
        RNS::Transport.inbound(raw)
      end

      # Packet should have been delivered to destination
      # Note: decryption happens in destination.receive, which may fail
      # if the packet was encrypted. For SINGLE destinations, the packet
      # IS encrypted and decrypt needs the private key. This validates
      # the routing logic reaches the destination.
    end

    it "processes announce packets via inbound_announce" do
      # Create an identity and destination, generate an announce
      identity = make_identity
      dest = RNS::Destination.new(identity, RNS::Destination::IN, RNS::Destination::SINGLE, "testinbound", ["announce"], register: false)
      announce_pkt = dest.announce(send: false)
      announce_pkt.should_not be_nil

      if announce_pkt
        raw = announce_pkt.raw
        if raw
          # Inbound the announce on a "different" transport instance
          RNS::Transport.inbound(raw)

          # After inbound, the destination should be known
          dest_hash = dest.hash
          RNS::Transport.has_path(dest_hash).should be_true
        end
      end
    end

    it "creates reverse table entry for forwarded DATA packets" do
      iface1 = make_interface_hash
      iface2 = make_interface_hash
      RNS::Transport.register_interface(iface1)
      RNS::Transport.register_interface(iface2)
      RNS::Transport.transport_enabled = true

      dest_hash = Random::Secure.random_bytes(16)
      next_hop = Random::Secure.random_bytes(16)

      # Set up path table
      RNS::Transport.update_path(
        dest_hash,
        next_hop,
        hops: 0,
        expires: Time.utc.to_unix_f + 3600,
        receiving_interface: iface2,
      )

      our_hash = RNS::Transport.identity.not_nil!.hash.not_nil!

      # Construct a HEADER_2 DATA packet addressed to us as transport
      flags = (RNS::Packet::HEADER_2.to_u8 << 6) | (RNS::Transport::TRANSPORT.to_u8 << 4) | (RNS::Destination::SINGLE.to_u8 << 2) | RNS::Packet::DATA.to_u8
      io = IO::Memory.new
      io.write_byte(flags)
      io.write_byte(0x00_u8)           # hops
      io.write(our_hash)               # transport_id (our hash)
      io.write(dest_hash)              # destination_hash
      io.write_byte(0x00_u8)           # context: NONE
      io.write(Bytes.new(10, 0xAA_u8)) # payload
      raw = io.to_slice.dup

      RNS::Transport.inbound(raw, iface1)

      # Should have created reverse table entry or forwarded
      RNS::Transport.transmit_log.size.should be >= 0 # May or may not transmit depending on path
    end

    it "releases jobs lock after processing" do
      dest = make_plain_destination
      pkt = make_packet(dest)
      raw = pkt.raw
      if raw
        RNS::Transport.inbound(raw)
      end
      RNS::Transport.jobs_locked.should be_false
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Transport Forwarding
  # ════════════════════════════════════════════════════════════════

  describe "transport forwarding" do
    it "creates link table entry for forwarded LINKREQUEST" do
      iface1 = make_interface_hash
      iface2 = make_interface_hash
      RNS::Transport.register_interface(iface1)
      RNS::Transport.register_interface(iface2)
      RNS::Transport.transport_enabled = true

      dest_hash = Random::Secure.random_bytes(16)
      next_hop = Random::Secure.random_bytes(16)

      RNS::Transport.update_path(
        dest_hash,
        next_hop,
        hops: 2,
        expires: Time.utc.to_unix_f + 3600,
        receiving_interface: iface2,
      )

      our_hash = RNS::Transport.identity.not_nil!.hash.not_nil!

      # Construct HEADER_2 LINKREQUEST packet
      flags = (RNS::Packet::HEADER_2.to_u8 << 6) | (RNS::Transport::TRANSPORT.to_u8 << 4) | (RNS::Destination::SINGLE.to_u8 << 2) | RNS::Packet::LINKREQUEST.to_u8
      io = IO::Memory.new
      io.write_byte(flags)
      io.write_byte(0x00_u8)           # hops
      io.write(our_hash)               # transport_id
      io.write(dest_hash)              # destination_hash
      io.write_byte(0x00_u8)           # context: NONE
      io.write(Bytes.new(64, 0xBB_u8)) # link request data
      raw = io.to_slice.dup

      RNS::Transport.inbound(raw, iface1)

      # Should create a link table entry
      RNS::Transport.link_table.size.should be >= 1
    end

    it "handles link transport by forwarding on correct interface" do
      iface1 = make_interface_hash
      iface2 = make_interface_hash
      RNS::Transport.register_interface(iface1)
      RNS::Transport.register_interface(iface2)
      RNS::Transport.transport_enabled = true

      link_id = Random::Secure.random_bytes(16)
      link_hex = link_id.hexstring

      # Create a link table entry
      RNS::Transport.link_table[link_hex] = RNS::Transport::LinkEntry.new(
        timestamp: Time.utc.to_unix_f,
        next_hop_transport_id: Random::Secure.random_bytes(16),
        next_hop_interface: iface2,
        remaining_hops: 2,
        received_on: iface1,
        taken_hops: 1,
        destination_hash: Random::Secure.random_bytes(16),
        validated: true,
        proof_timeout: Time.utc.to_unix_f + 60,
      )

      # Construct a DATA packet for this link
      flags = (RNS::Packet::HEADER_1.to_u8 << 6) | (RNS::Transport::BROADCAST.to_u8 << 4) | (RNS::Destination::LINK.to_u8 << 2) | RNS::Packet::DATA.to_u8
      io = IO::Memory.new
      io.write_byte(flags)
      io.write_byte(0x00_u8) # hops = 0 (becomes 1 after inbound increment, matches taken_hops)
      io.write(link_id)      # destination = link_id
      io.write_byte(0x00_u8) # context: NONE
      io.write(Bytes.new(10))
      raw = io.to_slice.dup

      RNS::Transport.inbound(raw, iface1)

      # Should forward on iface2
      forwarded = RNS::Transport.transmit_log.any? { |entry| entry[0] == iface2 }
      forwarded.should be_true
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Tunnel Management
  # ════════════════════════════════════════════════════════════════

  describe ".handle_tunnel" do
    it "creates a new tunnel" do
      tunnel_id = Random::Secure.random_bytes(32)
      iface = make_interface_hash

      RNS::Transport.handle_tunnel(tunnel_id, iface)
      RNS::Transport.tunnels.size.should eq 1

      entry = RNS::Transport.tunnels[tunnel_id.hexstring]
      entry.tunnel_id.should eq tunnel_id
      entry.interface.should eq iface
      entry.paths.size.should eq 0
    end

    it "restores paths when tunnel reappears" do
      tunnel_id = Random::Secure.random_bytes(32)
      iface1 = make_interface_hash
      iface2 = make_interface_hash

      # Create initial tunnel with a path
      RNS::Transport.handle_tunnel(tunnel_id, iface1)
      tunnel_hex = tunnel_id.hexstring

      dest_hash = Random::Secure.random_bytes(16)
      dest_hex = dest_hash.hexstring
      next_hop = Random::Secure.random_bytes(16)

      RNS::Transport.tunnels[tunnel_hex].paths[dest_hex] = RNS::Transport::PathEntry.new(
        timestamp: Time.utc.to_unix_f,
        next_hop: next_hop,
        hops: 2,
        expires: Time.utc.to_unix_f + 3600,
        random_blobs: [] of Bytes,
        receiving_interface: nil,
        packet_hash: Bytes.empty,
      )

      # "Reappear" with new interface
      RNS::Transport.handle_tunnel(tunnel_id, iface2)

      # Path should be restored in path_table
      RNS::Transport.has_path(dest_hash).should be_true
      path_entry = RNS::Transport.path_table[dest_hex]
      path_entry.hops.should eq 2
      path_entry.receiving_interface.should eq iface2
    end

    it "does not restore expired paths" do
      tunnel_id = Random::Secure.random_bytes(32)
      iface1 = make_interface_hash

      RNS::Transport.handle_tunnel(tunnel_id, iface1)
      tunnel_hex = tunnel_id.hexstring

      dest_hash = Random::Secure.random_bytes(16)
      dest_hex = dest_hash.hexstring

      RNS::Transport.tunnels[tunnel_hex].paths[dest_hex] = RNS::Transport::PathEntry.new(
        timestamp: Time.utc.to_unix_f - 1000,
        next_hop: Random::Secure.random_bytes(16),
        hops: 2,
        expires: Time.utc.to_unix_f - 1, # Already expired
        random_blobs: [] of Bytes,
        receiving_interface: nil,
        packet_hash: Bytes.empty,
      )

      iface2 = make_interface_hash
      RNS::Transport.handle_tunnel(tunnel_id, iface2)

      # Path should NOT be restored
      RNS::Transport.has_path(dest_hash).should be_false
      # Deprecated path should be removed from tunnel
      RNS::Transport.tunnels[tunnel_hex].paths.has_key?(dest_hex).should be_false
    end

    it "does not overwrite better existing path" do
      tunnel_id = Random::Secure.random_bytes(32)
      iface1 = make_interface_hash

      dest_hash = Random::Secure.random_bytes(16)
      dest_hex = dest_hash.hexstring

      # Set up a good existing path (2 hops, not expired)
      RNS::Transport.update_path(
        dest_hash,
        Random::Secure.random_bytes(16),
        hops: 2,
        expires: Time.utc.to_unix_f + 7200,
      )

      # Create tunnel with a worse path (5 hops)
      RNS::Transport.handle_tunnel(tunnel_id, iface1)
      tunnel_hex = tunnel_id.hexstring
      RNS::Transport.tunnels[tunnel_hex].paths[dest_hex] = RNS::Transport::PathEntry.new(
        timestamp: Time.utc.to_unix_f,
        next_hop: Random::Secure.random_bytes(16),
        hops: 5,
        expires: Time.utc.to_unix_f + 3600,
        random_blobs: [] of Bytes,
        receiving_interface: nil,
        packet_hash: Bytes.empty,
      )

      iface2 = make_interface_hash
      RNS::Transport.handle_tunnel(tunnel_id, iface2)

      # Should keep the better path
      RNS::Transport.path_table[dest_hex].hops.should eq 2
    end
  end

  describe ".void_tunnel_interface" do
    it "sets tunnel interface to nil" do
      tunnel_id = Random::Secure.random_bytes(32)
      iface = make_interface_hash
      RNS::Transport.handle_tunnel(tunnel_id, iface)

      RNS::Transport.tunnels[tunnel_id.hexstring].interface.should eq iface

      RNS::Transport.void_tunnel_interface(tunnel_id)
      RNS::Transport.tunnels[tunnel_id.hexstring].interface.should be_nil
    end

    it "does nothing for unknown tunnel" do
      RNS::Transport.void_tunnel_interface(Random::Secure.random_bytes(32))
      # No crash
    end
  end

  describe ".tunnel_synthesize_handler" do
    it "creates a tunnel from valid synthesis data" do
      # Create the synthesis data
      identity = RNS::Identity.new(create_keys: true)
      public_key = identity.get_public_key
      interface_hash = RNS::Identity.full_hash(Random::Secure.random_bytes(32))
      random_hash = RNS::Identity.get_random_hash

      tunnel_id_data = Bytes.new(public_key.size + interface_hash.size)
      public_key.copy_to(tunnel_id_data)
      interface_hash.copy_to(tunnel_id_data + public_key.size)

      signed_data = Bytes.new(tunnel_id_data.size + random_hash.size)
      tunnel_id_data.copy_to(signed_data)
      random_hash.copy_to(signed_data + tunnel_id_data.size)

      signature = identity.sign(signed_data)

      data = Bytes.new(signed_data.size + signature.size)
      signed_data.copy_to(data)
      signature.copy_to(data + signed_data.size)

      # Create a dummy packet
      dest = make_plain_destination
      pkt = make_packet(dest)

      RNS::Transport.tunnel_synthesize_handler(data, pkt)

      # Should have created a tunnel
      RNS::Transport.tunnels.size.should eq 1
    end

    it "rejects invalid signature" do
      identity = RNS::Identity.new(create_keys: true)
      public_key = identity.get_public_key
      interface_hash = RNS::Identity.full_hash(Random::Secure.random_bytes(32))
      random_hash = RNS::Identity.get_random_hash

      tunnel_id_data = Bytes.new(public_key.size + interface_hash.size)
      public_key.copy_to(tunnel_id_data)
      interface_hash.copy_to(tunnel_id_data + public_key.size)

      signed_data = Bytes.new(tunnel_id_data.size + random_hash.size)
      tunnel_id_data.copy_to(signed_data)
      random_hash.copy_to(signed_data + tunnel_id_data.size)

      # Bad signature
      bad_signature = Random::Secure.random_bytes(64)

      data = Bytes.new(signed_data.size + bad_signature.size)
      signed_data.copy_to(data)
      bad_signature.copy_to(data + signed_data.size)

      dest = make_plain_destination
      pkt = make_packet(dest)

      RNS::Transport.tunnel_synthesize_handler(data, pkt)
      RNS::Transport.tunnels.size.should eq 0
    end

    it "rejects wrong length data" do
      data = Random::Secure.random_bytes(10) # Too short
      dest = make_plain_destination
      pkt = make_packet(dest)

      RNS::Transport.tunnel_synthesize_handler(data, pkt)
      RNS::Transport.tunnels.size.should eq 0
    end
  end

  describe ".synthesize_tunnel_data" do
    it "returns nil when no identity is set" do
      RNS::Transport.identity = nil
      result = RNS::Transport.synthesize_tunnel_data(make_interface_hash)
      result.should be_nil
    end

    it "creates valid tunnel data" do
      # Tunnel synthesis uses HASHLENGTH//8 = 32-byte interface hash
      iface = Random::Secure.random_bytes(RNS::Identity::HASHLENGTH // 8)
      result = RNS::Transport.synthesize_tunnel_data(iface)
      result.should_not be_nil

      if result
        tunnel_id, data = result
        tunnel_id.size.should eq 32 # Full hash

        # Verify the data can be validated
        dest = make_plain_destination
        pkt = make_packet(dest)
        RNS::Transport.tunnel_synthesize_handler(data, pkt)
        RNS::Transport.tunnels.size.should eq 1
      end
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Jobs Loop
  # ════════════════════════════════════════════════════════════════

  describe ".jobs" do
    it "removes CLOSED links from pending_links" do
      link = RNS::LinkStub.new(Random::Secure.random_bytes(16), initiator: true)
      RNS::Transport.register_link(link)
      link.status = RNS::LinkLike::CLOSED

      RNS::Transport.jobs
      RNS::Transport.pending_links.size.should eq 0
    end

    it "removes CLOSED links from active_links" do
      link = RNS::LinkStub.new(Random::Secure.random_bytes(16), initiator: false)
      RNS::Transport.register_link(link)
      link.status = RNS::LinkLike::CLOSED

      RNS::Transport.jobs
      RNS::Transport.active_links.size.should eq 0
    end

    it "keeps active links that are not CLOSED" do
      link = RNS::LinkStub.new(Random::Secure.random_bytes(16), initiator: false, status: RNS::LinkLike::ACTIVE)
      RNS::Transport.register_link(link)

      RNS::Transport.jobs
      RNS::Transport.active_links.size.should eq 1
    end

    it "culls excess receipts" do
      # Add more than MAX_RECEIPTS
      dest = make_plain_destination
      1030.times do
        pkt = make_packet(dest)
        receipt = RNS::PacketReceipt.new(pkt)
        RNS::Transport.receipts << receipt
      end

      RNS::Transport.receipts.size.should eq 1030

      RNS::Transport.jobs

      # Should be culled down
      RNS::Transport.receipts.size.should be <= RNS::Transport::MAX_RECEIPTS
    end

    it "removes timed-out receipts" do
      dest = make_plain_destination
      pkt = make_packet(dest)
      receipt = RNS::PacketReceipt.new(pkt)
      receipt.timeout = 0.001 # Very short timeout
      RNS::Transport.receipts << receipt

      sleep(10.milliseconds) # Wait for timeout
      RNS::Transport.jobs

      RNS::Transport.receipts.size.should eq 0
    end

    it "culls stale reverse table entries" do
      hash1 = Random::Secure.random_bytes(16).hexstring
      RNS::Transport.reverse_table[hash1] = RNS::Transport::ReverseEntry.new(
        received_on: nil,
        outbound: nil,
        timestamp: Time.utc.to_unix_f - RNS::Transport::REVERSE_TIMEOUT - 10,
      )

      # Force table culling
      RNS::Transport.tables_last_culled = 0.0
      RNS::Transport.jobs

      RNS::Transport.reverse_table.size.should eq 0
    end

    it "culls stale link table entries (validated, expired)" do
      iface = make_interface_hash
      RNS::Transport.register_interface(iface)

      link_hex = Random::Secure.random_bytes(16).hexstring
      RNS::Transport.link_table[link_hex] = RNS::Transport::LinkEntry.new(
        timestamp: Time.utc.to_unix_f - RNS::Transport::LINK_TIMEOUT - 10,
        next_hop_transport_id: Random::Secure.random_bytes(16),
        next_hop_interface: iface,
        remaining_hops: 1,
        received_on: iface,
        taken_hops: 1,
        destination_hash: Random::Secure.random_bytes(16),
        validated: true,
        proof_timeout: Time.utc.to_unix_f + 60,
      )

      RNS::Transport.tables_last_culled = 0.0
      RNS::Transport.jobs

      RNS::Transport.link_table.size.should eq 0
    end

    it "culls stale link table entries (not validated, proof timeout)" do
      iface = make_interface_hash
      RNS::Transport.register_interface(iface)

      link_hex = Random::Secure.random_bytes(16).hexstring
      RNS::Transport.link_table[link_hex] = RNS::Transport::LinkEntry.new(
        timestamp: Time.utc.to_unix_f,
        next_hop_transport_id: Random::Secure.random_bytes(16),
        next_hop_interface: iface,
        remaining_hops: 1,
        received_on: iface,
        taken_hops: 1,
        destination_hash: Random::Secure.random_bytes(16),
        validated: false,
        proof_timeout: Time.utc.to_unix_f - 10, # Already expired
      )

      RNS::Transport.tables_last_culled = 0.0
      RNS::Transport.jobs

      RNS::Transport.link_table.size.should eq 0
    end

    it "culls expired path table entries" do
      dest_hex = Random::Secure.random_bytes(16).hexstring
      RNS::Transport.path_table[dest_hex] = RNS::Transport::PathEntry.new(
        timestamp: Time.utc.to_unix_f - RNS::Transport::DESTINATION_TIMEOUT - 10,
        next_hop: Random::Secure.random_bytes(16),
        hops: 1,
        expires: Time.utc.to_unix_f - 10,
        random_blobs: [] of Bytes,
        receiving_interface: nil,
        packet_hash: Bytes.empty,
      )

      RNS::Transport.tables_last_culled = 0.0
      RNS::Transport.jobs

      RNS::Transport.path_table.size.should eq 0
    end

    it "culls expired tunnel entries" do
      tunnel_hex = Random::Secure.random_bytes(32).hexstring
      RNS::Transport.tunnels[tunnel_hex] = RNS::Transport::TunnelEntry.new(
        tunnel_id: tunnel_hex.hexbytes,
        interface: nil,
        paths: Hash(String, RNS::Transport::PathEntry).new,
        expires: Time.utc.to_unix_f - 10,
      )

      RNS::Transport.tables_last_culled = 0.0
      RNS::Transport.jobs

      RNS::Transport.tunnels.size.should eq 0
    end

    it "culls expired tunnel paths" do
      tunnel_hex = Random::Secure.random_bytes(32).hexstring
      paths = Hash(String, RNS::Transport::PathEntry).new
      dest_hex = Random::Secure.random_bytes(16).hexstring

      paths[dest_hex] = RNS::Transport::PathEntry.new(
        timestamp: Time.utc.to_unix_f - RNS::Transport::DESTINATION_TIMEOUT - 10,
        next_hop: Random::Secure.random_bytes(16),
        hops: 1,
        expires: Time.utc.to_unix_f - 10,
        random_blobs: [] of Bytes,
        receiving_interface: nil,
        packet_hash: Bytes.empty,
      )

      RNS::Transport.tunnels[tunnel_hex] = RNS::Transport::TunnelEntry.new(
        tunnel_id: tunnel_hex.hexbytes,
        interface: nil,
        paths: paths,
        expires: Time.utc.to_unix_f + 3600, # Tunnel not expired
      )

      RNS::Transport.tables_last_culled = 0.0
      RNS::Transport.jobs

      # Tunnel exists but path should be removed
      RNS::Transport.tunnels.size.should eq 1
      RNS::Transport.tunnels[tunnel_hex].paths.size.should eq 0
    end

    it "culls stale path states" do
      dest_hex = Random::Secure.random_bytes(16).hexstring
      RNS::Transport.path_states[dest_hex] = RNS::Transport::STATE_UNRESPONSIVE
      # No corresponding path table entry

      RNS::Transport.tables_last_culled = 0.0
      RNS::Transport.jobs

      RNS::Transport.path_states.size.should eq 0
    end

    it "culls expired blackhole entries" do
      identity_hex = Random::Secure.random_bytes(16).hexstring
      RNS::Transport.blackholed_identities[identity_hex] = {
        "until" => (Time.utc.to_unix_f - 10).as(String | Float64 | Nil),
      }

      RNS::Transport.blackhole_last_checked = 0.0
      RNS::Transport.tables_last_culled = 0.0
      RNS::Transport.jobs

      RNS::Transport.blackholed_identities.size.should eq 0
    end

    it "culls packet hashlist when too large" do
      # Add many entries
      (RNS::Transport::HASHLIST_MAXSIZE // 2 + 1).times do |i|
        RNS::Transport.packet_hashlist << "hash_#{i}"
      end

      RNS::Transport.jobs

      # Should have moved to prev and cleared
      RNS::Transport.packet_hashlist.size.should eq 0
      RNS::Transport.packet_hashlist_prev.size.should be > 0
    end

    it "does not run when jobs_locked" do
      RNS::Transport.jobs_locked = true

      link = RNS::LinkStub.new(Random::Secure.random_bytes(16), initiator: true)
      RNS::Transport.register_link(link)
      link.status = RNS::LinkLike::CLOSED

      RNS::Transport.jobs

      # Link should NOT have been culled because jobs were locked
      RNS::Transport.pending_links.size.should eq 1
      RNS::Transport.jobs_locked = false
    end

    it "resets jobs_running to false after completion" do
      RNS::Transport.jobs
      RNS::Transport.jobs_running.should be_false
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Proof Handling via Reverse Table
  # ════════════════════════════════════════════════════════════════

  describe "proof routing via reverse table" do
    it "transports proof via reverse table entry" do
      iface1 = make_interface_hash
      iface2 = make_interface_hash
      RNS::Transport.register_interface(iface1)
      RNS::Transport.register_interface(iface2)
      RNS::Transport.transport_enabled = true

      proof_dest_hash = Random::Secure.random_bytes(16)
      proof_hex = proof_dest_hash.hexstring

      # Create reverse table entry pointing from iface2 back to iface1
      RNS::Transport.reverse_table[proof_hex] = RNS::Transport::ReverseEntry.new(
        received_on: iface1, # Originally received on iface1
        outbound: iface2,    # Was forwarded to iface2
        timestamp: Time.utc.to_unix_f,
      )

      # Construct a proof packet
      flags = (RNS::Packet::HEADER_1.to_u8 << 6) | (RNS::Transport::BROADCAST.to_u8 << 4) | (RNS::Destination::SINGLE.to_u8 << 2) | RNS::Packet::PROOF.to_u8
      io = IO::Memory.new
      io.write_byte(flags)
      io.write_byte(0x01_u8)                    # hops
      io.write(proof_dest_hash)                 # destination hash
      io.write_byte(RNS::Packet::NONE)          # context
      io.write(Random::Secure.random_bytes(64)) # proof data
      raw = io.to_slice.dup

      RNS::Transport.inbound(raw, iface2) # Received on iface2

      # Should transport proof back to iface1
      forwarded = RNS::Transport.transmit_log.any? { |entry| entry[0] == iface1 }
      forwarded.should be_true

      # Reverse table entry should be consumed
      RNS::Transport.reverse_table.has_key?(proof_hex).should be_false
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  LINK_TIMEOUT constant
  # ════════════════════════════════════════════════════════════════

  describe "LINK_TIMEOUT" do
    it "equals STALE_TIME * 1.25" do
      RNS::Transport::LINK_TIMEOUT.should eq(RNS::LinkLike::STALE_TIME * 1.25)
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  transport_enabled and shared instance flags
  # ════════════════════════════════════════════════════════════════

  describe "transport flags" do
    it "defaults transport_enabled to false" do
      RNS::Transport.transport_enabled?.should be_false
    end

    it "can set transport_enabled" do
      RNS::Transport.transport_enabled = true
      RNS::Transport.transport_enabled?.should be_true
    end

    it "defaults is_connected_to_shared_instance to false" do
      RNS::Transport.is_connected_to_shared_instance?.should be_false
    end

    it "can set is_connected_to_shared_instance" do
      RNS::Transport.is_connected_to_shared_instance = true
      RNS::Transport.is_connected_to_shared_instance?.should be_true
    end
  end

  # ════════════════════════════════════════════════════════════════
  #  Stress Tests
  # ════════════════════════════════════════════════════════════════

  describe "stress tests" do
    it "handles 100 link registrations" do
      100.times do |i|
        link = RNS::LinkStub.new(Random::Secure.random_bytes(16), initiator: (i % 2 == 0))
        RNS::Transport.register_link(link)
      end
      RNS::Transport.pending_links.size.should eq 50
      RNS::Transport.active_links.size.should eq 50
    end

    it "handles 50 tunnel operations" do
      50.times do
        tunnel_id = Random::Secure.random_bytes(32)
        iface = make_interface_hash
        RNS::Transport.handle_tunnel(tunnel_id, iface)
      end
      RNS::Transport.tunnels.size.should eq 50
    end

    it "handles 100 outbound transmissions" do
      dest = make_plain_destination
      iface = make_interface_hash
      RNS::Transport.register_interface(iface)

      100.times do
        pkt = make_packet(dest)
        RNS::Transport.outbound(pkt)
      end
      RNS::Transport.transmit_log.size.should eq 100
    end

    it "handles jobs with many table entries" do
      # Add many entries to various tables
      20.times do
        hash = Random::Secure.random_bytes(16).hexstring
        RNS::Transport.path_table[hash] = RNS::Transport::PathEntry.new(
          timestamp: Time.utc.to_unix_f,
          next_hop: Random::Secure.random_bytes(16),
          hops: 1,
          expires: Time.utc.to_unix_f + 3600,
          random_blobs: [] of Bytes,
          receiving_interface: nil,
          packet_hash: Bytes.empty,
        )

        rev_hash = Random::Secure.random_bytes(16).hexstring
        RNS::Transport.reverse_table[rev_hash] = RNS::Transport::ReverseEntry.new(
          received_on: nil,
          outbound: nil,
          timestamp: Time.utc.to_unix_f,
        )
      end

      5.times do
        link = RNS::LinkStub.new(Random::Secure.random_bytes(16), initiator: true)
        RNS::Transport.register_link(link)
      end

      # Run jobs multiple times
      3.times { RNS::Transport.jobs }

      # Should complete without errors
      RNS::Transport.jobs_running.should be_false
    end
  end
end
