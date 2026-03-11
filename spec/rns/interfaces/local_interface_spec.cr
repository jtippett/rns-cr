require "../../spec_helper"

# Helper to find a free port
private def free_port : Int32
  server = TCPServer.new("127.0.0.1", 0)
  port = server.local_address.port
  server.close
  port
end

# Helper to wait for a condition with timeout
private def wait_for(timeout = 2.seconds, interval = 10.milliseconds, &)
  deadline = Time.monotonic + timeout
  while Time.monotonic < deadline
    return if yield
    sleep interval
  end
end

# Generate a unique Unix socket path for testing
private def test_socket_path : String
  "/tmp/rns_test_#{Process.pid}_#{Random::Secure.hex(4)}.sock"
end

describe RNS::LocalClientInterface do
  describe "constants" do
    it "has RECONNECT_WAIT of 8" do
      RNS::LocalClientInterface::RECONNECT_WAIT.should eq(8)
    end

    it "has AUTOCONFIGURE_MTU enabled" do
      RNS::LocalClientInterface::AUTOCONFIGURE_MTU.should be_true
    end

    it "has HW_MTU_DEFAULT of 262144" do
      RNS::LocalClientInterface::HW_MTU_DEFAULT.should eq(262144)
    end
  end

  describe "connected socket constructor" do
    it "creates an interface from a connected TCP socket" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      iface = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "test_client"
      )

      iface.name.should eq("test_client")
      iface.online.should be_true
      iface.receives?.should be_true
      iface.is_connected_to_shared_instance.should be_false
      iface.bitrate.should eq(1_000_000_000_i64)
      iface.mode.should eq(RNS::Interface::MODE_FULL)

      iface.detach
      client_sock.close rescue nil
      server.close
    end

    it "creates an interface from a connected Unix socket" do
      path = test_socket_path
      server = UNIXServer.new(path)
      client_sock = UNIXSocket.new(path)
      server_sock = server.accept

      iface = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "unix_client"
      )

      iface.name.should eq("unix_client")
      iface.online.should be_true
      iface.is_connected_to_shared_instance.should be_false

      iface.detach
      client_sock.close rescue nil
      server.close
      File.delete?(path)
    end

    it "sets TCP_NODELAY for TCP sockets" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      iface = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "nodelay_test"
      )

      # Interface was created — TCP_NODELAY is set during construction
      iface.online.should be_true

      iface.detach
      client_sock.close rescue nil
      server.close
    end
  end

  describe "TCP port constructor" do
    it "connects to a local TCP server" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      iface = RNS::LocalClientInterface.new(
        target_port: port,
        name: "tcp_client"
      )

      iface.name.should eq("tcp_client")
      iface.online.should be_true
      iface.is_connected_to_shared_instance.should be_true
      iface.never_connected.should be_false
      iface.target_ip.should eq("127.0.0.1")
      iface.target_port.should eq(port)

      iface.detach
      server.close
    end
  end

  describe "Unix socket constructor" do
    it "connects to a Unix domain socket server" do
      path = test_socket_path
      server = UNIXServer.new(path)

      iface = RNS::LocalClientInterface.new(
        socket_path: path,
        name: "unix_connect"
      )

      iface.name.should eq("unix_connect")
      iface.online.should be_true
      iface.is_connected_to_shared_instance.should be_true
      iface.never_connected.should be_false
      iface.socket_path.should eq(path)

      iface.detach
      server.close
      File.delete?(path)
    end
  end

  describe "HDLC outgoing framing" do
    it "sends HDLC-framed data" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      received = Channel(Bytes).new(1)
      cb = Proc(Bytes, RNS::Interface, Nil).new { |data, _iface| received.send(data.dup) }

      iface = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "hdlc_out",
        inbound_callback: cb
      )

      # Send data from the "other side" (client_sock) using HDLC framing
      test_data = Random::Secure.random_bytes(50)
      framed = RNS::HDLC.frame(test_data)
      client_sock.write(framed)
      client_sock.flush

      select
      when result = received.receive
        result.should eq(test_data)
      when timeout(2.seconds)
        fail "Timed out waiting for HDLC data"
      end

      iface.detach
      client_sock.close rescue nil
      server.close
    end

    it "correctly frames outgoing data with HDLC" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      iface = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "hdlc_out2"
      )

      test_data = Random::Secure.random_bytes(30)
      iface.process_outgoing(test_data)

      # Read the framed data from the client side
      buf = Bytes.new(4096)
      bytes_read = client_sock.read(buf)
      received = buf[0, bytes_read]

      # Verify HDLC framing: FLAG + escaped_data + FLAG
      received.first.should eq(RNS::HDLC::FLAG)
      received.last.should eq(RNS::HDLC::FLAG)

      # Unescape and verify
      inner = received[1, received.size - 2]
      unescaped = RNS::HDLC.unescape(inner)
      unescaped.should eq(test_data)

      iface.detach
      client_sock.close rescue nil
      server.close
    end
  end

  describe "HDLC roundtrip" do
    it "sends and receives data between two connected interfaces" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      received_a = Channel(Bytes).new(1)
      received_b = Channel(Bytes).new(1)

      cb_a = Proc(Bytes, RNS::Interface, Nil).new { |data, _| received_a.send(data.dup) }
      cb_b = Proc(Bytes, RNS::Interface, Nil).new { |data, _| received_b.send(data.dup) }

      iface_a = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "a",
        inbound_callback: cb_a
      )

      iface_b = RNS::LocalClientInterface.new(
        connected_socket: client_sock,
        name: "b",
        inbound_callback: cb_b
      )

      # A sends to B
      test_data_ab = Random::Secure.random_bytes(40)
      iface_a.process_outgoing(test_data_ab)

      select
      when result = received_b.receive
        result.should eq(test_data_ab)
      when timeout(2.seconds)
        fail "Timed out waiting for A->B data"
      end

      # B sends to A
      test_data_ba = Random::Secure.random_bytes(35)
      iface_b.process_outgoing(test_data_ba)

      select
      when result = received_a.receive
        result.should eq(test_data_ba)
      when timeout(2.seconds)
        fail "Timed out waiting for B->A data"
      end

      iface_a.detach
      iface_b.detach
      server.close
    end

    it "handles data containing HDLC special bytes" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      received = Channel(Bytes).new(1)
      cb = Proc(Bytes, RNS::Interface, Nil).new { |data, _| received.send(data.dup) }

      iface_a = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "special_a",
        inbound_callback: cb
      )

      iface_b = RNS::LocalClientInterface.new(
        connected_socket: client_sock,
        name: "special_b"
      )

      # Data with HDLC FLAG and ESC bytes embedded
      test_data = Bytes.new(30)
      Random::Secure.random_bytes(test_data)
      test_data[5] = RNS::HDLC::FLAG
      test_data[10] = RNS::HDLC::ESC
      test_data[15] = RNS::HDLC::FLAG
      test_data[20] = RNS::HDLC::ESC

      iface_b.process_outgoing(test_data)

      select
      when result = received.receive
        result.should eq(test_data)
      when timeout(2.seconds)
        fail "Timed out waiting for data with special bytes"
      end

      iface_a.detach
      iface_b.detach
      server.close
    end

    it "handles multiple messages in sequence" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      received = Channel(Bytes).new(10)
      cb = Proc(Bytes, RNS::Interface, Nil).new { |data, _| received.send(data.dup) }

      iface_a = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "multi_a",
        inbound_callback: cb
      )

      iface_b = RNS::LocalClientInterface.new(
        connected_socket: client_sock,
        name: "multi_b"
      )

      messages = (0...5).map { Random::Secure.random_bytes(25 + rand(25)) }
      messages.each { |msg| iface_b.process_outgoing(msg) }

      5.times do |i|
        select
        when result = received.receive
          result.should eq(messages[i])
        when timeout(2.seconds)
          fail "Timed out waiting for message #{i}"
        end
      end

      iface_a.detach
      iface_b.detach
      server.close
    end
  end

  describe "byte counters" do
    it "tracks rxb and txb" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      received = Channel(Bytes).new(1)
      cb = Proc(Bytes, RNS::Interface, Nil).new { |data, _| received.send(data.dup) }

      iface_a = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "counter_a",
        inbound_callback: cb
      )

      iface_b = RNS::LocalClientInterface.new(
        connected_socket: client_sock,
        name: "counter_b"
      )

      test_data = Random::Secure.random_bytes(50)
      iface_b.process_outgoing(test_data)

      select
      when received.receive
      when timeout(2.seconds)
        fail "Timed out"
      end

      iface_b.txb.should be > 0
      iface_a.rxb.should eq(test_data.size.to_i64)

      iface_a.detach
      iface_b.detach
      server.close
    end
  end

  describe "should_ingress_limit?" do
    it "always returns false" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      iface = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "ingress_test"
      )

      iface.should_ingress_limit?.should be_false

      iface.detach
      client_sock.close rescue nil
      server.close
    end
  end

  describe "teardown" do
    it "sets interface offline" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      iface = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "teardown_test"
      )

      iface.online.should be_true
      iface.teardown(nowarning: true)
      iface.online.should be_false
      iface.dir_in.should be_false
      iface.dir_out.should be_false

      client_sock.close rescue nil
      server.close
    end

    it "removes from parent's spawned_interfaces" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      parent_port = free_port
      parent = RNS::LocalServerInterface.new(bindport: parent_port)

      iface = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "child"
      )
      iface.parent_interface = parent
      parent.spawned_interfaces.not_nil! << iface

      parent.spawned_interfaces.not_nil!.size.should eq(1)
      iface.teardown(nowarning: true)
      # Wait for spawned_interfaces cleanup
      wait_for { parent.spawned_interfaces.not_nil!.empty? }
      parent.spawned_interfaces.not_nil!.size.should eq(0)

      client_sock.close rescue nil
      server.close
      parent.detach
    end
  end

  describe "detach" do
    it "marks interface as detached and closes socket" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      iface = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "detach_test"
      )

      iface.detached?.should be_false
      iface.detach
      iface.detached?.should be_true
      iface.online.should be_false

      client_sock.close rescue nil
      server.close
    end
  end

  describe "remote close handling" do
    it "detects when remote end closes (server-spawned)" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      iface = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "close_test"
      )

      iface.online.should be_true
      client_sock.close
      wait_for { !iface.online }
      iface.online.should be_false

      server.close
    end
  end

  describe "to_s" do
    it "formats with target_port for TCP connections" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      iface = RNS::LocalClientInterface.new(
        target_port: port,
        name: "tcp_str"
      )

      iface.to_s.should eq("LocalInterface[#{port}]")

      iface.detach
      server.close
    end

    it "formats with socket_path for Unix connections" do
      path = test_socket_path
      server = UNIXServer.new(path)

      iface = RNS::LocalClientInterface.new(
        socket_path: path,
        name: "unix_str"
      )

      iface.to_s.should eq("LocalInterface[#{path}]")

      iface.detach
      server.close
      File.delete?(path)
    end

    it "shows 0 when no target port set" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      iface = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "no_port"
      )

      iface.to_s.should eq("LocalInterface[0]")

      iface.detach
      client_sock.close rescue nil
      server.close
    end
  end

  describe "base class" do
    it "inherits from Interface" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      iface = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "base_test"
      )

      iface.is_a?(RNS::Interface).should be_true

      iface.detach
      client_sock.close rescue nil
      server.close
    end

    it "has correct default direction flags" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      iface = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "dir_test"
      )

      iface.dir_in.should be_true
      iface.dir_out.should be_false

      iface.detach
      client_sock.close rescue nil
      server.close
    end
  end

  describe "force_bitrate" do
    it "defaults to false" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      iface = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "bitrate_test"
      )

      iface.force_bitrate.should be_false

      iface.detach
      client_sock.close rescue nil
      server.close
    end
  end

  describe "process_outgoing when offline" do
    it "silently drops data when not online" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      iface = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "offline_test"
      )

      iface.online = false
      test_data = Random::Secure.random_bytes(20)
      iface.process_outgoing(test_data) # Should not raise
      iface.txb.should eq(0)

      iface.detach
      client_sock.close rescue nil
      server.close
    end
  end

  describe "stress" do
    it "handles rapid sequential messages" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)
      client_sock = TCPSocket.new("127.0.0.1", port)
      server_sock = server.accept

      count = Atomic(Int32).new(0)
      cb = Proc(Bytes, RNS::Interface, Nil).new { |_data, _| count.add(1) }

      iface_a = RNS::LocalClientInterface.new(
        connected_socket: server_sock,
        name: "stress_a",
        inbound_callback: cb
      )

      iface_b = RNS::LocalClientInterface.new(
        connected_socket: client_sock,
        name: "stress_b"
      )

      50.times do
        iface_b.process_outgoing(Random::Secure.random_bytes(30))
      end

      wait_for(timeout: 5.seconds) { count.get >= 50 }
      count.get.should eq(50)

      iface_a.detach
      iface_b.detach
      server.close
    end
  end
