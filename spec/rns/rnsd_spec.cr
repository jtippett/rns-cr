require "../spec_helper"

# Rnsd spec tests the daemon module's argument parsing, example config output,
# and program_setup logic. We cannot fully integration-test the daemon (it
# loops forever), so we test the components that make up the daemon.

describe RNS::Rnsd do
  describe ".example_config" do
    it "returns a non-empty string" do
      config = RNS::Rnsd.example_config
      config.should be_a(String)
      config.size.should be > 100
    end

    it "contains [reticulum] section" do
      config = RNS::Rnsd.example_config
      config.should contain("[reticulum]")
    end

    it "contains [logging] section" do
      config = RNS::Rnsd.example_config
      config.should contain("[logging]")
    end

    it "contains [interfaces] section" do
      config = RNS::Rnsd.example_config
      config.should contain("[interfaces]")
    end

    it "contains AutoInterface example" do
      config = RNS::Rnsd.example_config
      config.should contain("AutoInterface")
    end

    it "contains TCP interface examples" do
      config = RNS::Rnsd.example_config
      config.should contain("TCPServerInterface")
      config.should contain("TCPClientInterface")
    end

    it "contains UDP interface example" do
      config = RNS::Rnsd.example_config
      config.should contain("UDPInterface")
    end

    it "contains RNode interface example" do
      config = RNS::Rnsd.example_config
      config.should contain("RNodeInterface")
    end

    it "contains KISS interface examples" do
      config = RNS::Rnsd.example_config
      config.should contain("KISSInterface")
      config.should contain("AX25KISSInterface")
    end

    it "contains I2P interface example" do
      config = RNS::Rnsd.example_config
      config.should contain("I2PInterface")
    end
  end

  describe ".parse_args" do
    it "returns defaults with no arguments" do
      args = RNS::Rnsd.parse_args([] of String)
      args.config.should be_nil
      args.verbose.should eq 0
      args.quiet.should eq 0
      args.service.should be_false
      args.interactive.should be_false
      args.example_config.should be_false
      args.version.should be_false
    end

    it "parses --config option" do
      args = RNS::Rnsd.parse_args(["--config", "/tmp/test_config"])
      args.config.should eq "/tmp/test_config"
    end

    it "parses -v for verbosity" do
      args = RNS::Rnsd.parse_args(["-v"])
      args.verbose.should eq 1
    end

    it "parses multiple -v flags" do
      args = RNS::Rnsd.parse_args(["-vvv"])
      args.verbose.should eq 3
    end

    it "parses -q for quietness" do
      args = RNS::Rnsd.parse_args(["-q"])
      args.quiet.should eq 1
    end

    it "parses multiple -q flags" do
      args = RNS::Rnsd.parse_args(["-qqq"])
      args.quiet.should eq 3
    end

    it "parses -s / --service flag" do
      args = RNS::Rnsd.parse_args(["-s"])
      args.service.should be_true

      args2 = RNS::Rnsd.parse_args(["--service"])
      args2.service.should be_true
    end

    it "parses -i / --interactive flag" do
      args = RNS::Rnsd.parse_args(["-i"])
      args.interactive.should be_true

      args2 = RNS::Rnsd.parse_args(["--interactive"])
      args2.interactive.should be_true
    end

    it "parses --exampleconfig flag" do
      args = RNS::Rnsd.parse_args(["--exampleconfig"])
      args.example_config.should be_true
    end

    it "parses --version flag" do
      args = RNS::Rnsd.parse_args(["--version"])
      args.version.should be_true
    end

    it "parses combined flags" do
      args = RNS::Rnsd.parse_args(["-vvqs", "--config", "/tmp/cfg"])
      args.verbose.should eq 2
      args.quiet.should eq 1
      args.service.should be_true
      args.config.should eq "/tmp/cfg"
    end

    it "parses --join with a token argument" do
      args = RNS::Rnsd.parse_args(["--join", "AEBQ4DIZQ"])
      args.join_token.should eq("AEBQ4DIZQ")
    end

    it "defaults join_token to nil" do
      args = RNS::Rnsd.parse_args([] of String)
      args.join_token.should be_nil
    end
  end

  describe ".compute_verbosity" do
    it "returns verbosity minus quietness" do
      args = RNS::Rnsd.parse_args(["-vvq"])
      verbosity = RNS::Rnsd.compute_verbosity(args)
      verbosity.should eq 1
    end

    it "returns nil when service mode is enabled" do
      args = RNS::Rnsd.parse_args(["-vs"])
      verbosity = RNS::Rnsd.compute_verbosity(args)
      verbosity.should be_nil
    end

    it "returns 0 when no flags are specified" do
      args = RNS::Rnsd.parse_args([] of String)
      verbosity = RNS::Rnsd.compute_verbosity(args)
      verbosity.should eq 0
    end
  end

  describe ".compute_logdest" do
    it "returns LOG_STDOUT by default" do
      args = RNS::Rnsd.parse_args([] of String)
      dest = RNS::Rnsd.compute_logdest(args)
      dest.should eq RNS::LOG_STDOUT
    end

    it "returns LOG_FILE when service flag is set" do
      args = RNS::Rnsd.parse_args(["-s"])
      dest = RNS::Rnsd.compute_logdest(args)
      dest.should eq RNS::LOG_FILE
    end
  end

  describe ".version_string" do
    it "includes rnsd and version number" do
      str = RNS::Rnsd.version_string
      str.should contain("rnsd")
      str.should contain(RNS::VERSION)
    end
  end
end
