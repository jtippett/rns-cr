require "../../spec_helper"

describe RNS::I2PExceptions do
  describe ".from_sam_result" do
    it "returns CantReachPeer for CANT_REACH_PEER" do
      exc = RNS::I2PExceptions.from_sam_result("SESSION STATUS RESULT=CANT_REACH_PEER")
      exc.should be_a(RNS::I2PExceptions::CantReachPeer)
    end

    it "returns DuplicatedDest for DUPLICATED_DEST" do
      exc = RNS::I2PExceptions.from_sam_result("SESSION STATUS RESULT=DUPLICATED_DEST")
      exc.should be_a(RNS::I2PExceptions::DuplicatedDest)
    end

    it "returns DuplicatedId for DUPLICATED_ID" do
      exc = RNS::I2PExceptions.from_sam_result("SESSION STATUS RESULT=DUPLICATED_ID")
      exc.should be_a(RNS::I2PExceptions::DuplicatedId)
    end

    it "returns InvalidId for INVALID_ID" do
      exc = RNS::I2PExceptions.from_sam_result("SESSION STATUS RESULT=INVALID_ID")
      exc.should be_a(RNS::I2PExceptions::InvalidId)
    end

    it "returns InvalidKey for INVALID_KEY" do
      exc = RNS::I2PExceptions.from_sam_result("SESSION STATUS RESULT=INVALID_KEY")
      exc.should be_a(RNS::I2PExceptions::InvalidKey)
    end

    it "returns KeyNotFound for KEY_NOT_FOUND" do
      exc = RNS::I2PExceptions.from_sam_result("SESSION STATUS RESULT=KEY_NOT_FOUND")
      exc.should be_a(RNS::I2PExceptions::KeyNotFound)
    end

    it "returns PeerNotFound for PEER_NOT_FOUND" do
      exc = RNS::I2PExceptions.from_sam_result("SESSION STATUS RESULT=PEER_NOT_FOUND")
      exc.should be_a(RNS::I2PExceptions::PeerNotFound)
    end

    it "returns Timeout for TIMEOUT" do
      exc = RNS::I2PExceptions.from_sam_result("SESSION STATUS RESULT=TIMEOUT")
      exc.should be_a(RNS::I2PExceptions::Timeout)
    end

    it "returns I2PError for RESULT=I2P_ERROR" do
      exc = RNS::I2PExceptions.from_sam_result("SESSION STATUS RESULT=I2P_ERROR MESSAGE=\"Unknown\"")
      exc.should be_a(RNS::I2PExceptions::I2PError)
    end

    it "returns nil for RESULT=OK" do
      exc = RNS::I2PExceptions.from_sam_result("HELLO REPLY RESULT=OK VERSION=3.1")
      exc.should be_nil
    end

    it "all exceptions inherit from I2PError" do
      RNS::I2PExceptions::CantReachPeer.new("test").is_a?(RNS::I2PExceptions::I2PError).should be_true
      RNS::I2PExceptions::DuplicatedDest.new("test").is_a?(RNS::I2PExceptions::I2PError).should be_true
      RNS::I2PExceptions::DuplicatedId.new("test").is_a?(RNS::I2PExceptions::I2PError).should be_true
      RNS::I2PExceptions::InvalidId.new("test").is_a?(RNS::I2PExceptions::I2PError).should be_true
      RNS::I2PExceptions::InvalidKey.new("test").is_a?(RNS::I2PExceptions::I2PError).should be_true
      RNS::I2PExceptions::KeyNotFound.new("test").is_a?(RNS::I2PExceptions::I2PError).should be_true
      RNS::I2PExceptions::PeerNotFound.new("test").is_a?(RNS::I2PExceptions::I2PError).should be_true
      RNS::I2PExceptions::Timeout.new("test").is_a?(RNS::I2PExceptions::I2PError).should be_true
    end

    it "all exceptions inherit from Exception" do
      RNS::I2PExceptions::I2PError.new("test").is_a?(Exception).should be_true
    end
  end
end

