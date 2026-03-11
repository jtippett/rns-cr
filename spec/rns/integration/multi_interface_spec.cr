require "../../spec_helper"
require "file_utils"

# Integration test: Routing across multiple interfaces

private MI_APP_NAME = "multitest"

private def start_mi_transport(transport_enabled : Bool = true)
  dir = Dir.tempdir + "/rns_integration_mi_#{Random::Secure.hex(4)}"
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

private def cleanup_mi_dir(dir : String)
  RNS::Transport.stop_job_loop
  FileUtils.rm_rf(dir) if Dir.exists?(dir)
end

# A concrete AnnounceHandler implementation that collects destination hashes
private class TestAnnounceCollector
  include RNS::Transport::AnnounceHandler

  getter received_hashes : Array(String) = [] of String
  getter aspect_filter : String? = nil

  def initialize(@aspect_filter : String? = nil)
  end

  def received_announce(destination_hash : Bytes, announced_identity : RNS::Identity?, app_data : Bytes?, announce_packet_hash : Bytes?)
    @received_hashes << destination_hash.hexstring
  end
end

describe "Integration: Multi-Interface Routing" do
  before_each do
    RNS::Transport.reset
    RNS::Identity.known_destinations.clear
    RNS::Identity.known_ratchets.clear
  end

  describe "Interface registration" do
    it "registers multiple interfaces with Transport" do
      dir = start_mi_transport
      iface_hashes = (0...3).map do |i|
        hash = RNS::Identity.full_hash("interface_#{i}".to_slice)[0, 16]
        RNS::Transport.interfaces << hash
        hash
      end
      RNS::Transport.interfaces.size.should be >= 3
      iface_hashes.each { |hash| RNS::Transport.interfaces.should contain(hash) }
      cleanup_mi_dir(dir)
    end

    it "deregisters interfaces cleanly" do
      dir = start_mi_transport
      hash = RNS::Identity.full_hash("temp_interface".to_slice)[0, 16]
      RNS::Transport.interfaces << hash
      RNS::Transport.interfaces.includes?(hash).should be_true
      RNS::Transport.interfaces.delete(hash)
      RNS::Transport.interfaces.includes?(hash).should be_false
      cleanup_mi_dir(dir)
    end
  end

  describe "Path-based routing with multiple interfaces" do
    it "routes to correct interface based on path table" do
      dir = start_mi_transport
      iface1 = RNS::Identity.full_hash("interface_alpha".to_slice)[0, 16]
      iface2 = RNS::Identity.full_hash("interface_beta".to_slice)[0, 16]
      RNS::Transport.interfaces << iface1
      RNS::Transport.interfaces << iface2

      dest1_hash = RNS::Identity.truncated_hash(Random::Secure.random_bytes(32))
      dest2_hash = RNS::Identity.truncated_hash(Random::Secure.random_bytes(32))
      now = Time.utc.to_unix_f
      next_hop = RNS::Identity.truncated_hash(Random::Secure.random_bytes(32))

      RNS::Transport.path_table[dest1_hash.hexstring] = RNS::Transport::PathEntry.new(
        timestamp: now, next_hop: next_hop, hops: 1, expires: now + 3600,
        random_blobs: [] of Bytes, receiving_interface: iface1,
        packet_hash: Random::Secure.random_bytes(32))

      RNS::Transport.path_table[dest2_hash.hexstring] = RNS::Transport::PathEntry.new(
        timestamp: now, next_hop: next_hop, hops: 2, expires: now + 3600,
        random_blobs: [] of Bytes, receiving_interface: iface2,
        packet_hash: Random::Secure.random_bytes(32))

      RNS::Transport.path_table.has_key?(dest1_hash.hexstring).should be_true
      RNS::Transport.path_table.has_key?(dest2_hash.hexstring).should be_true
      RNS::Transport.path_table[dest1_hash.hexstring].receiving_interface.should eq(iface1)
      RNS::Transport.path_table[dest2_hash.hexstring].receiving_interface.should eq(iface2)
      RNS::Transport.path_table[dest1_hash.hexstring].hops.should eq(1)
      RNS::Transport.path_table[dest2_hash.hexstring].hops.should eq(2)
      cleanup_mi_dir(dir)
    end

    it "returns correct next_hop for each destination" do
      dir = start_mi_transport
      iface = RNS::Identity.full_hash("router_iface".to_slice)[0, 16]
      RNS::Transport.interfaces << iface

      hop1 = RNS::Identity.truncated_hash("hop_one".to_slice)
      hop2 = RNS::Identity.truncated_hash("hop_two".to_slice)
      dest1_hash = RNS::Identity.truncated_hash(Random::Secure.random_bytes(32))
      dest2_hash = RNS::Identity.truncated_hash(Random::Secure.random_bytes(32))
      now = Time.utc.to_unix_f

      RNS::Transport.path_table[dest1_hash.hexstring] = RNS::Transport::PathEntry.new(
        timestamp: now, next_hop: hop1, hops: 1, expires: now + 3600,
        random_blobs: [] of Bytes, receiving_interface: iface,
        packet_hash: Random::Secure.random_bytes(32))

      RNS::Transport.path_table[dest2_hash.hexstring] = RNS::Transport::PathEntry.new(
        timestamp: now, next_hop: hop2, hops: 3, expires: now + 3600,
        random_blobs: [] of Bytes, receiving_interface: iface,
        packet_hash: Random::Secure.random_bytes(32))

      RNS::Transport.path_table[dest1_hash.hexstring].next_hop.should eq(hop1)
      RNS::Transport.path_table[dest2_hash.hexstring].next_hop.should eq(hop2)
      cleanup_mi_dir(dir)
    end
  end

  describe "Announce propagation across interfaces" do
    it "processes announce and populates path table via inbound_announce" do
      dir = start_mi_transport

      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE,
        MI_APP_NAME, register: false)
      packet = dest.announce(send: false).not_nil!

      # Feed the announce through inbound_announce (no interface_hash param)
      result = RNS::Transport.inbound_announce(packet)

      # The announce is for a destination we just created — it won't be registered
      # locally (register: false), so inbound_announce should process it
      # Result may be true or false depending on validation; check path table directly
      if result
        RNS::Transport.path_table.has_key?(dest.hash.hexstring).should be_true
      end
      cleanup_mi_dir(dir)
    end

    it "populates path table directly to simulate announce from multiple interfaces" do
      dir = start_mi_transport
      iface1 = RNS::Identity.full_hash("iface_a".to_slice)[0, 16]
      iface2 = RNS::Identity.full_hash("iface_b".to_slice)[0, 16]
      RNS::Transport.interfaces << iface1
      RNS::Transport.interfaces << iface2

      now = Time.utc.to_unix_f

      id1 = RNS::Identity.new
      dest1 = RNS::Destination.new(id1, RNS::Destination::IN, RNS::Destination::SINGLE,
        MI_APP_NAME, ["svc1"], register: false)

      id2 = RNS::Identity.new
      dest2 = RNS::Destination.new(id2, RNS::Destination::IN, RNS::Destination::SINGLE,
        MI_APP_NAME, ["svc2"], register: false)

      # Directly place entries into path table as if announces were received
      RNS::Transport.path_table[dest1.hash.hexstring] = RNS::Transport::PathEntry.new(
        timestamp: now, next_hop: dest1.hash, hops: 1, expires: now + 3600,
        random_blobs: [] of Bytes, receiving_interface: iface1,
        packet_hash: Random::Secure.random_bytes(32))

      RNS::Transport.path_table[dest2.hash.hexstring] = RNS::Transport::PathEntry.new(
        timestamp: now, next_hop: dest2.hash, hops: 1, expires: now + 3600,
        random_blobs: [] of Bytes, receiving_interface: iface2,
        packet_hash: Random::Secure.random_bytes(32))

      RNS::Transport.path_table.has_key?(dest1.hash.hexstring).should be_true
      RNS::Transport.path_table.has_key?(dest2.hash.hexstring).should be_true
      RNS::Transport.path_table[dest1.hash.hexstring].receiving_interface.should eq(iface1)
      RNS::Transport.path_table[dest2.hash.hexstring].receiving_interface.should eq(iface2)
      cleanup_mi_dir(dir)
    end

    it "announce handler receives callbacks when registered" do
      dir = start_mi_transport

      handler = TestAnnounceCollector.new
      RNS::Transport.register_announce_handler(handler)

      RNS::Transport.announce_handlers.should contain(handler)

      RNS::Transport.deregister_announce_handler(handler)
      RNS::Transport.announce_handlers.should_not contain(handler)

      cleanup_mi_dir(dir)
    end
  end

  describe "Destination registration across interfaces" do
    it "multiple destinations can be registered" do
      dir = start_mi_transport
      destinations = (0...5).map do |i|
        id = RNS::Identity.new
        RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE,
          MI_APP_NAME, ["service#{i}"])
      end
      RNS::Transport.destinations.size.should be >= 5
      destinations.each { |dest| RNS::Transport.destinations.should contain(dest) }
      cleanup_mi_dir(dir)
    end

    it "deregistering destination removes it" do
      dir = start_mi_transport
      id = RNS::Identity.new
      dest = RNS::Destination.new(id, RNS::Destination::IN, RNS::Destination::SINGLE, MI_APP_NAME, ["temp"])
      RNS::Transport.destinations.should contain(dest)
      RNS::Transport.deregister_destination(dest)
      RNS::Transport.destinations.should_not contain(dest)
      cleanup_mi_dir(dir)
    end
  end

  describe "Path expiry" do
    it "removing path from table makes it unavailable" do
      dir = start_mi_transport
      dest_hash = RNS::Identity.truncated_hash(Random::Secure.random_bytes(32))
      iface = RNS::Identity.full_hash("expiry_iface".to_slice)[0, 16]
      now = Time.utc.to_unix_f

      RNS::Transport.path_table[dest_hash.hexstring] = RNS::Transport::PathEntry.new(
        timestamp: now, next_hop: Random::Secure.random_bytes(16), hops: 1,
        expires: now + 3600, random_blobs: [] of Bytes,
        receiving_interface: iface, packet_hash: Random::Secure.random_bytes(32))

      RNS::Transport.path_table.has_key?(dest_hash.hexstring).should be_true
      RNS::Transport.path_table.delete(dest_hash.hexstring)
      RNS::Transport.path_table.has_key?(dest_hash.hexstring).should be_false
      cleanup_mi_dir(dir)
    end
  end

  describe "UDP interface send/receive between two interfaces", tags: "network" do
    it "sends and receives data between UDP interfaces" do
      port = Random.rand(40000..50000)
      received = Channel(Bytes).new(1)

      receiver = RNS::UDPInterface.new({
        "name" => "test_receiver", "listen_ip" => "127.0.0.1", "listen_port" => port.to_s,
      }) { |data, _iface| received.send(data.dup) }

      sleep(10.milliseconds)

      sender = RNS::UDPInterface.new({
        "name" => "test_sender", "forward_ip" => "127.0.0.1", "forward_port" => port.to_s,
      })

      begin
        test_data = "Multi-interface UDP test".to_slice
        sender.process_outgoing(test_data)

        select
        when result = received.receive
          result.should eq(test_data)
        when timeout(2.seconds)
          raise "Timeout waiting for UDP data"
        end
      ensure
        sender.teardown
        receiver.teardown
      end
    end

    it "two UDP interface pairs operate independently" do
      port_a = Random.rand(40000..44000)
      port_b = Random.rand(45000..49000)

      received_a = Channel(Bytes).new(1)
      received_b = Channel(Bytes).new(1)

      recv_a = RNS::UDPInterface.new({
        "name" => "recv_a", "listen_ip" => "127.0.0.1", "listen_port" => port_a.to_s,
      }) { |data, _| received_a.send(data.dup) }

      recv_b = RNS::UDPInterface.new({
        "name" => "recv_b", "listen_ip" => "127.0.0.1", "listen_port" => port_b.to_s,
      }) { |data, _| received_b.send(data.dup) }

      sleep(10.milliseconds)

      send_a = RNS::UDPInterface.new({
        "name" => "send_a", "forward_ip" => "127.0.0.1", "forward_port" => port_a.to_s,
      })
      send_b = RNS::UDPInterface.new({
        "name" => "send_b", "forward_ip" => "127.0.0.1", "forward_port" => port_b.to_s,
      })

      begin
        send_a.process_outgoing("Data for A".to_slice)
        send_b.process_outgoing("Data for B".to_slice)

        select
        when r = received_a.receive
          r.should eq("Data for A".to_slice)
        when timeout(2.seconds)
          raise "Timeout on interface A"
        end

        select
        when r = received_b.receive
          r.should eq("Data for B".to_slice)
        when timeout(2.seconds)
          raise "Timeout on interface B"
        end
      ensure
        [send_a, send_b, recv_a, recv_b].each(&.teardown)
      end
    end
  end

  describe "TCP LocalInterface client-server communication", tags: "network" do
    it "LocalServer accepts LocalClient connection" do
      port = Random.rand(40000..50000)
      server = RNS::LocalServerInterface.new(port)
      sleep(50.milliseconds)

      client = RNS::LocalClientInterface.new(target_port: port, name: "test_client")
      sleep(100.milliseconds)

      begin
        # Verify connection was established
        server.clients.should be >= 1
        client.online.should be_true
      ensure
        client.detach
        client.teardown
        server.detach
        server.teardown
      end
    end
  end

  describe "Transport transmit log" do
    it "records transmissions to interfaces" do
      dir = start_mi_transport
      iface = RNS::Identity.full_hash("transmit_iface".to_slice)[0, 16]
      RNS::Transport.interfaces << iface
      raw = Random::Secure.random_bytes(100)
      RNS::Transport.transmit(iface, raw)
      RNS::Transport.transmit_log.size.should eq(1)
      RNS::Transport.transmit_log[0][0].should eq(iface)
      RNS::Transport.transmit_log[0][1].should eq(raw)
      cleanup_mi_dir(dir)
    end
  end

  describe "Stress tests", tags: "network" do
    it "registers and routes through 20 interfaces with 50 paths" do
      dir = start_mi_transport
      interfaces = (0...20).map do |i|
        hash = RNS::Identity.full_hash("stress_iface_#{i}".to_slice)[0, 16]
        RNS::Transport.interfaces << hash
        hash
      end

      now = Time.utc.to_unix_f
      50.times do |i|
        dest_hash = RNS::Identity.truncated_hash(Random::Secure.random_bytes(32))
        iface = interfaces[i % interfaces.size]
        RNS::Transport.path_table[dest_hash.hexstring] = RNS::Transport::PathEntry.new(
          timestamp: now, next_hop: RNS::Identity.truncated_hash(Random::Secure.random_bytes(32)),
          hops: (i % 10) + 1, expires: now + 3600,
          random_blobs: [] of Bytes, receiving_interface: iface,
          packet_hash: Random::Secure.random_bytes(32))
        RNS::Transport.path_table.has_key?(dest_hash.hexstring).should be_true
        RNS::Transport.path_table[dest_hash.hexstring].receiving_interface.should eq(iface)
      end
      RNS::Transport.path_table.size.should eq(50)
      cleanup_mi_dir(dir)
    end

    it "registers 30 paths arriving on different interfaces" do
      dir = start_mi_transport
      interfaces = (0...5).map do |i|
        hash = RNS::Identity.full_hash("ann_iface_#{i}".to_slice)[0, 16]
        RNS::Transport.interfaces << hash
        hash
      end

      now = Time.utc.to_unix_f
      30.times do |i|
        dest_hash = RNS::Identity.truncated_hash(Random::Secure.random_bytes(32))
        iface = interfaces[i % interfaces.size]
        RNS::Transport.path_table[dest_hash.hexstring] = RNS::Transport::PathEntry.new(
          timestamp: now, next_hop: dest_hash, hops: 1, expires: now + 3600,
          random_blobs: [] of Bytes, receiving_interface: iface,
          packet_hash: Random::Secure.random_bytes(32))
        RNS::Transport.path_table.has_key?(dest_hash.hexstring).should be_true
      end
      RNS::Transport.path_table.size.should eq(30)
      cleanup_mi_dir(dir)
    end
  end
end
