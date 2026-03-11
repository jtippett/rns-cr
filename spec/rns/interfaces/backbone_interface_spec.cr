require "../../spec_helper"

describe RNS::BackboneInterface do
  describe "constants" do
    it "has correct HW_MTU" do
      RNS::BackboneInterfaceConstants::HW_MTU.should eq(1048576)
    end

    it "has correct BITRATE_GUESS for server" do
      RNS::BackboneInterface::BITRATE_GUESS.should eq(1_000_000_000_i64)
    end

    it "has correct DEFAULT_IFAC_SIZE for server" do
      RNS::BackboneInterface::DEFAULT_IFAC_SIZE.should eq(16)
    end

    it "has AUTOCONFIGURE_MTU enabled" do
      RNS::BackboneInterface.autoconfigure_mtu?.should be_true
    end
  end

  describe "#initialize" do
    it "creates a server interface with bind IP and port" do
      config = {
        "name"        => "TestBackbone",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => "4242",
      }
      iface = RNS::BackboneInterface.new(config)
      iface.name.should eq("TestBackbone")
      iface.bind_ip.should eq("127.0.0.1")
      iface.bind_port.should eq(4242)
      iface.online.should be_true
      iface.mode.should eq(RNS::Interface::MODE_FULL)
      iface.supports_discovery.should be_true
      iface.bitrate.should eq(1_000_000_000_i64)
      iface.detach
    end

    it "uses port parameter as fallback for listen_port" do
      config = {
        "name"      => "TestBackbone",
        "listen_ip" => "127.0.0.1",
        "port"      => "4243",
      }
      iface = RNS::BackboneInterface.new(config)
      iface.bind_port.should eq(4243)
      iface.detach
    end

    it "raises when no port is configured" do
      config = {
        "name"      => "TestBackbone",
        "listen_ip" => "127.0.0.1",
      }
      expect_raises(ArgumentError, /No TCP port/) do
        RNS::BackboneInterface.new(config)
      end
    end

    it "raises when no bind IP is configured" do
      config = {
        "name"        => "TestBackbone",
        "listen_port" => "4244",
      }
      expect_raises(ArgumentError, /No TCP bind IP/) do
        RNS::BackboneInterface.new(config)
      end
    end
  end

  describe "#clients" do
    it "starts with zero clients" do
      config = {
        "name"        => "TestBackbone",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => "4245",
      }
      iface = RNS::BackboneInterface.new(config)
      iface.clients.should eq(0)
      iface.detach
    end
  end

  describe "#process_outgoing" do
    it "is a no-op (server does not transmit directly)" do
      config = {
        "name"        => "TestBackbone",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => "4246",
      }
      iface = RNS::BackboneInterface.new(config)
      iface.process_outgoing(Bytes[1, 2, 3])
      iface.txb.should eq(0)
      iface.detach
    end
  end

  describe "#to_s" do
    it "formats IPv4 address correctly" do
      config = {
        "name"        => "TestBB",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => "4247",
      }
      iface = RNS::BackboneInterface.new(config)
      iface.to_s.should eq("BackboneInterface[TestBB/127.0.0.1:4247]")
      iface.detach
    end

    it "formats IPv6 address with brackets" do
      config = {
        "name"        => "TestBB6",
        "listen_ip"   => "::1",
        "listen_port" => "4248",
      }
      # May fail to bind on some systems; just test format logic
      begin
        iface = RNS::BackboneInterface.new(config)
        iface.to_s.should eq("BackboneInterface[TestBB6/[::1]:4248]")
        iface.detach
      rescue
        # Skip if IPv6 not available
      end
    end
  end

  describe "#received_announce and #sent_announce" do
    it "tracks announce frequency from spawned interfaces" do
      config = {
        "name"        => "TestBB",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => "4249",
      }
      iface = RNS::BackboneInterface.new(config)
      iface.ia_freq_deque.size.should eq(0)
      iface.received_announce(from_spawned: true)
      iface.ia_freq_deque.size.should eq(1)
      iface.sent_announce(from_spawned: true)
      iface.oa_freq_deque.size.should eq(1)
      iface.detach
    end

    it "does not track when from_spawned is false" do
      config = {
        "name"        => "TestBB",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => "4250",
      }
      iface = RNS::BackboneInterface.new(config)
      iface.received_announce(from_spawned: false)
      iface.ia_freq_deque.size.should eq(0)
      iface.sent_announce(from_spawned: false)
      iface.oa_freq_deque.size.should eq(0)
      iface.detach
    end
  end

  describe "#detach" do
    it "marks the interface as offline and detached" do
      config = {
        "name"        => "TestBB",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => "4251",
      }
      iface = RNS::BackboneInterface.new(config)
      iface.online.should be_true
      iface.detach
      iface.online.should be_false
      iface.detached?.should be_true
    end
  end