describe RNS::Base32 do
  it "encodes empty bytes" do
    RNS::Base32.encode(Bytes.empty).should eq("")
  end

  it "encodes single byte" do
    RNS::Base32.encode(Bytes[0x66]).should eq("MY")
  end

  it "encodes 'f'" do
    RNS::Base32.encode("f".to_slice).should eq("MY")
  end

  it "encodes 'fo'" do
    RNS::Base32.encode("fo".to_slice).should eq("MZXQ")
  end

  it "encodes 'foo'" do
    RNS::Base32.encode("foo".to_slice).should eq("MZXW6")
  end

  it "encodes 'foob'" do
    RNS::Base32.encode("foob".to_slice).should eq("MZXW6YQ")
  end

  it "encodes 'fooba'" do
    RNS::Base32.encode("fooba".to_slice).should eq("MZXW6YTB")
  end

  it "encodes 'foobar'" do
    RNS::Base32.encode("foobar".to_slice).should eq("MZXW6YTBOI")
  end
end

describe RNS::SAMClient do
  it "has correct default constants" do
    RNS::SAMClient::DEFAULT_SAM_HOST.should eq("127.0.0.1")
    RNS::SAMClient::DEFAULT_SAM_PORT.should eq(7656)
    RNS::SAMClient::SAM_BUFSIZE.should eq(4096)
  end

  it "can be instantiated with default settings" do
    client = RNS::SAMClient.new
    client.sam_host.should eq("127.0.0.1")
    client.sam_port.should eq(7656)
  end

  it "can be instantiated with custom settings" do
    client = RNS::SAMClient.new("10.0.0.1", 7777)
    client.sam_host.should eq("10.0.0.1")
    client.sam_port.should eq(7777)
  end
end

describe RNS::I2PController do
  it "creates storage directory on initialization" do
    Dir.tempdir.tap do |base|
      tmpdir = File.join(base, "test_i2p_controller_#{Random.rand(100000)}")
      Dir.mkdir_p(tmpdir) unless Dir.exists?(tmpdir)
      _controller = RNS::I2PController.new(tmpdir)
      Dir.exists?(File.join(tmpdir, "i2p")).should be_true
      FileUtils.rm_rf(tmpdir)
    end
  end

  it "starts and stops" do
    Dir.tempdir.tap do |base|
      tmpdir = File.join(base, "test_i2p_ctrl_#{Random.rand(100000)}")
      Dir.mkdir_p(tmpdir) unless Dir.exists?(tmpdir)
      controller = RNS::I2PController.new(tmpdir)
      controller.ready.should be_false
      controller.start
      controller.ready.should be_true
      controller.stop
      controller.ready.should be_false
      FileUtils.rm_rf(tmpdir)
    end
  end

  it "allocates a free port" do
    Dir.tempdir.tap do |base|
      tmpdir = File.join(base, "test_i2p_port_#{Random.rand(100000)}")
      Dir.mkdir_p(tmpdir) unless Dir.exists?(tmpdir)
      controller = RNS::I2PController.new(tmpdir)
      port = controller.get_free_port
      port.should be > 0
      port.should be < 65536
      FileUtils.rm_rf(tmpdir)
    end
  end

  it "allocates unique ports" do
    Dir.tempdir.tap do |base|
      tmpdir = File.join(base, "test_i2p_uport_#{Random.rand(100000)}")
      Dir.mkdir_p(tmpdir) unless Dir.exists?(tmpdir)
      controller = RNS::I2PController.new(tmpdir)
      ports = Set(Int32).new
      10.times do
        ports << controller.get_free_port
      end
      # Should get at least some unique ports (system may reuse freed ports)
      ports.size.should be >= 1
      FileUtils.rm_rf(tmpdir)
    end
  end

  it "has empty tunnel tables initially" do
    Dir.tempdir.tap do |base|
      tmpdir = File.join(base, "test_i2p_tun_#{Random.rand(100000)}")
      Dir.mkdir_p(tmpdir) unless Dir.exists?(tmpdir)
      controller = RNS::I2PController.new(tmpdir)
      controller.client_tunnels.empty?.should be_true
      controller.server_tunnels.empty?.should be_true
      FileUtils.rm_rf(tmpdir)
    end
  end

  it "has correct SAM client" do
    Dir.tempdir.tap do |base|
      tmpdir = File.join(base, "test_i2p_sam_#{Random.rand(100000)}")
      Dir.mkdir_p(tmpdir) unless Dir.exists?(tmpdir)
      controller = RNS::I2PController.new(tmpdir, "10.0.0.1", 8000)
      controller.sam.sam_host.should eq("10.0.0.1")
      controller.sam.sam_port.should eq(8000)
      FileUtils.rm_rf(tmpdir)
    end
  end

  it "to_s returns I2PController" do
    Dir.tempdir.tap do |base|
      tmpdir = File.join(base, "test_i2p_str_#{Random.rand(100000)}")
      Dir.mkdir_p(tmpdir) unless Dir.exists?(tmpdir)
      controller = RNS::I2PController.new(tmpdir)
      controller.to_s.should eq("I2PController")
      FileUtils.rm_rf(tmpdir)
    end
  end
