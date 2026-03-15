require "../../spec_helper"

describe "Management auto-start" do
  it "creates Manager when management is enabled in config" do
    config_text = <<-CFG
    [reticulum]
      share_instance = no
      enable_transport = no
    [management]
      enabled = yes
      reticule_dest_hash = aabbccdd00112233aabbccdd00112233
      report_interval = 30
    CFG
    lines = config_text.lines.map(&.lstrip)
    config = RNS::ConfigObj.new(lines)
    instance = RNS::ReticulumInstance.new(config, _test: true)
    instance.apply_config

    instance.management.should_not be_nil
    instance.management.not_nil!.link_status.should eq(
      RNS::Management::Manager::LinkStatus::Disconnected
    )
  end

  it "does not create Manager when management is disabled" do
    config_text = <<-CFG
    [reticulum]
      share_instance = no
      enable_transport = no
    CFG
    lines = config_text.lines.map(&.lstrip)
    config = RNS::ConfigObj.new(lines)
    instance = RNS::ReticulumInstance.new(config, _test: true)
    instance.apply_config

    instance.management.should be_nil
  end

  it "passes configured report_interval and heartbeat_interval to Manager" do
    config_text = <<-CFG
    [reticulum]
      share_instance = no
      enable_transport = no
    [management]
      enabled = yes
      report_interval = 45
      heartbeat_interval = 20
    CFG
    lines = config_text.lines.map(&.lstrip)
    config = RNS::ConfigObj.new(lines)
    instance = RNS::ReticulumInstance.new(config, _test: true)
    instance.apply_config

    instance.management.should_not be_nil
    instance.management_report_interval.should eq(45.0)
    instance.management_heartbeat_interval.should eq(20.0)
  end

  it "does not call connect in test mode (link stays disconnected)" do
    config_text = <<-CFG
    [reticulum]
      share_instance = no
      enable_transport = no
    [management]
      enabled = yes
      reticule_dest_hash = aabbccdd00112233aabbccdd00112233
    CFG
    lines = config_text.lines.map(&.lstrip)
    config = RNS::ConfigObj.new(lines)
    instance = RNS::ReticulumInstance.new(config, _test: true)
    instance.apply_config

    mgr = instance.management.not_nil!
    # In test mode, connect should NOT have been called, so status stays Disconnected
    mgr.link_status.should eq(RNS::Management::Manager::LinkStatus::Disconnected)
  end
end