end

describe RNS::BackboneClientInterface do
  describe "constants" do
    it "has correct BITRATE_GUESS" do
      RNS::BackboneClientInterface::BITRATE_GUESS.should eq(100_000_000_i64)
    end

    it "has correct DEFAULT_IFAC_SIZE" do
      RNS::BackboneClientInterface::DEFAULT_IFAC_SIZE.should eq(16)
    end

    it "has correct RECONNECT_WAIT" do
      RNS::BackboneClientInterface::RECONNECT_WAIT.should eq(5)
    end

    it "has correct TCP socket option constants" do
      RNS::BackboneClientInterface::TCP_USER_TIMEOUT.should eq(24)
      RNS::BackboneClientInterface::TCP_PROBE_AFTER.should eq(5)
      RNS::BackboneClientInterface::TCP_PROBE_INTERVAL.should eq(2)
      RNS::BackboneClientInterface::TCP_PROBES.should eq(12)
    end

    it "has correct INITIAL_CONNECT_TIMEOUT" do
      RNS::BackboneClientInterface::INITIAL_CONNECT_TIMEOUT.should eq(5)
    end

    it "has AUTOCONFIGURE_MTU enabled" do
      RNS::BackboneClientInterface.autoconfigure_mtu?.should be_true
    end
  end

  describe "spawned client from connected socket" do
    it "creates a client from a pre-connected socket" do
      # Start a temporary TCP server to generate a connected socket pair
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port

      client_sock = TCPSocket.new("127.0.0.1", port)
      accepted_sock = server.accept

      iface = RNS::BackboneClientInterface.new(
        connected_socket: accepted_sock,
        name: "TestClient"
      )
      iface.name.should eq("TestClient")
      iface.online.should be_true
      iface.initiator?.should be_false
      iface.mode.should eq(RNS::Interface::MODE_FULL)
      iface.bitrate.should eq(100_000_000_i64)

      iface.detach
      client_sock.close rescue nil
      server.close rescue nil
    end
  end

  describe "HDLC framing" do
    it "frames outgoing data with HDLC" do
      # Create a connected pair for testing
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port

      client_sock = TCPSocket.new("127.0.0.1", port)
      accepted_sock = server.accept

      iface = RNS::BackboneClientInterface.new(
        connected_socket: accepted_sock,
        name: "TestClient"
      )

      # Send data through the backbone client
      test_data = Bytes[0x01, 0x02, 0x03, 0x04]
      iface.process_outgoing(test_data)

      # Read from the other side of the socket
      buf = Bytes.new(256)
      bytes_read = client_sock.read(buf)
      received = buf[0, bytes_read]

      # Should be HDLC framed: FLAG + escaped_data + FLAG
      received[0].should eq(RNS::HDLC::FLAG)
      received[received.size - 1].should eq(RNS::HDLC::FLAG)

      # Unescape the inner data
      inner = received[1, received.size - 2]
      unescaped = RNS::HDLC.unescape(inner)
      unescaped.should eq(test_data)

      iface.detach
      client_sock.close rescue nil
      server.close rescue nil
    end

    it "escapes HDLC special bytes in outgoing data" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port

      client_sock = TCPSocket.new("127.0.0.1", port)
      accepted_sock = server.accept

      iface = RNS::BackboneClientInterface.new(
        connected_socket: accepted_sock,
        name: "TestClient"
      )

      # Data containing HDLC FLAG and ESC bytes
      test_data = Bytes[0x7E, 0x7D, 0x42]
      iface.process_outgoing(test_data)

      buf = Bytes.new(256)
      bytes_read = client_sock.read(buf)
      received = buf[0, bytes_read]

      # Verify framing
      received[0].should eq(RNS::HDLC::FLAG)
      received[received.size - 1].should eq(RNS::HDLC::FLAG)

      # Verify content roundtrips correctly
      inner = received[1, received.size - 2]
      unescaped = RNS::HDLC.unescape(inner)
      unescaped.should eq(test_data)

      iface.detach
      client_sock.close rescue nil
      server.close rescue nil
    end
  end

  describe "receive and HDLC deframing" do
    it "receives HDLC framed data and delivers to callback" do
      received_data = nil
      received_iface = nil

      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port

      client_sock = TCPSocket.new("127.0.0.1", port)
      accepted_sock = server.accept

      callback = ->(data : Bytes, iface : RNS::Interface) {
        received_data = data.dup
        received_iface = iface
        nil
      }

      iface = RNS::BackboneClientInterface.new(
        connected_socket: accepted_sock,
        name: "TestClient",
        inbound_callback: callback
      )

      # Create an HDLC-framed message with enough data to pass HEADER_MINSIZE check
      test_data = Bytes.new(20) { |i| (i + 1).to_u8 }
      framed = RNS::HDLC.frame(test_data)
      client_sock.write(framed)
      client_sock.flush

      # Wait briefly for the read fiber to process
      sleep 100.milliseconds

      received_data.should_not be_nil
      received_data.should eq(test_data)

      iface.detach
      client_sock.close rescue nil
      server.close rescue nil
    end

    it "handles multiple frames in a single read" do
      received_frames = [] of Bytes

      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port

      client_sock = TCPSocket.new("127.0.0.1", port)
      accepted_sock = server.accept

      callback = ->(data : Bytes, _iface : RNS::Interface) {
        received_frames << data.dup
        nil
      }

      iface = RNS::BackboneClientInterface.new(
        connected_socket: accepted_sock,
        name: "TestClient",
        inbound_callback: callback
      )

      # Send two frames together
      frame1_data = Bytes.new(20) { |i| (i + 1).to_u8 }
      frame2_data = Bytes.new(20) { |i| (i + 100).to_u8 }
      framed1 = RNS::HDLC.frame(frame1_data)
      framed2 = RNS::HDLC.frame(frame2_data)

      combined = IO::Memory.new
      combined.write(framed1)
      combined.write(framed2)
      client_sock.write(combined.to_slice)
      client_sock.flush

      sleep 100.milliseconds

      received_frames.size.should eq(2)
      received_frames[0].should eq(frame1_data)
      received_frames[1].should eq(frame2_data)

      iface.detach
      client_sock.close rescue nil
      server.close rescue nil
    end

    it "ignores frames smaller than HEADER_MINSIZE" do
      received_frames = [] of Bytes

      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port

      client_sock = TCPSocket.new("127.0.0.1", port)
      accepted_sock = server.accept

      callback = ->(data : Bytes, _iface : RNS::Interface) {
        received_frames << data.dup
        nil
      }

      iface = RNS::BackboneClientInterface.new(
        connected_socket: accepted_sock,
        name: "TestClient",
        inbound_callback: callback
      )

      # Send a too-small frame (less than HEADER_MINSIZE bytes)
      tiny_data = Bytes[0x01, 0x02]
      framed = RNS::HDLC.frame(tiny_data)
      client_sock.write(framed)
      client_sock.flush

      sleep 100.milliseconds

      received_frames.size.should eq(0)

      iface.detach
      client_sock.close rescue nil
      server.close rescue nil
    end
  end

  describe "incoming connection (server + client integration)" do
    it "accepts incoming connections and creates spawned interfaces" do
      received_data = nil
      callback = ->(data : Bytes, _iface : RNS::Interface) {
        received_data = data.dup
        nil
      }

      config = {
        "name"        => "TestBBServer",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => "0",
      }
      srv = RNS::BackboneInterface.new(config, inbound_callback: callback)

      # Get the actual port the server bound to
      actual_port = srv.bind_port

      # Connect a client
      client_sock = TCPSocket.new("127.0.0.1", actual_port)
      sleep 100.milliseconds

      srv.clients.should be >= 1

      # Send HDLC framed data from client
      test_data = Bytes.new(20) { |i| (i + 1).to_u8 }
      framed = RNS::HDLC.frame(test_data)
      client_sock.write(framed)
      client_sock.flush
      sleep 100.milliseconds

      received_data.should eq(test_data)

      client_sock.close rescue nil
      srv.detach
    end

    it "spawned client inherits parent properties" do
      config = {
        "name"        => "TestBBServer",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => "0",
      }
      srv = RNS::BackboneInterface.new(config)
      srv.announce_rate_target = 5
      srv.announce_rate_grace = 10
      srv.announce_rate_penalty = 20

      actual_port = srv.bind_port

      client_sock = TCPSocket.new("127.0.0.1", actual_port)
      sleep 100.milliseconds

      srv.clients.should eq(1)

      if si = srv.spawned_interfaces
        spawned = si.first
        spawned.should be_a(RNS::BackboneClientInterface)
        bc = spawned.as(RNS::BackboneClientInterface)
        bc.parent_interface.should eq(srv)
        bc.announce_rate_target.should eq(5)
        bc.announce_rate_grace.should eq(10)
        bc.announce_rate_penalty.should eq(20)
        bc.mode.should eq(srv.mode)
      else
        fail "No spawned interfaces found"
      end

      client_sock.close rescue nil
      srv.detach
    end
  end

  describe "initiator client" do
    it "connects to a remote server" do
      # Start a server to connect to
      tcp_server = TCPServer.new("127.0.0.1", 0)
      port = tcp_server.local_address.port

      config = {
        "name"        => "TestBBClient",
        "target_host" => "127.0.0.1",
        "target_port" => port.to_s,
      }
      iface = RNS::BackboneClientInterface.new(config)
      iface.online.should be_true
      iface.initiator?.should be_true
      iface.name.should eq("TestBBClient")

      # Accept on the server side
      accepted = tcp_server.accept
      accepted.should_not be_nil

      iface.detach
      accepted.close rescue nil
      tcp_server.close rescue nil
    end
  end

  describe "#process_incoming" do
    it "tracks rxb on both client and parent" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port

      client_sock = TCPSocket.new("127.0.0.1", port)
      accepted_sock = server.accept

      parent = RNS::BackboneInterface.new({
        "name"        => "TestBBParent",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => "0",
      })

      iface = RNS::BackboneClientInterface.new(
        connected_socket: accepted_sock,
        name: "TestClient"
      )
      iface.parent_interface = parent

      iface.rxb.should eq(0)
      parent.rxb.should eq(0)

      # Simulate process_incoming
      iface.process_incoming(Bytes.new(100))
      iface.rxb.should eq(100)
      parent.rxb.should eq(100)

      iface.detach
      parent.detach
      client_sock.close rescue nil
      server.close rescue nil
    end
  end

  describe "#teardown" do
    it "marks the interface as offline" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port

      client_sock = TCPSocket.new("127.0.0.1", port)
      accepted_sock = server.accept

      iface = RNS::BackboneClientInterface.new(
        connected_socket: accepted_sock,
        name: "TestClient"
      )
      iface.online.should be_true
      iface.teardown
      iface.online.should be_false
      iface.dir_in.should be_false
      iface.dir_out.should be_false

      client_sock.close rescue nil
      server.close rescue nil
    end

    it "removes itself from parent spawned_interfaces" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port

      client_sock = TCPSocket.new("127.0.0.1", port)
      accepted_sock = server.accept

      parent = RNS::BackboneInterface.new({
        "name"        => "TestBBParent",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => "0",
      })
      parent.spawned_interfaces = [] of RNS::Interface

      iface = RNS::BackboneClientInterface.new(
        connected_socket: accepted_sock,
        name: "TestClient"
      )
      iface.parent_interface = parent
      parent.spawned_interfaces.not_nil! << iface

      parent.spawned_interfaces.not_nil!.size.should eq(1)
      iface.teardown
      parent.spawned_interfaces.not_nil!.size.should eq(0)

      parent.detach
      client_sock.close rescue nil
      server.close rescue nil
    end
  end

  describe "#to_s" do
    it "formats with IPv4 address" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port

      client_sock = TCPSocket.new("127.0.0.1", port)
      accepted_sock = server.accept

      iface = RNS::BackboneClientInterface.new(
        connected_socket: accepted_sock,
        name: "TestClient"
      )
      iface.target_ip = "10.0.0.1"
      iface.target_port = 4242

      iface.to_s.should eq("BackboneInterface[TestClient/10.0.0.1:4242]")

      iface.detach
      client_sock.close rescue nil
      server.close rescue nil
    end

    it "formats IPv6 address with brackets" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port

      client_sock = TCPSocket.new("127.0.0.1", port)
      accepted_sock = server.accept

      iface = RNS::BackboneClientInterface.new(
        connected_socket: accepted_sock,
        name: "TestClient"
      )
      iface.target_ip = "::1"
      iface.target_port = 4242

      iface.to_s.should eq("BackboneInterface[TestClient/[::1]:4242]")

      iface.detach
      client_sock.close rescue nil
      server.close rescue nil
    end
  end
end
