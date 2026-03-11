require "../spec_helper"

describe RNS::Rnpath do
  describe ".version_string" do
    it "includes rnpath and version number" do
      str = RNS::Rnpath.version_string
      str.should contain("rnpath")
      str.should contain(RNS::VERSION)
    end
  end

  describe ".parse_args" do
    it "returns defaults with no arguments" do
      args = RNS::Rnpath.parse_args([] of String)
      args.config.should be_nil
      args.verbose.should eq 0
      args.table.should be_false
      args.max_hops.should be_nil
      args.rates.should be_false
      args.drop.should be_false
      args.drop_announces.should be_false
      args.drop_via.should be_false
      args.remote.should be_nil
      args.identity.should be_nil
      args.blackholed.should be_false
      args.blackhole.should be_false
      args.unblackhole.should be_false
      args.duration.should be_nil
      args.reason.should be_nil
      args.blackholed_list.should be_false
      args.json.should be_false
      args.destination.should be_nil
      args.list_filter.should be_nil
      args.version.should be_false
    end

    it "parses --config option" do
      args = RNS::Rnpath.parse_args(["--config", "/tmp/test"])
      args.config.should eq "/tmp/test"
    end

    it "parses --version flag" do
      args = RNS::Rnpath.parse_args(["--version"])
      args.version.should be_true
    end

    it "parses -t / --table flag" do
      args = RNS::Rnpath.parse_args(["-t"])
      args.table.should be_true

      args2 = RNS::Rnpath.parse_args(["--table"])
      args2.table.should be_true
    end

    it "parses -m / --max option" do
      args = RNS::Rnpath.parse_args(["-m", "5"])
      args.max_hops.should eq 5

      args2 = RNS::Rnpath.parse_args(["--max", "10"])
      args2.max_hops.should eq 10
    end

    it "parses -r / --rates flag" do
      args = RNS::Rnpath.parse_args(["-r"])
      args.rates.should be_true

      args2 = RNS::Rnpath.parse_args(["--rates"])
      args2.rates.should be_true
    end

    it "parses -d / --drop flag" do
      args = RNS::Rnpath.parse_args(["-d"])
      args.drop.should be_true

      args2 = RNS::Rnpath.parse_args(["--drop"])
      args2.drop.should be_true
    end

    it "parses -D / --drop-announces flag" do
      args = RNS::Rnpath.parse_args(["-D"])
      args.drop_announces.should be_true

      args2 = RNS::Rnpath.parse_args(["--drop-announces"])
      args2.drop_announces.should be_true
    end

    it "parses -x / --drop-via flag" do
      args = RNS::Rnpath.parse_args(["-x"])
      args.drop_via.should be_true

      args2 = RNS::Rnpath.parse_args(["--drop-via"])
      args2.drop_via.should be_true
    end

    it "parses -w timeout option" do
      args = RNS::Rnpath.parse_args(["-w", "30.5"])
      args.timeout.should eq 30.5
    end

    it "parses -R remote hash option" do
      args = RNS::Rnpath.parse_args(["-R", "abcdef0123456789abcdef0123456789"])
      args.remote.should eq "abcdef0123456789abcdef0123456789"
    end

    it "parses -i identity path option" do
      args = RNS::Rnpath.parse_args(["-i", "/path/to/id"])
      args.identity.should eq "/path/to/id"
    end

    it "parses -W remote timeout option" do
      args = RNS::Rnpath.parse_args(["-W", "60.0"])
      args.remote_timeout.should eq 60.0
    end

    it "parses -b / --blackholed flag" do
      args = RNS::Rnpath.parse_args(["-b"])
      args.blackholed.should be_true
    end

    it "parses -B / --blackhole flag" do
      args = RNS::Rnpath.parse_args(["-B"])
      args.blackhole.should be_true
    end

    it "parses -U / --unblackhole flag" do
      args = RNS::Rnpath.parse_args(["-U"])
      args.unblackhole.should be_true
    end

    it "parses --duration option" do
      args = RNS::Rnpath.parse_args(["--duration", "24.0"])
      args.duration.should eq 24.0
    end

    it "parses --reason option" do
      args = RNS::Rnpath.parse_args(["--reason", "spamming"])
      args.reason.should eq "spamming"
    end

    it "parses -p / --blackholed-list flag" do
      args = RNS::Rnpath.parse_args(["-p"])
      args.blackholed_list.should be_true
    end

    it "parses -j / --json flag" do
      args = RNS::Rnpath.parse_args(["-j"])
      args.json.should be_true
    end

    it "parses -v for verbosity" do
      args = RNS::Rnpath.parse_args(["-v"])
      args.verbose.should eq 1
    end

    it "parses positional destination argument" do
      args = RNS::Rnpath.parse_args(["abcdef0123456789abcdef0123456789"])
      args.destination.should eq "abcdef0123456789abcdef0123456789"
    end

    it "parses two positional args (destination + list_filter)" do
      args = RNS::Rnpath.parse_args(["abcdef0123456789", "my_filter"])
      args.destination.should eq "abcdef0123456789"
      args.list_filter.should eq "my_filter"
    end

    it "parses combined short flags" do
      args = RNS::Rnpath.parse_args(["-trdj"])
      args.table.should be_true
      args.rates.should be_true
      args.drop.should be_true
      args.json.should be_true
    end

    it "raises on unknown argument" do
      expect_raises(ArgumentError) do
        RNS::Rnpath.parse_args(["--unknown"])
      end
    end

    it "raises on missing --config value" do
      expect_raises(ArgumentError) do
        RNS::Rnpath.parse_args(["--config"])
      end
    end
  end

  describe ".parse_hash" do
    it "parses valid 32-character hex hash" do
      result = RNS::Rnpath.parse_hash("abcdef0123456789abcdef0123456789")
      result.should be_a(Bytes)
      result.size.should eq 16
    end

    it "raises on wrong length" do
      expect_raises(ArgumentError, /length is invalid/) do
        RNS::Rnpath.parse_hash("abcdef")
      end
    end

    it "raises on invalid hex characters" do
      expect_raises(ArgumentError, /Invalid destination/) do
        RNS::Rnpath.parse_hash("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")
      end
    end
  end

  describe ".pretty_date" do
    it "formats seconds" do
      ts = (Time.utc - 30.seconds).to_unix
      result = RNS::Rnpath.pretty_date(ts)
      result.should contain("seconds")
    end

    it "formats minutes" do
      ts = (Time.utc - 5.minutes).to_unix
      result = RNS::Rnpath.pretty_date(ts)
      result.should contain("minutes")
    end

    it "formats hours" do
      ts = (Time.utc - 3.hours).to_unix
      result = RNS::Rnpath.pretty_date(ts)
      result.should contain("hours")
    end

    it "formats 1 day" do
      ts = (Time.utc - 1.day).to_unix
      result = RNS::Rnpath.pretty_date(ts)
      result.should eq "1 day"
    end

    it "formats multiple days" do
      ts = (Time.utc - 5.days).to_unix
      result = RNS::Rnpath.pretty_date(ts)
      result.should contain("days")
    end

    it "formats weeks" do
      ts = (Time.utc - 14.days).to_unix
      result = RNS::Rnpath.pretty_date(ts)
      result.should contain("weeks")
    end

    it "formats months" do
      ts = (Time.utc - 60.days).to_unix
      result = RNS::Rnpath.pretty_date(ts)
      result.should contain("months")
    end

    it "formats years" do
      ts = (Time.utc - 400.days).to_unix
      result = RNS::Rnpath.pretty_date(ts)
      result.should contain("year")
    end
  end

  describe ".format_path_table" do
    it "formats entries sorted by interface and hops" do
      entries = [
        RNS::Rnpath::PathTableEntry.new(
          hash: "abcdef0123456789abcdef0123456789".hexbytes,
          timestamp: Time.utc.to_unix_f - 100,
          via: "1111111111111111".hexbytes,
          hops: 2,
          expires: Time.utc.to_unix_f + 3600,
          interface: "iface_a"
        ),
        RNS::Rnpath::PathTableEntry.new(
          hash: "1234567890abcdef1234567890abcdef".hexbytes,
          timestamp: Time.utc.to_unix_f - 200,
          via: "2222222222222222".hexbytes,
          hops: 1,
          expires: Time.utc.to_unix_f + 7200,
          interface: "iface_a"
        ),
      ]

      output = RNS::Rnpath.format_path_table(entries)
      output.should contain("hop")
      output.should contain("away via")
      output.should contain("expires")
      # 1-hop entry should come first (sorted by interface then hops)
      lines = output.split("\n")
      lines.first.should contain("1 hop")
    end

    it "filters by destination hash" do
      target = "abcdef0123456789abcdef0123456789".hexbytes
      entries = [
        RNS::Rnpath::PathTableEntry.new(
          hash: target,
          timestamp: Time.utc.to_unix_f,
          via: "1111111111111111".hexbytes,
          hops: 1,
          expires: Time.utc.to_unix_f + 3600,
          interface: "iface_a"
        ),
        RNS::Rnpath::PathTableEntry.new(
          hash: "9999999999999999".hexbytes,
          timestamp: Time.utc.to_unix_f,
          via: "2222222222222222".hexbytes,
          hops: 2,
          expires: Time.utc.to_unix_f + 3600,
          interface: "iface_b"
        ),
      ]

      output = RNS::Rnpath.format_path_table(entries, target)
      lines = output.split("\n").reject(&.empty?)
      lines.size.should eq 1
      output.should contain("abcdef0123456789abcdef0123456789")
    end

    it "returns no path known for unmatched filter" do
      entries = [
        RNS::Rnpath::PathTableEntry.new(
          hash: "abcdef0123456789abcdef0123456789".hexbytes,
          timestamp: Time.utc.to_unix_f,
          via: "1111111111111111".hexbytes,
          hops: 1,
          expires: Time.utc.to_unix_f + 3600,
          interface: "iface_a"
        ),
      ]

      target = "0000000000000000".hexbytes
      output = RNS::Rnpath.format_path_table(entries, target)
      output.should eq "No path known"
    end

    it "handles empty table" do
      output = RNS::Rnpath.format_path_table([] of RNS::Rnpath::PathTableEntry)
      output.should eq ""
    end

    it "uses singular hop for 1 hop" do
      entries = [
        RNS::Rnpath::PathTableEntry.new(
          hash: "abcdef0123456789abcdef0123456789".hexbytes,
          timestamp: Time.utc.to_unix_f,
          via: "1111111111111111".hexbytes,
          hops: 1,
          expires: Time.utc.to_unix_f + 3600,
          interface: "iface_a"
        ),
      ]

      output = RNS::Rnpath.format_path_table(entries)
      output.should contain("1 hop ")
      output.should_not contain("1 hops")
    end

    it "uses plural hops for 2+ hops" do
      entries = [
        RNS::Rnpath::PathTableEntry.new(
          hash: "abcdef0123456789abcdef0123456789".hexbytes,
          timestamp: Time.utc.to_unix_f,
          via: "1111111111111111".hexbytes,
          hops: 3,
          expires: Time.utc.to_unix_f + 3600,
          interface: "iface_a"
        ),
      ]

      output = RNS::Rnpath.format_path_table(entries)
      output.should contain("3 hops")
    end
  end

  describe ".format_rate_table" do
    it "returns no info for empty table" do
      output = RNS::Rnpath.format_rate_table([] of RNS::Rnpath::RateTableEntry)
      output.should eq "No information available"
    end

    it "formats rate entries" do
      now = Time.utc.to_unix_f
      entries = [
        RNS::Rnpath::RateTableEntry.new(
          hash: "abcdef0123456789abcdef0123456789".hexbytes,
          last: now - 60.0,
          rate_violations: 0,
          blocked_until: 0.0,
          timestamps: [now - 3600.0, now - 1800.0, now - 60.0]
        ),
      ]

      output = RNS::Rnpath.format_rate_table(entries)
      output.should contain("last heard")
      output.should contain("announces/hour")
    end

    it "shows rate violations" do
      now = Time.utc.to_unix_f
      entries = [
        RNS::Rnpath::RateTableEntry.new(
          hash: "abcdef0123456789abcdef0123456789".hexbytes,
          last: now - 30.0,
          rate_violations: 3,
          blocked_until: 0.0,
          timestamps: [now - 100.0, now - 50.0, now - 30.0]
        ),
      ]

      output = RNS::Rnpath.format_rate_table(entries)
      output.should contain("3 active rate violations")
    end

    it "shows singular rate violation" do
      now = Time.utc.to_unix_f
      entries = [
        RNS::Rnpath::RateTableEntry.new(
          hash: "abcdef0123456789abcdef0123456789".hexbytes,
          last: now - 30.0,
          rate_violations: 1,
          blocked_until: 0.0,
          timestamps: [now - 30.0]
        ),
      ]

      output = RNS::Rnpath.format_rate_table(entries)
      output.should contain("1 active rate violation")
      output.should_not contain("violations")
    end

    it "filters by destination hash" do
      now = Time.utc.to_unix_f
      target = "abcdef0123456789abcdef0123456789".hexbytes
      entries = [
        RNS::Rnpath::RateTableEntry.new(
          hash: target,
          last: now - 30.0,
          rate_violations: 0,
          blocked_until: 0.0,
          timestamps: [now - 30.0]
        ),
        RNS::Rnpath::RateTableEntry.new(
          hash: "9999999999999999".hexbytes,
          last: now - 60.0,
          rate_violations: 0,
          blocked_until: 0.0,
          timestamps: [now - 60.0]
        ),
      ]

      output = RNS::Rnpath.format_rate_table(entries, target)
      output.should contain("abcdef0123456789abcdef0123456789")
      lines = output.split("\n").reject(&.empty?)
      lines.size.should eq 1
    end

    it "returns no info when filter finds nothing" do
      now = Time.utc.to_unix_f
      entries = [
        RNS::Rnpath::RateTableEntry.new(
          hash: "abcdef0123456789abcdef0123456789".hexbytes,
          last: now,
          rate_violations: 0,
          blocked_until: 0.0,
          timestamps: [now]
        ),
      ]

      target = "0000000000000000".hexbytes
      output = RNS::Rnpath.format_rate_table(entries, target)
      output.should eq "No information available"
    end
  end

  describe ".format_path_found" do
    it "formats singular hop" do
      hash = "abcdef0123456789abcdef0123456789".hexbytes
      next_hop = "1111111111111111".hexbytes
      output = RNS::Rnpath.format_path_found(hash, 1, next_hop, "UDPInterface")
      output.should contain("1 hop ")
      output.should_not contain("1 hops")
      output.should contain("Path found")
      output.should contain("UDPInterface")
    end

    it "formats plural hops" do
      hash = "abcdef0123456789abcdef0123456789".hexbytes
      next_hop = "1111111111111111".hexbytes
      output = RNS::Rnpath.format_path_found(hash, 3, next_hop, "TCPInterface")
      output.should contain("3 hops")
      output.should contain("TCPInterface")
    end
  end

  describe "path table integration" do
    before_each do
      RNS::Transport.reset
    end

    after_each do
      RNS::Transport.reset
    end

    it "collects path entries from Transport" do
      hash1 = Random::Secure.random_bytes(16)
      hash2 = Random::Secure.random_bytes(16)
      next_hop = Random::Secure.random_bytes(16)
      now = Time.utc.to_unix_f

      RNS::Transport.update_path(hash1, next_hop, 2, now + 3600.0)
      RNS::Transport.update_path(hash2, next_hop, 1, now + 7200.0)

      table = RNS::Rnpath.get_path_table
      table.size.should eq 2
    end

    it "filters by max_hops" do
      hash1 = Random::Secure.random_bytes(16)
      hash2 = Random::Secure.random_bytes(16)
      next_hop = Random::Secure.random_bytes(16)
      now = Time.utc.to_unix_f

      RNS::Transport.update_path(hash1, next_hop, 2, now + 3600.0)
      RNS::Transport.update_path(hash2, next_hop, 5, now + 7200.0)

      table = RNS::Rnpath.get_path_table(max_hops: 3)
      table.size.should eq 1
      table.first.hops.should eq 2
    end

    it "drops a path" do
      hash = Random::Secure.random_bytes(16)
      next_hop = Random::Secure.random_bytes(16)
      now = Time.utc.to_unix_f

      RNS::Transport.update_path(hash, next_hop, 1, now + 3600.0)
      RNS::Transport.has_path(hash).should be_true

      result = RNS::Rnpath.drop_path(hash)
      result.should be_true
    end

    it "drops all paths via a transport instance" do
      transport_hash = Random::Secure.random_bytes(16)
      other_hop = Random::Secure.random_bytes(16)
      now = Time.utc.to_unix_f

      hash1 = Random::Secure.random_bytes(16)
      hash2 = Random::Secure.random_bytes(16)
      hash3 = Random::Secure.random_bytes(16)

      RNS::Transport.update_path(hash1, transport_hash, 1, now + 3600.0)
      RNS::Transport.update_path(hash2, transport_hash, 2, now + 3600.0)
      RNS::Transport.update_path(hash3, other_hop, 1, now + 3600.0)

      count = RNS::Rnpath.drop_all_via(transport_hash)
      count.should eq 2
    end

    it "collects rate table entries from Transport" do
      table = RNS::Rnpath.get_rate_table
      table.should be_a(Array(RNS::Rnpath::RateTableEntry))
    end
  end

  describe "stress tests" do
    it "formats 50 path table entries" do
      entries = (0...50).map do |i|
        hash = Bytes.new(16)
        hash[0] = i.to_u8
        RNS::Rnpath::PathTableEntry.new(
          hash: hash,
          timestamp: Time.utc.to_unix_f - i * 100,
          via: Bytes.new(16, 0xAA_u8),
          hops: (i % 5) + 1,
          expires: Time.utc.to_unix_f + 3600.0,
          interface: "iface_#{i % 3}"
        )
      end

      output = RNS::Rnpath.format_path_table(entries)
      lines = output.split("\n").reject(&.empty?)
      lines.size.should eq 50
    end

    it "formats 30 rate table entries" do
      now = Time.utc.to_unix_f
      entries = (0...30).map do |i|
        hash = Bytes.new(16)
        hash[0] = i.to_u8
        RNS::Rnpath::RateTableEntry.new(
          hash: hash,
          last: now - i * 60.0,
          rate_violations: i % 4,
          blocked_until: 0.0,
          timestamps: [now - 3600.0, now - 1800.0, now - (i * 60.0)]
        )
      end

      output = RNS::Rnpath.format_rate_table(entries)
      lines = output.split("\n").reject(&.empty?)
      lines.size.should eq 30
    end

    it "parses 20 argument combinations" do
      combos = [
        ["-t"],
        ["-r"],
        ["-d", "abcdef0123456789abcdef0123456789"],
        ["-D"],
        ["-x", "abcdef0123456789abcdef0123456789"],
        ["-t", "-m", "3"],
        ["-t", "-j"],
        ["-r", "-j"],
        ["-b"],
        ["-B", "abcdef0123456789abcdef0123456789"],
        ["-U", "abcdef0123456789abcdef0123456789"],
        ["-p"],
        ["--table", "--max", "5"],
        ["--rates", "--json"],
        ["-t", "-v", "-v"],
        ["--config", "/tmp/x", "-t"],
        ["-w", "30", "abcdef0123456789abcdef0123456789"],
        ["-R", "abcdef0123456789abcdef0123456789", "-i", "/tmp/id"],
        ["-tj"],
        ["--version"],
      ]

      combos.each do |combo|
        args = RNS::Rnpath.parse_args(combo)
        args.should be_a(RNS::Rnpath::Args)
      end
    end
  end
end