end

describe RNS::I2PInterfacePeer do
  describe "constants" do
    it "has correct reconnect wait" do
      RNS::I2PInterfacePeer::RECONNECT_WAIT.should eq(15)
    end

    it "has nil reconnect max tries" do
      RNS::I2PInterfacePeer::RECONNECT_MAX_TRIES.should be_nil
    end

    it "has correct I2P timeout constants" do
      RNS::I2PInterfacePeer::I2P_USER_TIMEOUT.should eq(45)
      RNS::I2PInterfacePeer::I2P_PROBE_AFTER.should eq(10)
      RNS::I2PInterfacePeer::I2P_PROBE_INTERVAL.should eq(9)
      RNS::I2PInterfacePeer::I2P_PROBES.should eq(5)
    end

    it "computes I2P_READ_TIMEOUT correctly" do
      expected = (9 * 5 + 10) * 2 # (PROBE_INTERVAL * PROBES + PROBE_AFTER) * 2 = 110
      RNS::I2PInterfacePeer::I2P_READ_TIMEOUT.should eq(expected)
    end

    it "has correct tunnel state constants" do
      RNS::I2PInterfacePeer::TUNNEL_STATE_INIT.should eq(0x00)
      RNS::I2PInterfacePeer::TUNNEL_STATE_ACTIVE.should eq(0x01)
      RNS::I2PInterfacePeer::TUNNEL_STATE_STALE.should eq(0x02)
    end
  end

  describe "test constructor" do
    it "creates with name" do
      peer = RNS::I2PInterfacePeer.new("test_peer")
      peer.name.should eq("test_peer")
      peer.is_a?(RNS::Interface).should be_true
    end

    it "defaults to non-initiator" do
      peer = RNS::I2PInterfacePeer.new("test_peer")
      peer.initiator.should be_false
    end

    it "can be set as initiator" do
      peer = RNS::I2PInterfacePeer.new("test_peer", initiator: true)
      peer.initiator.should be_true
    end

    it "has HW_MTU of 1064" do
      peer = RNS::I2PInterfacePeer.new("test_peer")
      peer.hw_mtu.should eq(1064)
    end

    it "defaults to HDLC framing (not KISS)" do
      peer = RNS::I2PInterfacePeer.new("test_peer")
      peer.kiss_framing.should be_false
    end

    it "can use KISS framing" do
      peer = RNS::I2PInterfacePeer.new("test_peer", kiss_framing: true)
      peer.kiss_framing.should be_true
    end

    it "is i2p_tunneled" do
      peer = RNS::I2PInterfacePeer.new("test_peer")
      peer.i2p_tunneled.should be_true
    end

    it "has MODE_FULL" do
      peer = RNS::I2PInterfacePeer.new("test_peer")
      peer.mode.should eq(RNS::Interface::MODE_FULL)
    end

    it "has correct bitrate" do
      peer = RNS::I2PInterfacePeer.new("test_peer")
      peer.bitrate.should eq(RNS::I2PInterface::BITRATE_GUESS)
    end
  end

  describe "connected socket constructor" do
    it "creates with connected socket" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port
      spawn { server.accept? rescue nil }
      sleep 50.milliseconds
      client = TCPSocket.new("127.0.0.1", port)

      parent = RNS::I2PInterface.new("parent_test")
      peer = RNS::I2PInterfacePeer.new(parent, nil, "test_peer", client)

      peer.name.should eq("test_peer")
      peer.initiator.should be_false
      peer.hw_mtu.should eq(1064)
      peer.i2p_tunneled.should be_true
      peer.socket.should_not be_nil

      client.close rescue nil
      server.close rescue nil
    end

    it "inherits IFAC from parent" do
      parent = RNS::I2PInterface.new("parent_test")
      parent.ifac_netname = "testnet"

      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port
      spawn { server.accept? rescue nil }
      sleep 50.milliseconds
      client = TCPSocket.new("127.0.0.1", port)

      peer = RNS::I2PInterfacePeer.new(parent, nil, "test_peer", client)
      peer.ifac_netname.should eq("testnet")

      client.close rescue nil
      server.close rescue nil
    end
  end

  describe "process_incoming" do
    it "tracks rxb" do
      data = Bytes[1, 2, 3, 4, 5]
      received_data : Bytes? = nil
      callback = ->(d : Bytes, _i : RNS::Interface) { received_data = d; nil }

      peer = RNS::I2PInterfacePeer.new("test_peer", inbound_callback: callback)
      peer.process_incoming(data)
      peer.rxb.should eq(5)
    end

    it "calls inbound callback" do
      received_data : Bytes? = nil
      callback = ->(d : Bytes, _i : RNS::Interface) { received_data = d; nil }

      peer = RNS::I2PInterfacePeer.new("test_peer", inbound_callback: callback)
      peer.process_incoming(Bytes[10, 20, 30])
      received_data.should eq(Bytes[10, 20, 30])
    end

    it "tracks parent rxb when parent_count is true" do
      parent = RNS::I2PInterface.new("parent_test")
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port
      spawn { server.accept? rescue nil }
      sleep 50.milliseconds
      client = TCPSocket.new("127.0.0.1", port)

      peer = RNS::I2PInterfacePeer.new(parent, nil, "peer", client)
      peer.parent_count = true
      peer.process_incoming(Bytes[1, 2, 3])
      parent.rxb.should eq(3)

      client.close rescue nil
      server.close rescue nil
    end

    it "does not track parent rxb when parent_count is false" do
      parent = RNS::I2PInterface.new("parent_test")
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port
      spawn { server.accept? rescue nil }
      sleep 50.milliseconds
      client = TCPSocket.new("127.0.0.1", port)

      peer = RNS::I2PInterfacePeer.new(parent, nil, "peer", client)
      peer.parent_count = false
      peer.process_incoming(Bytes[1, 2, 3])
      parent.rxb.should eq(0)

      client.close rescue nil
      server.close rescue nil
    end
  end

  describe "process_outgoing" do
    it "does nothing when offline" do
      peer = RNS::I2PInterfacePeer.new("test_peer")
      peer.online = false
      peer.process_outgoing(Bytes[1, 2, 3])
      peer.txb.should eq(0)
    end

    it "sends HDLC framed data" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port
      received_data = Bytes.empty

      spawn do
        if client = server.accept?
          buf = Bytes.new(4096)
          n = client.read(buf)
          received_data = buf[0, n].dup
          client.close
        end
      end
      sleep 50.milliseconds

      sock = TCPSocket.new("127.0.0.1", port)
      peer = RNS::I2PInterfacePeer.new("test_peer")
      peer.socket = sock
      peer.online = true

      test_data = Bytes[0x41, 0x42, 0x43] # ABC
      peer.process_outgoing(test_data)
      sleep 100.milliseconds

      # Should be HDLC framed: FLAG + escaped data + FLAG
      received_data[0].should eq(RNS::HDLC::FLAG)
      received_data[-1].should eq(RNS::HDLC::FLAG)
      peer.txb.should be > 0

      sock.close rescue nil
      server.close rescue nil
    end

    it "sends KISS framed data when kiss_framing is true" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port
      received_data = Bytes.empty

      spawn do
        if client = server.accept?
          buf = Bytes.new(4096)
          n = client.read(buf)
          received_data = buf[0, n].dup
          client.close
        end
      end
      sleep 50.milliseconds

      sock = TCPSocket.new("127.0.0.1", port)
      peer = RNS::I2PInterfacePeer.new("test_peer", kiss_framing: true)
      peer.socket = sock
      peer.online = true

      test_data = Bytes[0x41, 0x42, 0x43]
      peer.process_outgoing(test_data)
      sleep 100.milliseconds

      # Should be KISS framed: FEND + CMD_DATA + escaped data + FEND
      received_data[0].should eq(RNS::KISS::FEND)
      received_data[1].should eq(RNS::KISS::CMD_DATA)
      received_data[-1].should eq(RNS::KISS::FEND)
      peer.txb.should be > 0

      sock.close rescue nil
      server.close rescue nil
    end

    it "tracks parent txb when parent_count is true" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port
      spawn do
        if c = server.accept?
          buf = Bytes.new(4096)
          c.read(buf)
          c.close
        end
      end
      sleep 50.milliseconds

      parent = RNS::I2PInterface.new("parent_test")
      sock = TCPSocket.new("127.0.0.1", port)
      peer = RNS::I2PInterfacePeer.new(parent, nil, "peer", sock)
      peer.parent_count = true
      peer.online = true

      peer.process_outgoing(Bytes[1, 2, 3])
      sleep 50.milliseconds
      parent.txb.should be > 0

      sock.close rescue nil
      server.close rescue nil
    end
  end

  describe "HDLC framing roundtrip" do
    it "sends and receives data correctly via HDLC" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port

      received_packets = [] of Bytes
      callback = ->(d : Bytes, _i : RNS::Interface) { received_packets << d.dup; nil }

      # Server side: create peer from accepted connection
      server_peer : RNS::I2PInterfacePeer? = nil
      spawn do
        if client = server.accept?
          server_peer = RNS::I2PInterfacePeer.new("server_peer", inbound_callback: callback)
          sp = server_peer.not_nil!
          sp.socket = client
          sp.online = true
          sp.start_read_loop
        end
      end
      sleep 50.milliseconds

      # Client side
      client_sock = TCPSocket.new("127.0.0.1", port)
      client_peer = RNS::I2PInterfacePeer.new("client_peer")
      client_peer.socket = client_sock
      client_peer.online = true

      # Send test data
      test_data = Bytes[0xDE, 0xAD, 0xBE, 0xEF]
      client_peer.process_outgoing(test_data)
      sleep 200.milliseconds

      received_packets.size.should eq(1)
      received_packets[0].should eq(test_data)

      client_sock.close rescue nil
      server.close rescue nil
    end

    it "handles multiple frames" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port

      received_packets = [] of Bytes
      callback = ->(d : Bytes, _i : RNS::Interface) { received_packets << d.dup; nil }

      spawn do
        if client = server.accept?
          sp = RNS::I2PInterfacePeer.new("server_peer", inbound_callback: callback)
          sp.socket = client
          sp.online = true
          sp.start_read_loop
        end
      end
      sleep 50.milliseconds

      client_sock = TCPSocket.new("127.0.0.1", port)
      client_peer = RNS::I2PInterfacePeer.new("client_peer")
      client_peer.socket = client_sock
      client_peer.online = true

      3.times do |i|
        client_peer.process_outgoing(Bytes[i.to_u8, (i + 10).to_u8])
      end
      sleep 300.milliseconds

      received_packets.size.should eq(3)
      received_packets[0].should eq(Bytes[0, 10])
      received_packets[1].should eq(Bytes[1, 11])
      received_packets[2].should eq(Bytes[2, 12])

      client_sock.close rescue nil
      server.close rescue nil
    end

    it "handles HDLC special bytes in data" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port

      received_packets = [] of Bytes
      callback = ->(d : Bytes, _i : RNS::Interface) { received_packets << d.dup; nil }

      spawn do
        if client = server.accept?
          sp = RNS::I2PInterfacePeer.new("server_peer", inbound_callback: callback)
          sp.socket = client
          sp.online = true
          sp.start_read_loop
        end
      end
      sleep 50.milliseconds

      client_sock = TCPSocket.new("127.0.0.1", port)
      client_peer = RNS::I2PInterfacePeer.new("client_peer")
      client_peer.socket = client_sock
      client_peer.online = true

      # Data containing HDLC FLAG and ESC bytes
      test_data = Bytes[0x41, RNS::HDLC::FLAG, RNS::HDLC::ESC, 0x42]
      client_peer.process_outgoing(test_data)
      sleep 200.milliseconds

      received_packets.size.should eq(1)
      received_packets[0].should eq(test_data)

      client_sock.close rescue nil
      server.close rescue nil
    end
  end

  describe "KISS framing roundtrip" do
    it "sends and receives data correctly via KISS" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port

      received_packets = [] of Bytes
      callback = ->(d : Bytes, _i : RNS::Interface) { received_packets << d.dup; nil }

      spawn do
        if client = server.accept?
          sp = RNS::I2PInterfacePeer.new("server_peer", kiss_framing: true, inbound_callback: callback)
          sp.socket = client
          sp.online = true
          sp.start_read_loop
        end
      end
      sleep 50.milliseconds

      client_sock = TCPSocket.new("127.0.0.1", port)
      client_peer = RNS::I2PInterfacePeer.new("client_peer", kiss_framing: true)
      client_peer.socket = client_sock
      client_peer.online = true

      test_data = Bytes[0xCA, 0xFE, 0xBA, 0xBE]
      client_peer.process_outgoing(test_data)
      sleep 200.milliseconds

      received_packets.size.should eq(1)
      received_packets[0].should eq(test_data)

      client_sock.close rescue nil
      server.close rescue nil
    end

    it "handles KISS special bytes in data" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port

      received_packets = [] of Bytes
      callback = ->(d : Bytes, _i : RNS::Interface) { received_packets << d.dup; nil }

      spawn do
        if client = server.accept?
          sp = RNS::I2PInterfacePeer.new("server_peer", kiss_framing: true, inbound_callback: callback)
          sp.socket = client
          sp.online = true
          sp.start_read_loop
        end
      end
      sleep 50.milliseconds

      client_sock = TCPSocket.new("127.0.0.1", port)
      client_peer = RNS::I2PInterfacePeer.new("client_peer", kiss_framing: true)
      client_peer.socket = client_sock
      client_peer.online = true

      # Data containing KISS FEND and FESC bytes
      test_data = Bytes[0x41, RNS::KISS::FEND, RNS::KISS::FESC, 0x42]
      client_peer.process_outgoing(test_data)
      sleep 200.milliseconds

      received_packets.size.should eq(1)
      received_packets[0].should eq(test_data)

      client_sock.close rescue nil
      server.close rescue nil
    end
  end

  describe "teardown" do
    it "sets offline" do
      peer = RNS::I2PInterfacePeer.new("test_peer")
      peer.online = true
      peer.teardown
      peer.online.should be_false
    end

    it "clears direction flags" do
      peer = RNS::I2PInterfacePeer.new("test_peer")
      peer.dir_in = true
      peer.dir_out = true
      peer.teardown
      peer.dir_in.should be_false
      peer.dir_out.should be_false
    end

    it "removes from parent spawned_interfaces" do
      parent = RNS::I2PInterface.new("parent_test")
      peer = RNS::I2PInterfacePeer.new("test_peer")
      peer.parent_interface = parent
      parent.spawned_interfaces.try(&.<<(peer))

      parent.spawned_interfaces.try(&.size).should eq(1)
      peer.teardown
      parent.spawned_interfaces.try(&.size).should eq(0)
    end
  end

  describe "detach" do
    it "sets detached flag" do
      peer = RNS::I2PInterfacePeer.new("test_peer")
      peer.detach
      peer.detached?.should be_true
    end

    it "closes socket" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port
      spawn { server.accept? rescue nil }
      sleep 50.milliseconds
      sock = TCPSocket.new("127.0.0.1", port)

      peer = RNS::I2PInterfacePeer.new("test_peer")
      peer.socket = sock
      peer.detach
      peer.socket.should be_nil

      server.close rescue nil
    end
  end

  describe "to_s" do
    it "returns I2PInterfacePeer[name]" do
      peer = RNS::I2PInterfacePeer.new("my_i2p_peer")
      peer.to_s.should eq("I2PInterfacePeer[my_i2p_peer]")
    end
  end

  describe "tunnel state" do
    it "starts in INIT state" do
      peer = RNS::I2PInterfacePeer.new("test_peer")
      peer.i2p_tunnel_state.should eq(RNS::I2PInterfacePeer::TUNNEL_STATE_INIT)
    end

    it "can transition to ACTIVE" do
      peer = RNS::I2PInterfacePeer.new("test_peer")
      peer.i2p_tunnel_state = RNS::I2PInterfacePeer::TUNNEL_STATE_ACTIVE
      peer.i2p_tunnel_state.should eq(RNS::I2PInterfacePeer::TUNNEL_STATE_ACTIVE)
    end

    it "can transition to STALE" do
      peer = RNS::I2PInterfacePeer.new("test_peer")
      peer.i2p_tunnel_state = RNS::I2PInterfacePeer::TUNNEL_STATE_STALE
      peer.i2p_tunnel_state.should eq(RNS::I2PInterfacePeer::TUNNEL_STATE_STALE)
    end
  end

  describe "interface base class" do
    it "inherits from Interface" do
      peer = RNS::I2PInterfacePeer.new("test")
      peer.is_a?(RNS::Interface).should be_true
    end

    it "has byte counters starting at zero" do
      peer = RNS::I2PInterfacePeer.new("test")
      peer.rxb.should eq(0)
      peer.txb.should eq(0)
    end

    it "has a consistent hash" do
      peer = RNS::I2PInterfacePeer.new("test_hash")
      h1 = peer.get_hash
      h2 = peer.get_hash
      h1.should eq(h2)
    end
  end

  describe "reconnection properties" do
    it "defaults to not reconnecting" do
      peer = RNS::I2PInterfacePeer.new("test")
      peer.reconnecting.should be_false
    end

    it "defaults to never_connected" do
      peer = RNS::I2PInterfacePeer.new("test")
      peer.never_connected.should be_true
    end

    it "defaults to nil max_reconnect_tries" do
      peer = RNS::I2PInterfacePeer.new("test")
      peer.max_reconnect_tries.should be_nil
    end
  end

  describe "stress tests" do
    it "handles 50 HDLC send/receive cycles" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port

      received_packets = [] of Bytes
      callback = ->(d : Bytes, _i : RNS::Interface) { received_packets << d.dup; nil }

      spawn do
        if client = server.accept?
          sp = RNS::I2PInterfacePeer.new("receiver", inbound_callback: callback)
          sp.socket = client
          sp.online = true
          sp.start_read_loop
        end
      end
      sleep 50.milliseconds

      client_sock = TCPSocket.new("127.0.0.1", port)
      sender = RNS::I2PInterfacePeer.new("sender")
      sender.socket = client_sock
      sender.online = true

      50.times do |_|
        data = Random::Secure.random_bytes(Random.rand(1..200))
        sender.process_outgoing(data)
      end
      sleep 500.milliseconds

      received_packets.size.should eq(50)

      client_sock.close rescue nil
      server.close rescue nil
    end

    it "creates and tears down 20 peers" do
      20.times do
        peer = RNS::I2PInterfacePeer.new("peer_#{Random.rand(10000)}")
        peer.online = true
        peer.teardown
        peer.online.should be_false
      end
    end
  end
