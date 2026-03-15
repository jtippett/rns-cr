require "../../spec_helper"

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

describe RNS::Management::Manager do
  describe "initialization" do
    it "creates a management destination with correct aspect" do
      instance = make_test_instance
      identity = RNS::Identity.new(create_keys: true)
      manager = RNS::Management::Manager.new(
        identity: identity,
        reticulum_instance: instance,
        config_path: nil,
      )

      manager.destination.should_not be_nil
      manager.destination.name.should contain("reticule.node.mgmt")
    end

    it "starts in disconnected state" do
      instance = make_test_instance
      identity = RNS::Identity.new(create_keys: true)
      manager = RNS::Management::Manager.new(
        identity: identity,
        reticulum_instance: instance,
        config_path: nil,
      )

      manager.link_status.should eq(RNS::Management::Manager::LinkStatus::Disconnected)
    end
  end

  describe "#state_collector" do
    it "exposes a state collector" do
      instance = make_test_instance
      identity = RNS::Identity.new(create_keys: true)
      manager = RNS::Management::Manager.new(
        identity: identity,
        reticulum_instance: instance,
        config_path: nil,
      )

      manager.state_collector.should be_a(RNS::Management::StateCollector)
    end
  end

  describe "config handling" do
    it "validates incoming config sections and rejects invalid ones" do
      instance = make_test_instance
      identity = RNS::Identity.new(create_keys: true)
      manager = RNS::Management::Manager.new(
        identity: identity,
        reticulum_instance: instance,
        config_path: nil,
      )

      push = RNS::Management::ConfigPush.new
      push.push_id = Bytes.new(16, 0x01_u8)
      push.strategy = 0_u8
      push.config_sections = {"bad" => {"ifac_size" => "999"}}
      push.expected_hash = Bytes.new(32)

      ack = manager.handle_config_push(push)
      ack.status.should eq(RNS::Management::ConfigAck::STATUS_VALIDATION_FAILED)
      ack.error_message.should_not be_nil
    end

    it "returns the push_id in the ack" do
      instance = make_test_instance
      identity = RNS::Identity.new(create_keys: true)
      manager = RNS::Management::Manager.new(
        identity: identity,
        reticulum_instance: instance,
        config_path: nil,
      )

      push_id = Bytes.new(16, 0xAB_u8)
      push = RNS::Management::ConfigPush.new
      push.push_id = push_id
      push.strategy = 0_u8
      push.config_sections = {"bad" => {"ifac_size" => "0"}}
      push.expected_hash = Bytes.new(32)

      ack = manager.handle_config_push(push)
      ack.push_id.should eq(push_id)
    end

    it "rejects empty network name" do
      instance = make_test_instance
      identity = RNS::Identity.new(create_keys: true)
      manager = RNS::Management::Manager.new(
        identity: identity,
        reticulum_instance: instance,
        config_path: nil,
      )

      push = RNS::Management::ConfigPush.new
      push.push_id = Bytes.new(16, 0x02_u8)
      push.strategy = 0_u8
      push.config_sections = {"iface" => {"networkname" => "  "}}
      push.expected_hash = Bytes.new(32)

      ack = manager.handle_config_push(push)
      ack.status.should eq(RNS::Management::ConfigAck::STATUS_VALIDATION_FAILED)
    end

    it "rejects invalid mode" do
      instance = make_test_instance
      identity = RNS::Identity.new(create_keys: true)
      manager = RNS::Management::Manager.new(
        identity: identity,
        reticulum_instance: instance,
        config_path: nil,
      )

      push = RNS::Management::ConfigPush.new
      push.push_id = Bytes.new(16, 0x03_u8)
      push.strategy = 0_u8
      push.config_sections = {"iface" => {"mode" => "invalid_mode"}}
      push.expected_hash = Bytes.new(32)

      ack = manager.handle_config_push(push)
      ack.status.should eq(RNS::Management::ConfigAck::STATUS_VALIDATION_FAILED)
    end
  end

  describe "#shutdown" do
    it "sets link status to disconnected" do
      instance = make_test_instance
      identity = RNS::Identity.new(create_keys: true)
      manager = RNS::Management::Manager.new(
        identity: identity,
        reticulum_instance: instance,
        config_path: nil,
      )

      manager.shutdown
      manager.link_status.should eq(RNS::Management::Manager::LinkStatus::Disconnected)
    end
  end
end
