require "../../spec_helper"

describe "Management module wiring" do
  it "is accessible from the RNS namespace" do
    RNS::Management::NodeStateReport.msgtype.should eq(0x0100_u16)
    RNS::Management::ConfigPush.msgtype.should eq(0x0101_u16)
    RNS::Management::ConfigAck.msgtype.should eq(0x0102_u16)
    RNS::Management::Heartbeat.msgtype.should eq(0x0103_u16)
    RNS::Management::JoinRequest.msgtype.should eq(0x0110_u16)
    RNS::Management::JoinResponse.msgtype.should eq(0x0111_u16)
  end

  it "parses management config section" do
    config_text = <<-CFG
    [reticulum]
      share_instance = no
      enable_transport = no
    [management]
      enabled = yes
      reticule_dest_hash = aabbccdd00112233aabbccdd00112233
      node_id = 1122334455667788
      report_interval = 60
      heartbeat_interval = 15
    CFG
    lines = config_text.lines.map(&.lstrip)
    config = RNS::ConfigObj.new(lines)
    instance = RNS::ReticulumInstance.new(config, _test: true)
    instance.apply_config

    # The instance should have parsed management config without error
    instance.should_not be_nil
    instance.management_enabled.should be_true
    instance.management_report_interval.should eq(60.0)
    instance.management_heartbeat_interval.should eq(15.0)
  end

  it "defaults management to disabled" do
    config_text = <<-CFG
    [reticulum]
      share_instance = no
      enable_transport = no
    CFG
    lines = config_text.lines.map(&.lstrip)
    config = RNS::ConfigObj.new(lines)
    instance = RNS::ReticulumInstance.new(config, _test: true)
    instance.apply_config

    instance.management_enabled.should be_false
    instance.management_report_interval.should eq(30.0)
    instance.management_heartbeat_interval.should eq(10.0)
  end

  it "keeps management disabled when enabled = no" do
    config_text = <<-CFG
    [reticulum]
      share_instance = no
    [management]
      enabled = no
    CFG
    lines = config_text.lines.map(&.lstrip)
    config = RNS::ConfigObj.new(lines)
    instance = RNS::ReticulumInstance.new(config, _test: true)
    instance.apply_config

    instance.management_enabled.should be_false
  end
end
