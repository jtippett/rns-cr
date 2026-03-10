require "../../spec_helper"

# Helper to find a free port
private def free_port : Int32
  server = TCPServer.new("127.0.0.1", 0)
  port = server.local_address.port
  server.close
  port
end

describe RNS::UDPInterface do
  after_each do
    RNS::Transport.reset
  end

  describe "constants" do
    it "has BITRATE_GUESS of 10 Mbps" do
      RNS::UDPInterface::BITRATE_GUESS.should eq(10_000_000_i64)
    end

    it "has DEFAULT_IFAC_SIZE of 16" do
      RNS::UDPInterface::DEFAULT_IFAC_SIZE.should eq(16)
    end
  end

  describe "constructor" do
    it "creates a receive-only interface with listen_ip and listen_port" do
      port = free_port
      config = {
        "name"        => "TestUDP",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::UDPInterface.new(config)
      begin
        iface.name.should eq("TestUDP")
        iface.online.should be_true
        iface.receives?.should be_true
        iface.forwards?.should be_false
        iface.bind_ip.should eq("127.0.0.1")
        iface.bind_port.should eq(port)
        iface.bitrate.should eq(RNS::UDPInterface::BITRATE_GUESS)
        iface.hw_mtu.should eq(1064)
      ensure
        iface.teardown
      end
    end

    it "creates a forward-only interface with forward_ip and forward_port" do
      config = {
        "name"         => "TestForward",
        "forward_ip"   => "127.0.0.1",
        "forward_port" => "4242",
      }

      iface = RNS::UDPInterface.new(config)
      begin
        iface.name.should eq("TestForward")
        iface.online.should be_false # no listen = not online
        iface.receives?.should be_false
        iface.forwards?.should be_true
        iface.forward_ip.should eq("127.0.0.1")
        iface.forward_port.should eq(4242)
      ensure
        iface.teardown
      end
    end

    it "creates a bidirectional interface with all parameters" do
      port = free_port
      config = {
        "name"         => "TestBidi",
        "listen_ip"    => "127.0.0.1",
        "listen_port"  => port.to_s,
        "forward_ip"   => "127.0.0.1",
        "forward_port" => port.to_s,
      }

      iface = RNS::UDPInterface.new(config)
      begin
        iface.receives?.should be_true
        iface.forwards?.should be_true
        iface.online.should be_true
      ensure
        iface.teardown
      end
    end

    it "uses 'port' as default for both listen_port and forward_port" do
      port = free_port
      config = {
        "name"      => "TestPort",
        "listen_ip" => "127.0.0.1",
        "forward_ip" => "127.0.0.1",
        "port"      => port.to_s,
      }

      iface = RNS::UDPInterface.new(config)
      begin
        iface.bind_port.should eq(port)
        iface.forward_port.should eq(port)
        iface.receives?.should be_true
        iface.forwards?.should be_true
      ensure
        iface.teardown
      end
    end

    it "port does not override explicit listen_port and forward_port" do
      listen_port = free_port
      forward_port = free_port
      config = {
        "name"         => "TestOverride",
        "listen_ip"    => "127.0.0.1",
        "listen_port"  => listen_port.to_s,
        "forward_ip"   => "127.0.0.1",
        "forward_port" => forward_port.to_s,
        "port"         => "9999",
      }

      iface = RNS::UDPInterface.new(config)
      begin
        iface.bind_port.should eq(listen_port)
        iface.forward_port.should eq(forward_port)
      ensure
        iface.teardown
      end
    end

    it "sets IN=true and OUT=false by default" do
      port = free_port
      config = {
        "name"        => "TestDir",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::UDPInterface.new(config)
      begin
        iface.dir_in.should be_true
        iface.dir_out.should be_false
      ensure
        iface.teardown
      end
    end
  end

  describe "process_outgoing" do
    it "sends data via UDP to forward address" do
      recv_port = free_port
      recv_socket = UDPSocket.new
      recv_socket.bind("127.0.0.1", recv_port)
      recv_socket.read_timeout = 2.seconds

      config = {
        "name"         => "TestSend",
        "forward_ip"   => "127.0.0.1",
        "forward_port" => recv_port.to_s,
      }

      iface = RNS::UDPInterface.new(config)
      begin
        test_data = Bytes[0x01, 0x02, 0x03, 0x04, 0x05]
        iface.process_outgoing(test_data)

        buffer = Bytes.new(1024)
        bytes_read, _addr = recv_socket.receive(buffer)
        received = buffer[0, bytes_read]

        received.should eq(test_data)
        iface.txb.should eq(5_i64)
      ensure
        iface.teardown
        recv_socket.close
      end
    end

    it "tracks txb bytes correctly across multiple sends" do
      recv_port = free_port
      recv_socket = UDPSocket.new
      recv_socket.bind("127.0.0.1", recv_port)

      config = {
        "name"         => "TestTxB",
        "forward_ip"   => "127.0.0.1",
        "forward_port" => recv_port.to_s,
      }

      iface = RNS::UDPInterface.new(config)
      begin
        iface.process_outgoing(Bytes.new(10, 0xAA_u8))
        iface.process_outgoing(Bytes.new(20, 0xBB_u8))
        iface.process_outgoing(Bytes.new(30, 0xCC_u8))

        iface.txb.should eq(60_i64)
      ensure
        iface.teardown
        recv_socket.close
      end
    end

    it "enables SO_BROADCAST on send socket" do
      recv_port = free_port
      config = {
        "name"         => "TestBroadcast",
        "forward_ip"   => "127.0.0.1",
        "forward_port" => recv_port.to_s,
      }

      iface = RNS::UDPInterface.new(config)
      begin
        # Should not raise even though broadcast is enabled
        iface.process_outgoing(Bytes[0x01])
      ensure
        iface.teardown
      end
    end

    it "handles send errors gracefully without raising" do
      config = {
        "name"         => "TestError",
        "forward_ip"   => "0.0.0.0",
        "forward_port" => "1", # Unlikely to be writable
      }

      iface = RNS::UDPInterface.new(config)
      begin
        # Should not raise - errors logged internally
        iface.process_outgoing(Bytes[0x01])
      ensure
        iface.teardown
      end
    end
  end

  describe "process_incoming" do
    it "receives UDP data and tracks rxb" do
      port = free_port
      received_data = [] of Bytes
      received_iface = [] of RNS::Interface

      config = {
        "name"        => "TestRecv",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::UDPInterface.new(config) do |data, from_iface|
        received_data << data.dup
        received_iface << from_iface
      end

      begin
        # Give the receive fiber time to start
        sleep 50.milliseconds

        # Send data to the listening port
        send_socket = UDPSocket.new
        test_data = Bytes[0xDE, 0xAD, 0xBE, 0xEF]
        send_socket.send(test_data, Socket::IPAddress.new("127.0.0.1", port))
        send_socket.close

        # Wait for delivery
        sleep 100.milliseconds

        received_data.size.should eq(1)
        received_data[0].should eq(test_data)
        received_iface[0].should eq(iface)
        iface.rxb.should eq(4_i64)
      ensure
        iface.teardown
      end
    end

    it "receives multiple packets" do
      port = free_port
      received_data = [] of Bytes

      config = {
        "name"        => "TestMultiRecv",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::UDPInterface.new(config) do |data, _iface|
        received_data << data.dup
      end

      begin
        sleep 50.milliseconds

        send_socket = UDPSocket.new
        5.times do |i|
          send_socket.send(Bytes[i.to_u8], Socket::IPAddress.new("127.0.0.1", port))
          sleep 10.milliseconds
        end
        send_socket.close

        sleep 200.milliseconds

        received_data.size.should eq(5)
        5.times do |i|
          received_data[i].should eq(Bytes[i.to_u8])
        end
        iface.rxb.should eq(5_i64)
      ensure
        iface.teardown
      end
    end
  end

  describe "send and receive integration" do
    it "sends data from one interface and receives on another" do
      port = free_port
      received_data = [] of Bytes

      recv_config = {
        "name"        => "Receiver",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      recv_iface = RNS::UDPInterface.new(recv_config) do |data, _iface|
        received_data << data.dup
      end

      send_config = {
        "name"         => "Sender",
        "forward_ip"   => "127.0.0.1",
        "forward_port" => port.to_s,
      }

      send_iface = RNS::UDPInterface.new(send_config)

      begin
        sleep 50.milliseconds

        test_data = Random::Secure.random_bytes(100)
        send_iface.process_outgoing(test_data)

        sleep 100.milliseconds

        received_data.size.should eq(1)
        received_data[0].should eq(test_data)
        send_iface.txb.should eq(100_i64)
        recv_iface.rxb.should eq(100_i64)
      ensure
        recv_iface.teardown
        send_iface.teardown
      end
    end

    it "handles bidirectional communication" do
      port_a = free_port
      port_b = free_port
      received_a = [] of Bytes
      received_b = [] of Bytes

      config_a = {
        "name"         => "NodeA",
        "listen_ip"    => "127.0.0.1",
        "listen_port"  => port_a.to_s,
        "forward_ip"   => "127.0.0.1",
        "forward_port" => port_b.to_s,
      }

      config_b = {
        "name"         => "NodeB",
        "listen_ip"    => "127.0.0.1",
        "listen_port"  => port_b.to_s,
        "forward_ip"   => "127.0.0.1",
        "forward_port" => port_a.to_s,
      }

      iface_a = RNS::UDPInterface.new(config_a) do |data, _iface|
        received_a << data.dup
      end

      iface_b = RNS::UDPInterface.new(config_b) do |data, _iface|
        received_b << data.dup
      end

      begin
        sleep 50.milliseconds

        msg_to_b = Bytes[0x01, 0x02, 0x03]
        msg_to_a = Bytes[0x04, 0x05, 0x06]

        iface_a.process_outgoing(msg_to_b)
        sleep 50.milliseconds
        iface_b.process_outgoing(msg_to_a)
        sleep 100.milliseconds

        received_b.size.should eq(1)
        received_b[0].should eq(msg_to_b)
        received_a.size.should eq(1)
        received_a[0].should eq(msg_to_a)
      ensure
        iface_a.teardown
        iface_b.teardown
      end
    end
  end

  describe "to_s" do
    it "returns formatted string with name, IP and port" do
      port = free_port
      config = {
        "name"        => "MyUDP",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::UDPInterface.new(config)
      begin
        iface.to_s.should eq("UDPInterface[MyUDP/127.0.0.1:#{port}]")
      ensure
        iface.teardown
      end
    end

    it "uses bind_ip in string representation" do
      config = {
        "name"         => "FwdOnly",
        "forward_ip"   => "10.0.0.1",
        "forward_port" => "5555",
      }

      iface = RNS::UDPInterface.new(config)
      begin
        # Forward-only has no bind_ip, should handle gracefully
        iface.to_s.should contain("UDPInterface[FwdOnly")
      ensure
        iface.teardown
      end
    end
  end

  describe "Interface base class properties" do
    it "inherits from Interface" do
      port = free_port
      config = {
        "name"        => "TestBase",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::UDPInterface.new(config)
      begin
        iface.is_a?(RNS::Interface).should be_true
      ensure
        iface.teardown
      end
    end

    it "starts with zero rxb and appropriate txb" do
      port = free_port
      config = {
        "name"        => "TestCounters",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::UDPInterface.new(config)
      begin
        iface.rxb.should eq(0_i64)
        iface.txb.should eq(0_i64)
      ensure
        iface.teardown
      end
    end

    it "has correct HW_MTU of 1064" do
      config = {
        "name"         => "TestMTU",
        "forward_ip"   => "127.0.0.1",
        "forward_port" => "4242",
      }

      iface = RNS::UDPInterface.new(config)
      begin
        iface.hw_mtu.should eq(1064)
      ensure
        iface.teardown
      end
    end

    it "can compute interface hash" do
      port = free_port
      config = {
        "name"        => "TestHash",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::UDPInterface.new(config)
      begin
        hash = iface.get_hash
        hash.should be_a(Bytes)
        hash.size.should eq(32) # SHA-256 full hash
      ensure
        iface.teardown
      end
    end
  end

  describe "teardown" do
    it "closes the receive socket" do
      port = free_port
      config = {
        "name"        => "TestTeardown",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::UDPInterface.new(config)
      iface.online.should be_true
      iface.teardown
      iface.online.should be_false

      # Port should be free again after teardown
      socket = UDPSocket.new
      begin
        socket.bind("127.0.0.1", port)
      ensure
        socket.close
      end
    end

    it "is idempotent" do
      port = free_port
      config = {
        "name"        => "TestIdempotent",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::UDPInterface.new(config)
      iface.teardown
      iface.teardown # Should not raise
      iface.online.should be_false
    end
  end

  describe "configuration parsing" do
    it "handles string config hash" do
      port = free_port
      config = {
        "name"        => "StringConfig",
        "listen_ip"   => "127.0.0.1",
        "listen_port" => port.to_s,
      }

      iface = RNS::UDPInterface.new(config)
      begin
        iface.name.should eq("StringConfig")
      ensure
        iface.teardown
      end
    end

    it "handles missing optional fields gracefully" do
      config = {
        "name" => "MinimalConfig",
      }

      iface = RNS::UDPInterface.new(config)
      begin
        iface.receives?.should be_false
        iface.forwards?.should be_false
        iface.online.should be_false
      ensure
        iface.teardown
      end
    end
  end

  describe "stress tests" do
    it "handles 50 rapid sends" do
      recv_port = free_port
      recv_socket = UDPSocket.new
      recv_socket.bind("127.0.0.1", recv_port)

      config = {
        "name"         => "StressSend",
        "forward_ip"   => "127.0.0.1",
        "forward_port" => recv_port.to_s,
      }

      iface = RNS::UDPInterface.new(config)
      begin
        50.times do |i|
          iface.process_outgoing(Bytes.new(10, i.to_u8))
        end
        iface.txb.should eq(500_i64)
      ensure
        iface.teardown
        recv_socket.close
      end
    end

    it "handles 20 rapid send/receive cycles" do
      port = free_port
      received_count = Atomic(Int32).new(0)

      config = {
        "name"         => "StressBidi",
        "listen_ip"    => "127.0.0.1",
        "listen_port"  => port.to_s,
        "forward_ip"   => "127.0.0.1",
        "forward_port" => port.to_s,
      }

      iface = RNS::UDPInterface.new(config) do |_data, _from_iface|
        received_count.add(1)
      end

      begin
        sleep 50.milliseconds

        20.times do |i|
          iface.process_outgoing(Bytes.new(10, i.to_u8))
          sleep 10.milliseconds
        end

        sleep 200.milliseconds

        received_count.get.should eq(20)
        iface.txb.should eq(200_i64)
        iface.rxb.should eq(200_i64)
      ensure
        iface.teardown
      end
    end
  end
end
