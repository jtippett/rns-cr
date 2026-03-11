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

describe RNS::KISS do
  describe "constants" do
    it "has correct FEND, FESC, TFEND, TFESC values" do
      RNS::KISS::FEND.should eq(0xC0_u8)
      RNS::KISS::FESC.should eq(0xDB_u8)
      RNS::KISS::TFEND.should eq(0xDC_u8)
      RNS::KISS::TFESC.should eq(0xDD_u8)
    end

    it "has correct CMD_DATA and CMD_UNKNOWN values" do
      RNS::KISS::CMD_DATA.should eq(0x00_u8)
      RNS::KISS::CMD_UNKNOWN.should eq(0xFE_u8)
    end
  end

  describe "escape" do
    it "escapes FEND bytes" do
      data = Bytes[0x01, 0xC0, 0x02]
      escaped = RNS::KISS.escape(data)
      escaped.should eq(Bytes[0x01, 0xDB, 0xDC, 0x02])
    end

    it "escapes FESC bytes" do
      data = Bytes[0x01, 0xDB, 0x02]
      escaped = RNS::KISS.escape(data)
      escaped.should eq(Bytes[0x01, 0xDB, 0xDD, 0x02])
    end

    it "escapes both FEND and FESC" do
      data = Bytes[0xC0, 0xDB]
      escaped = RNS::KISS.escape(data)
      escaped.should eq(Bytes[0xDB, 0xDC, 0xDB, 0xDD])
    end

    it "returns data unchanged when no special bytes" do
      data = Bytes[0x01, 0x02, 0x03]
      escaped = RNS::KISS.escape(data)
      escaped.should eq(data)
    end

    it "handles empty data" do
      data = Bytes.new(0)
      escaped = RNS::KISS.escape(data)
      escaped.size.should eq(0)
    end
  end

  describe "unescape" do
    it "unescapes FEND sequence" do
      data = Bytes[0x01, 0xDB, 0xDC, 0x02]
      unescaped = RNS::KISS.unescape(data)
      unescaped.should eq(Bytes[0x01, 0xC0, 0x02])
    end

    it "unescapes FESC sequence" do
      data = Bytes[0x01, 0xDB, 0xDD, 0x02]
      unescaped = RNS::KISS.unescape(data)
      unescaped.should eq(Bytes[0x01, 0xDB, 0x02])
    end

    it "handles empty data" do
      data = Bytes.new(0)
      unescaped = RNS::KISS.unescape(data)
      unescaped.size.should eq(0)
    end
  end

  describe "escape/unescape roundtrip" do
    it "roundtrips arbitrary data" do
      100.times do
        size = rand(0..200)
        original = Random::Secure.random_bytes(size)
        escaped = RNS::KISS.escape(original)
        unescaped = RNS::KISS.unescape(escaped)
        unescaped.should eq(original)
      end
    end
  end

  describe "frame" do
    it "wraps data with FEND CMD_DATA and trailing FEND" do
      data = Bytes[0x01, 0x02, 0x03]
      framed = RNS::KISS.frame(data)
      framed[0].should eq(RNS::KISS::FEND)
      framed[1].should eq(RNS::KISS::CMD_DATA)
      framed[-1].should eq(RNS::KISS::FEND)
    end

    it "escapes data within the frame" do
      data = Bytes[0xC0] # FEND byte
      framed = RNS::KISS.frame(data)
      # FEND + CMD_DATA + escaped(FEND) + FEND = 0xC0 0x00 0xDB 0xDC 0xC0
      framed.should eq(Bytes[0xC0, 0x00, 0xDB, 0xDC, 0xC0])
    end

    it "handles empty data" do
      framed = RNS::KISS.frame(Bytes.new(0))
      framed.should eq(Bytes[0xC0, 0x00, 0xC0])
    end
  end
end

describe RNS::TCPInterfaceConstants do
  it "has HW_MTU of 262144" do
    RNS::TCPInterfaceConstants::HW_MTU.should eq(262144)
  end
end

