require "../spec_helper"

describe RNS::Rnx do
  describe ".version_string" do
    it "includes rnx and version number" do
      str = RNS::Rnx.version_string
      str.should contain("rnx")
      str.should contain(RNS::VERSION)
    end
  end

  describe "constants" do
    it "has APP_NAME" do
      RNS::Rnx::APP_NAME.should eq "rnx"
    end

    it "has REMOTE_EXEC_GRACE" do
      RNS::Rnx::REMOTE_EXEC_GRACE.should eq 2.0
    end

    it "has SPINNER_SYMS" do
      RNS::Rnx::SPINNER_SYMS.size.should eq 7
    end
  end

  describe ".parse_args" do
    it "returns defaults with no arguments" do
      args = RNS::Rnx.parse_args([] of String)
      args.config.should be_nil
      args.verbose.should eq 0
      args.quiet.should eq 0
      args.print_identity.should be_false
      args.listen.should be_false
      args.identity.should be_nil
      args.interactive.should be_false
      args.no_announce.should be_false
      args.allowed.should be_empty
      args.noauth.should be_false
      args.noid.should be_false
      args.detailed.should be_false
      args.mirror.should be_false
      args.result_timeout.should be_nil
      args.stdin_data.should be_nil
      args.stdout_limit.should be_nil
      args.stderr_limit.should be_nil
      args.version.should be_false
      args.destination.should be_nil
      args.command.should be_nil
    end

    it "parses --config option" do
      args = RNS::Rnx.parse_args(["--config", "/tmp/test"])
      args.config.should eq "/tmp/test"
    end

    it "parses --version flag" do
      args = RNS::Rnx.parse_args(["--version"])
      args.version.should be_true
    end

    it "parses -v / --verbose (repeatable)" do
      args = RNS::Rnx.parse_args(["-v"])
      args.verbose.should eq 1

      args2 = RNS::Rnx.parse_args(["--verbose", "--verbose", "--verbose"])
      args2.verbose.should eq 3
    end

    it "parses -q / --quiet (repeatable)" do
      args = RNS::Rnx.parse_args(["-q"])
      args.quiet.should eq 1

      args2 = RNS::Rnx.parse_args(["--quiet", "--quiet"])
      args2.quiet.should eq 2
    end

    it "parses -p / --print-identity" do
      args = RNS::Rnx.parse_args(["-p"])
      args.print_identity.should be_true

      args2 = RNS::Rnx.parse_args(["--print-identity"])
      args2.print_identity.should be_true
    end

    it "parses -l / --listen" do
      args = RNS::Rnx.parse_args(["-l"])
      args.listen.should be_true

      args2 = RNS::Rnx.parse_args(["--listen"])
      args2.listen.should be_true
    end

    it "parses -i identity path" do
      args = RNS::Rnx.parse_args(["-i", "/path/to/identity"])
      args.identity.should eq "/path/to/identity"
    end

    it "parses -x / --interactive" do
      args = RNS::Rnx.parse_args(["-x"])
      args.interactive.should be_true

      args2 = RNS::Rnx.parse_args(["--interactive"])
      args2.interactive.should be_true
    end

    it "parses -b / --no-announce" do
      args = RNS::Rnx.parse_args(["-b"])
      args.no_announce.should be_true

      args2 = RNS::Rnx.parse_args(["--no-announce"])
      args2.no_announce.should be_true
    end

    it "parses -a allowed hashes (repeatable)" do
      args = RNS::Rnx.parse_args(["-a", "abc123", "-a", "def456"])
      args.allowed.should eq ["abc123", "def456"]
    end

    it "parses -n / --noauth" do
      args = RNS::Rnx.parse_args(["-n"])
      args.noauth.should be_true

      args2 = RNS::Rnx.parse_args(["--noauth"])
      args2.noauth.should be_true
    end

    it "parses -N / --noid" do
      args = RNS::Rnx.parse_args(["-N"])
      args.noid.should be_true

      args2 = RNS::Rnx.parse_args(["--noid"])
      args2.noid.should be_true
    end

    it "parses -d / --detailed" do
      args = RNS::Rnx.parse_args(["-d"])
      args.detailed.should be_true

      args2 = RNS::Rnx.parse_args(["--detailed"])
      args2.detailed.should be_true
    end

    it "parses -m mirror flag" do
      args = RNS::Rnx.parse_args(["-m"])
      args.mirror.should be_true
    end

    it "parses -w timeout" do
      args = RNS::Rnx.parse_args(["-w", "30.5"])
      args.timeout.should eq 30.5
    end

    it "parses -W result timeout" do
      args = RNS::Rnx.parse_args(["-W", "60.0"])
      args.result_timeout.should eq 60.0
    end

    it "parses --stdin" do
      args = RNS::Rnx.parse_args(["--stdin", "hello world"])
      args.stdin_data.should eq "hello world"
    end

    it "parses --stdout limit" do
      args = RNS::Rnx.parse_args(["--stdout", "4096"])
      args.stdout_limit.should eq 4096
    end

    it "parses --stderr limit" do
      args = RNS::Rnx.parse_args(["--stderr", "1024"])
      args.stderr_limit.should eq 1024
    end

    it "parses positional destination and command" do
      args = RNS::Rnx.parse_args(["a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4", "ls -la"])
      args.destination.should eq "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
      args.command.should eq "ls -la"
    end

    it "parses combined short flags" do
      args = RNS::Rnx.parse_args(["-vvqplxbnNdm"])
      args.verbose.should eq 2
      args.quiet.should eq 1
      args.print_identity.should be_true
      args.listen.should be_true
      args.interactive.should be_true
      args.no_announce.should be_true
      args.noauth.should be_true
      args.noid.should be_true
      args.detailed.should be_true
      args.mirror.should be_true
    end

    it "parses a full execute command" do
      args = RNS::Rnx.parse_args(["-v", "--config", "/etc/rns", "-m", "-d",
        "-w", "30", "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4", "uname -a"])
      args.verbose.should eq 1
      args.config.should eq "/etc/rns"
      args.mirror.should be_true
      args.detailed.should be_true
      args.timeout.should eq 30.0
      args.destination.should eq "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
      args.command.should eq "uname -a"
    end

    it "parses a full listen command" do
      args = RNS::Rnx.parse_args(["-l", "-n", "-b", "-a", "aabb"])
      args.listen.should be_true
      args.noauth.should be_true
      args.no_announce.should be_true
      args.allowed.should eq ["aabb"]
    end

    it "parses interactive execute with limits" do
      args = RNS::Rnx.parse_args(["-x", "-d", "--stdin", "input data",
        "--stdout", "8192", "--stderr", "4096", "-W", "120",
        "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4", "cat"])
      args.interactive.should be_true
      args.detailed.should be_true
      args.stdin_data.should eq "input data"
      args.stdout_limit.should eq 8192
      args.stderr_limit.should eq 4096
      args.result_timeout.should eq 120.0
      args.destination.should eq "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
      args.command.should eq "cat"
    end

    it "raises on unknown argument" do
      expect_raises(ArgumentError, /Unknown argument/) do
        RNS::Rnx.parse_args(["--unknown"])
      end
    end

    it "raises on extra positional arguments" do
      expect_raises(ArgumentError, /Unexpected positional/) do
        RNS::Rnx.parse_args(["dest", "cmd", "extra"])
      end
    end

    it "raises when --config missing value" do
      expect_raises(ArgumentError, /--config requires/) do
        RNS::Rnx.parse_args(["--config"])
      end
    end

    it "raises when -w missing value" do
      expect_raises(ArgumentError, /-w requires/) do
        RNS::Rnx.parse_args(["-w"])
      end
    end

    it "raises when --stdin missing value" do
      expect_raises(ArgumentError, /--stdin requires/) do
        RNS::Rnx.parse_args(["--stdin"])
      end
    end
  end

  describe ".parse_destination_hash" do
    it "parses valid 32-char hex string" do
      hex = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
      result = RNS::Rnx.parse_destination_hash(hex)
      result.size.should eq 16
      result.should eq hex.hexbytes
    end

    it "raises on invalid length" do
      expect_raises(ArgumentError, /invalid/) do
        RNS::Rnx.parse_destination_hash("abc123")
      end
    end

    it "raises on invalid hex characters" do
      expect_raises(ArgumentError, /Invalid destination/) do
        RNS::Rnx.parse_destination_hash("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")
      end
    end
  end

  describe ".size_str" do
    it "formats zero bytes" do
      RNS::Rnx.size_str(0).should eq "0 B"
    end

    it "formats small byte values" do
      RNS::Rnx.size_str(512).should eq "512 B"
    end

    it "formats kilobyte values" do
      RNS::Rnx.size_str(1500).should eq "1.50 KB"
    end

    it "formats megabyte values" do
      RNS::Rnx.size_str(1_500_000).should eq "1.50 MB"
    end

    it "formats bit values" do
      RNS::Rnx.size_str(1000, "b").should eq "8.00 Kb"
    end

    it "matches Python output for boundary values" do
      RNS::Rnx.size_str(999).should eq "999 B"
      RNS::Rnx.size_str(1000).should eq "1.00 KB"
    end
  end

  describe ".pretty_time" do
    it "formats seconds only" do
      RNS::Rnx.pretty_time(5.0).should eq "5.0s"
    end

    it "formats minutes and seconds" do
      RNS::Rnx.pretty_time(65.0).should eq "1m and 5.0s"
    end

    it "formats hours, minutes, seconds" do
      RNS::Rnx.pretty_time(3665.0).should eq "1h, 1m and 5.0s"
    end

    it "formats days" do
      RNS::Rnx.pretty_time(90061.0).should eq "1d, 1h, 1m and 1.0s"
    end

    it "uses plural forms correctly" do
      RNS::Rnx.pretty_time(1.0).should eq "1.0s"
      # Exact 1 second should be singular - but Python uses round(2) so 1.0
      RNS::Rnx.pretty_time(2.0).should eq "2.0s"
    end

    it "handles verbose mode" do
      RNS::Rnx.pretty_time(65.5, verbose: true).should eq "1 minute and 5.5 seconds"
    end

    it "handles verbose mode with plurals" do
      RNS::Rnx.pretty_time(7265.0, verbose: true).should eq "2 hours, 1 minute and 5.0 seconds"
    end

    it "handles zero" do
      RNS::Rnx.pretty_time(0.0).should eq ""
    end

    it "handles fractional seconds" do
      result = RNS::Rnx.pretty_time(0.75)
      result.should eq "0.75s"
    end

    it "handles exactly one of each unit (verbose)" do
      # 1 day + 1 hour + 1 minute + 1 second = 90061
      result = RNS::Rnx.pretty_time(90061.0, verbose: true)
      result.should contain("1 day")
      result.should contain("1 hour")
      result.should contain("1 minute")
      result.should contain("1.0 second")
      # Singular forms
      result.should_not contain("days")
      result.should_not contain("hours")
      result.should_not contain("minutes")
    end

    it "handles multiple of each unit (verbose)" do
      # 2 days + 3 hours + 4 minutes + 5 seconds = 183845
      result = RNS::Rnx.pretty_time(183845.0, verbose: true)
      result.should contain("2 days")
      result.should contain("3 hours")
      result.should contain("4 minutes")
      result.should contain("5.0 seconds")
    end
  end

  describe ".format_result" do
    it "formats successful execution with stdout" do
      result = [true, 0_i32, "hello\n".to_slice, Bytes.empty, 6_i32, 0_i32, 1000.0, 1001.0] of Bool | Int32? | Bytes? | Int64? | Float64?
      output, retval = RNS::Rnx.format_result(result, false, false, nil, nil)
      output.should eq "hello\n"
      retval.should eq 0
    end

    it "formats successful execution with stderr" do
      result = [true, 1_i32, Bytes.empty, "error\n".to_slice, 0_i32, 6_i32, 1000.0, 1001.0] of Bool | Int32? | Bytes? | Int64? | Float64?
      output, retval = RNS::Rnx.format_result(result, false, false, nil, nil)
      output.should eq "error\n"
      retval.should eq 1
    end

    it "formats failed execution" do
      result = [false, nil, nil, nil, nil, nil, 1000.0, nil] of Bool | Int32? | Bytes? | Int64? | Float64?
      output, retval = RNS::Rnx.format_result(result, false, false, nil, nil)
      output.should contain("could not execute")
      retval.should be_nil
    end

    it "formats detailed output with timing" do
      result = [true, 0_i32, "output".to_slice, Bytes.empty, 6_i32, 0_i32, 1000.0, 1002.5] of Bool | Int32? | Bytes? | Int64? | Float64?
      output, retval = RNS::Rnx.format_result(result, true, false, nil, nil)
      output.should contain("output")
      output.should contain("End of remote output")
      output.should contain("2.5 seconds")
      retval.should eq 0
    end

    it "formats detailed output with stdout byte counts" do
      result = [true, 0_i32, "ab".to_slice, Bytes.empty, 100_i32, 0_i32, 1000.0, 1001.0] of Bool | Int32? | Bytes? | Int64? | Float64?
      output, retval = RNS::Rnx.format_result(result, true, false, nil, nil)
      output.should contain("100 bytes to stdout")
      output.should contain("2 bytes displayed")
    end

    it "shows truncation warning in non-detailed mode" do
      # stdout was truncated: returned 10 bytes but total was 100
      result = [true, 0_i32, ("a" * 10).to_slice, Bytes.empty, 100_i32, 0_i32, 1000.0, 1001.0] of Bool | Int32? | Bytes? | Int64? | Float64?
      output, retval = RNS::Rnx.format_result(result, false, false, 10, nil)
      output.should contain("truncated")
      output.should contain("stdout truncated to 10 bytes")
    end

    it "no truncation warning when all data returned" do
      result = [true, 0_i32, "hello".to_slice, Bytes.empty, 5_i32, 0_i32, 1000.0, 1001.0] of Bool | Int32? | Bytes? | Int64? | Float64?
      output, retval = RNS::Rnx.format_result(result, false, false, nil, nil)
      output.should_not contain("truncated")
    end
  end

  describe ".usage_string" do
    it "contains usage information" do
      usage = RNS::Rnx.usage_string
      usage.should contain("Reticulum Remote Execution Utility")
      usage.should contain("destination")
      usage.should contain("command")
      usage.should contain("--listen")
      usage.should contain("--interactive")
      usage.should contain("--no-announce")
      usage.should contain("--noauth")
      usage.should contain("--noid")
      usage.should contain("--detailed")
      usage.should contain("--stdin")
      usage.should contain("--stdout")
      usage.should contain("--stderr")
    end
  end

  describe "stress tests" do
    it "parses 30 different valid argument combinations" do
      combos = [
        [] of String,
        ["--version"],
        ["-l"],
        ["-l", "-n"],
        ["-l", "-p"],
        ["-l", "-b"],
        ["-v", "-v", "-v"],
        ["-q", "-q"],
        ["--config", "/tmp"],
        ["-x"],
        ["-d"],
        ["-m"],
        ["-N"],
        ["-a", "hash1"],
        ["-a", "h1", "-a", "h2"],
        ["-i", "/id"],
        ["-w", "60"],
        ["-W", "120"],
        ["--stdin", "hello"],
        ["--stdout", "4096"],
        ["--stderr", "1024"],
        ["dest1", "cmd1"],
        ["-vvqplxbnNdm"],
        ["-l", "-n", "-b", "-a", "x"],
        ["-d", "-m", "-N", "dest", "cmd"],
        ["-v", "--config", "/etc", "d1", "cmd"],
        ["-x", "-d", "--stdin", "in", "d1", "cat"],
        ["--listen", "--noauth", "--no-announce"],
        ["--print-identity"],
        ["-l", "-a", "h1", "-a", "h2", "-a", "h3"],
      ]
      combos.each do |combo|
        args = RNS::Rnx.parse_args(combo)
        args.should_not be_nil
      end
    end

    it "size_str handles 20 different values" do
      values = [0, 1, 100, 500, 999, 1000, 1500, 10_000, 100_000,
                500_000, 1_000_000, 5_000_000, 10_000_000, 100_000_000,
                1_000_000_000_i64, 5_000_000_000_i64, 10_000_000_000_i64,
                100_000_000_000_i64, 1_000_000_000_000_i64, 5_000_000_000_000_i64]
      values.each do |v|
        result = RNS::Rnx.size_str(v)
        result.should_not be_empty
        result.should contain("B")
      end
    end

    it "pretty_time handles 20 different durations" do
      durations = [0.0, 0.5, 1.0, 2.5, 10.0, 30.0, 59.99, 60.0,
                   61.0, 120.0, 300.0, 600.0, 3600.0, 3661.0,
                   7200.0, 36000.0, 86400.0, 90061.0, 172800.0, 259200.0]
      durations.each do |d|
        result = RNS::Rnx.pretty_time(d)
        # Zero produces empty string, all others produce content
        if d > 0
          result.should_not be_empty
        end
      end
    end
  end
end