end

describe RNS::LocalServerInterface do
  describe "TCP server" do
    describe "constants" do
      it "has AUTOCONFIGURE_MTU enabled" do
        RNS::LocalServerInterface::AUTOCONFIGURE_MTU.should be_true
      end

      it "has HW_MTU_DEFAULT of 262144" do
        RNS::LocalServerInterface::HW_MTU_DEFAULT.should eq(262144)
      end
    end

    describe "constructor" do
      it "creates a server bound to localhost" do
        port = free_port
        server = RNS::LocalServerInterface.new(bindport: port)

        server.name.should eq("Reticulum")
        server.online.should be_true
        server.bind_ip.should eq("127.0.0.1")
        server.bind_port.should eq(port)
        server.clients.should eq(0)
        server.is_local_shared_instance.should be_true
        server.bitrate.should eq(1_000_000_000_i64)
        server.mode.should eq(RNS::Interface::MODE_FULL)

        server.detach
      end

      it "has empty spawned_interfaces initially" do
        port = free_port
        server = RNS::LocalServerInterface.new(bindport: port)

        server.spawned_interfaces.should_not be_nil
        server.spawned_interfaces.not_nil!.size.should eq(0)

        server.detach
      end

      it "has correct direction flags" do
        port = free_port
        server = RNS::LocalServerInterface.new(bindport: port)

        server.dir_in.should be_true
        server.dir_out.should be_false

        server.detach
      end
    end

    describe "incoming connections" do
      it "accepts a client connection" do
        port = free_port
        received = Channel(Bytes).new(1)
        cb = Proc(Bytes, RNS::Interface, Nil).new { |data, _| received.send(data.dup) }

        server = RNS::LocalServerInterface.new(
          bindport: port,
          inbound_callback: cb
        )

        client = TCPSocket.new("127.0.0.1", port)
        sleep 100.milliseconds # Let server accept

        wait_for { server.clients >= 1 }
        server.clients.should eq(1)
        server.spawned_interfaces.not_nil!.size.should eq(1)

        client.close rescue nil
        server.detach
      end

      it "accepts multiple client connections" do
        port = free_port
        server = RNS::LocalServerInterface.new(bindport: port)

        clients = [] of TCPSocket
        3.times do
          clients << TCPSocket.new("127.0.0.1", port)
          sleep 50.milliseconds
        end

        wait_for { server.clients >= 3 }
        server.clients.should eq(3)
        server.spawned_interfaces.not_nil!.size.should eq(3)

        clients.each { |client| client.close rescue nil }
        server.detach
      end

      it "spawned interface receives data from client" do
        port = free_port
        received = Channel(Bytes).new(1)
        cb = Proc(Bytes, RNS::Interface, Nil).new { |data, _| received.send(data.dup) }

        server = RNS::LocalServerInterface.new(
          bindport: port,
          inbound_callback: cb
        )

        client = TCPSocket.new("127.0.0.1", port)
        sleep 100.milliseconds

        test_data = Random::Secure.random_bytes(40)
        framed = RNS::HDLC.frame(test_data)
        client.write(framed)
        client.flush

        select
        when result = received.receive
          result.should eq(test_data)
        when timeout(2.seconds)
          fail "Timed out waiting for data through local server"
        end

        client.close rescue nil
        server.detach
      end

      it "sets parent_interface on spawned clients" do
        port = free_port
        server = RNS::LocalServerInterface.new(bindport: port)

        client = TCPSocket.new("127.0.0.1", port)
        sleep 100.milliseconds

        wait_for { server.spawned_interfaces.not_nil!.size >= 1 }
        spawned = server.spawned_interfaces.not_nil!.first
        spawned.parent_interface.should eq(server)

        client.close rescue nil
        server.detach
      end
    end

    describe "announce tracking" do
      it "tracks received_announce when from_spawned" do
        port = free_port
        server = RNS::LocalServerInterface.new(bindport: port)

        server.ia_freq_deque.size.should eq(0)
        server.received_announce(from_spawned: true)
        server.ia_freq_deque.size.should eq(1)

        server.detach
      end

      it "does not track received_announce when not from_spawned" do
        port = free_port
        server = RNS::LocalServerInterface.new(bindport: port)

        server.received_announce(from_spawned: false)
        server.ia_freq_deque.size.should eq(0)

        server.detach
      end

      it "tracks sent_announce when from_spawned" do
        port = free_port
        server = RNS::LocalServerInterface.new(bindport: port)

        server.oa_freq_deque.size.should eq(0)
        server.sent_announce(from_spawned: true)
        server.oa_freq_deque.size.should eq(1)

        server.detach
      end
    end

    describe "process_outgoing" do
      it "is a no-op" do
        port = free_port
        server = RNS::LocalServerInterface.new(bindport: port)

        # Should not raise
        server.process_outgoing(Random::Secure.random_bytes(20))
        server.txb.should eq(0)

        server.detach
      end
    end

    describe "detach" do
      it "stops accepting connections" do
        port = free_port
        server = RNS::LocalServerInterface.new(bindport: port)
        server.online.should be_true

        server.detach
        server.online.should be_false
        server.detached?.should be_true

        # Connecting should fail after detach
        expect_raises(Exception) do
          TCPSocket.new("127.0.0.1", port, connect_timeout: 1.seconds)
        end
      end
    end

    describe "to_s" do
      it "formats as Shared Instance with port" do
        port = free_port
        server = RNS::LocalServerInterface.new(bindport: port)

        server.to_s.should eq("Shared Instance[#{port}]")

        server.detach
      end
    end

    describe "base class" do
      it "inherits from Interface" do
        port = free_port
        server = RNS::LocalServerInterface.new(bindport: port)

        server.is_a?(RNS::Interface).should be_true

        server.detach
      end
    end
  end

  describe "Unix socket server" do
    describe "constructor" do
      it "creates a server with Unix domain socket" do
        path = test_socket_path
        server = RNS::LocalServerInterface.new(socket_path: path)

        server.name.should eq("Reticulum")
        server.online.should be_true
        server.socket_path.should eq(path)
        server.clients.should eq(0)

        server.detach
        File.delete?(path)
      end
    end

    describe "incoming connections" do
      it "accepts a Unix socket client" do
        path = test_socket_path
        received = Channel(Bytes).new(1)
        cb = Proc(Bytes, RNS::Interface, Nil).new { |data, _| received.send(data.dup) }

        server = RNS::LocalServerInterface.new(
          socket_path: path,
          inbound_callback: cb
        )

        client = UNIXSocket.new(path)
        sleep 100.milliseconds

        wait_for { server.clients >= 1 }
        server.clients.should eq(1)

        # Send data through
        test_data = Random::Secure.random_bytes(30)
        framed = RNS::HDLC.frame(test_data)
        client.write(framed)
        client.flush

        select
        when result = received.receive
          result.should eq(test_data)
        when timeout(2.seconds)
          fail "Timed out waiting for Unix socket data"
        end

        client.close rescue nil
        server.detach
        File.delete?(path)
      end
    end

    describe "to_s" do
      it "formats as Shared Instance with socket path" do
        path = test_socket_path
        server = RNS::LocalServerInterface.new(socket_path: path)

        server.to_s.should eq("Shared Instance[#{path}]")

        server.detach
        File.delete?(path)
      end
    end

    describe "detach" do
      it "cleans up socket file" do
        path = test_socket_path
        server = RNS::LocalServerInterface.new(socket_path: path)

        File.exists?(path).should be_true
        server.detach
        File.exists?(path).should be_false
      end
    end
  end

  describe "multi-client communication" do
    it "routes data from multiple clients independently" do
      port = free_port
      received_data = [] of Bytes
      mutex = Mutex.new
      cb = Proc(Bytes, RNS::Interface, Nil).new do |data, _|
        mutex.synchronize { received_data << data.dup }
      end

      server = RNS::LocalServerInterface.new(
        bindport: port,
        inbound_callback: cb
      )

      client1 = TCPSocket.new("127.0.0.1", port)
      client2 = TCPSocket.new("127.0.0.1", port)
      sleep 100.milliseconds

      wait_for { server.clients >= 2 }

      msg1 = Random::Secure.random_bytes(25)
      msg2 = Random::Secure.random_bytes(30)

      client1.write(RNS::HDLC.frame(msg1))
      client1.flush
      sleep 50.milliseconds
      client2.write(RNS::HDLC.frame(msg2))
      client2.flush

      wait_for(timeout: 5.seconds) { mutex.synchronize { received_data.size >= 2 } }
      mutex.synchronize do
        received_data.size.should eq(2)
        received_data.should contain(msg1)
        received_data.should contain(msg2)
      end

      client1.close rescue nil
      client2.close rescue nil
      server.detach
    end
  end

  describe "stress" do
    it "handles rapid connections and messages" do
      port = free_port
      count = Atomic(Int32).new(0)
      cb = Proc(Bytes, RNS::Interface, Nil).new { |_, _| count.add(1) }

      server = RNS::LocalServerInterface.new(
        bindport: port,
        inbound_callback: cb
      )

      clients = [] of TCPSocket
      5.times do
        c = TCPSocket.new("127.0.0.1", port)
        clients << c
        sleep 20.milliseconds
      end

      wait_for { server.clients >= 5 }

      # Each client sends 10 messages
      clients.each do |client|
        10.times do
          client.write(RNS::HDLC.frame(Random::Secure.random_bytes(25)))
          client.flush
        end
      end

      wait_for(timeout: 5.seconds) { count.get >= 50 }
      count.get.should eq(50)

      clients.each { |client| client.close rescue nil }
      server.detach
    end
  end
end
