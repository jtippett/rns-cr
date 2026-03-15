require "../../spec_helper"

# Minimal concrete interface for lifecycle testing
class LifecycleTestInterface < RNS::Interface
  IN  = true
  OUT = true

  def initialize(name : String = "LifecycleTest")
    super()
    @name = name
    @online = true
  end

  def process_outgoing(data : Bytes)
  end
end

private def make_test_instance
  config_text = <<-CFG
  [reticulum]
    share_instance = no
    enable_transport = no
  CFG
  lines = config_text.lines.map(&.lstrip)
  config = RNS::ConfigObj.new(lines)
  RNS::ReticulumInstance.new(config, _test: true)
end

describe "Interface Lifecycle" do
  describe "remove_interface" do
    it "removes a registered interface by name" do
      instance = make_test_instance
      iface = LifecycleTestInterface.new("removable")
      instance.add_interface(iface)

      RNS::Transport.interface_objects.any? { |i| i.name == "removable" }.should be_true
      instance.remove_interface("removable").should be_true
      RNS::Transport.interface_objects.any? { |i| i.name == "removable" }.should be_false
    end

    it "returns false for nonexistent interface" do
      instance = make_test_instance
      instance.remove_interface("nonexistent").should be_false
    end

    it "refuses to remove management_protected interface" do
      instance = make_test_instance
      iface = LifecycleTestInterface.new("protected")
      iface.management_protected = true
      instance.add_interface(iface)

      instance.remove_interface("protected").should be_false
      RNS::Transport.interface_objects.any? { |i| i.name == "protected" }.should be_true
    end
  end

  describe "update_interface_ifac" do
    it "updates IFAC credentials on a named interface" do
      instance = make_test_instance
      iface = LifecycleTestInterface.new("ifac-target")
      instance.add_interface(iface)

      result = instance.update_interface_ifac("ifac-target",
        network_name: "new-net", passphrase: "new-pass", ifac_size: 16_u8)
      result.should be_true

      found = RNS::Transport.interface_objects.find { |i| i.name == "ifac-target" }
      found.should_not be_nil
      found.not_nil!.ifac_netname.should eq("new-net")
      found.not_nil!.ifac_netkey.should eq("new-pass")
      found.not_nil!.ifac_key.should_not be_nil
    end

    it "returns false for nonexistent interface" do
      instance = make_test_instance
      instance.update_interface_ifac("ghost",
        network_name: "x", passphrase: "y", ifac_size: 16_u8).should be_false
    end
  end
end
