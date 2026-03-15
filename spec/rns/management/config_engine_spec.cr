require "../../spec_helper"

describe RNS::Management::ConfigEngine do
  describe ".validate_config_sections" do
    it "accepts valid config sections" do
      sections = {
        "interfaces" => {"type" => "AutoInterface", "enabled" => "yes"},
      }
      result = RNS::Management::ConfigEngine.validate_config_sections(sections)
      result[:valid].should be_true
      result[:errors].should be_empty
    end

    it "rejects invalid ifac_size" do
      sections = {
        "test_iface" => {"ifac_size" => "128"},  # > 64
      }
      result = RNS::Management::ConfigEngine.validate_config_sections(sections)
      result[:valid].should be_false
      result[:errors].size.should be > 0
    end

    it "rejects zero announce_rate_target" do
      sections = {
        "test_iface" => {"announce_rate_target" => "0"},
      }
      result = RNS::Management::ConfigEngine.validate_config_sections(sections)
      result[:valid].should be_false
    end
  end

  describe ".diff_config" do
    it "detects IFAC credential changes as hot-reloadable" do
      old_sections = {"my_iface" => {"networkname" => "old-net", "passphrase" => "old-pass"}}
      new_sections = {"my_iface" => {"networkname" => "new-net", "passphrase" => "new-pass"}}

      changes = RNS::Management::ConfigEngine.diff_config(old_sections, new_sections)
      changes.size.should eq(1)
      changes[0].section.should eq("my_iface")
      changes[0].reload_type.should eq(RNS::Management::ConfigEngine::ReloadType::Hot)
    end

    it "detects new interface as targeted" do
      old_sections = {} of String => Hash(String, String)
      new_sections = {"new_iface" => {"type" => "TCPClientInterface", "target_host" => "10.0.0.1"}}

      changes = RNS::Management::ConfigEngine.diff_config(old_sections, new_sections)
      changes.size.should eq(1)
      changes[0].reload_type.should eq(RNS::Management::ConfigEngine::ReloadType::Targeted)
    end

    it "detects removed interface as targeted" do
      old_sections = {"old_iface" => {"type" => "TCPClientInterface", "target_host" => "10.0.0.1"}}
      new_sections = {} of String => Hash(String, String)

      changes = RNS::Management::ConfigEngine.diff_config(old_sections, new_sections)
      changes.size.should eq(1)
      changes[0].change_type.should eq(RNS::Management::ConfigEngine::ChangeType::Removed)
      changes[0].reload_type.should eq(RNS::Management::ConfigEngine::ReloadType::Targeted)
    end

    it "detects bind address change as targeted" do
      old_sections = {"iface" => {"target_host" => "10.0.0.1", "target_port" => "4242"}}
      new_sections = {"iface" => {"target_host" => "10.0.0.2", "target_port" => "4242"}}

      changes = RNS::Management::ConfigEngine.diff_config(old_sections, new_sections)
      changes.size.should eq(1)
      changes[0].reload_type.should eq(RNS::Management::ConfigEngine::ReloadType::Targeted)
    end

    it "detects announce rate changes as hot-reloadable" do
      old_sections = {"iface" => {"announce_rate_target" => "3600"}}
      new_sections = {"iface" => {"announce_rate_target" => "1800"}}

      changes = RNS::Management::ConfigEngine.diff_config(old_sections, new_sections)
      changes.size.should eq(1)
      changes[0].reload_type.should eq(RNS::Management::ConfigEngine::ReloadType::Hot)
    end

    it "returns empty for identical configs" do
      sections = {"iface" => {"type" => "AutoInterface"}}
      changes = RNS::Management::ConfigEngine.diff_config(sections, sections)
      changes.should be_empty
    end
  end

  describe ".compute_config_hash" do
    it "returns consistent SHA-256 hash" do
      content = "[reticulum]\n  enable_transport = yes\n"
      hash1 = RNS::Management::ConfigEngine.compute_config_hash(content)
      hash2 = RNS::Management::ConfigEngine.compute_config_hash(content)
      hash1.should eq(hash2)
      hash1.size.should eq(32)  # SHA-256 = 32 bytes
    end

    it "returns different hash for different content" do
      hash1 = RNS::Management::ConfigEngine.compute_config_hash("config_a")
      hash2 = RNS::Management::ConfigEngine.compute_config_hash("config_b")
      hash1.should_not eq(hash2)
    end
  end
end
