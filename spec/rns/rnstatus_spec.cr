require "../spec_helper"

SORT_IFACES_A_B = [
  RNS::Rnstatus::InterfaceStat.new(
    name: "A", short_name: "A", hash: Bytes[1], type_name: "Test",
    status: true, mode: 0x01_u8, rxb: 100_i64, txb: 200_i64,
    rxs: 1.0, txs: 2.0, clients: nil, bitrate: 1000_i64,
    incoming_announce_frequency: 0.5, outgoing_announce_frequency: 0.1,
    held_announces: 3, announce_queue: nil, ifac_signature: nil,
    ifac_size: 0, ifac_netname: nil, autoconnect_source: nil, peers: nil
  ),
  RNS::Rnstatus::InterfaceStat.new(
    name: "B", short_name: "B", hash: Bytes[2], type_name: "Test",
    status: true, mode: 0x01_u8, rxb: 500_i64, txb: 600_i64,
    rxs: 5.0, txs: 6.0, clients: nil, bitrate: 5000_i64,
    incoming_announce_frequency: 2.0, outgoing_announce_frequency: 1.0,
    held_announces: 1, announce_queue: nil, ifac_signature: nil,
    ifac_size: 0, ifac_netname: nil, autoconnect_source: nil, peers: nil
  ),
]

