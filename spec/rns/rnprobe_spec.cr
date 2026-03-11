require "../spec_helper"

describe RNS::Rnprobe do
  describe ".version_string" do
    it "includes rnprobe and version number" do
      str = RNS::Rnprobe.version_string
      str.should contain("rnprobe")
      str.should contain(RNS::VERSION)
    end
  end

  describe ".parse_args" do
    it "returns defaults with no arguments" do
      args = RNS::Rnprobe.parse_args([] of String)
      args.config.should be_nil
      args.size.should be_nil
      args.probes.should eq 1
      args.timeout.should be_nil
      args.wait.should eq 0.0
      args.verbose.should eq 0
      args.full_name.should be_nil
      args.destination_hash.should be_nil
      args.version.should be_false
    end

    it "parses --config option" do
      args = RNS::Rnprobe.parse_args(["--config", "/tmp/test"])
      args.config.should eq "/tmp/test"
    end

    it "parses --version flag" do
      args = RNS::Rnprobe.parse_args(["--version"])
      args.version.should be_true
    end

    it "parses -s / --size option" do
      args = RNS::Rnprobe.parse_args(["-s", "64"])
      args.size.should eq 64

      args2 = RNS::Rnprobe.parse_args(["--size", "128"])
      args2.size.should eq 128
    end

    it "parses -n / --probes option" do
      args = RNS::Rnprobe.parse_args(["-n", "5"])
      args.probes.should eq 5

      args2 = RNS::Rnprobe.parse_args(["--probes", "10"])
      args2.probes.should eq 10
    end

    it "parses -t / --timeout option" do
      args = RNS::Rnprobe.parse_args(["-t", "30.5"])
      args.timeout.should eq 30.5

      args2 = RNS::Rnprobe.parse_args(["--timeout", "60"])
      args2.timeout.should eq 60.0
    end

    it "parses -w / --wait option" do
      args = RNS::Rnprobe.parse_args(["-w", "2.5"])
      args.wait.should eq 2.5

      args2 = RNS::Rnprobe.parse_args(["--wait", "1.0"])
      args2.wait.should eq 1.0
    end

    it "parses -v for verbosity" do
      args = RNS::Rnprobe.parse_args(["-v"])
      args.verbose.should eq 1
    end

    it "parses multiple -v flags" do
      args = RNS::Rnprobe.parse_args(["-v", "-v", "-v"])
      args.verbose.should eq 3
    end

    it "parses combined -vv flags" do
      args = RNS::Rnprobe.parse_args(["-vv"])
      args.verbose.should eq 2
    end

    it "parses positional arguments" do
      args = RNS::Rnprobe.parse_args(["myapp.echo", "abcdef0123456789abcdef0123456789"])
      args.full_name.should eq "myapp.echo"
      args.destination_hash.should eq "abcdef0123456789abcdef0123456789"
    end

    it "parses full combination of options" do
      args = RNS::Rnprobe.parse_args([
        "--config", "/tmp/rns",
        "-s", "32",
        "-n", "3",
        "-t", "15.0",
        "-w", "1.0",
        "-v",
        "myapp.echo",
        "abcdef0123456789abcdef0123456789",
      ])
      args.config.should eq "/tmp/rns"
      args.size.should eq 32
      args.probes.should eq 3
      args.timeout.should eq 15.0
      args.wait.should eq 1.0
      args.verbose.should eq 1
      args.full_name.should eq "myapp.echo"
      args.destination_hash.should eq "abcdef0123456789abcdef0123456789"
    end

    it "raises on unknown argument" do
      expect_raises(ArgumentError) do
        RNS::Rnprobe.parse_args(["--unknown"])
      end
    end

    it "raises on missing --config value" do
      expect_raises(ArgumentError) do
        RNS::Rnprobe.parse_args(["--config"])
      end
    end

    it "raises on missing --size value" do
      expect_raises(ArgumentError) do
        RNS::Rnprobe.parse_args(["--size"])
      end
    end

    it "raises on missing --probes value" do
      expect_raises(ArgumentError) do
        RNS::Rnprobe.parse_args(["--probes"])
      end
    end

    it "raises on extra positional argument" do
      expect_raises(ArgumentError) do
        RNS::Rnprobe.parse_args(["a", "b", "c"])
      end
    end
  end

  describe ".parse_destination_hash" do
    it "parses valid 32-character hex hash" do
      result = RNS::Rnprobe.parse_destination_hash("abcdef0123456789abcdef0123456789")
      result.should be_a(Bytes)
      result.size.should eq 16
    end

    it "raises on wrong length" do
      expect_raises(ArgumentError, /length is invalid/) do
        RNS::Rnprobe.parse_destination_hash("abcdef")
      end
    end

    it "raises on invalid hex characters" do
      expect_raises(ArgumentError, /Invalid destination/) do
        RNS::Rnprobe.parse_destination_hash("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")
      end
    end
  end

  describe ".format_probe_reply" do
    it "formats RTT in seconds for >= 1s" do
      dest = "abcdef0123456789abcdef0123456789".hexbytes
      output = RNS::Rnprobe.format_probe_reply(dest, 2, 1.234)
      output.should contain("1.234 seconds")
      output.should contain("2 hops")
      output.should contain("Valid reply")
    end

    it "formats RTT in milliseconds for < 1s" do
      dest = "abcdef0123456789abcdef0123456789".hexbytes
      output = RNS::Rnprobe.format_probe_reply(dest, 1, 0.05)
      output.should contain("50.0 milliseconds")
      output.should contain("1 hop")
      output.should_not contain("1 hops")
    end

    it "includes reception stats when provided" do
      dest = "abcdef0123456789abcdef0123456789".hexbytes
      output = RNS::Rnprobe.format_probe_reply(dest, 1, 0.1, " [RSSI -70 dBm]")
      output.should contain("[RSSI -70 dBm]")
    end

    it "uses singular hop for 1 hop" do
      dest = "abcdef0123456789abcdef0123456789".hexbytes
      output = RNS::Rnprobe.format_probe_reply(dest, 1, 0.5)
      output.should contain("1 hop")
      output.should_not contain("1 hops")
    end

    it "uses plural hops for 0 hops" do
      dest = "abcdef0123456789abcdef0123456789".hexbytes
      output = RNS::Rnprobe.format_probe_reply(dest, 0, 0.5)
      output.should contain("0 hops")
    end

    it "uses plural hops for multiple hops" do
      dest = "abcdef0123456789abcdef0123456789".hexbytes
      output = RNS::Rnprobe.format_probe_reply(dest, 5, 2.0)
      output.should contain("5 hops")
    end
  end

  describe ".format_probe_summary" do
    it "shows 0% loss when all probes replied" do
      output = RNS::Rnprobe.format_probe_summary(5, 5)
      output.should contain("Sent 5")
      output.should contain("received 5")
      output.should contain("packet loss 0.0%")
    end

    it "shows 100% loss when no probes replied" do
      output = RNS::Rnprobe.format_probe_summary(3, 0)
      output.should contain("Sent 3")
      output.should contain("received 0")
      output.should contain("packet loss 100.0%")
    end

    it "shows partial loss" do
      output = RNS::Rnprobe.format_probe_summary(10, 7)
      output.should contain("Sent 10")
      output.should contain("received 7")
      output.should contain("packet loss 30.0%")
    end

    it "handles single probe" do
      output = RNS::Rnprobe.format_probe_summary(1, 1)
      output.should contain("Sent 1")
      output.should contain("received 1")
      output.should contain("packet loss 0.0%")
    end
  end

  describe ".usage_string" do
    it "contains usage information" do
      usage = RNS::Rnprobe.usage_string
      usage.should contain("Reticulum Probe Utility")
      usage.should contain("full_name")
      usage.should contain("destination_hash")
      usage.should contain("--config")
      usage.should contain("--size")
      usage.should contain("--probes")
      usage.should contain("--timeout")
      usage.should contain("--wait")
      usage.should contain("--verbose")
      usage.should contain("--version")
    end
  end

  describe "stress tests" do
    it "parses 15 argument combinations" do
      combos = [
        [] of String,
        ["--version"],
        ["-s", "16"],
        ["-n", "5"],
        ["-t", "30"],
        ["-w", "2"],
        ["-v"],
        ["-vv"],
        ["-v", "-v", "-v"],
        ["--config", "/tmp/test"],
        ["myapp.echo", "abcdef0123456789abcdef0123456789"],
        ["-s", "32", "-n", "3", "-t", "15", "-w", "1"],
        ["-v", "--config", "/tmp/x", "-s", "64"],
        ["--size", "128", "--probes", "10", "--timeout", "60", "--wait", "5"],
        ["-s", "16", "myapp.test", "1234567890abcdef1234567890abcdef"],
      ]

      combos.each do |combo|
        args = RNS::Rnprobe.parse_args(combo)
        args.should be_a(RNS::Rnprobe::Args)
      end
    end

    it "formats 20 probe replies" do
      dest = "abcdef0123456789abcdef0123456789".hexbytes
      (0...20).each do |i|
        rtt = (i + 1) * 0.1
        hops = (i % 5) + 1
        output = RNS::Rnprobe.format_probe_reply(dest, hops, rtt)
        output.should contain("Valid reply")
      end
    end

    it "formats probe summaries with varied loss rates" do
      (0..10).each do |replies|
        output = RNS::Rnprobe.format_probe_summary(10, replies)
        output.should contain("Sent 10")
        output.should contain("received #{replies}")
        output.should contain("packet loss")
      end
    end
  end
end
