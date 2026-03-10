require "../spec_helper"

describe RNS do
  describe "log level constants" do
    it "defines LOG_NONE as -1" do
      RNS::LOG_NONE.should eq(-1)
    end

    it "defines LOG_CRITICAL as 0" do
      RNS::LOG_CRITICAL.should eq(0)
    end

    it "defines LOG_ERROR as 1" do
      RNS::LOG_ERROR.should eq(1)
    end

    it "defines LOG_WARNING as 2" do
      RNS::LOG_WARNING.should eq(2)
    end

    it "defines LOG_NOTICE as 3" do
      RNS::LOG_NOTICE.should eq(3)
    end

    it "defines LOG_INFO as 4" do
      RNS::LOG_INFO.should eq(4)
    end

    it "defines LOG_VERBOSE as 5" do
      RNS::LOG_VERBOSE.should eq(5)
    end

    it "defines LOG_DEBUG as 6" do
      RNS::LOG_DEBUG.should eq(6)
    end

    it "defines LOG_EXTREME as 7" do
      RNS::LOG_EXTREME.should eq(7)
    end
  end

  describe "log destination constants" do
    it "defines LOG_STDOUT as 0x91" do
      RNS::LOG_STDOUT.should eq(0x91)
    end

    it "defines LOG_FILE as 0x92" do
      RNS::LOG_FILE.should eq(0x92)
    end

    it "defines LOG_CALLBACK as 0x93" do
      RNS::LOG_CALLBACK.should eq(0x93)
    end
  end

  describe "LOG_MAXSIZE" do
    it "is 5 MB" do
      RNS::LOG_MAXSIZE.should eq(5 * 1024 * 1024)
    end
  end

  describe ".loglevelname" do
    it "returns [Critical] for LOG_CRITICAL" do
      RNS.loglevelname(RNS::LOG_CRITICAL).should eq("[Critical]")
    end

    it "returns [Error]    for LOG_ERROR" do
      RNS.loglevelname(RNS::LOG_ERROR).should eq("[Error]   ")
    end

    it "returns [Warning]  for LOG_WARNING" do
      RNS.loglevelname(RNS::LOG_WARNING).should eq("[Warning] ")
    end

    it "returns [Notice]   for LOG_NOTICE" do
      RNS.loglevelname(RNS::LOG_NOTICE).should eq("[Notice]  ")
    end

    it "returns [Info]     for LOG_INFO" do
      RNS.loglevelname(RNS::LOG_INFO).should eq("[Info]    ")
    end

    it "returns [Verbose]  for LOG_VERBOSE" do
      RNS.loglevelname(RNS::LOG_VERBOSE).should eq("[Verbose] ")
    end

    it "returns [Debug]    for LOG_DEBUG" do
      RNS.loglevelname(RNS::LOG_DEBUG).should eq("[Debug]   ")
    end

    it "returns [Extra]    for LOG_EXTREME" do
      RNS.loglevelname(RNS::LOG_EXTREME).should eq("[Extra]   ")
    end

    it "returns Unknown for invalid level" do
      RNS.loglevelname(99).should eq("Unknown")
    end
  end

  describe ".log" do
    it "logs to callback when logdest is LOG_CALLBACK" do
      original_dest = RNS.logdest
      original_level = RNS.loglevel
      captured = [] of String

      RNS.logdest = RNS::LOG_CALLBACK
      RNS.loglevel = RNS::LOG_EXTREME
      RNS.logcall = ->(msg : String) { captured << msg }

      RNS.log("test message", RNS::LOG_NOTICE)

      captured.size.should eq(1)
      captured[0].should contain("test message")
      captured[0].should contain("[Notice]")

      # Restore
      RNS.logdest = original_dest
      RNS.loglevel = original_level
      RNS.logcall = nil
    end

    it "does not log when level is above loglevel" do
      original_dest = RNS.logdest
      original_level = RNS.loglevel
      captured = [] of String

      RNS.logdest = RNS::LOG_CALLBACK
      RNS.loglevel = RNS::LOG_ERROR
      RNS.logcall = ->(msg : String) { captured << msg }

      RNS.log("should not appear", RNS::LOG_INFO)

      captured.size.should eq(0)

      # Restore
      RNS.logdest = original_dest
      RNS.loglevel = original_level
      RNS.logcall = nil
    end

    it "does not log when loglevel is LOG_NONE" do
      original_dest = RNS.logdest
      original_level = RNS.loglevel
      captured = [] of String

      RNS.logdest = RNS::LOG_CALLBACK
      RNS.loglevel = RNS::LOG_NONE
      RNS.logcall = ->(msg : String) { captured << msg }

      RNS.log("should not appear", RNS::LOG_CRITICAL)

      captured.size.should eq(0)

      # Restore
      RNS.logdest = original_dest
      RNS.loglevel = original_level
      RNS.logcall = nil
    end

    it "defaults to LOG_NOTICE level" do
      original_dest = RNS.logdest
      original_level = RNS.loglevel
      captured = [] of String

      RNS.logdest = RNS::LOG_CALLBACK
      RNS.loglevel = RNS::LOG_NOTICE
      RNS.logcall = ->(msg : String) { captured << msg }

      RNS.log("default level message")

      captured.size.should eq(1)

      # Restore
      RNS.logdest = original_dest
      RNS.loglevel = original_level
      RNS.logcall = nil
    end

    it "includes timestamp in log output" do
      original_dest = RNS.logdest
      original_level = RNS.loglevel
      captured = [] of String

      RNS.logdest = RNS::LOG_CALLBACK
      RNS.loglevel = RNS::LOG_EXTREME
      RNS.logcall = ->(msg : String) { captured << msg }

      RNS.log("timestamp test", RNS::LOG_NOTICE)

      captured.size.should eq(1)
      # Should start with [YYYY-MM-DD HH:MM:SS]
      captured[0].should match(/^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]/)

      # Restore
      RNS.logdest = original_dest
      RNS.loglevel = original_level
      RNS.logcall = nil
    end

    it "logs to file when logdest is LOG_FILE" do
      original_dest = RNS.logdest
      original_level = RNS.loglevel
      original_file = RNS.logfile

      tempfile = File.tempname("rns_log_test", ".log")
      begin
        RNS.logdest = RNS::LOG_FILE
        RNS.loglevel = RNS::LOG_EXTREME
        RNS.logfile = tempfile

        RNS.log("file log test", RNS::LOG_NOTICE)

        File.exists?(tempfile).should be_true
        content = File.read(tempfile)
        content.should contain("file log test")
        content.should contain("[Notice]")
      ensure
        File.delete(tempfile) if File.exists?(tempfile)
        RNS.logdest = original_dest
        RNS.loglevel = original_level
        RNS.logfile = original_file
      end
    end

    it "supports compact log format" do
      original_dest = RNS.logdest
      original_level = RNS.loglevel
      original_compact = RNS.compact_log_fmt
      captured = [] of String

      RNS.logdest = RNS::LOG_CALLBACK
      RNS.loglevel = RNS::LOG_EXTREME
      RNS.compact_log_fmt = true
      RNS.logcall = ->(msg : String) { captured << msg }

      RNS.log("compact test", RNS::LOG_NOTICE)

      captured.size.should eq(1)
      # Compact format should NOT include the level name
      captured[0].should_not contain("[Notice]")
      captured[0].should contain("compact test")

      # Restore
      RNS.logdest = original_dest
      RNS.loglevel = original_level
      RNS.compact_log_fmt = original_compact
      RNS.logcall = nil
    end
  end

  describe ".timestamp_str" do
    it "formats a time value as YYYY-MM-DD HH:MM:SS" do
      # Use a known time
      result = RNS.timestamp_str(0.0) # epoch
      result.should match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
    end
  end

  describe ".host_os" do
    it "returns the platform string" do
      os = RNS.host_os
      os.should be_a(String)
      os.should_not be_empty
    end
  end

  describe ".rand" do
    it "returns a Float64 between 0 and 1" do
      100.times do
        val = RNS.rand
        val.should be >= 0.0
        val.should be < 1.0
      end
    end

    it "returns different values on successive calls" do
      values = (0...10).map { RNS.rand }
      values.uniq.size.should be > 1
    end
  end
end