describe RNS::Rnstatus do
  describe ".version_string" do
    it "includes rnstatus and version number" do
      str = RNS::Rnstatus.version_string
      str.should contain("rnstatus")
      str.should contain(RNS::VERSION)
    end
  end

  describe ".parse_args" do
    it "returns defaults with no arguments" do
      args = RNS::Rnstatus.parse_args([] of String)
      args.config.should be_nil
      args.verbose.should eq 0
      args.all.should be_false
      args.announce_stats.should be_false
      args.link_stats.should be_false
      args.totals.should be_false
      args.sort.should be_nil
      args.reverse.should be_false
      args.json.should be_false
      args.remote.should be_nil
      args.identity.should be_nil
      args.filter.should be_nil
      args.version.should be_false
    end

    it "parses --config option" do
      args = RNS::Rnstatus.parse_args(["--config", "/tmp/test"])
      args.config.should eq "/tmp/test"
    end

    it "parses --version flag" do
      args = RNS::Rnstatus.parse_args(["--version"])
      args.version.should be_true
    end

    it "parses -a / --all flag" do
      args = RNS::Rnstatus.parse_args(["-a"])
      args.all.should be_true

      args2 = RNS::Rnstatus.parse_args(["--all"])
      args2.all.should be_true
    end

    it "parses -A / --announce-stats flag" do
      args = RNS::Rnstatus.parse_args(["-A"])
      args.announce_stats.should be_true

      args2 = RNS::Rnstatus.parse_args(["--announce-stats"])
      args2.announce_stats.should be_true
    end

    it "parses -l / --link-stats flag" do
      args = RNS::Rnstatus.parse_args(["-l"])
      args.link_stats.should be_true

      args2 = RNS::Rnstatus.parse_args(["--link-stats"])
      args2.link_stats.should be_true
    end

    it "parses -t / --totals flag" do
      args = RNS::Rnstatus.parse_args(["-t"])
      args.totals.should be_true

      args2 = RNS::Rnstatus.parse_args(["--totals"])
      args2.totals.should be_true
    end

    it "parses -s / --sort option" do
      args = RNS::Rnstatus.parse_args(["-s", "rate"])
      args.sort.should eq "rate"

      args2 = RNS::Rnstatus.parse_args(["--sort", "traffic"])
      args2.sort.should eq "traffic"
    end

    it "parses -r / --reverse flag" do
      args = RNS::Rnstatus.parse_args(["-r"])
      args.reverse.should be_true
    end

    it "parses -j / --json flag" do
      args = RNS::Rnstatus.parse_args(["-j"])
      args.json.should be_true
    end

    it "parses -R option for remote hash" do
      args = RNS::Rnstatus.parse_args(["-R", "abcdef0123456789abcdef0123456789"])
      args.remote.should eq "abcdef0123456789abcdef0123456789"
    end

    it "parses -i option for identity path" do
      args = RNS::Rnstatus.parse_args(["-i", "/path/to/id"])
      args.identity.should eq "/path/to/id"
    end

    it "parses -w option for timeout" do
      args = RNS::Rnstatus.parse_args(["-w", "30.5"])
      args.timeout.should eq 30.5
    end

    it "parses -v for verbosity" do
      args = RNS::Rnstatus.parse_args(["-v"])
      args.verbose.should eq 1
    end

    it "parses multiple -v flags" do
      args = RNS::Rnstatus.parse_args(["-vvv"])
      args.verbose.should eq 3
    end

    it "parses positional filter argument" do
      args = RNS::Rnstatus.parse_args(["UDP"])
      args.filter.should eq "UDP"
    end

    it "parses combined short flags" do
      args = RNS::Rnstatus.parse_args(["-aAltrj"])
      args.all.should be_true
      args.announce_stats.should be_true
      args.link_stats.should be_true
      args.totals.should be_true
      args.reverse.should be_true
      args.json.should be_true
    end

    it "parses combined flags with other options" do
      args = RNS::Rnstatus.parse_args(["-vvAl", "--config", "/tmp/cfg", "-s", "rate", "MyFilter"])
      args.verbose.should eq 2
      args.announce_stats.should be_true
      args.link_stats.should be_true
      args.config.should eq "/tmp/cfg"
      args.sort.should eq "rate"
      args.filter.should eq "MyFilter"
    end

    it "raises on unknown argument" do
      expect_raises(ArgumentError) do
        RNS::Rnstatus.parse_args(["--unknown"])
      end
    end

    it "raises on missing --config value" do
      expect_raises(ArgumentError) do
        RNS::Rnstatus.parse_args(["--config"])
      end
    end
  end

  describe ".speed_str" do
    it "formats zero correctly" do
      RNS::Rnstatus.speed_str(0.0).should eq "0.00 bps"
    end

    it "formats sub-kilo value" do
      str = RNS::Rnstatus.speed_str(500.0)
      str.should contain("500.00")
      str.should contain("bps")
    end

    it "formats kilo value" do
      str = RNS::Rnstatus.speed_str(1500.0)
      str.should contain("1.50")
      str.should contain("kbps")
    end

    it "formats mega value" do
      str = RNS::Rnstatus.speed_str(2_500_000.0)
      str.should contain("2.50")
      str.should contain("Mbps")
    end

    it "formats giga value" do
      str = RNS::Rnstatus.speed_str(1_000_000_000.0)
      str.should contain("1.00")
      str.should contain("Gbps")
    end
  end

  describe ".size_str" do
    it "formats zero bytes" do
      RNS::Rnstatus.size_str(0.0).should eq "0 B"
    end

    it "formats bytes under 1000" do
      str = RNS::Rnstatus.size_str(500.0)
      str.should eq "500 B"
    end

    it "formats kilobytes" do
      str = RNS::Rnstatus.size_str(1500.0)
      str.should contain("1.50")
      str.should contain("KB")
    end

    it "formats megabytes" do
      str = RNS::Rnstatus.size_str(2_500_000.0)
      str.should contain("2.50")
      str.should contain("MB")
    end

    it "formats with bits suffix" do
      str = RNS::Rnstatus.size_str(500.0, "b")
      str.should contain("4.00")
      str.should contain("Kb")
    end
  end

  describe ".mode_str" do
    it "returns Full for MODE_FULL" do
      RNS::Rnstatus.mode_str(RNS::Interface::MODE_FULL).should eq "Full"
    end

    it "returns Access Point for MODE_ACCESS_POINT" do
      RNS::Rnstatus.mode_str(RNS::Interface::MODE_ACCESS_POINT).should eq "Access Point"
    end

    it "returns Point-to-Point for MODE_POINT_TO_POINT" do
      RNS::Rnstatus.mode_str(RNS::Interface::MODE_POINT_TO_POINT).should eq "Point-to-Point"
    end

    it "returns Roaming for MODE_ROAMING" do
      RNS::Rnstatus.mode_str(RNS::Interface::MODE_ROAMING).should eq "Roaming"
    end

    it "returns Boundary for MODE_BOUNDARY" do
      RNS::Rnstatus.mode_str(RNS::Interface::MODE_BOUNDARY).should eq "Boundary"
    end

    it "returns Gateway for MODE_GATEWAY" do
      RNS::Rnstatus.mode_str(RNS::Interface::MODE_GATEWAY).should eq "Gateway"
    end

    it "returns Full for unknown mode" do
      RNS::Rnstatus.mode_str(0xFF_u8).should eq "Full"
    end
  end

  describe ".hidden_interface?" do
    it "hides LocalInterface clients" do
      RNS::Rnstatus.hidden_interface?("LocalInterface[some/path]").should be_true
    end

    it "hides TCPInterface clients" do
      RNS::Rnstatus.hidden_interface?("TCPInterface[Client 10.0.0.1:4242]").should be_true
    end

    it "hides BackboneInterface clients" do
      RNS::Rnstatus.hidden_interface?("BackboneInterface[Client on 10.0.0.1:4242]").should be_true
    end

    it "hides AutoInterfacePeer" do
      RNS::Rnstatus.hidden_interface?("AutoInterfacePeer[fe80::1]").should be_true
    end

    it "hides WeaveInterfacePeer" do
      RNS::Rnstatus.hidden_interface?("WeaveInterfacePeer[fe80::2]").should be_true
    end

    it "shows regular interfaces" do
      RNS::Rnstatus.hidden_interface?("UDPInterface[Default]").should be_false
    end

    it "shows TCP server interfaces" do
      RNS::Rnstatus.hidden_interface?("TCPServerInterface[Server on 4242]").should be_false
    end

    it "shows Shared Instance" do
      RNS::Rnstatus.hidden_interface?("Shared Instance[37428]").should be_false
    end
  end

  describe ".format_interface" do
    it "includes interface name" do
      stat = RNS::Rnstatus::InterfaceStat.new(
        name: "UDPInterface[Default]",
        short_name: "Default",
        hash: Bytes[1, 2, 3],
        type_name: "UDPInterface",
        status: true,
        mode: RNS::Interface::MODE_FULL,
        rxb: 1024_i64,
        txb: 2048_i64,
        rxs: 0.0,
        txs: 0.0,
        clients: nil,
        bitrate: 10_000_000_i64,
        incoming_announce_frequency: 0.0,
        outgoing_announce_frequency: 0.0,
        held_announces: 0,
        announce_queue: 0,
        ifac_signature: nil,
        ifac_size: 0,
        ifac_netname: nil,
        autoconnect_source: nil,
        peers: nil,
      )

      output = RNS::Rnstatus.format_interface(stat)
      output.should contain("UDPInterface[Default]")
      output.should contain("Status    : Up")
      output.should contain("Mode      : Full")
      output.should contain("Rate      :")
      output.should contain("Traffic   :")
    end

    it "shows Down status when offline" do
      stat = RNS::Rnstatus::InterfaceStat.new(
        name: "Test[x]",
        short_name: "x",
        hash: Bytes[1],
        type_name: "Test",
        status: false,
        mode: RNS::Interface::MODE_FULL,
        rxb: 0_i64,
        txb: 0_i64,
        rxs: 0.0,
        txs: 0.0,
        clients: nil,
        bitrate: nil,
        incoming_announce_frequency: 0.0,
        outgoing_announce_frequency: 0.0,
        held_announces: 0,
        announce_queue: nil,
        ifac_signature: nil,
        ifac_size: 0,
        ifac_netname: nil,
        autoconnect_source: nil,
        peers: nil,
      )

      output = RNS::Rnstatus.format_interface(stat)
      output.should contain("Status    : Down")
    end

    it "shows clients for shared instance" do
      stat = RNS::Rnstatus::InterfaceStat.new(
        name: "Shared Instance[37428]",
        short_name: "Shared Instance",
        hash: Bytes[1],
        type_name: "LocalServerInterface",
        status: true,
        mode: RNS::Interface::MODE_FULL,
        rxb: 0_i64,
        txb: 0_i64,
        rxs: 0.0,
        txs: 0.0,
        clients: 3,
        bitrate: nil,
        incoming_announce_frequency: 0.0,
        outgoing_announce_frequency: 0.0,
        held_announces: 0,
        announce_queue: nil,
        ifac_signature: nil,
        ifac_size: 0,
        ifac_netname: nil,
        autoconnect_source: nil,
        peers: nil,
      )

      output = RNS::Rnstatus.format_interface(stat)
      output.should contain("Serving   : 2 programs")
    end

    it "shows singular program for 2 clients (2-1=1)" do
      stat = RNS::Rnstatus::InterfaceStat.new(
        name: "Shared Instance[37428]",
        short_name: "Shared Instance",
        hash: Bytes[1],
        type_name: "LocalServerInterface",
        status: true,
        mode: RNS::Interface::MODE_FULL,
        rxb: 0_i64,
        txb: 0_i64,
        rxs: 0.0,
        txs: 0.0,
        clients: 2,
        bitrate: nil,
        incoming_announce_frequency: 0.0,
        outgoing_announce_frequency: 0.0,
        held_announces: 0,
        announce_queue: nil,
        ifac_signature: nil,
        ifac_size: 0,
        ifac_netname: nil,
        autoconnect_source: nil,
        peers: nil,
      )

      output = RNS::Rnstatus.format_interface(stat)
      output.should contain("Serving   : 1 program")
    end

    it "shows announce stats when astats=true" do
      stat = RNS::Rnstatus::InterfaceStat.new(
        name: "UDPInterface[Default]",
        short_name: "Default",
        hash: Bytes[1],
        type_name: "UDPInterface",
        status: true,
        mode: RNS::Interface::MODE_FULL,
        rxb: 0_i64,
        txb: 0_i64,
        rxs: 0.0,
        txs: 0.0,
        clients: nil,
        bitrate: 10_000_000_i64,
        incoming_announce_frequency: 1.5,
        outgoing_announce_frequency: 0.5,
        held_announces: 3,
        announce_queue: 2,
        ifac_signature: nil,
        ifac_size: 0,
        ifac_netname: nil,
        autoconnect_source: nil,
        peers: nil,
      )

      output = RNS::Rnstatus.format_interface(stat, astats: true)
      output.should contain("Queued    : 2 announces")
      output.should contain("Held      : 3 announces")
      output.should contain("Announces :")
    end

    it "shows IFAC access info" do
      sig = Bytes[0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11, 0x22, 0x33]
      stat = RNS::Rnstatus::InterfaceStat.new(
        name: "UDPInterface[Default]",
        short_name: "Default",
        hash: Bytes[1],
        type_name: "UDPInterface",
        status: true,
        mode: RNS::Interface::MODE_FULL,
        rxb: 0_i64,
        txb: 0_i64,
        rxs: 0.0,
        txs: 0.0,
        clients: nil,
        bitrate: nil,
        incoming_announce_frequency: 0.0,
        outgoing_announce_frequency: 0.0,
        held_announces: 0,
        announce_queue: nil,
        ifac_signature: sig,
        ifac_size: 8,
        ifac_netname: "TestNet",
        autoconnect_source: nil,
        peers: nil,
      )

      output = RNS::Rnstatus.format_interface(stat)
      output.should contain("Network   : TestNet")
      output.should contain("Access    : 64-bit IFAC by")
    end

    it "shows autoconnect source" do
      stat = RNS::Rnstatus::InterfaceStat.new(
        name: "TCPClientInterface[Remote]",
        short_name: "Remote",
        hash: Bytes[1],
        type_name: "TCPClientInterface",
        status: true,
        mode: RNS::Interface::MODE_FULL,
        rxb: 0_i64,
        txb: 0_i64,
        rxs: 0.0,
        txs: 0.0,
        clients: nil,
        bitrate: nil,
        incoming_announce_frequency: 0.0,
        outgoing_announce_frequency: 0.0,
        held_announces: 0,
        announce_queue: nil,
        ifac_signature: nil,
        ifac_size: 0,
        ifac_netname: nil,
        autoconnect_source: "AutoInterface[Default]",
        peers: nil,
      )

      output = RNS::Rnstatus.format_interface(stat)
      output.should contain("Source    : Auto-connect via <AutoInterface[Default]>")
    end

    it "shows peers count" do
      stat = RNS::Rnstatus::InterfaceStat.new(
        name: "AutoInterface[Default]",
        short_name: "Default",
        hash: Bytes[1],
        type_name: "AutoInterface",
        status: true,
        mode: RNS::Interface::MODE_FULL,
        rxb: 0_i64,
        txb: 0_i64,
        rxs: 0.0,
        txs: 0.0,
        clients: nil,
        bitrate: nil,
        incoming_announce_frequency: 0.0,
        outgoing_announce_frequency: 0.0,
        held_announces: 0,
        announce_queue: nil,
        ifac_signature: nil,
        ifac_size: 0,
        ifac_netname: nil,
        autoconnect_source: nil,
        peers: 5,
      )

      output = RNS::Rnstatus.format_interface(stat)
      output.should contain("Peers     : 5 reachable")
    end

    it "hides mode for shared instance" do
      stat = RNS::Rnstatus::InterfaceStat.new(
        name: "Shared Instance[37428]",
        short_name: "Shared Instance",
        hash: Bytes[1],
        type_name: "LocalServerInterface",
        status: true,
        mode: RNS::Interface::MODE_FULL,
        rxb: 0_i64,
        txb: 0_i64,
        rxs: 0.0,
        txs: 0.0,
        clients: 1,
        bitrate: nil,
        incoming_announce_frequency: 0.0,
        outgoing_announce_frequency: 0.0,
        held_announces: 0,
        announce_queue: nil,
        ifac_signature: nil,
        ifac_size: 0,
        ifac_netname: nil,
        autoconnect_source: nil,
        peers: nil,
      )

      output = RNS::Rnstatus.format_interface(stat)
      output.should_not contain("Mode      :")
    end
  end

  describe ".sort_interfaces" do
    it "sorts by rate" do
      ifaces = SORT_IFACES_A_B.dup
      sorted = RNS::Rnstatus.sort_interfaces(ifaces, "rate", false)
      sorted.first.name.should eq "B"
    end

    it "sorts by rx" do
      ifaces = SORT_IFACES_A_B.dup
      sorted = RNS::Rnstatus.sort_interfaces(ifaces, "rx", false)
      sorted.first.name.should eq "B"
    end

    it "sorts by tx" do
      ifaces = SORT_IFACES_A_B.dup
      sorted = RNS::Rnstatus.sort_interfaces(ifaces, "tx", false)
      sorted.first.name.should eq "B"
    end

    it "sorts by traffic" do
      ifaces = SORT_IFACES_A_B.dup
      sorted = RNS::Rnstatus.sort_interfaces(ifaces, "traffic", false)
      sorted.first.name.should eq "B"
    end

    it "sorts by announces" do
      ifaces = SORT_IFACES_A_B.dup
      sorted = RNS::Rnstatus.sort_interfaces(ifaces, "announces", false)
      sorted.first.name.should eq "B"
    end

    it "sorts by held" do
      ifaces = SORT_IFACES_A_B.dup
      sorted = RNS::Rnstatus.sort_interfaces(ifaces, "held", false)
      sorted.first.name.should eq "A"
    end

    it "reverses sort" do
      ifaces = SORT_IFACES_A_B.dup
      sorted = RNS::Rnstatus.sort_interfaces(ifaces, "rate", true)
      sorted.first.name.should eq "A"
    end

    it "returns unchanged for nil sorting" do
      ifaces = SORT_IFACES_A_B.dup
      result = RNS::Rnstatus.sort_interfaces(ifaces, nil, false)
      result.size.should eq 2
    end

    it "returns unchanged for unknown sort key" do
      ifaces = SORT_IFACES_A_B.dup
      result = RNS::Rnstatus.sort_interfaces(ifaces, "bogus", false)
      result.size.should eq 2
    end
  end

  describe ".format_status" do
    it "produces empty output for no interfaces" do
      stats = RNS::Rnstatus::TransportStats.new(
        interfaces: [] of RNS::Rnstatus::InterfaceStat,
        rxb: 0_i64,
        txb: 0_i64,
        rxs: 0_i64,
        txs: 0_i64,
        transport_id: nil,
        network_id: nil,
        transport_uptime: nil,
        probe_responder: nil,
      )

      output = RNS::Rnstatus.format_status(stats)
      output.strip.should eq ""
    end

    it "shows transport instance when transport_id is present" do
      tid = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                  0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10]
      stats = RNS::Rnstatus::TransportStats.new(
        interfaces: [] of RNS::Rnstatus::InterfaceStat,
        rxb: 0_i64,
        txb: 0_i64,
        rxs: 0_i64,
        txs: 0_i64,
        transport_id: tid,
        network_id: nil,
        transport_uptime: 3600.0,
        probe_responder: nil,
      )

      output = RNS::Rnstatus.format_status(stats)
      output.should contain("Transport Instance")
      output.should contain("running")
      output.should contain("Uptime is")
    end

    it "shows traffic totals when enabled" do
      stats = RNS::Rnstatus::TransportStats.new(
        interfaces: [] of RNS::Rnstatus::InterfaceStat,
        rxb: 1024_i64,
        txb: 2048_i64,
        rxs: 100_i64,
        txs: 200_i64,
        transport_id: nil,
        network_id: nil,
        transport_uptime: nil,
        probe_responder: nil,
      )

      output = RNS::Rnstatus.format_status(stats, traffic_totals: true)
      output.should contain("Totals")
    end

    it "filters interfaces by name" do
      ifaces = [
        RNS::Rnstatus::InterfaceStat.new(
          name: "UDPInterface[Default]", short_name: "Default", hash: Bytes[1],
          type_name: "UDPInterface", status: true, mode: 0x01_u8,
          rxb: 0_i64, txb: 0_i64, rxs: 0.0, txs: 0.0, clients: nil,
          bitrate: nil, incoming_announce_frequency: 0.0, outgoing_announce_frequency: 0.0,
          held_announces: 0, announce_queue: nil, ifac_signature: nil,
          ifac_size: 0, ifac_netname: nil, autoconnect_source: nil, peers: nil
        ),
        RNS::Rnstatus::InterfaceStat.new(
          name: "TCPServerInterface[Server]", short_name: "Server", hash: Bytes[2],
          type_name: "TCPServerInterface", status: true, mode: 0x01_u8,
          rxb: 0_i64, txb: 0_i64, rxs: 0.0, txs: 0.0, clients: nil,
          bitrate: nil, incoming_announce_frequency: 0.0, outgoing_announce_frequency: 0.0,
          held_announces: 0, announce_queue: nil, ifac_signature: nil,
          ifac_size: 0, ifac_netname: nil, autoconnect_source: nil, peers: nil
        ),
      ]

      stats = RNS::Rnstatus::TransportStats.new(
        interfaces: ifaces,
        rxb: 0_i64, txb: 0_i64, rxs: 0_i64, txs: 0_i64,
        transport_id: nil, network_id: nil, transport_uptime: nil, probe_responder: nil,
      )

      output = RNS::Rnstatus.format_status(stats, name_filter: "UDP")
      output.should contain("UDPInterface")
      output.should_not contain("TCPServerInterface")
    end

    it "hides default-hidden interfaces unless dispall" do
      ifaces = [
        RNS::Rnstatus::InterfaceStat.new(
          name: "LocalInterface[/tmp/sock]", short_name: "Local", hash: Bytes[1],
          type_name: "LocalClientInterface", status: true, mode: 0x01_u8,
          rxb: 0_i64, txb: 0_i64, rxs: 0.0, txs: 0.0, clients: nil,
          bitrate: nil, incoming_announce_frequency: 0.0, outgoing_announce_frequency: 0.0,
          held_announces: 0, announce_queue: nil, ifac_signature: nil,
          ifac_size: 0, ifac_netname: nil, autoconnect_source: nil, peers: nil
        ),
      ]

      stats = RNS::Rnstatus::TransportStats.new(
        interfaces: ifaces,
        rxb: 0_i64, txb: 0_i64, rxs: 0_i64, txs: 0_i64,
        transport_id: nil, network_id: nil, transport_uptime: nil, probe_responder: nil,
      )

      hidden = RNS::Rnstatus.format_status(stats, dispall: false)
      hidden.should_not contain("LocalInterface")

      shown = RNS::Rnstatus.format_status(stats, dispall: true)
      shown.should contain("LocalInterface")
    end

    it "shows link table entry count when lstats enabled" do
      tid = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                  0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10]
      stats = RNS::Rnstatus::TransportStats.new(
        interfaces: [] of RNS::Rnstatus::InterfaceStat,
        rxb: 0_i64, txb: 0_i64, rxs: 0_i64, txs: 0_i64,
        transport_id: tid, network_id: nil, transport_uptime: 100.0, probe_responder: nil,
      )

      output = RNS::Rnstatus.format_status(stats, lstats: true, link_count: 5)
      output.should contain("5 entries in link table")
    end

    it "shows singular link table entry" do
      tid = Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                  0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10]
      stats = RNS::Rnstatus::TransportStats.new(
        interfaces: [] of RNS::Rnstatus::InterfaceStat,
        rxb: 0_i64, txb: 0_i64, rxs: 0_i64, txs: 0_i64,
        transport_id: tid, network_id: nil, transport_uptime: 100.0, probe_responder: nil,
      )

      output = RNS::Rnstatus.format_status(stats, lstats: true, link_count: 1)
      output.should contain("1 entry in link table")
    end
  end
end
