require "../../spec_helper"
require "file_utils"

private def shared_free_port : Int32
  server = TCPServer.new("127.0.0.1", 0)
  port = server.local_address.port
  server.close
  port
end

private def shared_wait_for(timeout = 2.seconds, interval = 10.milliseconds, &)
  deadline = Time.instant + timeout
  while Time.instant < deadline
    return if yield
    sleep interval
  end
end

private def start_shared_announce_transport
  dir = Dir.tempdir + "/rns_shared_announce_#{Random::Secure.hex(4)}"
  Dir.mkdir_p(dir)
  owner = RNS::Transport::OwnerRef.new(
    is_connected_to_shared_instance: false,
    storage_path: dir,
    cache_path: dir,
    transport_enabled: false,
  )
  RNS::Transport.start(owner)
  dir
end

private def cleanup_shared_announce_transport(dir : String)
  RNS::Transport.stop_job_loop
  FileUtils.rm_rf(dir) if Dir.exists?(dir)
end

describe "Integration: shared instance announce propagation", tags: "network" do
  before_each do
    RNS::Transport.reset
    RNS::Identity.known_destinations.clear
    RNS::Identity.known_ratchets.clear
  end

  it "forwards announces from one local client to the other local clients" do
    dir = start_shared_announce_transport
    port = shared_free_port
    received = Channel(Bytes).new(1)
    server = nil.as(RNS::LocalServerInterface?)
    client_a = nil.as(RNS::LocalClientInterface?)
    client_b = nil.as(RNS::LocalClientInterface?)

    server = RNS::LocalServerInterface.new(
      bindport: port,
      inbound_callback: RNS::Transport::INBOUND_DISPATCH
    )
    server.dir_out = true
    RNS::Transport.register_interface(server)

    client_a = RNS::LocalClientInterface.new(target_port: port, name: "announce_a")
    client_b = RNS::LocalClientInterface.new(
      target_port: port,
      name: "announce_b",
      inbound_callback: ->(data : Bytes, _iface : RNS::Interface) { received.send(data.dup) }
    )

    shared_wait_for(timeout: 5.seconds) do
      server.clients >= 2 && RNS::Transport.local_client_interfaces.size == 2
    end

    source_identity = RNS::Identity.new
    source_destination = RNS::Destination.new(
      source_identity,
      RNS::Destination::IN,
      RNS::Destination::SINGLE,
      "sharedannounce",
      ["fanout"],
      register: false
    )
    outbound = source_destination.announce(app_data: "mesh-visible".to_slice, send: false).not_nil!
    outbound.pack

    client_a.process_outgoing(outbound.raw.not_nil!)

    forwarded_raw = select
    when raw = received.receive
      raw
    when timeout(5.seconds)
      fail "Timed out waiting for forwarded announce on second local client"
    end

    forwarded = RNS::Packet.new(nil, forwarded_raw)
    forwarded.unpack.should be_true
    forwarded.packet_type.should eq(RNS::Packet::ANNOUNCE)
    forwarded.header_type.should eq(RNS::Packet::HEADER_2)
    forwarded.transport_type.should eq(RNS::Transport::TRANSPORT)
    forwarded.transport_id.should eq(RNS::Transport.identity.not_nil!.hash)
    forwarded.destination_hash.should eq(source_destination.hash)
    forwarded.data.should eq(outbound.data)

    path_entry = RNS::Transport.path_table[source_destination.hash.hexstring]?
    path_entry.should_not be_nil
  ensure
    if iface = client_a
      begin
        iface.detach
      rescue
      end
    end
    if iface = client_b
      begin
        iface.detach
      rescue
      end
    end
    if iface = server
      begin
        iface.detach
      rescue
      end
    end
    cleanup_shared_announce_transport(dir) if dir
  end
end