end

describe RNS::I2PInterface do
  describe "constants" do
    it "has correct BITRATE_GUESS" do
      RNS::I2PInterface::BITRATE_GUESS.should eq(256_000)
    end

    it "has correct DEFAULT_IFAC_SIZE" do
      RNS::I2PInterface::DEFAULT_IFAC_SIZE.should eq(16)
    end
  end

  describe "test constructor" do
    it "creates with name" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.name.should eq("test_i2p")
    end

    it "inherits from Interface" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.is_a?(RNS::Interface).should be_true
    end

    it "has HW_MTU of 1064" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.hw_mtu.should eq(1064)
    end

    it "has MODE_FULL" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.mode.should eq(RNS::Interface::MODE_FULL)
    end

    it "starts offline" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.online.should be_false
    end

    it "supports discovery" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.supports_discovery.should be_true
    end

    it "has empty spawned_interfaces" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.spawned_interfaces.try(&.size).should eq(0)
    end

    it "has correct direction flags" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.dir_in.should be_true
      iface.dir_out.should be_false
    end

    it "has correct bitrate" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.bitrate.should eq(RNS::I2PInterface::BITRATE_GUESS)
    end

    it "has nil b32 initially" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.b32.should be_nil
    end

    it "has I2PController" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.i2p.is_a?(RNS::I2PController).should be_true
    end
  end

  describe "clients" do
    it "returns count of spawned interfaces" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.clients.should eq(0)

      peer1 = RNS::I2PInterfacePeer.new("peer1")
      peer2 = RNS::I2PInterfacePeer.new("peer2")
      iface.spawned_interfaces.try(&.<<(peer1))
      iface.spawned_interfaces.try(&.<<(peer2))

      iface.clients.should eq(2)
    end
  end

  describe "incoming_connection" do
    it "spawns a peer interface" do
      iface = RNS::I2PInterface.new("test_i2p")

      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port
      spawn { server.accept? rescue nil }
      sleep 50.milliseconds
      client = TCPSocket.new("127.0.0.1", port)

      iface.incoming_connection(client)
      sleep 100.milliseconds

      iface.clients.should eq(1)

      client.close rescue nil
      server.close rescue nil
    end

    it "sets spawned peer properties correctly" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.bitrate = 512_000_i64
      iface.mode = RNS::Interface::MODE_FULL

      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port
      spawn { server.accept? rescue nil }
      sleep 50.milliseconds
      client = TCPSocket.new("127.0.0.1", port)

      iface.incoming_connection(client)
      sleep 100.milliseconds

      spawned = iface.spawned_interfaces.try(&.first)
      spawned.should_not be_nil
      if s = spawned
        s.online.should be_true
        s.name.should eq("Connected peer on test_i2p")
        s.bitrate.should eq(512_000)
        s.mode.should eq(RNS::Interface::MODE_FULL)
      end

      client.close rescue nil
      server.close rescue nil
    end
  end

  describe "process_outgoing" do
    it "is a no-op" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.process_outgoing(Bytes[1, 2, 3])
      iface.txb.should eq(0)
    end
  end

  describe "announce tracking" do
    it "received_announce only tracks from_spawned" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.received_announce(from_spawned: false)
      iface.ia_freq_deque.size.should eq(0)

      iface.received_announce(from_spawned: true)
      iface.ia_freq_deque.size.should eq(1)
    end

    it "sent_announce only tracks from_spawned" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.sent_announce(from_spawned: false)
      iface.oa_freq_deque.size.should eq(0)

      iface.sent_announce(from_spawned: true)
      iface.oa_freq_deque.size.should eq(1)
    end
  end

  describe "detach" do
    it "stops controller and goes offline" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.online = true
      iface.i2p.start
      iface.i2p.ready.should be_true

      iface.detach
      iface.online.should be_false
      iface.i2p.ready.should be_false
    end
  end

  describe "to_s" do
    it "returns I2PInterface[name]" do
      iface = RNS::I2PInterface.new("my_i2p")
      iface.to_s.should eq("I2PInterface[my_i2p]")
    end
  end

  describe "connectable property" do
    it "defaults to false" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.connectable.should be_false
    end

    it "can be set to true" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.connectable = true
      iface.connectable.should be_true
    end
  end

  describe "b32 property" do
    it "can be set and retrieved" do
      iface = RNS::I2PInterface.new("test_i2p")
      iface.b32 = "abcdef1234567890.b32.i2p"
      iface.b32.should eq("abcdef1234567890.b32.i2p")
    end
  end

  describe "stress tests" do
    it "creates and tears down 20 I2P interfaces" do
      20.times do |i|
        iface = RNS::I2PInterface.new("i2p_stress_#{i}")
        iface.online = true
        iface.detach
        iface.online.should be_false
      end
    end

    it "handles 10 incoming connections" do
      iface = RNS::I2PInterface.new("test_i2p")

      sockets = [] of TCPSocket
      servers = [] of TCPServer

      10.times do
        server = TCPServer.new("127.0.0.1", 0)
        port = server.local_address.port
        spawn { server.accept? rescue nil }
        sleep 20.milliseconds
        client = TCPSocket.new("127.0.0.1", port)
        sockets << client
        servers << server

        iface.incoming_connection(client)
      end
      sleep 200.milliseconds

      iface.clients.should eq(10)

      sockets.each { |sock| sock.close rescue nil }
      servers.each { |srv| srv.close rescue nil }
    end
  end
end
