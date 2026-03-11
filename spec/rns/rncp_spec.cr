require "../spec_helper"

describe RNS::Rncp do
  describe ".version_string" do
    it "includes rncp and version number" do
      str = RNS::Rncp.version_string
      str.should contain("rncp")
      str.should contain(RNS::VERSION)
    end
  end

  describe "constants" do
    it "has APP_NAME" do
      RNS::Rncp::APP_NAME.should eq "rncp"
    end

    it "has REQ_FETCH_NOT_ALLOWED" do
      RNS::Rncp::REQ_FETCH_NOT_ALLOWED.should eq 0xF0_u8
    end

    it "has SPINNER_SYMS" do
      RNS::Rncp::SPINNER_SYMS.size.should eq 7
    end

    it "has ERASE_STR" do
      RNS::Rncp::ERASE_STR.should contain("\33[2K")
    end
  end

  describe ".parse_args" do
    it "returns defaults with no arguments" do
      args = RNS::Rncp.parse_args([] of String)
      args.config.should be_nil
      args.verbose.should eq 0
      args.quiet.should eq 0
      args.silent.should be_false
      args.listen.should be_false
      args.no_compress.should be_false
      args.allow_fetch.should be_false
      args.fetch.should be_false
      args.jail.should be_nil
      args.save.should be_nil
      args.overwrite.should be_false
      args.announce.should eq(-1)
      args.allowed.should be_empty
      args.no_auth.should be_false
      args.print_identity.should be_false
      args.identity.should be_nil
      args.phy_rates.should be_false
      args.version.should be_false
      args.file.should be_nil
      args.destination.should be_nil
    end

    it "parses --config option" do
      args = RNS::Rncp.parse_args(["--config", "/tmp/test"])
      args.config.should eq "/tmp/test"
    end

    it "parses --version flag" do
      args = RNS::Rncp.parse_args(["--version"])
      args.version.should be_true
    end

    it "parses -v / --verbose (repeatable)" do
      args = RNS::Rncp.parse_args(["-v"])
      args.verbose.should eq 1

      args2 = RNS::Rncp.parse_args(["--verbose", "--verbose"])
      args2.verbose.should eq 2
    end

    it "parses -q / --quiet (repeatable)" do
      args = RNS::Rncp.parse_args(["-q"])
      args.quiet.should eq 1

      args2 = RNS::Rncp.parse_args(["--quiet", "--quiet", "--quiet"])
      args2.quiet.should eq 3
    end

    it "parses -S / --silent" do
      args = RNS::Rncp.parse_args(["-S"])
      args.silent.should be_true

      args2 = RNS::Rncp.parse_args(["--silent"])
      args2.silent.should be_true
    end

    it "parses -l / --listen" do
      args = RNS::Rncp.parse_args(["-l"])
      args.listen.should be_true

      args2 = RNS::Rncp.parse_args(["--listen"])
      args2.listen.should be_true
    end

    it "parses -C / --no-compress" do
      args = RNS::Rncp.parse_args(["-C"])
      args.no_compress.should be_true

      args2 = RNS::Rncp.parse_args(["--no-compress"])
      args2.no_compress.should be_true
    end

    it "parses -F / --allow-fetch" do
      args = RNS::Rncp.parse_args(["-F"])
      args.allow_fetch.should be_true

      args2 = RNS::Rncp.parse_args(["--allow-fetch"])
      args2.allow_fetch.should be_true
    end

    it "parses -f / --fetch" do
      args = RNS::Rncp.parse_args(["-f"])
      args.fetch.should be_true

      args2 = RNS::Rncp.parse_args(["--fetch"])
      args2.fetch.should be_true
    end

    it "parses -j / --jail with path" do
      args = RNS::Rncp.parse_args(["-j", "/home/user/files"])
      args.jail.should eq "/home/user/files"

      args2 = RNS::Rncp.parse_args(["--jail", "/tmp/jail"])
      args2.jail.should eq "/tmp/jail"
    end

    it "parses -s / --save with path" do
      args = RNS::Rncp.parse_args(["-s", "/tmp/output"])
      args.save.should eq "/tmp/output"

      args2 = RNS::Rncp.parse_args(["--save", "/home/downloads"])
      args2.save.should eq "/home/downloads"
    end

    it "parses -O / --overwrite" do
      args = RNS::Rncp.parse_args(["-O"])
      args.overwrite.should be_true

      args2 = RNS::Rncp.parse_args(["--overwrite"])
      args2.overwrite.should be_true
    end

    it "parses -b announce interval" do
      args = RNS::Rncp.parse_args(["-b", "30"])
      args.announce.should eq 30

      args2 = RNS::Rncp.parse_args(["-b", "0"])
      args2.announce.should eq 0
    end

    it "parses -a allowed hashes (repeatable)" do
      args = RNS::Rncp.parse_args(["-a", "abc123", "-a", "def456"])
      args.allowed.should eq ["abc123", "def456"]
    end

    it "parses -n / --no-auth" do
      args = RNS::Rncp.parse_args(["-n"])
      args.no_auth.should be_true

      args2 = RNS::Rncp.parse_args(["--no-auth"])
      args2.no_auth.should be_true
    end

    it "parses -p / --print-identity" do
      args = RNS::Rncp.parse_args(["-p"])
      args.print_identity.should be_true

      args2 = RNS::Rncp.parse_args(["--print-identity"])
      args2.print_identity.should be_true
    end

    it "parses -i identity path" do
      args = RNS::Rncp.parse_args(["-i", "/path/to/identity"])
      args.identity.should eq "/path/to/identity"
    end

    it "parses -w timeout" do
      args = RNS::Rncp.parse_args(["-w", "30.5"])
      args.timeout.should eq 30.5
    end

    it "parses -P / --phy-rates" do
      args = RNS::Rncp.parse_args(["-P"])
      args.phy_rates.should be_true

      args2 = RNS::Rncp.parse_args(["--phy-rates"])
      args2.phy_rates.should be_true
    end

    it "parses positional file and destination" do
      args = RNS::Rncp.parse_args(["myfile.txt", "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"])
      args.file.should eq "myfile.txt"
      args.destination.should eq "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
    end

    it "parses combined short flags" do
      args = RNS::Rncp.parse_args(["-vvqSlCFfOnpP"])
      args.verbose.should eq 2
      args.quiet.should eq 1
      args.silent.should be_true
      args.listen.should be_true
      args.no_compress.should be_true
      args.allow_fetch.should be_true
      args.fetch.should be_true
      args.overwrite.should be_true
      args.no_auth.should be_true
      args.print_identity.should be_true
      args.phy_rates.should be_true
    end

    it "parses a full send command" do
      args = RNS::Rncp.parse_args(["-v", "--config", "/etc/rns", "-w", "30",
        "test.dat", "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"])
      args.verbose.should eq 1
      args.config.should eq "/etc/rns"
      args.timeout.should eq 30.0
      args.file.should eq "test.dat"
      args.destination.should eq "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
    end

    it "parses a full listen command" do
      args = RNS::Rncp.parse_args(["-l", "-F", "-j", "/tmp/files", "-s", "/tmp/recv",
        "-a", "aabb", "-n", "-b", "60"])
      args.listen.should be_true
      args.allow_fetch.should be_true
      args.jail.should eq "/tmp/files"
      args.save.should eq "/tmp/recv"
      args.allowed.should eq ["aabb"]
      args.no_auth.should be_true
      args.announce.should eq 60
    end

    it "parses a full fetch command" do
      args = RNS::Rncp.parse_args(["-f", "-s", "/tmp/out", "-O",
        "remote_file.bin", "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"])
      args.fetch.should be_true
      args.save.should eq "/tmp/out"
      args.overwrite.should be_true
      args.file.should eq "remote_file.bin"
      args.destination.should eq "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
    end

    it "raises on unknown argument" do
      expect_raises(ArgumentError, /Unknown argument/) do
        RNS::Rncp.parse_args(["--unknown"])
      end
    end

    it "raises on extra positional arguments" do
      expect_raises(ArgumentError, /Unexpected positional/) do
        RNS::Rncp.parse_args(["file1", "dest1", "extra"])
      end
    end

    it "raises when --config missing value" do
      expect_raises(ArgumentError, /--config requires/) do
        RNS::Rncp.parse_args(["--config"])
      end
    end

    it "raises when -j missing value" do
      expect_raises(ArgumentError, /--jail requires/) do
        RNS::Rncp.parse_args(["-j"])
      end
    end

    it "raises when -b missing value" do
      expect_raises(ArgumentError, /-b requires/) do
        RNS::Rncp.parse_args(["-b"])
      end
    end
  end

  describe ".parse_destination_hash" do
    it "parses valid 32-char hex string" do
      hex = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
      result = RNS::Rncp.parse_destination_hash(hex)
      result.size.should eq 16
      result.should eq hex.hexbytes
    end

    it "raises on invalid length" do
      expect_raises(ArgumentError, /invalid/) do
        RNS::Rncp.parse_destination_hash("abc123")
      end
    end

    it "raises on invalid hex characters" do
      expect_raises(ArgumentError, /Invalid destination/) do
        RNS::Rncp.parse_destination_hash("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")
      end
    end
  end

  describe ".size_str" do
    it "formats zero bytes" do
      RNS::Rncp.size_str(0).should eq "0 B"
    end

    it "formats small byte values" do
      RNS::Rncp.size_str(512).should eq "512 B"
    end

    it "formats kilobyte values" do
      RNS::Rncp.size_str(1500).should eq "1.50 KB"
    end

    it "formats megabyte values" do
      RNS::Rncp.size_str(1_500_000).should eq "1.50 MB"
    end

    it "formats gigabyte values" do
      RNS::Rncp.size_str(1_500_000_000_i64).should eq "1.50 GB"
    end

    it "formats bit values when suffix is 'b'" do
      # 1000 bytes = 8000 bits = 8.00 Kb
      RNS::Rncp.size_str(1000, "b").should eq "8.00 Kb"
    end

    it "formats zero bits" do
      RNS::Rncp.size_str(0, "b").should eq "0 b"
    end

    it "handles negative values" do
      result = RNS::Rncp.size_str(-512)
      result.should eq "-512 B"
    end

    it "formats terabyte values" do
      RNS::Rncp.size_str(2_000_000_000_000_i64).should eq "2.00 TB"
    end

    it "matches Python output for 100 bytes" do
      RNS::Rncp.size_str(100).should eq "100 B"
    end

    it "matches Python output for 999 bytes" do
      RNS::Rncp.size_str(999).should eq "999 B"
    end

    it "matches Python output for 1000 bytes" do
      RNS::Rncp.size_str(1000).should eq "1.00 KB"
    end

    it "formats float values" do
      RNS::Rncp.size_str(1234.56).should eq "1.23 KB"
    end
  end

  describe ".format_progress" do
    it "formats basic progress" do
      result = RNS::Rncp.format_progress(50.0, "500 B", "1.00 KB", "100 B")
      result.should eq "50.0% - 500 B of 1.00 KB - 100 Bps"
    end

    it "formats progress with phy_str" do
      result = RNS::Rncp.format_progress(75.5, "756 B", "1.00 KB", "200 B", " (1.60 Kbps at physical layer)")
      result.should contain("at physical layer")
    end
  end

  describe ".format_transfer_complete" do
    it "formats complete transfer" do
      result = RNS::Rncp.format_transfer_complete(100.0, "1.00 KB", "1.00 KB", "2.5s", "400 B")
      result.should eq "100.0% - 1.00 KB of 1.00 KB in 2.5s - 400 Bps"
    end
  end

  describe ".usage_string" do
    it "contains usage information" do
      usage = RNS::Rncp.usage_string
      usage.should contain("Reticulum File Transfer Utility")
      usage.should contain("file")
      usage.should contain("destination")
      usage.should contain("--listen")
      usage.should contain("--fetch")
      usage.should contain("--allow-fetch")
      usage.should contain("--jail")
      usage.should contain("--save")
      usage.should contain("--no-compress")
      usage.should contain("--phy-rates")
    end
  end

  describe "stress tests" do
    it "parses 30 different valid argument combinations" do
      combos = [
        [] of String,
        ["--version"],
        ["-l"],
        ["-l", "-F"],
        ["-l", "-n"],
        ["-l", "-p"],
        ["-f", "file", "dest"],
        ["-v", "-v", "-v"],
        ["-q", "-q"],
        ["--config", "/tmp"],
        ["-S"],
        ["-C"],
        ["-O"],
        ["-P"],
        ["-b", "10"],
        ["-b", "0"],
        ["-a", "hash1"],
        ["-a", "h1", "-a", "h2"],
        ["-i", "/id"],
        ["-w", "60"],
        ["-j", "/jail"],
        ["-s", "/save"],
        ["file.txt", "abcdef"],
        ["-vvqSlCFfOnpP"],
        ["-l", "-F", "-j", "/jail", "-n"],
        ["-f", "-s", "/out", "-O"],
        ["-v", "--config", "/etc", "f.bin", "d1"],
        ["-l", "-b", "30", "-a", "x"],
        ["--silent", "--no-compress", "--fetch"],
        ["--listen", "--allow-fetch", "--no-auth", "--print-identity"],
      ]
      combos.each do |combo|
        args = RNS::Rncp.parse_args(combo)
        args.should_not be_nil
      end
    end

    it "size_str handles 20 different values correctly" do
      values = [0, 1, 100, 500, 999, 1000, 1500, 10_000, 100_000,
                500_000, 1_000_000, 5_000_000, 10_000_000, 100_000_000,
                1_000_000_000_i64, 5_000_000_000_i64, 10_000_000_000_i64,
                100_000_000_000_i64, 1_000_000_000_000_i64, 5_000_000_000_000_i64]
      values.each do |v|
        result = RNS::Rncp.size_str(v)
        result.should_not be_empty
        result.should contain("B")
      end
    end

    it "size_str handles 20 different bit values" do
      values = [0, 1, 100, 500, 999, 1000, 1500, 10_000, 100_000,
                500_000, 1_000_000, 5_000_000, 10_000_000, 100_000_000,
                1_000_000_000_i64, 5_000_000_000_i64, 10_000_000_000_i64,
                100_000_000_000_i64, 1_000_000_000_000_i64, 5_000_000_000_000_i64]
      values.each do |v|
        result = RNS::Rncp.size_str(v, "b")
        result.should_not be_empty
        result.should contain("b")
      end
    end
  end
end
