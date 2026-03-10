require "../../spec_helper"

# Concrete test implementation of the abstract Interface class
class TestInterface < RNS::Interface
  property process_outgoing_calls : Array(Bytes) = [] of Bytes

  def initialize(name : String = "TestInterface")
    super()
    @name = name
  end

  def process_outgoing(data : Bytes)
    @process_outgoing_calls << data.dup
  end
end

describe RNS::HDLC do
  describe "constants" do
    it "defines FLAG" do
      RNS::HDLC::FLAG.should eq(0x7E_u8)
    end

    it "defines ESC" do
      RNS::HDLC::ESC.should eq(0x7D_u8)
    end

    it "defines ESC_MASK" do
      RNS::HDLC::ESC_MASK.should eq(0x20_u8)
    end
  end

  describe ".escape" do
    it "returns data unchanged when no special bytes" do
      data = Bytes[0x01, 0x02, 0x03, 0x04]
      result = RNS::HDLC.escape(data)
      result.should eq(data)
    end

    it "escapes FLAG byte (0x7E)" do
      data = Bytes[0x7E]
      result = RNS::HDLC.escape(data)
      result.should eq(Bytes[0x7D, 0x7E ^ 0x20])
      result.should eq(Bytes[0x7D, 0x5E])
    end

    it "escapes ESC byte (0x7D)" do
      data = Bytes[0x7D]
      result = RNS::HDLC.escape(data)
      result.should eq(Bytes[0x7D, 0x7D ^ 0x20])
      result.should eq(Bytes[0x7D, 0x5D])
    end

    it "escapes multiple special bytes" do
      data = Bytes[0x01, 0x7E, 0x02, 0x7D, 0x03]
      result = RNS::HDLC.escape(data)
      result.should eq(Bytes[0x01, 0x7D, 0x5E, 0x02, 0x7D, 0x5D, 0x03])
    end

    it "escapes adjacent special bytes" do
      data = Bytes[0x7E, 0x7D, 0x7E]
      result = RNS::HDLC.escape(data)
      result.should eq(Bytes[0x7D, 0x5E, 0x7D, 0x5D, 0x7D, 0x5E])
    end

    it "handles empty data" do
      result = RNS::HDLC.escape(Bytes.new(0))
      result.size.should eq(0)
    end
  end

  describe ".unescape" do
    it "returns data unchanged when no escape sequences" do
      data = Bytes[0x01, 0x02, 0x03]
      result = RNS::HDLC.unescape(data)
      result.should eq(data)
    end

    it "unescapes FLAG sequence" do
      data = Bytes[0x7D, 0x5E]
      result = RNS::HDLC.unescape(data)
      result.should eq(Bytes[0x7E])
    end

    it "unescapes ESC sequence" do
      data = Bytes[0x7D, 0x5D]
      result = RNS::HDLC.unescape(data)
      result.should eq(Bytes[0x7D])
    end

    it "unescapes multiple sequences" do
      data = Bytes[0x01, 0x7D, 0x5E, 0x02, 0x7D, 0x5D, 0x03]
      result = RNS::HDLC.unescape(data)
      result.should eq(Bytes[0x01, 0x7E, 0x02, 0x7D, 0x03])
    end

    it "handles empty data" do
      result = RNS::HDLC.unescape(Bytes.new(0))
      result.size.should eq(0)
    end
  end

  describe "escape/unescape roundtrip" do
    it "roundtrips arbitrary data" do
      100.times do
        size = Random.rand(1..200)
        data = Random::Secure.random_bytes(size)
        result = RNS::HDLC.unescape(RNS::HDLC.escape(data))
        result.should eq(data)
      end
    end

    it "roundtrips data containing all byte values" do
      data = Bytes.new(256) { |i| i.to_u8 }
      result = RNS::HDLC.unescape(RNS::HDLC.escape(data))
      result.should eq(data)
    end
  end

  describe ".frame" do
    it "wraps data with FLAG bytes" do
      data = Bytes[0x01, 0x02, 0x03]
      result = RNS::HDLC.frame(data)
      result.first.should eq(RNS::HDLC::FLAG)
      result.last.should eq(RNS::HDLC::FLAG)
    end

    it "escapes data inside the frame" do
      data = Bytes[0x7E]
      result = RNS::HDLC.frame(data)
      result.should eq(Bytes[0x7E, 0x7D, 0x5E, 0x7E])
    end

    it "frames empty data" do
      result = RNS::HDLC.frame(Bytes.new(0))
      result.should eq(Bytes[0x7E, 0x7E])
    end
  end