describe RNS::TCPClientInterface do
  after_each do
    RNS::Transport.reset
  end

  describe "constants" do
    it "has BITRATE_GUESS of 10 Mbps" do
      RNS::TCPClientInterface::BITRATE_GUESS.should eq(10_000_000_i64)
    end

    it "has DEFAULT_IFAC_SIZE of 16" do
      RNS::TCPClientInterface::DEFAULT_IFAC_SIZE.should eq(16)
    end

    it "has AUTOCONFIGURE_MTU enabled" do
      RNS::TCPClientInterface::AUTOCONFIGURE_MTU.should be_true
    end

    it "has correct reconnect constants" do
      RNS::TCPClientInterface::RECONNECT_WAIT.should eq(5)
      RNS::TCPClientInterface::RECONNECT_MAX_TRIES.should be_nil
    end

    it "has correct TCP keepalive constants" do
      RNS::TCPClientInterface::TCP_USER_TIMEOUT.should eq(24)
      RNS::TCPClientInterface::TCP_PROBE_AFTER.should eq(5)
      RNS::TCPClientInterface::TCP_PROBE_INTERVAL.should eq(2)
      RNS::TCPClientInterface::TCP_PROBES.should eq(12)
    end

    it "has correct I2P constants" do
      RNS::TCPClientInterface::I2P_USER_TIMEOUT.should eq(45)
      RNS::TCPClientInterface::I2P_PROBE_AFTER.should eq(10)
      RNS::TCPClientInterface::I2P_PROBE_INTERVAL.should eq(9)
      RNS::TCPClientInterface::I2P_PROBES.should eq(5)
    end

    it "has INITIAL_CONNECT_TIMEOUT of 5" do
      RNS::TCPClientInterface::INITIAL_CONNECT_TIMEOUT.should eq(5)
    end
  end

  describe "constructor from config (initiator)" do
    it "connects to a TCP server" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      config = {
        "name"        => "TestTCP",
        "target_host" => "127.0.0.1",
        "target_port" => port.to_s,
      }

      iface = RNS::TCPClientInterface.new(config)
      begin
        sleep 100.milliseconds
        iface.name.should eq("TestTCP")
        iface.online.should be_true
        iface.initiator?.should be_true
        iface.receives?.should be_true
        iface.bitrate.should eq(RNS::TCPClientInterface::BITRATE_GUESS)
      ensure
        iface.teardown
        server.close
      end
    end

    it "sets direction flags" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      config = {
        "name"        => "TestDir",
        "target_host" => "127.0.0.1",
        "target_port" => port.to_s,
      }

      iface = RNS::TCPClientInterface.new(config)
      begin
        iface.dir_in.should be_true
        iface.dir_out.should be_false
      ensure
        iface.teardown
        server.close
      end
    end

    it "sets KISS framing from config" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      config = {
        "name"         => "TestKISS",
        "target_host"  => "127.0.0.1",
        "target_port"  => port.to_s,
        "kiss_framing" => "true",
      }

      iface = RNS::TCPClientInterface.new(config)
      begin
        iface.kiss_framing.should be_true
      ensure
        iface.teardown
        server.close
      end
    end

    it "sets I2P tunneled from config" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      config = {
        "name"         => "TestI2P",
        "target_host"  => "127.0.0.1",
        "target_port"  => port.to_s,
        "i2p_tunneled" => "true",
      }

      iface = RNS::TCPClientInterface.new(config)
      begin
        iface.i2p_tunneled.should be_true
      ensure
        iface.teardown
        server.close
      end
    end

    it "uses custom connect_timeout from config" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      config = {
        "name"            => "TestTimeout",
        "target_host"     => "127.0.0.1",
        "target_port"     => port.to_s,
        "connect_timeout" => "10",
      }

      iface = RNS::TCPClientInterface.new(config)
      begin
        iface.online.should be_true
      ensure
        iface.teardown
        server.close
      end
    end

    it "handles max_reconnect_tries from config" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      config = {
        "name"                => "TestMaxRetries",
        "target_host"         => "127.0.0.1",
        "target_port"         => port.to_s,
        "max_reconnect_tries" => "3",
      }

      iface = RNS::TCPClientInterface.new(config)
      begin
        iface.online.should be_true
      ensure
        iface.teardown
        server.close
      end
    end
  end

  describe "constructor from connected socket" do
    it "creates interface from pre-connected socket" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      client_socket = TCPSocket.new("127.0.0.1", port)
      server_socket = server.accept

      iface = RNS::TCPClientInterface.new(
        connected_socket: server_socket,
        name: "SpawnedClient"
      )

      begin
        iface.name.should eq("SpawnedClient")
        iface.online.should be_true
        iface.initiator?.should be_false
        iface.receives?.should be_true
      ensure
        iface.teardown
        client_socket.close rescue nil
        server.close
      end
    end

    it "uses callback from pre-connected socket constructor" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      client_socket = TCPSocket.new("127.0.0.1", port)
      server_socket = server.accept

      received = [] of Bytes

      callback = Proc(Bytes, RNS::Interface, Nil).new do |data, _iface|
        received << data.dup
      end

      iface = RNS::TCPClientInterface.new(
        connected_socket: server_socket,
        name: "CallbackClient",
        inbound_callback: callback
      )

      begin
        sleep 50.milliseconds

        # Send HDLC-framed data through the client socket
        test_data = Random::Secure.random_bytes(30)
        framed = RNS::HDLC.frame(test_data)
        client_socket.write(framed)
        client_socket.flush

        wait_for { received.size > 0 }

        received.size.should eq(1)
        received[0].should eq(test_data)
      ensure
        iface.teardown
        client_socket.close rescue nil
        server.close
      end
    end
  end

  describe "process_outgoing with HDLC framing" do
    it "sends HDLC-framed data" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      client_socket = TCPSocket.new("127.0.0.1", port)
      server_socket = server.accept

      iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "HDLCSender"
      )

      begin
        test_data = Bytes[0x01, 0x02, 0x03, 0x04, 0x05]
        iface.process_outgoing(test_data)

        # Read the framed data from server side
        buf = Bytes.new(1024)
        server_socket.read_timeout = 2.seconds
        bytes_read = server_socket.read(buf)
        received = buf[0, bytes_read]

        # Should be HDLC framed: FLAG + escaped(data) + FLAG
        expected = RNS::HDLC.frame(test_data)
        received.should eq(expected)
      ensure
        iface.teardown
        server_socket.close rescue nil
        server.close
      end
    end

    it "tracks txb correctly" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      client_socket = TCPSocket.new("127.0.0.1", port)
      _server_socket = server.accept

      iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "TxBTracker"
      )

      begin
        data1 = Bytes.new(10, 0xAA_u8)
        data2 = Bytes.new(20, 0xBB_u8)

        iface.process_outgoing(data1)
        iface.process_outgoing(data2)

        # txb tracks framed data size (FLAG + escaped + FLAG)
        expected_txb = RNS::HDLC.frame(data1).size.to_i64 + RNS::HDLC.frame(data2).size.to_i64
        iface.txb.should eq(expected_txb)
      ensure
        iface.teardown
        server.close
      end
    end

    it "tracks parent interface txb" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      client_socket = TCPSocket.new("127.0.0.1", port)
      _server_socket = server.accept

      # Create a parent server interface
      parent_port = free_port
      parent_config = {
        "name"        => "ParentServer",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => parent_port.to_s,
      }
      parent = RNS::TCPServerInterface.new(parent_config)

      iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "ChildClient"
      )
      iface.parent_interface = parent

      begin
        data = Bytes.new(10, 0xAA_u8)
        iface.process_outgoing(data)

        parent.txb.should be > 0
      ensure
        iface.teardown
        parent.detach
        server.close
      end
    end
  end

  describe "process_outgoing with KISS framing" do
    it "sends KISS-framed data" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      client_socket = TCPSocket.new("127.0.0.1", port)
      server_socket = server.accept

      iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "KISSSender",
        kiss_framing: true
      )

      begin
        test_data = Bytes[0x01, 0x02, 0x03, 0x04, 0x05]
        iface.process_outgoing(test_data)

        buf = Bytes.new(1024)
        server_socket.read_timeout = 2.seconds
        bytes_read = server_socket.read(buf)
        received = buf[0, bytes_read]

        expected = RNS::KISS.frame(test_data)
        received.should eq(expected)
      ensure
        iface.teardown
        server_socket.close rescue nil
        server.close
      end
    end
  end

  describe "HDLC framing roundtrip" do
    it "sends and receives data correctly via HDLC framing" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      received_data = [] of Bytes

      # Create a server-side client interface
      client_socket = TCPSocket.new("127.0.0.1", port)
      server_socket = server.accept

      callback = Proc(Bytes, RNS::Interface, Nil).new do |data, _iface|
        received_data << data.dup
      end

      server_iface = RNS::TCPClientInterface.new(
        connected_socket: server_socket,
        name: "ServerSide",
        inbound_callback: callback
      )

      # Create a client-side interface
      client_iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "ClientSide"
      )

      begin
        sleep 50.milliseconds

        test_data = Random::Secure.random_bytes(50)
        client_iface.process_outgoing(test_data)

        wait_for { received_data.size > 0 }

        received_data.size.should eq(1)
        received_data[0].should eq(test_data)
        server_iface.rxb.should be > 0
      ensure
        client_iface.teardown
        server_iface.teardown
        server.close
      end
    end

    it "handles multiple frames in sequence" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      received_data = [] of Bytes

      client_socket = TCPSocket.new("127.0.0.1", port)
      server_socket = server.accept

      callback = Proc(Bytes, RNS::Interface, Nil).new do |data, _iface|
        received_data << data.dup
      end

      server_iface = RNS::TCPClientInterface.new(
        connected_socket: server_socket,
        name: "MultiServer",
        inbound_callback: callback
      )

      client_iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "MultiClient"
      )

      begin
        sleep 50.milliseconds

        messages = (0...5).map { |i| Random::Secure.random_bytes(20 + i * 10) }
        messages.each do |msg|
          client_iface.process_outgoing(msg)
          sleep 20.milliseconds
        end

        wait_for { received_data.size >= 5 }

        received_data.size.should eq(5)
        messages.each_with_index do |msg, i|
          received_data[i].should eq(msg)
        end
      ensure
        client_iface.teardown
        server_iface.teardown
        server.close
      end
    end

    it "handles data containing HDLC special bytes" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      received_data = [] of Bytes

      client_socket = TCPSocket.new("127.0.0.1", port)
      server_socket = server.accept

      callback = Proc(Bytes, RNS::Interface, Nil).new do |data, _iface|
        received_data << data.dup
      end

      server_iface = RNS::TCPClientInterface.new(
        connected_socket: server_socket,
        name: "EscServer",
        inbound_callback: callback
      )

      client_iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "EscClient"
      )

      begin
        sleep 50.milliseconds

        # Data containing HDLC FLAG and ESC bytes
        test_data = Bytes.new(30) { |i| (i * 7 % 256).to_u8 }
        test_data[5] = RNS::HDLC::FLAG
        test_data[10] = RNS::HDLC::ESC
        test_data[15] = RNS::HDLC::FLAG
        test_data[20] = RNS::HDLC::ESC

        client_iface.process_outgoing(test_data)

        wait_for { received_data.size > 0 }

        received_data.size.should eq(1)
        received_data[0].should eq(test_data)
      ensure
        client_iface.teardown
        server_iface.teardown
        server.close
      end
    end
  end

  describe "KISS framing roundtrip" do
    it "sends and receives data correctly via KISS framing" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      received_data = [] of Bytes

      client_socket = TCPSocket.new("127.0.0.1", port)
      server_socket = server.accept

      callback = Proc(Bytes, RNS::Interface, Nil).new do |data, _iface|
        received_data << data.dup
      end

      server_iface = RNS::TCPClientInterface.new(
        connected_socket: server_socket,
        name: "KISSServer",
        kiss_framing: true,
        inbound_callback: callback
      )

      client_iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "KISSClient",
        kiss_framing: true
      )

      begin
        sleep 50.milliseconds

        test_data = Random::Secure.random_bytes(50)
        client_iface.process_outgoing(test_data)

        wait_for { received_data.size > 0 }

        received_data.size.should eq(1)
        received_data[0].should eq(test_data)
      ensure
        client_iface.teardown
        server_iface.teardown
        server.close
      end
    end

    it "handles data containing KISS special bytes" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      received_data = [] of Bytes

      client_socket = TCPSocket.new("127.0.0.1", port)
      server_socket = server.accept

      callback = Proc(Bytes, RNS::Interface, Nil).new do |data, _iface|
        received_data << data.dup
      end

      server_iface = RNS::TCPClientInterface.new(
        connected_socket: server_socket,
        name: "KISSEscServer",
        kiss_framing: true,
        inbound_callback: callback
      )

      client_iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "KISSEscClient",
        kiss_framing: true
      )

      begin
        sleep 50.milliseconds

        # Data containing KISS FEND and FESC bytes
        test_data = Bytes.new(30) { |i| (i * 7 % 256).to_u8 }
        test_data[5] = RNS::KISS::FEND
        test_data[10] = RNS::KISS::FESC
        test_data[15] = RNS::KISS::FEND
        test_data[20] = RNS::KISS::FESC

        client_iface.process_outgoing(test_data)

        wait_for { received_data.size > 0 }

        received_data.size.should eq(1)
        received_data[0].should eq(test_data)
      ensure
        client_iface.teardown
        server_iface.teardown
        server.close
      end
    end
  end

  describe "bidirectional communication" do
    it "sends data in both directions" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      server_received = [] of Bytes
      client_received = [] of Bytes

      client_socket = TCPSocket.new("127.0.0.1", port)
      server_socket = server.accept

      server_cb = Proc(Bytes, RNS::Interface, Nil).new do |data, _iface|
        server_received << data.dup
      end

      client_cb = Proc(Bytes, RNS::Interface, Nil).new do |data, _iface|
        client_received << data.dup
      end

      server_iface = RNS::TCPClientInterface.new(
        connected_socket: server_socket,
        name: "BidiServer",
        inbound_callback: server_cb
      )

      client_iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "BidiClient",
        inbound_callback: client_cb
      )

      begin
        sleep 50.milliseconds

        msg_to_server = Random::Secure.random_bytes(40)
        msg_to_client = Random::Secure.random_bytes(40)

        client_iface.process_outgoing(msg_to_server)
        sleep 20.milliseconds
        server_iface.process_outgoing(msg_to_client)

        wait_for { server_received.size > 0 && client_received.size > 0 }

        server_received.size.should eq(1)
        server_received[0].should eq(msg_to_server)
        client_received.size.should eq(1)
        client_received[0].should eq(msg_to_client)
      ensure
        client_iface.teardown
        server_iface.teardown
        server.close
      end
    end
  end

  describe "reconnection" do
    it "reconnects after server restart" do
      port = free_port
      received_data = [] of Bytes

      server = TCPServer.new("127.0.0.1", port)

      callback = Proc(Bytes, RNS::Interface, Nil).new do |data, _iface|
        received_data << data.dup
      end

      config = {
        "name"        => "ReconnectTest",
        "target_host" => "127.0.0.1",
        "target_port" => port.to_s,
      }

      iface = RNS::TCPClientInterface.new(config, inbound_callback: callback)

      begin
        sleep 100.milliseconds
        iface.online.should be_true

        # Accept the first connection and close it
        first_client = server.accept
        first_client.close
        server.close

        # Wait for the interface to notice the disconnect
        wait_for(timeout: 3.seconds) { !iface.online }

        # Restart server on same port
        server = TCPServer.new("127.0.0.1", port)

        # Wait for reconnection (RECONNECT_WAIT = 5s, so give it time)
        wait_for(timeout: 8.seconds) { iface.online }

        iface.online.should be_true
      ensure
        iface.teardown
        server.close rescue nil
      end
    end

    it "stops after max_reconnect_tries" do
      port = free_port

      config = {
        "name"                => "MaxRetriesTest",
        "target_host"         => "127.0.0.1",
        "target_port"         => port.to_s,
        "max_reconnect_tries" => "1",
        "connect_timeout"     => "1",
      }

      iface = RNS::TCPClientInterface.new(config)
      begin
        # Should fail initial connect and start reconnecting
        iface.online.should be_false
        # Give time for reconnect attempts to exhaust
        sleep 8.seconds
        iface.online.should be_false
      ensure
        iface.teardown
      end
    end
  end

  describe "teardown" do
    it "closes socket and marks offline" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      client_socket = TCPSocket.new("127.0.0.1", port)
      _server_socket = server.accept

      iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "TeardownTest"
      )

      iface.online.should be_true
      iface.teardown
      iface.online.should be_false
      iface.dir_in.should be_false
      iface.dir_out.should be_false

      server.close
    end

    it "removes self from parent spawned_interfaces" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      client_socket = TCPSocket.new("127.0.0.1", port)
      _server_socket = server.accept

      parent_port = free_port
      parent_config = {
        "name"        => "Parent",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => parent_port.to_s,
      }
      parent = RNS::TCPServerInterface.new(parent_config)

      iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "Child"
      )
      iface.parent_interface = parent
      parent.spawned_interfaces.try(&.<<(iface))

      parent.spawned_interfaces.try(&.size).should eq(1)
      iface.teardown
      parent.spawned_interfaces.try(&.size).should eq(0)

      parent.detach
      server.close
    end
  end

  describe "detach" do
    it "marks interface as detached and offline" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      client_socket = TCPSocket.new("127.0.0.1", port)
      _server_socket = server.accept

      iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "DetachTest"
      )

      iface.online.should be_true
      iface.detach
      iface.online.should be_false
      iface.detached?.should be_true

      server.close
    end
  end

  describe "connection closed by remote" do
    it "non-initiator tears down when remote closes" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      client_socket = TCPSocket.new("127.0.0.1", port)
      server_socket = server.accept

      iface = RNS::TCPClientInterface.new(
        connected_socket: server_socket,
        name: "RemoteCloseTest"
      )

      begin
        sleep 50.milliseconds
        iface.online.should be_true

        # Close from client side
        client_socket.close

        wait_for { !iface.online }
        iface.online.should be_false
      ensure
        iface.teardown
        server.close
      end
    end
  end

  describe "process_outgoing when offline" do
    it "does nothing when offline" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      client_socket = TCPSocket.new("127.0.0.1", port)
      _server_socket = server.accept

      iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "OfflineTest"
      )
      iface.teardown # Take offline
      iface.process_outgoing(Bytes[0x01, 0x02, 0x03])
      iface.txb.should eq(0_i64)

      server.close
    end
  end

  describe "to_s" do
    it "returns formatted string with name, IP and port" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      config = {
        "name"        => "MyTCP",
        "target_host" => "127.0.0.1",
        "target_port" => port.to_s,
      }

      iface = RNS::TCPClientInterface.new(config)
      begin
        iface.to_s.should eq("TCPInterface[MyTCP/127.0.0.1:#{port}]")
      ensure
        iface.teardown
        server.close
      end
    end

    it "wraps IPv6 addresses in brackets" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      client_socket = TCPSocket.new("127.0.0.1", port)
      _server_socket = server.accept

      iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "IPv6Test"
      )
      iface.target_ip = "::1"
      iface.target_port = 4242

      begin
        iface.to_s.should eq("TCPInterface[IPv6Test/[::1]:4242]")
      ensure
        iface.teardown
        server.close
      end
    end
  end

  describe "Interface base class" do
    it "inherits from Interface" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      client_socket = TCPSocket.new("127.0.0.1", port)
      _server_socket = server.accept

      iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "InheritTest"
      )

      begin
        iface.is_a?(RNS::Interface).should be_true
      ensure
        iface.teardown
        server.close
      end
    end

    it "has correct HW_MTU" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      client_socket = TCPSocket.new("127.0.0.1", port)
      _server_socket = server.accept

      iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "MTUTest"
      )

      begin
        iface.hw_mtu.should eq(RNS::TCPInterfaceConstants::HW_MTU)
      ensure
        iface.teardown
        server.close
      end
    end

    it "can compute interface hash" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      client_socket = TCPSocket.new("127.0.0.1", port)
      _server_socket = server.accept

      iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "HashTest"
      )

      begin
        hash = iface.get_hash
        hash.should be_a(Bytes)
        hash.size.should eq(32)
      ensure
        iface.teardown
        server.close
      end
    end

    it "starts with zero counters" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      client_socket = TCPSocket.new("127.0.0.1", port)
      _server_socket = server.accept

      iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "CounterTest"
      )

      begin
        iface.rxb.should eq(0_i64)
        iface.txb.should eq(0_i64)
      ensure
        iface.teardown
        server.close
      end
    end
  end

  describe "stress tests" do
    it "handles 30 rapid HDLC sends and receives" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      received_data = [] of Bytes

      client_socket = TCPSocket.new("127.0.0.1", port)
      server_socket = server.accept

      callback = Proc(Bytes, RNS::Interface, Nil).new do |data, _iface|
        received_data << data.dup
      end

      server_iface = RNS::TCPClientInterface.new(
        connected_socket: server_socket,
        name: "StressServer",
        inbound_callback: callback
      )

      client_iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "StressClient"
      )

      begin
        sleep 50.milliseconds

        messages = (0...30).map { Random::Secure.random_bytes(rand(20..100)) }
        messages.each do |msg|
          client_iface.process_outgoing(msg)
          sleep 5.milliseconds
        end

        wait_for(timeout: 5.seconds) { received_data.size >= 30 }

        received_data.size.should eq(30)
        messages.each_with_index do |msg, i|
          received_data[i].should eq(msg)
        end
      ensure
        client_iface.teardown
        server_iface.teardown
        server.close
      end
    end

    it "handles 20 rapid KISS sends and receives" do
      port = free_port
      server = TCPServer.new("127.0.0.1", port)

      received_data = [] of Bytes

      client_socket = TCPSocket.new("127.0.0.1", port)
      server_socket = server.accept

      callback = Proc(Bytes, RNS::Interface, Nil).new do |data, _iface|
        received_data << data.dup
      end

      server_iface = RNS::TCPClientInterface.new(
        connected_socket: server_socket,
        name: "KISSStressServer",
        kiss_framing: true,
        inbound_callback: callback
      )

      client_iface = RNS::TCPClientInterface.new(
        connected_socket: client_socket,
        name: "KISSStressClient",
        kiss_framing: true
      )

      begin
        sleep 50.milliseconds

        messages = (0...20).map { Random::Secure.random_bytes(rand(20..80)) }
        messages.each do |msg|
          client_iface.process_outgoing(msg)
          sleep 5.milliseconds
        end

        wait_for(timeout: 5.seconds) { received_data.size >= 20 }

        received_data.size.should eq(20)
        messages.each_with_index do |msg, i|
          received_data[i].should eq(msg)
        end
      ensure
        client_iface.teardown
        server_iface.teardown
        server.close
      end
    end
  end
