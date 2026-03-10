require "../../spec_helper"
require "../../../src/rns/vendor/config_obj"

describe RNS::ConfigObj do
  describe ".new (empty)" do
    it "creates an empty config" do
      config = RNS::ConfigObj.new
      config.size.should eq(0)
      config.sections.should be_empty
      config.scalars.should be_empty
    end
  end

  describe "parsing from string lines" do
    it "parses simple key = value pairs" do
      lines = [
        "key1 = value1",
        "key2 = value2",
      ]
      config = RNS::ConfigObj.new(lines)
      config["key1"].should eq("value1")
      config["key2"].should eq("value2")
    end

    it "parses values with leading/trailing whitespace trimmed" do
      lines = [
        "key =   hello world  ",
      ]
      config = RNS::ConfigObj.new(lines)
      config["key"].should eq("hello world")
    end

    it "handles quoted string values (double quotes)" do
      lines = [
        "key = \"hello world\"",
      ]
      config = RNS::ConfigObj.new(lines)
      config["key"].should eq("hello world")
    end

    it "handles quoted string values (single quotes)" do
      lines = [
        "key = 'hello world'",
      ]
      config = RNS::ConfigObj.new(lines)
      config["key"].should eq("hello world")
    end

    it "ignores comment lines" do
      lines = [
        "# This is a comment",
        "key = value",
        "  # Another comment",
      ]
      config = RNS::ConfigObj.new(lines)
      config["key"].should eq("value")
      config.size.should eq(1)
    end

    it "ignores blank lines" do
      lines = [
        "",
        "key = value",
        "",
        "key2 = value2",
        "",
      ]
      config = RNS::ConfigObj.new(lines)
      config["key"].should eq("value")
      config["key2"].should eq("value2")
    end

    it "handles inline comments" do
      lines = [
        "key = value # this is a comment",
      ]
      config = RNS::ConfigObj.new(lines)
      config["key"].should eq("value")
    end

    it "parses empty string values as empty string" do
      lines = [
        "key = \"\"",
      ]
      config = RNS::ConfigObj.new(lines)
      config["key"].should eq("")
    end
  end

  describe "sections" do
    it "parses top-level sections" do
      lines = [
        "[section1]",
        "key1 = value1",
        "[section2]",
        "key2 = value2",
      ]
      config = RNS::ConfigObj.new(lines)
      config.sections.should eq(["section1", "section2"])
      section1 = config.section("section1")
      section1["key1"].should eq("value1")
      section2 = config.section("section2")
      section2["key2"].should eq("value2")
    end

    it "parses nested sections with double brackets" do
      lines = [
        "[interfaces]",
        "  [[Default Interface]]",
        "    type = AutoInterface",
        "    enabled = Yes",
        "  [[TCP Interface]]",
        "    type = TCPServerInterface",
        "    listen_port = 7000",
      ]
      config = RNS::ConfigObj.new(lines)
      interfaces = config.section("interfaces")
      interfaces.sections.should eq(["Default Interface", "TCP Interface"])

      default_if = interfaces.section("Default Interface")
      default_if["type"].should eq("AutoInterface")
      default_if["enabled"].should eq("Yes")

      tcp_if = interfaces.section("TCP Interface")
      tcp_if["type"].should eq("TCPServerInterface")
      tcp_if["listen_port"].should eq("7000")
    end

    it "handles deeply nested sections" do
      lines = [
        "[level1]",
        "  [[level2]]",
        "    [[[level3]]]",
        "      key = deep_value",
      ]
      config = RNS::ConfigObj.new(lines)
      l1 = config.section("level1")
      l2 = l1.section("level2")
      l3 = l2.section("level3")
      l3["key"].should eq("deep_value")
    end

    it "handles sibling sections at the same depth" do
      lines = [
        "[parent]",
        "  [[child1]]",
        "    key1 = val1",
        "  [[child2]]",
        "    key2 = val2",
      ]
      config = RNS::ConfigObj.new(lines)
      parent = config.section("parent")
      parent.sections.size.should eq(2)
      parent.section("child1")["key1"].should eq("val1")
      parent.section("child2")["key2"].should eq("val2")
    end

    it "returns section depth correctly" do
      lines = [
        "[section]",
        "  [[subsection]]",
        "    key = value",
      ]
      config = RNS::ConfigObj.new(lines)
      config.depth.should eq(0)
      config.section("section").depth.should eq(1)
      config.section("section").section("subsection").depth.should eq(2)
    end
  end

  describe "iterating over sections" do
    it "iterates over subsection names within an interfaces section" do
      lines = [
        "[interfaces]",
        "  [[Interface A]]",
        "    type = UDPInterface",
        "  [[Interface B]]",
        "    type = TCPServerInterface",
      ]
      config = RNS::ConfigObj.new(lines)
      interfaces = config.section("interfaces")
      names = [] of String
      interfaces.sections.each { |name| names << name }
      names.should eq(["Interface A", "Interface B"])
    end
  end

  describe "type conversion" do
    describe "#as_bool" do
      it "converts 'Yes' to true" do
        config = RNS::ConfigObj.new(["key = Yes"])
        config.as_bool("key").should be_true
      end

      it "converts 'yes' to true (case insensitive)" do
        config = RNS::ConfigObj.new(["key = yes"])
        config.as_bool("key").should be_true
      end

      it "converts 'No' to false" do
        config = RNS::ConfigObj.new(["key = No"])
        config.as_bool("key").should be_false
      end

      it "converts 'no' to false (case insensitive)" do
        config = RNS::ConfigObj.new(["key = no"])
        config.as_bool("key").should be_false
      end

      it "converts 'True' to true" do
        config = RNS::ConfigObj.new(["key = True"])
        config.as_bool("key").should be_true
      end

      it "converts 'False' to false" do
        config = RNS::ConfigObj.new(["key = False"])
        config.as_bool("key").should be_false
      end

      it "converts 'On' to true" do
        config = RNS::ConfigObj.new(["key = On"])
        config.as_bool("key").should be_true
      end

      it "converts 'Off' to false" do
        config = RNS::ConfigObj.new(["key = Off"])
        config.as_bool("key").should be_false
      end

      it "converts '1' to true" do
        config = RNS::ConfigObj.new(["key = 1"])
        config.as_bool("key").should be_true
      end

      it "converts '0' to false" do
        config = RNS::ConfigObj.new(["key = 0"])
        config.as_bool("key").should be_false
      end

      it "raises ValueError for invalid bool" do
        config = RNS::ConfigObj.new(["key = fish"])
        expect_raises(RNS::ConfigObj::ValueError) do
          config.as_bool("key")
        end
      end
    end

    describe "#as_int" do
      it "converts string to integer" do
        config = RNS::ConfigObj.new(["key = 42"])
        config.as_int("key").should eq(42)
      end

      it "converts negative integer" do
        config = RNS::ConfigObj.new(["key = -7"])
        config.as_int("key").should eq(-7)
      end

      it "raises on invalid integer" do
        config = RNS::ConfigObj.new(["key = fish"])
        expect_raises(ArgumentError) do
          config.as_int("key")
        end
      end
    end

    describe "#as_float" do
      it "converts string to float" do
        config = RNS::ConfigObj.new(["key = 3.14"])
        config.as_float("key").should be_close(3.14, 0.001)
      end

      it "converts integer string to float" do
        config = RNS::ConfigObj.new(["key = 1"])
        config.as_float("key").should eq(1.0)
      end

      it "raises on invalid float" do
        config = RNS::ConfigObj.new(["key = fish"])
        expect_raises(ArgumentError) do
          config.as_float("key")
        end
      end
    end

    describe "#as_list" do
      it "wraps a single value in an array" do
        config = RNS::ConfigObj.new(["key = single_value"])
        config.as_list("key").should eq(["single_value"])
      end

      it "parses comma-separated list values" do
        config = RNS::ConfigObj.new(["key = a, b, c"])
        config.as_list("key").should eq(["a", "b", "c"])
      end

      it "returns already-parsed list as-is" do
        config = RNS::ConfigObj.new(["key = item1, item2"])
        result = config.as_list("key")
        result.should eq(["item1", "item2"])
      end

      it "handles empty list (single comma)" do
        config = RNS::ConfigObj.new(["key = ,"])
        config.as_list("key").should be_empty
      end

      it "handles single-element list with trailing comma" do
        config = RNS::ConfigObj.new(["key = single,"])
        config.as_list("key").should eq(["single"])
      end
    end
  end

  describe "dictionary-like access" do
    it "supports has_key? to check key existence" do
      config = RNS::ConfigObj.new(["key = value"])
      config.has_key?("key").should be_true
      config.has_key?("nonexistent").should be_false
    end

    it "supports [] with default value for missing keys" do
      config = RNS::ConfigObj.new(["key = value"])
      config.get("key", "default").should eq("value")
      config.get("missing", "default").should eq("default")
    end

    it "supports []= to set values" do
      config = RNS::ConfigObj.new
      config["new_key"] = "new_value"
      config["new_key"].should eq("new_value")
    end

    it "tracks scalars and sections separately" do
      lines = [
        "scalar_key = value",
        "[section_key]",
        "  nested = yes",
      ]
      config = RNS::ConfigObj.new(lines)
      config.scalars.should eq(["scalar_key"])
      config.sections.should eq(["section_key"])
    end
  end

  describe "file I/O" do
    it "reads config from a file" do
      tmpfile = File.tempfile("config_test", ".conf") do |file|
        file.print("[reticulum]\n")
        file.print("  enable_transport = no\n")
        file.print("  share_instance = Yes\n")
        file.print("\n")
        file.print("[logging]\n")
        file.print("  loglevel = 4\n")
      end

      begin
        config = RNS::ConfigObj.from_file(tmpfile.path)
        config.sections.should eq(["reticulum", "logging"])
        config.section("reticulum")["enable_transport"].should eq("no")
        config.section("reticulum")["share_instance"].should eq("Yes")
        config.section("logging")["loglevel"].should eq("4")
      ensure
        tmpfile.delete
      end
    end

    it "writes config to a file" do
      lines = [
        "[reticulum]",
        "  enable_transport = False",
        "  share_instance = Yes",
        "[logging]",
        "  loglevel = 4",
      ]
      config = RNS::ConfigObj.new(lines)

      tmpfile = File.tempfile("config_write_test", ".conf")
      begin
        config.write(tmpfile.path)

        # Read back and verify
        config2 = RNS::ConfigObj.from_file(tmpfile.path)
        config2.section("reticulum")["enable_transport"].should eq("False")
        config2.section("reticulum")["share_instance"].should eq("Yes")
        config2.section("logging")["loglevel"].should eq("4")
      ensure
        tmpfile.delete
      end
    end
  end

  describe "RNS test config" do
    it "parses the RNS test configuration" do
      lines = [
        "[reticulum]",
        "  enable_transport = no",
        "  share_instance = Yes",
        "  instance_name = testrunner",
        "  shared_instance_port = 55905",
        "  instance_control_port = 55906",
        "  panic_on_interface_error = No",
        "",
        "[logging]",
        "  loglevel = 1",
        "",
        "[interfaces]",
        "  # No interfaces, only local traffic",
      ]
      config = RNS::ConfigObj.new(lines)

      ret = config.section("reticulum")
      ret.as_bool("enable_transport").should be_false
      ret.as_bool("share_instance").should be_true
      ret["instance_name"].should eq("testrunner")
      ret.as_int("shared_instance_port").should eq(55905)
      ret.as_int("instance_control_port").should eq(55906)
      ret.as_bool("panic_on_interface_error").should be_false

      config.section("logging").as_int("loglevel").should eq(1)

      interfaces = config.section("interfaces")
      interfaces.sections.should be_empty
      interfaces.scalars.should be_empty
    end
  end

  describe "RNS default config" do
    it "parses the default RNS configuration with interfaces" do
      lines = [
        "# This is the default Reticulum config file.",
        "",
        "[reticulum]",
        "",
        "enable_transport = False",
        "share_instance = Yes",
        "instance_name = default",
        "",
        "[logging]",
        "loglevel = 4",
        "",
        "[interfaces]",
        "",
        "  [[Default Interface]]",
        "    type = AutoInterface",
        "    enabled = Yes",
      ]
      config = RNS::ConfigObj.new(lines)

      ret = config.section("reticulum")
      ret.as_bool("enable_transport").should be_false
      ret.as_bool("share_instance").should be_true
      ret["instance_name"].should eq("default")

      config.section("logging").as_int("loglevel").should eq(4)

      interfaces = config.section("interfaces")
      interfaces.sections.should eq(["Default Interface"])

      default_if = interfaces.section("Default Interface")
      default_if["type"].should eq("AutoInterface")
      default_if.as_bool("enabled").should be_true
    end
  end

  describe "dropping back to a previous nesting level" do
    it "handles sections going back to root level" do
      lines = [
        "[section1]",
        "  [[child]]",
        "    key = val",
        "[section2]",
        "  key2 = val2",
      ]
      config = RNS::ConfigObj.new(lines)
      config.sections.should eq(["section1", "section2"])
      config.section("section1").section("child")["key"].should eq("val")
      config.section("section2")["key2"].should eq("val2")
    end
  end

  describe "quoted section names" do
    it "handles quoted section names" do
      lines = [
        "[\"Section With Spaces\"]",
        "  key = value",
      ]
      config = RNS::ConfigObj.new(lines)
      config.sections.should eq(["Section With Spaces"])
    end
  end

  describe "list values" do
    it "parses comma-separated values as a list" do
      lines = ["key = alpha, beta, gamma"]
      config = RNS::ConfigObj.new(lines)
      val = config["key"]
      val.should be_a(Array(String))
      val.as(Array(String)).should eq(["alpha", "beta", "gamma"])
    end

    it "parses quoted values in lists" do
      lines = ["key = \"hello world\", \"foo bar\""]
      config = RNS::ConfigObj.new(lines)
      val = config["key"]
      val.should be_a(Array(String))
      val.as(Array(String)).should eq(["hello world", "foo bar"])
    end
  end

  describe "config setting" do
    it "can set and get scalars on sections" do
      config = RNS::ConfigObj.new
      config["key"] = "value"
      config["key"].should eq("value")
      config.scalars.should eq(["key"])
    end

    it "can create new sections via hash assignment" do
      config = RNS::ConfigObj.new
      config.add_section("new_section")
      section = config.section("new_section")
      section["inner_key"] = "inner_value"
      section["inner_key"].should eq("inner_value")
    end
  end
end