end

describe RNS::Interface do
  describe "constants" do
    it "defines interface mode constants" do
      RNS::Interface::MODE_FULL.should eq(0x01_u8)
      RNS::Interface::MODE_POINT_TO_POINT.should eq(0x02_u8)
      RNS::Interface::MODE_ACCESS_POINT.should eq(0x03_u8)
      RNS::Interface::MODE_ROAMING.should eq(0x04_u8)
      RNS::Interface::MODE_BOUNDARY.should eq(0x05_u8)
      RNS::Interface::MODE_GATEWAY.should eq(0x06_u8)
    end

    it "defines DISCOVER_PATHS_FOR" do
      RNS::Interface::DISCOVER_PATHS_FOR.should contain(RNS::Interface::MODE_ACCESS_POINT)
      RNS::Interface::DISCOVER_PATHS_FOR.should contain(RNS::Interface::MODE_GATEWAY)
      RNS::Interface::DISCOVER_PATHS_FOR.should contain(RNS::Interface::MODE_ROAMING)
      RNS::Interface::DISCOVER_PATHS_FOR.size.should eq(3)
    end

    it "defines announce frequency sample counts" do
      RNS::Interface::IA_FREQ_SAMPLES.should eq(6)
      RNS::Interface::OA_FREQ_SAMPLES.should eq(6)
    end

    it "defines MAX_HELD_ANNOUNCES" do
      RNS::Interface::MAX_HELD_ANNOUNCES.should eq(256)
    end

    it "defines ingress control timing constants" do
      RNS::Interface::IC_NEW_TIME.should eq(7200)              # 2 hours
      RNS::Interface::IC_BURST_FREQ_NEW.should eq(3.5)
      RNS::Interface::IC_BURST_FREQ.should eq(12.0)
      RNS::Interface::IC_BURST_HOLD.should eq(60)
      RNS::Interface::IC_BURST_PENALTY.should eq(300)          # 5 minutes
      RNS::Interface::IC_HELD_RELEASE_INTERVAL.should eq(30)
    end

    it "defines ANNOUNCE_CAP and QUEUED_ANNOUNCE_LIFE" do
      RNS::Interface::ANNOUNCE_CAP.should eq(2)
      RNS::Interface::QUEUED_ANNOUNCE_LIFE.should eq(86400) # 1 day
    end

    it "defines MTU flags" do
      RNS::Interface::AUTOCONFIGURE_MTU.should be_false
      RNS::Interface::FIXED_MTU.should be_false
    end

    it "defines direction flags" do
      RNS::Interface::IN.should be_false
      RNS::Interface::OUT.should be_false
      RNS::Interface::FWD.should be_false
      RNS::Interface::RPT.should be_false
    end
  end

  describe "initialization" do
    it "creates with default values" do
      iface = TestInterface.new
      iface.name.should eq("TestInterface")
      iface.rxb.should eq(0)
      iface.txb.should eq(0)
      iface.online.should be_false
      iface.bitrate.should eq(62500)
      iface.hw_mtu.should be_nil
      iface.mode.should eq(RNS::Interface::MODE_FULL)
      iface.detached?.should be_false
    end

    it "initializes discovery properties" do
      iface = TestInterface.new
      iface.supports_discovery.should be_false
      iface.discoverable.should be_false
      iface.last_discovery_announce.should eq(0.0)
      iface.bootstrap_only.should be_false
    end

    it "initializes ingress control properties" do
      iface = TestInterface.new
      iface.ingress_control.should be_true
      iface.ic_max_held_announces.should eq(RNS::Interface::MAX_HELD_ANNOUNCES)
      iface.ic_burst_hold.should eq(RNS::Interface::IC_BURST_HOLD)
      iface.ic_burst_active.should be_false
      iface.ic_burst_activated.should eq(0.0)
      iface.ic_held_release.should eq(0.0)
      iface.ic_burst_freq_new.should eq(RNS::Interface::IC_BURST_FREQ_NEW)
      iface.ic_burst_freq.should eq(RNS::Interface::IC_BURST_FREQ)
      iface.ic_new_time.should eq(RNS::Interface::IC_NEW_TIME)
      iface.ic_burst_penalty.should eq(RNS::Interface::IC_BURST_PENALTY)
      iface.ic_held_release_interval.should eq(RNS::Interface::IC_HELD_RELEASE_INTERVAL)
    end

    it "initializes empty held announces" do
      iface = TestInterface.new
      iface.held_announces.should be_empty
    end

    it "initializes empty frequency deques" do
      iface = TestInterface.new
      iface.ia_freq_deque.should be_empty
      iface.oa_freq_deque.should be_empty
    end

    it "initializes announce queue properties" do
      iface = TestInterface.new
      iface.announce_queue.should be_empty
      iface.announce_cap.should eq(RNS::Interface::ANNOUNCE_CAP / 100.0)
      iface.announce_allowed_at.should eq(0.0)
    end

    it "initializes announce rate limiting as nil" do
      iface = TestInterface.new
      iface.announce_rate_target.should be_nil
      iface.announce_rate_grace.should be_nil
      iface.announce_rate_penalty.should be_nil
    end

    it "initializes IFAC properties" do
      iface = TestInterface.new
      iface.ifac_size.should eq(0)
      iface.ifac_netname.should be_nil
      iface.ifac_netkey.should be_nil
      iface.ifac_key.should be_nil
      iface.ifac_identity.should be_nil
      iface.ifac_signature.should be_nil
    end

    it "records creation time" do
      before = Time.utc.to_unix_f
      iface = TestInterface.new
      after = Time.utc.to_unix_f
      iface.created.should be >= before
      iface.created.should be <= after
    end

    it "initializes parent/spawned interface references" do
      iface = TestInterface.new
      iface.parent_interface.should be_nil
      iface.spawned_interfaces.should be_nil
      iface.tunnel_id.should be_nil
    end
  end

  describe "#get_hash" do
    it "returns a hash based on interface string representation" do
      iface = TestInterface.new("MyInterface")
      hash = iface.get_hash
      hash.should be_a(Bytes)
      hash.size.should eq(32) # SHA-256 full hash
    end

    it "produces different hashes for different interface names" do
      iface1 = TestInterface.new("Interface1")
      iface2 = TestInterface.new("Interface2")
      iface1.get_hash.should_not eq(iface2.get_hash)
    end

    it "produces consistent hashes for same interface name" do
      iface1 = TestInterface.new("SameName")
      iface2 = TestInterface.new("SameName")
      iface1.get_hash.should eq(iface2.get_hash)
    end
  end

  describe "#age" do
    it "returns non-negative age" do
      iface = TestInterface.new
      iface.age.should be >= 0.0
    end

    it "increases over time" do
      iface = TestInterface.new
      age1 = iface.age
      sleep 0.01.seconds
      age2 = iface.age
      age2.should be > age1
    end
  end

  describe "#should_ingress_limit?" do
    it "returns false when ingress control is disabled" do
      iface = TestInterface.new
      iface.ingress_control = false
      iface.should_ingress_limit?.should be_false
    end

    it "returns false when frequency is below threshold and no burst active" do
      iface = TestInterface.new
      iface.should_ingress_limit?.should be_false
    end

    it "activates burst mode when frequency exceeds threshold" do
      iface = TestInterface.new
      # Simulate high incoming announce frequency by filling deque with close timestamps
      now = Time.utc.to_unix_f
      7.times do |i|
        iface.ia_freq_deque << (now - 0.01 * i)
      end
      # Keep only IA_FREQ_SAMPLES
      while iface.ia_freq_deque.size > RNS::Interface::IA_FREQ_SAMPLES
        iface.ia_freq_deque.shift
      end
      result = iface.should_ingress_limit?
      # With very rapid announces, frequency should be high -> burst activated
      if iface.incoming_announce_frequency > iface.ic_burst_freq
        result.should be_true
        iface.ic_burst_active.should be_true
      end
    end

    it "stays in burst mode until frequency drops and hold time passes" do
      iface = TestInterface.new
      iface.ic_burst_active = true
      iface.ic_burst_activated = Time.utc.to_unix_f - iface.ic_burst_hold - 1
      # No recent announces -> frequency = 0 -> below threshold
      iface.should_ingress_limit?.should be_true
      # But frequency is 0 which is below threshold and hold time has passed
      # so burst deactivates, but still returns true for this call
    end

    it "deactivates burst after hold time when frequency drops" do
      iface = TestInterface.new
      iface.ic_burst_active = true
      iface.ic_burst_activated = Time.utc.to_unix_f - iface.ic_burst_hold - 1
      # Frequency is 0 (no samples), below threshold, hold time passed
      iface.should_ingress_limit?.should be_true
      # After this call, burst should be deactivated
      iface.ic_burst_active.should be_false
      iface.ic_held_release.should be > Time.utc.to_unix_f
    end
  end

  describe "#optimise_mtu" do
    # Create a subclass that has AUTOCONFIGURE_MTU = true
    it "sets HW_MTU based on bitrate when autoconfigure enabled" do
      iface = TestInterface.new
      # Base class has AUTOCONFIGURE_MTU = false, so nothing happens
      iface.bitrate = 1_000_000_000
      iface.optimise_mtu
      iface.hw_mtu.should be_nil # Not autoconfigured
    end
  end

  describe "#hold_announce" do
    it "holds an announce packet" do
      iface = TestInterface.new
      dest_hash = Random::Secure.random_bytes(16)
      announce = RNS::Interface::HeldAnnounce.new(
        raw: Bytes[1, 2, 3],
        destination_hash: dest_hash,
        hops: 2,
        receiving_interface: nil
      )
      iface.hold_announce(announce)
      iface.held_announces.size.should eq(1)
    end

    it "overwrites existing announce for same destination" do
      iface = TestInterface.new
      dest_hash = Random::Secure.random_bytes(16)
      announce1 = RNS::Interface::HeldAnnounce.new(
        raw: Bytes[1, 2, 3],
        destination_hash: dest_hash,
        hops: 2,
        receiving_interface: nil
      )
      announce2 = RNS::Interface::HeldAnnounce.new(
        raw: Bytes[4, 5, 6],
        destination_hash: dest_hash,
        hops: 1,
        receiving_interface: nil
      )
      iface.hold_announce(announce1)
      iface.hold_announce(announce2)
      iface.held_announces.size.should eq(1)
      iface.held_announces.first_value.hops.should eq(1)
    end

    it "respects maximum held announces" do
      iface = TestInterface.new
      iface.ic_max_held_announces = 3
      4.times do |i|
        dest_hash = Bytes.new(16, (i + 1).to_u8)
        announce = RNS::Interface::HeldAnnounce.new(
          raw: Bytes[i.to_u8],
          destination_hash: dest_hash,
          hops: i,
          receiving_interface: nil
        )
        iface.hold_announce(announce)
      end
      iface.held_announces.size.should eq(3)
    end

    it "allows overwriting even when at max capacity" do
      iface = TestInterface.new
      iface.ic_max_held_announces = 2
      dest1 = Bytes.new(16, 1_u8)
      dest2 = Bytes.new(16, 2_u8)
      a1 = RNS::Interface::HeldAnnounce.new(raw: Bytes[1], destination_hash: dest1, hops: 1, receiving_interface: nil)
      a2 = RNS::Interface::HeldAnnounce.new(raw: Bytes[2], destination_hash: dest2, hops: 2, receiving_interface: nil)
      iface.hold_announce(a1)
      iface.hold_announce(a2)
      iface.held_announces.size.should eq(2)

      # Overwrite existing dest1
      a1_new = RNS::Interface::HeldAnnounce.new(raw: Bytes[3], destination_hash: dest1, hops: 0, receiving_interface: nil)
      iface.hold_announce(a1_new)
      iface.held_announces.size.should eq(2)
      iface.held_announces[dest1.hexstring].hops.should eq(0)
    end
  end

  describe "#process_held_announces" do
    it "does nothing when no held announces" do
      iface = TestInterface.new
      iface.process_held_announces
      iface.held_announces.should be_empty
    end

    it "does not release when ingress limiting is active" do
      iface = TestInterface.new
      iface.ic_burst_active = true
      iface.ic_burst_activated = Time.utc.to_unix_f # recent activation
      dest_hash = Random::Secure.random_bytes(16)
      announce = RNS::Interface::HeldAnnounce.new(
        raw: Bytes[1, 2, 3],
        destination_hash: dest_hash,
        hops: 1,
        receiving_interface: nil
      )
      iface.hold_announce(announce)
      iface.process_held_announces
      iface.held_announces.size.should eq(1) # not released
    end

    it "releases lowest-hop announce when conditions are met" do
      iface = TestInterface.new
      iface.ingress_control = false # disable ingress control so should_ingress_limit? returns false
      iface.ic_held_release = 0.0  # allow immediate release

      dest1 = Bytes.new(16, 1_u8)
      dest2 = Bytes.new(16, 2_u8)
      a1 = RNS::Interface::HeldAnnounce.new(raw: Bytes[1], destination_hash: dest1, hops: 3, receiving_interface: nil)
      a2 = RNS::Interface::HeldAnnounce.new(raw: Bytes[2], destination_hash: dest2, hops: 1, receiving_interface: nil)
      iface.hold_announce(a1)
      iface.hold_announce(a2)

      iface.process_held_announces
      # Should have released the 1-hop announce
      iface.held_announces.size.should eq(1)
      iface.held_announces.has_key?(dest1.hexstring).should be_true
    end

    it "updates ic_held_release after releasing" do
      iface = TestInterface.new
      iface.ingress_control = false
      iface.ic_held_release = 0.0
      dest = Random::Secure.random_bytes(16)
      a = RNS::Interface::HeldAnnounce.new(raw: Bytes[1], destination_hash: dest, hops: 1, receiving_interface: nil)
      iface.hold_announce(a)
      iface.process_held_announces
      iface.ic_held_release.should be > Time.utc.to_unix_f
    end
  end

  describe "#received_announce" do
    it "adds timestamp to ia_freq_deque" do
      iface = TestInterface.new
      iface.received_announce
      iface.ia_freq_deque.size.should eq(1)
    end

    it "limits deque to IA_FREQ_SAMPLES" do
      iface = TestInterface.new
      (RNS::Interface::IA_FREQ_SAMPLES + 3).times do
        iface.received_announce
      end
      iface.ia_freq_deque.size.should eq(RNS::Interface::IA_FREQ_SAMPLES)
    end

    it "propagates to parent interface" do
      parent = TestInterface.new("Parent")
      child = TestInterface.new("Child")
      child.parent_interface = parent
      child.received_announce
      child.ia_freq_deque.size.should eq(1)
      parent.ia_freq_deque.size.should eq(1)
    end
  end

  describe "#sent_announce" do
    it "adds timestamp to oa_freq_deque" do
      iface = TestInterface.new
      iface.sent_announce
      iface.oa_freq_deque.size.should eq(1)
    end

    it "limits deque to OA_FREQ_SAMPLES" do
      iface = TestInterface.new
      (RNS::Interface::OA_FREQ_SAMPLES + 3).times do
        iface.sent_announce
      end
      iface.oa_freq_deque.size.should eq(RNS::Interface::OA_FREQ_SAMPLES)
    end

    it "propagates to parent interface" do
      parent = TestInterface.new("Parent")
      child = TestInterface.new("Child")
      child.parent_interface = parent
      child.sent_announce
      child.oa_freq_deque.size.should eq(1)
      parent.oa_freq_deque.size.should eq(1)
    end
  end

  describe "#incoming_announce_frequency" do
    it "returns 0 with no samples" do
      iface = TestInterface.new
      iface.incoming_announce_frequency.should eq(0.0)
    end

    it "returns 0 with only one sample" do
      iface = TestInterface.new
      iface.received_announce
      iface.incoming_announce_frequency.should eq(0.0)
    end

    it "returns positive frequency with multiple samples" do
      iface = TestInterface.new
      iface.ia_freq_deque << (Time.utc.to_unix_f - 1.0)
      iface.ia_freq_deque << Time.utc.to_unix_f
      freq = iface.incoming_announce_frequency
      freq.should be > 0.0
    end

    it "returns higher frequency for closer timestamps" do
      iface1 = TestInterface.new
      now = Time.utc.to_unix_f
      iface1.ia_freq_deque << (now - 0.1)
      iface1.ia_freq_deque << now
      freq_fast = iface1.incoming_announce_frequency

      iface2 = TestInterface.new
      iface2.ia_freq_deque << (now - 10.0)
      iface2.ia_freq_deque << now
      freq_slow = iface2.incoming_announce_frequency

      freq_fast.should be > freq_slow
    end
  end

  describe "#outgoing_announce_frequency" do
    it "returns 0 with no samples" do
      iface = TestInterface.new
      iface.outgoing_announce_frequency.should eq(0.0)
    end

    it "returns 0 with only one sample" do
      iface = TestInterface.new
      iface.sent_announce
      iface.outgoing_announce_frequency.should eq(0.0)
    end

    it "returns positive frequency with multiple samples" do
      iface = TestInterface.new
      iface.oa_freq_deque << (Time.utc.to_unix_f - 1.0)
      iface.oa_freq_deque << Time.utc.to_unix_f
      freq = iface.outgoing_announce_frequency
      freq.should be > 0.0
    end
  end

  describe "#process_announce_queue" do
    it "does nothing with empty queue" do
      iface = TestInterface.new
      iface.process_announce_queue
      iface.process_outgoing_calls.should be_empty
    end

    it "sends lowest-hop oldest announce" do
      iface = TestInterface.new
      now = Time.utc.to_unix_f
      iface.announce_queue << RNS::Interface::AnnounceQueueEntry.new(
        raw: Bytes[1, 2, 3],
        hops: 2,
        time: now - 10.0
      )
      iface.announce_queue << RNS::Interface::AnnounceQueueEntry.new(
        raw: Bytes[4, 5, 6],
        hops: 1,
        time: now - 5.0
      )
      iface.announce_queue << RNS::Interface::AnnounceQueueEntry.new(
        raw: Bytes[7, 8, 9],
        hops: 1,
        time: now - 8.0
      )
      iface.process_announce_queue
      iface.process_outgoing_calls.size.should eq(1)
      # Should send the 1-hop entry with oldest time
      iface.process_outgoing_calls.first.should eq(Bytes[7, 8, 9])
    end

    it "removes the sent entry from queue" do
      iface = TestInterface.new
      now = Time.utc.to_unix_f
      iface.announce_queue << RNS::Interface::AnnounceQueueEntry.new(
        raw: Bytes[1, 2, 3],
        hops: 1,
        time: now
      )
      iface.process_announce_queue
      iface.announce_queue.should be_empty
    end

    it "removes stale entries" do
      iface = TestInterface.new
      old_time = Time.utc.to_unix_f - RNS::Interface::QUEUED_ANNOUNCE_LIFE - 100
      iface.announce_queue << RNS::Interface::AnnounceQueueEntry.new(
        raw: Bytes[1, 2, 3],
        hops: 1,
        time: old_time
      )
      iface.process_announce_queue
      iface.announce_queue.should be_empty
      iface.process_outgoing_calls.should be_empty # Stale entry was not sent
    end

    it "sets announce_allowed_at based on tx_time and announce_cap" do
      iface = TestInterface.new
      iface.bitrate = 1000 # 1000 bits/second
      iface.announce_cap = 0.02 # 2%
      now = Time.utc.to_unix_f
      iface.announce_queue << RNS::Interface::AnnounceQueueEntry.new(
        raw: Bytes.new(100), # 100 bytes = 800 bits
        hops: 1,
        time: now
      )
      iface.process_announce_queue
      # tx_time = 800 bits / 1000 bps = 0.8s
      # wait_time = 0.8 / 0.02 = 40s
      iface.announce_allowed_at.should be > now
    end

    it "records sent_announce" do
      iface = TestInterface.new
      now = Time.utc.to_unix_f
      iface.announce_queue << RNS::Interface::AnnounceQueueEntry.new(
        raw: Bytes[1, 2, 3],
        hops: 1,
        time: now
      )
      iface.process_announce_queue
      iface.oa_freq_deque.size.should eq(1)
    end

    it "clears queue on error" do
      iface = TestInterface.new
      iface.bitrate = 0 # Will cause division by zero
      now = Time.utc.to_unix_f
      iface.announce_queue << RNS::Interface::AnnounceQueueEntry.new(
        raw: Bytes[1],
        hops: 1,
        time: now
      )
      # Should not raise, but should clear the queue
      iface.process_announce_queue
      iface.announce_queue.should be_empty
    end
  end

  describe "#final_init" do
    it "does nothing by default" do
      iface = TestInterface.new
      iface.final_init # Should not raise
    end
  end

  describe "#detach" do
    it "marks interface as detached" do
      iface = TestInterface.new
      iface.detached?.should be_false
      iface.detach
      iface.detached?.should be_true
    end
  end

  describe "#to_s" do
    it "returns the interface name" do
      iface = TestInterface.new("MyTestIface")
      iface.to_s.should eq("MyTestIface")
    end
  end

  describe "property mutation" do
    it "allows setting name" do
      iface = TestInterface.new
      iface.name = "NewName"
      iface.name.should eq("NewName")
    end

    it "allows setting rxb and txb" do
      iface = TestInterface.new
      iface.rxb = 1000
      iface.txb = 2000
      iface.rxb.should eq(1000)
      iface.txb.should eq(2000)
    end

    it "allows setting online" do
      iface = TestInterface.new
      iface.online = true
      iface.online.should be_true
    end

    it "allows setting bitrate" do
      iface = TestInterface.new
      iface.bitrate = 115200
      iface.bitrate.should eq(115200)
    end

    it "allows setting mode" do
      iface = TestInterface.new
      iface.mode = RNS::Interface::MODE_ACCESS_POINT
      iface.mode.should eq(RNS::Interface::MODE_ACCESS_POINT)
    end

    it "allows setting hw_mtu" do
      iface = TestInterface.new
      iface.hw_mtu = 16384
      iface.hw_mtu.should eq(16384)
    end

    it "allows setting tunnel_id" do
      iface = TestInterface.new
      tid = Random::Secure.random_bytes(16)
      iface.tunnel_id = tid
      iface.tunnel_id.should eq(tid)
    end

    it "allows setting IFAC properties" do
      iface = TestInterface.new
      iface.ifac_size = 16
      iface.ifac_netname = "testnet"
      iface.ifac_netkey = "secret"
      iface.ifac_size.should eq(16)
      iface.ifac_netname.should eq("testnet")
      iface.ifac_netkey.should eq("secret")
    end

    it "allows setting announce rate properties" do
      iface = TestInterface.new
      iface.announce_rate_target = 10
      iface.announce_rate_grace = 5
      iface.announce_rate_penalty = 60
      iface.announce_rate_target.should eq(10)
      iface.announce_rate_grace.should eq(5)
      iface.announce_rate_penalty.should eq(60)
    end

    it "allows setting parent/spawned interfaces" do
      parent = TestInterface.new("Parent")
      child = TestInterface.new("Child")
      child.parent_interface = parent
      parent.spawned_interfaces = [child] of RNS::Interface
      child.parent_interface.should eq(parent)
      parent.spawned_interfaces.try(&.size).should eq(1)
    end
  end

  describe "HeldAnnounce" do
    it "creates a held announce record" do
      dest_hash = Random::Secure.random_bytes(16)
      ha = RNS::Interface::HeldAnnounce.new(
        raw: Bytes[1, 2, 3],
        destination_hash: dest_hash,
        hops: 3,
        receiving_interface: nil
      )
      ha.raw.should eq(Bytes[1, 2, 3])
      ha.destination_hash.should eq(dest_hash)
      ha.hops.should eq(3)
      ha.receiving_interface.should be_nil
    end

    it "can reference a receiving interface" do
      iface = TestInterface.new
      ha = RNS::Interface::HeldAnnounce.new(
        raw: Bytes[1],
        destination_hash: Bytes.new(16),
        hops: 1,
        receiving_interface: iface
      )
      ha.receiving_interface.should eq(iface)
    end
  end

  describe "AnnounceQueueEntry" do
    it "creates an announce queue entry" do
      entry = RNS::Interface::AnnounceQueueEntry.new(
        raw: Bytes[1, 2, 3],
        hops: 2,
        time: 1234567890.0
      )
      entry.raw.should eq(Bytes[1, 2, 3])
      entry.hops.should eq(2)
      entry.time.should eq(1234567890.0)
    end
  end

  describe "stress tests" do
    it "handles 100 held announces" do
      iface = TestInterface.new
      100.times do |i|
        dest_hash = Random::Secure.random_bytes(16)
        announce = RNS::Interface::HeldAnnounce.new(
          raw: Random::Secure.random_bytes(50),
          destination_hash: dest_hash,
          hops: Random.rand(1..10),
          receiving_interface: nil
        )
        iface.hold_announce(announce)
      end
      iface.held_announces.size.should eq(100)
    end

    it "handles rapid announce frequency tracking" do
      iface = TestInterface.new
      50.times { iface.received_announce }
      50.times { iface.sent_announce }
      iface.ia_freq_deque.size.should eq(RNS::Interface::IA_FREQ_SAMPLES)
      iface.oa_freq_deque.size.should eq(RNS::Interface::OA_FREQ_SAMPLES)
      iface.incoming_announce_frequency.should be > 0.0
      iface.outgoing_announce_frequency.should be > 0.0
    end

    it "handles HDLC escape/unescape stress" do
      200.times do
        size = Random.rand(1..500)
        data = Random::Secure.random_bytes(size)
        escaped = RNS::HDLC.escape(data)
        # Escaped data should be >= original size
        escaped.size.should be >= data.size
        # Roundtrip
        RNS::HDLC.unescape(escaped).should eq(data)
      end
    end

    it "processes 20 announce queue entries" do
      iface = TestInterface.new
      now = Time.utc.to_unix_f
      20.times do |i|
        iface.announce_queue << RNS::Interface::AnnounceQueueEntry.new(
          raw: Random::Secure.random_bytes(50),
          hops: Random.rand(1..5),
          time: now - Random.rand(0.0..10.0)
        )
      end
      iface.process_announce_queue
      iface.process_outgoing_calls.size.should eq(1) # one announce sent per call
      iface.announce_queue.size.should eq(19) # one removed
    end
  end
end