end

describe RNS::TCPServerInterface do
  after_each do
    RNS::Transport.reset
  end

  describe "constants" do
    it "has BITRATE_GUESS of 10 Mbps" do
      RNS::TCPServerInterface::BITRATE_GUESS.should eq(10_000_000_i64)
    end

    it "has DEFAULT_IFAC_SIZE of 16" do
      RNS::TCPServerInterface::DEFAULT_IFAC_SIZE.should eq(16)
    end

    it "has AUTOCONFIGURE_MTU enabled" do
      RNS::TCPServerInterface::AUTOCONFIGURE_MTU.should be_true
    end
  end

  describe "constructor" do
    it "creates server listening on bind_ip and bind_port" do
      port = free_port
      config = {
        "name"        => "TestServer",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::TCPServerInterface.new(config)
      begin
        iface.name.should eq("TestServer")
        iface.online.should be_true
        iface.bind_ip.should eq("127.0.0.1")
        iface.bind_port.should eq(port)
        iface.bitrate.should eq(RNS::TCPServerInterface::BITRATE_GUESS)
      ensure
        iface.detach
      end
    end

    it "uses 'port' as default for listen_port" do
      port = free_port
      config = {
        "name"      => "PortDefault",
        "listen_ip" => "127.0.0.1",
        "port"      => port.to_s,
      }

      iface = RNS::TCPServerInterface.new(config)
      begin
        iface.bind_port.should eq(port)
        iface.online.should be_true
      ensure
        iface.detach
      end
    end

    it "raises when no port configured" do
      config = {
        "name"      => "NoPort",
        "listen_ip" => "127.0.0.1",
      }

      expect_raises(ArgumentError, /No TCP port configured/) do
        RNS::TCPServerInterface.new(config)
      end
    end

    it "raises when no bind IP configured" do
      port = free_port
      config = {
        "name"        => "NoIP",
        "listen_port" => port.to_s,
      }

      expect_raises(ArgumentError, /No TCP bind IP configured/) do
        RNS::TCPServerInterface.new(config)
      end
    end

    it "sets direction flags" do
      port = free_port
      config = {
        "name"        => "DirFlags",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::TCPServerInterface.new(config)
      begin
        iface.dir_in.should be_true
        iface.dir_out.should be_false
      ensure
        iface.detach
      end
    end

    it "sets HW_MTU correctly" do
      port = free_port
      config = {
        "name"        => "MTUCheck",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::TCPServerInterface.new(config)
      begin
        iface.hw_mtu.should eq(RNS::TCPInterfaceConstants::HW_MTU)
      ensure
        iface.detach
      end
    end

    it "initializes with empty spawned_interfaces" do
      port = free_port
      config = {
        "name"        => "SpawnCheck",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::TCPServerInterface.new(config)
      begin
        iface.clients.should eq(0)
      ensure
        iface.detach
      end
    end
  end

  describe "incoming connections" do
    it "accepts a client connection and spawns interface" do
      port = free_port
      config = {
        "name"        => "AcceptTest",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::TCPServerInterface.new(config)
      begin
        sleep 50.milliseconds

        client = TCPSocket.new("127.0.0.1", port)

        wait_for { iface.clients > 0 }
        iface.clients.should eq(1)

        client.close
      ensure
        iface.detach
      end
    end

    it "accepts multiple client connections" do
      port = free_port
      config = {
        "name"        => "MultiAccept",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::TCPServerInterface.new(config)
      clients = [] of TCPSocket

      begin
        sleep 50.milliseconds

        3.times do
          clients << TCPSocket.new("127.0.0.1", port)
          sleep 50.milliseconds
        end

        wait_for { iface.clients >= 3 }
        iface.clients.should eq(3)
      ensure
        clients.each { |client| client.close rescue nil }
        iface.detach
      end
    end

    it "receives data from a client via spawned interface" do
      port = free_port
      received_data = [] of Bytes

      callback = Proc(Bytes, RNS::Interface, Nil).new do |data, _iface|
        received_data << data.dup
      end

      config = {
        "name"        => "DataRecvTest",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::TCPServerInterface.new(config, inbound_callback: callback)

      begin
        sleep 50.milliseconds

        client = TCPSocket.new("127.0.0.1", port)
        sleep 100.milliseconds

        # Send HDLC-framed data
        test_data = Random::Secure.random_bytes(30)
        framed = RNS::HDLC.frame(test_data)
        client.write(framed)
        client.flush

        wait_for { received_data.size > 0 }

        received_data.size.should eq(1)
        received_data[0].should eq(test_data)

        client.close
      ensure
        iface.detach
      end
    end

    it "tracks parent rxb from spawned interfaces" do
      port = free_port

      callback = Proc(Bytes, RNS::Interface, Nil).new do |_data, _iface|
      end

      config = {
        "name"        => "RxBTrack",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::TCPServerInterface.new(config, inbound_callback: callback)

      begin
        sleep 50.milliseconds

        client = TCPSocket.new("127.0.0.1", port)
        sleep 100.milliseconds

        test_data = Random::Secure.random_bytes(30)
        framed = RNS::HDLC.frame(test_data)
        client.write(framed)
        client.flush

        wait_for { iface.rxb > 0 }

        iface.rxb.should be > 0

        client.close
      ensure
        iface.detach
      end
    end
  end

  describe "received_announce and sent_announce" do
    it "only records when from_spawned is true" do
      port = free_port
      config = {
        "name"        => "AnnounceTest",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::TCPServerInterface.new(config)
      begin
        iface.received_announce(from_spawned: false)
        iface.ia_freq_deque.size.should eq(0)

        iface.received_announce(from_spawned: true)
        iface.ia_freq_deque.size.should eq(1)

        iface.sent_announce(from_spawned: false)
        iface.oa_freq_deque.size.should eq(0)

        iface.sent_announce(from_spawned: true)
        iface.oa_freq_deque.size.should eq(1)
      ensure
        iface.detach
      end
    end
  end

  describe "process_outgoing" do
    it "is a no-op" do
      port = free_port
      config = {
        "name"        => "NoOpTest",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::TCPServerInterface.new(config)
      begin
        iface.process_outgoing(Bytes[0x01, 0x02, 0x03])
        iface.txb.should eq(0_i64)
      ensure
        iface.detach
      end
    end
  end

  describe "detach" do
    it "closes server and marks offline" do
      port = free_port
      config = {
        "name"        => "DetachTest",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::TCPServerInterface.new(config)
      iface.online.should be_true
      iface.detach
      iface.online.should be_false
      iface.detached?.should be_true

      # Port should be free after detach
      sleep 50.milliseconds
      server = TCPServer.new("127.0.0.1", port)
      server.close
    end

    it "is idempotent" do
      port = free_port
      config = {
        "name"        => "IdempotentDetach",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::TCPServerInterface.new(config)
      iface.detach
      iface.detach # Should not raise
      iface.online.should be_false
    end
  end

  describe "to_s" do
    it "returns formatted string with name, IP and port" do
      port = free_port
      config = {
        "name"        => "MyServer",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::TCPServerInterface.new(config)
      begin
        iface.to_s.should eq("TCPServerInterface[MyServer/127.0.0.1:#{port}]")
      ensure
        iface.detach
      end
    end
  end

  describe "Interface base class" do
    it "inherits from Interface" do
      port = free_port
      config = {
        "name"        => "InheritTest",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::TCPServerInterface.new(config)
      begin
        iface.is_a?(RNS::Interface).should be_true
      ensure
        iface.detach
      end
    end
  end

  describe "stress tests" do
    it "handles 10 rapid client connections" do
      port = free_port
      config = {
        "name"        => "StressServer",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::TCPServerInterface.new(config)
      clients = [] of TCPSocket

      begin
        sleep 50.milliseconds

        10.times do
          clients << TCPSocket.new("127.0.0.1", port)
          sleep 20.milliseconds
        end

        wait_for(timeout: 5.seconds) { iface.clients >= 10 }
        iface.clients.should eq(10)
      ensure
        clients.each { |client| client.close rescue nil }
        iface.detach
      end
    end

    it "handles 20 rapid messages from multiple clients" do
      port = free_port
      received_data = [] of Bytes

      callback = Proc(Bytes, RNS::Interface, Nil).new do |data, _iface|
        received_data << data.dup
      end

      config = {
        "name"        => "MultiMsgServer",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::TCPServerInterface.new(config, inbound_callback: callback)

      clients = [] of TCPSocket

      begin
        sleep 50.milliseconds

        # Create 3 clients
        3.times do
          clients << TCPSocket.new("127.0.0.1", port)
        end
        sleep 200.milliseconds

        # Each client sends multiple messages
        clients.each_with_index do |client, client_idx|
          7.times do |msg_idx|
            data = Bytes.new(20) { |i| ((client_idx * 7 + msg_idx * 3 + i) % 256).to_u8 }
            framed = RNS::HDLC.frame(data)
            client.write(framed)
            client.flush
            sleep 5.milliseconds
          end
        end

        # 3 clients × 7 messages = 21 messages
        wait_for(timeout: 5.seconds) { received_data.size >= 21 }
        received_data.size.should be >= 20
      ensure
        clients.each { |client| client.close rescue nil }
        iface.detach
      end
    end
  end
end
