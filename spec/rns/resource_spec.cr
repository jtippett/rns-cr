require "../spec_helper"
require "file_utils"

# ═══════════════════════════════════════════════════════════════════
# Helpers for Resource testing
# ═══════════════════════════════════════════════════════════════════

private def create_in_destination(app_name = "test", aspects = ["resource"]) : RNS::Destination
  identity = RNS::Identity.new
  RNS::Destination.new(identity, RNS::Destination::IN, RNS::Destination::SINGLE,
    app_name, aspects, register: false)
end

# Create a Link with completed handshake and working encrypt/decrypt
private def create_resource_link : RNS::Link
  owner = create_in_destination
  peer_prv = RNS::Cryptography::X25519PrivateKey.generate
  peer_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
  link = RNS::Link.new(owner: owner, peer_pub_bytes: peer_prv.public_key.public_bytes,
    peer_sig_pub_bytes: peer_sig_prv.public_key.public_bytes)
  fake_id = RNS::Identity.truncated_hash(Random::Secure.random_bytes(32))
  link.set_link_id_bytes(fake_id)
  link.do_handshake
  link.status = RNS::LinkLike::ACTIVE
  link
end

private def with_temp_resourcepath(&)
  dir = File.tempname("rns_resource_test", "")
  Dir.mkdir_p(dir)
  old_path = RNS::Reticulum.resourcepath
  RNS::Reticulum.resourcepath = dir
  begin
    yield dir
  ensure
    RNS::Reticulum.resourcepath = old_path
    FileUtils.rm_rf(dir) if Dir.exists?(dir)
  end
end

describe RNS::BZip2 do
  it "compresses and decompresses empty data" do
    compressed = RNS::BZip2.compress(Bytes.empty)
    compressed.should eq(Bytes.empty)
    decompressed = RNS::BZip2.decompress(Bytes.empty)
    decompressed.should eq(Bytes.empty)
  end

  it "roundtrips small data" do
    data = "Hello, World!".to_slice
    compressed = RNS::BZip2.compress(data)
    compressed.should_not eq(data)
    decompressed = RNS::BZip2.decompress(compressed)
    decompressed.should eq(data)
  end

  it "roundtrips larger data" do
    data = Random::Secure.random_bytes(10_000)
    compressed = RNS::BZip2.compress(data)
    decompressed = RNS::BZip2.decompress(compressed)
    decompressed.should eq(data)
  end

  it "compresses repetitive data effectively" do
    data = Bytes.new(1000, 0x42_u8)
    compressed = RNS::BZip2.compress(data)
    compressed.size.should be < data.size
    RNS::BZip2.decompress(compressed).should eq(data)
  end

  it "roundtrips 50 random payloads" do
    50.times do
      size = Random.rand(1..5000)
      data = Random::Secure.random_bytes(size)
      decompressed = RNS::BZip2.decompress(RNS::BZip2.compress(data))
      decompressed.should eq(data)
    end
  end
end

describe RNS::Resource do
  before_each do
    RNS::Transport.reset
  end

  describe "constants" do
    it "has correct window constants" do
      RNS::Resource::WINDOW.should eq(4)
      RNS::Resource::WINDOW_MIN.should eq(2)
      RNS::Resource::WINDOW_MAX_SLOW.should eq(10)
      RNS::Resource::WINDOW_MAX_VERY_SLOW.should eq(4)
      RNS::Resource::WINDOW_MAX_FAST.should eq(75)
      RNS::Resource::WINDOW_MAX.should eq(RNS::Resource::WINDOW_MAX_FAST)
      RNS::Resource::FAST_RATE_THRESHOLD.should eq(4)
      RNS::Resource::VERY_SLOW_RATE_THRESHOLD.should eq(2)
      RNS::Resource::WINDOW_FLEXIBILITY.should eq(4)
    end

    it "has correct rate constants" do
      RNS::Resource::RATE_FAST.should eq(6250)
      RNS::Resource::RATE_VERY_SLOW.should eq(250)
    end

    it "has correct size constants" do
      RNS::Resource::MAPHASH_LEN.should eq(4)
      RNS::Resource::SDU.should eq(RNS::Packet::MDU)
      RNS::Resource::RANDOM_HASH_SIZE.should eq(4)
      RNS::Resource::MAX_EFFICIENT_SIZE.should eq(1_048_575)
      RNS::Resource::METADATA_MAX_SIZE.should eq(16_777_215)
      RNS::Resource::AUTO_COMPRESS_MAX_SIZE.should eq(67_108_864)
    end

    it "has correct timeout and retry constants" do
      RNS::Resource::PART_TIMEOUT_FACTOR.should eq(4)
      RNS::Resource::PART_TIMEOUT_FACTOR_AFTER_RTT.should eq(2)
      RNS::Resource::PROOF_TIMEOUT_FACTOR.should eq(3)
      RNS::Resource::MAX_RETRIES.should eq(16)
      RNS::Resource::MAX_ADV_RETRIES.should eq(4)
      RNS::Resource::SENDER_GRACE_TIME.should eq(10.0)
      RNS::Resource::PROCESSING_GRACE.should eq(1.0)
      RNS::Resource::RETRY_GRACE_TIME.should eq(0.25)
      RNS::Resource::PER_RETRY_DELAY.should eq(0.5)
      RNS::Resource::WATCHDOG_MAX_SLEEP.should eq(1.0)
    end

    it "has correct hashmap flags" do
      RNS::Resource::HASHMAP_IS_NOT_EXHAUSTED.should eq(0x00_u8)
      RNS::Resource::HASHMAP_IS_EXHAUSTED.should eq(0xFF_u8)
    end

    it "has correct status constants" do
      RNS::Resource::STATUS_NONE.should eq(0x00_u8)
      RNS::Resource::QUEUED.should eq(0x01_u8)
      RNS::Resource::ADVERTISED.should eq(0x02_u8)
      RNS::Resource::TRANSFERRING.should eq(0x03_u8)
      RNS::Resource::AWAITING_PROOF.should eq(0x04_u8)
      RNS::Resource::ASSEMBLING.should eq(0x05_u8)
      RNS::Resource::COMPLETE.should eq(0x06_u8)
      RNS::Resource::FAILED.should eq(0x07_u8)
      RNS::Resource::CORRUPT.should eq(0x08_u8)
    end
  end

  describe "sender construction" do
    it "creates a resource with bytes data (no advertise)" do
      link = create_resource_link
      data = Random::Secure.random_bytes(200)
      resource = RNS::Resource.new(data, link, advertise: false)

      resource.initiator.should be_true
      resource.encrypted.should be_true
      resource.size.should be > 0
      resource.total_parts.should be > 0
      resource.sender_parts.size.should eq(resource.total_parts)
      resource.hash.size.should eq(32)
      resource.random_hash.size.should eq(RNS::Resource::RANDOM_HASH_SIZE)
      resource.original_hash.should eq(resource.hash)
      resource.split.should be_false
      resource.segment_index.should eq(1)
      resource.total_segments.should eq(1)
    end

    it "computes unique hashes for different data" do
      link = create_resource_link
      data1 = Random::Secure.random_bytes(100)
      data2 = Random::Secure.random_bytes(100)
      r1 = RNS::Resource.new(data1, link, advertise: false)
      r2 = RNS::Resource.new(data2, link, advertise: false)
      r1.hash.should_not eq(r2.hash)
    end

    it "creates parts with map hashes" do
      link = create_resource_link
      data = Random::Secure.random_bytes(1000)
      resource = RNS::Resource.new(data, link, advertise: false)

      resource.sender_parts.each do |part|
        part.map_hash.should_not be_nil
        part.map_hash.not_nil!.size.should eq(RNS::Resource::MAPHASH_LEN)
      end
    end

    it "produces no hash collisions in map" do
      link = create_resource_link
      data = Random::Secure.random_bytes(5000)
      resource = RNS::Resource.new(data, link, advertise: false)

      hashes = resource.sender_parts.map(&.map_hash.not_nil!)
      hashes.uniq.size.should eq(hashes.size)
    end

    it "creates expected_proof for validation" do
      link = create_resource_link
      data = Random::Secure.random_bytes(200)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.expected_proof.size.should eq(32)
      resource.expected_proof.should_not eq(resource.hash)
    end

    it "frees encrypted data after part creation" do
      link = create_resource_link
      data = Random::Secure.random_bytes(200)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.data.should be_nil
    end

    it "handles auto_compress=false" do
      link = create_resource_link
      data = Bytes.new(200, 0x42_u8)
      resource = RNS::Resource.new(data, link, advertise: false, auto_compress: false)
      resource.compressed.should be_false
    end

    it "compresses compressible data" do
      link = create_resource_link
      data = Bytes.new(5000, 0x00_u8)
      resource = RNS::Resource.new(data, link, advertise: false, auto_compress: true)
      resource.compressed.should be_true
    end

    it "correctly sets SDU from link" do
      link = create_resource_link
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.sdu.should be > 0
    end

    it "sets timeout from link RTT" do
      link = create_resource_link
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.timeout.should be > 0.0
    end

    it "accepts custom timeout" do
      link = create_resource_link
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false, timeout: 42.0)
      resource.timeout.should eq(42.0)
    end

    it "handles request_id" do
      link = create_resource_link
      rid = Random::Secure.random_bytes(16)
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false, request_id: rid)
      resource.request_id.should eq(rid)
    end

    it "handles is_response flag" do
      link = create_resource_link
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false, is_response: true)
      resource.is_response.should be_true
    end

    it "creates resource with nil data (receiver)" do
      link = create_resource_link
      resource = RNS::Resource.new(nil, link, advertise: false)
      resource.initiator.should be_false
    end
  end

  describe "get_map_hash" do
    it "returns MAPHASH_LEN bytes" do
      link = create_resource_link
      resource = RNS::Resource.new(nil, link, advertise: false)
      resource.random_hash = Random::Secure.random_bytes(4)
      hash = resource.get_map_hash(Random::Secure.random_bytes(100))
      hash.size.should eq(RNS::Resource::MAPHASH_LEN)
    end

    it "produces different hashes for different data" do
      link = create_resource_link
      resource = RNS::Resource.new(nil, link, advertise: false)
      resource.random_hash = Random::Secure.random_bytes(4)
      h1 = resource.get_map_hash(Random::Secure.random_bytes(100))
      h2 = resource.get_map_hash(Random::Secure.random_bytes(100))
      h1.should_not eq(h2)
    end

    it "is deterministic for same input" do
      link = create_resource_link
      resource = RNS::Resource.new(nil, link, advertise: false)
      resource.random_hash = Random::Secure.random_bytes(4)
      data = Random::Secure.random_bytes(100)
      h1 = resource.get_map_hash(data)
      h2 = resource.get_map_hash(data)
      h1.should eq(h2)
    end
  end

  describe "progress" do
    it "returns 0.0 initially for sender" do
      link = create_resource_link
      data = Random::Secure.random_bytes(1000)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.get_progress.should eq(0.0)
    end

    it "returns 1.0 when complete" do
      link = create_resource_link
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.status = RNS::Resource::COMPLETE
      resource.get_progress.should eq(1.0)
    end

    it "returns fraction for partially sent" do
      link = create_resource_link
      data = Random::Secure.random_bytes(2000)
      resource = RNS::Resource.new(data, link, advertise: false)
      total = resource.total_parts
      if total > 1
        resource.sent_parts = total // 2
        progress = resource.get_progress
        progress.should be > 0.0
        progress.should be < 1.0
      end
    end

    it "get_segment_progress returns 0.0 initially" do
      link = create_resource_link
      data = Random::Secure.random_bytes(1000)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.get_segment_progress.should eq(0.0)
    end

    it "get_segment_progress returns 1.0 when complete" do
      link = create_resource_link
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.status = RNS::Resource::COMPLETE
      resource.get_segment_progress.should eq(1.0)
    end

    it "reports transfer_size" do
      link = create_resource_link
      data = Random::Secure.random_bytes(500)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.get_transfer_size.should eq(resource.size)
    end

    it "reports data_size" do
      link = create_resource_link
      data = Random::Secure.random_bytes(500)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.get_data_size.should eq(resource.total_size)
    end

    it "reports parts count" do
      link = create_resource_link
      data = Random::Secure.random_bytes(500)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.get_parts.should eq(resource.total_parts)
    end

    it "reports segments count" do
      link = create_resource_link
      data = Random::Secure.random_bytes(500)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.get_segments.should eq(resource.total_segments)
    end
  end

  describe "cancel" do
    it "sets status to FAILED" do
      link = create_resource_link
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.cancel
      resource.status.should eq(RNS::Resource::FAILED)
    end

    it "calls callback on cancel" do
      link = create_resource_link
      called = false
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false,
        callback: ->(r : RNS::Resource) { called = true; nil })
      resource.cancel
      called.should be_true
    end

    it "does not cancel already complete resource" do
      link = create_resource_link
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.status = RNS::Resource::COMPLETE
      resource.cancel
      resource.status.should eq(RNS::Resource::COMPLETE)
    end
  end

  describe "_rejected" do
    it "sets status to REJECTED for initiator" do
      link = create_resource_link
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource._rejected
      resource.status.should eq(RNS::Resource::REJECTED)
    end

    it "does not reject non-initiator" do
      link = create_resource_link
      resource = RNS::Resource.new(nil, link, advertise: false)
      resource._rejected
      resource.status.should eq(RNS::Resource::STATUS_NONE)
    end
  end

  describe "callback setters" do
    it "set_callback stores callback" do
      link = create_resource_link
      resource = RNS::Resource.new(nil, link, advertise: false)
      resource.set_callback(->(r : RNS::Resource) { nil })
      resource.callback.should_not be_nil
    end

    it "set_progress_callback stores callback" do
      link = create_resource_link
      resource = RNS::Resource.new(nil, link, advertise: false)
      resource.set_progress_callback(->(r : RNS::Resource) { nil })
      resource.progress_callback_proc.should_not be_nil
    end
  end

  describe "to_s" do
    it "includes hash hex" do
      link = create_resource_link
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false)
      str = resource.to_s
      str.should start_with("<")
      str.should end_with(">")
      str.size.should be > 2
    end
  end

  describe "window management" do
    it "initializes with WINDOW" do
      link = create_resource_link
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.window.should eq(RNS::Resource::WINDOW)
    end

    it "initializes with WINDOW_MAX_SLOW" do
      link = create_resource_link
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.window_max.should eq(RNS::Resource::WINDOW_MAX_SLOW)
    end

    it "initializes with WINDOW_MIN" do
      link = create_resource_link
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.window_min.should eq(RNS::Resource::WINDOW_MIN)
    end
  end

  describe "validate_proof" do
    it "validates correct proof" do
      link = create_resource_link
      data = Random::Secure.random_bytes(200)
      resource = RNS::Resource.new(data, link, advertise: false)

      proof_data = Bytes.new(resource.hash.size + resource.expected_proof.size)
      resource.hash.copy_to(proof_data)
      resource.expected_proof.copy_to(proof_data + resource.hash.size)

      resource.validate_proof(proof_data)
      resource.status.should eq(RNS::Resource::COMPLETE)
    end

    it "ignores incorrect proof" do
      link = create_resource_link
      data = Random::Secure.random_bytes(200)
      resource = RNS::Resource.new(data, link, advertise: false)

      wrong_proof = Random::Secure.random_bytes(64)
      resource.validate_proof(wrong_proof)
      resource.status.should_not eq(RNS::Resource::COMPLETE)
    end

    it "ignores proof when FAILED" do
      link = create_resource_link
      data = Random::Secure.random_bytes(200)
      resource = RNS::Resource.new(data, link, advertise: false)
      resource.status = RNS::Resource::FAILED

      proof_data = Bytes.new(resource.hash.size + resource.expected_proof.size)
      resource.hash.copy_to(proof_data)
      resource.expected_proof.copy_to(proof_data + resource.hash.size)

      resource.validate_proof(proof_data)
      resource.status.should eq(RNS::Resource::FAILED)
    end

    it "calls callback on successful proof validation" do
      link = create_resource_link
      called = false
      data = Random::Secure.random_bytes(200)
      resource = RNS::Resource.new(data, link, advertise: false,
        callback: ->(r : RNS::Resource) { called = true; nil })

      proof_data = Bytes.new(resource.hash.size + resource.expected_proof.size)
      resource.hash.copy_to(proof_data)
      resource.expected_proof.copy_to(proof_data + resource.hash.size)

      resource.validate_proof(proof_data)
      resource.status.should eq(RNS::Resource::COMPLETE)
      called.should be_true
    end
  end

  describe "EIFR calculation" do
    it "computes eifr from req_data_rtt_rate" do
      link = create_resource_link
      resource = RNS::Resource.new(nil, link, advertise: false)
      resource.req_data_rtt_rate = 1000.0
      resource.update_eifr
      resource.eifr.should eq(8000.0)
    end

    it "falls back to previous_eifr" do
      link = create_resource_link
      resource = RNS::Resource.new(nil, link, advertise: false)
      resource.previous_eifr = 5000.0
      resource.update_eifr
      resource.eifr.should eq(5000.0)
    end

    it "falls back to establishment_cost" do
      link = create_resource_link
      link.establishment_cost = 1000
      resource = RNS::Resource.new(nil, link, advertise: false)
      resource.update_eifr
      resource.eifr.should_not be_nil
    end
  end

  describe "hashmap_update" do
    it "updates hashmap entries" do
      link = create_resource_link
      resource = RNS::Resource.new(nil, link, advertise: false)
      resource.hash = Random::Secure.random_bytes(32)
      resource.random_hash = Random::Secure.random_bytes(4)
      resource.total_parts = 10
      resource.receiver_parts = Array(Bytes?).new(10, nil)
      resource.hashmap = Array(Bytes?).new(10, nil)
      resource.hashmap_height = 0
      resource.status = RNS::Resource::TRANSFERRING

      hashmap_bytes = Random::Secure.random_bytes(3 * RNS::Resource::MAPHASH_LEN)
      resource.hashmap_update(0, hashmap_bytes)

      resource.hashmap_height.should eq(3)
      resource.hashmap[0].should_not be_nil
      resource.hashmap[1].should_not be_nil
      resource.hashmap[2].should_not be_nil
      resource.hashmap[3].should be_nil
    end

    it "does not update when FAILED" do
      link = create_resource_link
      resource = RNS::Resource.new(nil, link, advertise: false)
      resource.status = RNS::Resource::FAILED
      resource.hashmap = Array(Bytes?).new(5, nil)
      resource.hashmap_update(0, Random::Secure.random_bytes(8))
      resource.hashmap_height.should eq(0)
    end
  end

  describe "stress tests" do
    it "creates 20 resources with varying data sizes" do
      link = create_resource_link
      20.times do
        size = Random.rand(50..5000)
        data = Random::Secure.random_bytes(size)
        resource = RNS::Resource.new(data, link, advertise: false)
        resource.initiator.should be_true
        resource.total_parts.should be > 0
        resource.sender_parts.size.should eq(resource.total_parts)
        resource.hash.size.should eq(32)
      end
    end

    it "validates proof for 10 different resources" do
      link = create_resource_link
      10.times do
        data = Random::Secure.random_bytes(Random.rand(100..2000))
        resource = RNS::Resource.new(data, link, advertise: false)

        proof_data = Bytes.new(resource.hash.size + resource.expected_proof.size)
        resource.hash.copy_to(proof_data)
        resource.expected_proof.copy_to(proof_data + resource.hash.size)

        resource.validate_proof(proof_data)
        resource.status.should eq(RNS::Resource::COMPLETE)
      end
    end
  end
end

describe RNS::ResourceAdvertisement do
  before_each do
    RNS::Transport.reset
  end

  describe "constants" do
    it "has correct OVERHEAD" do
      RNS::ResourceAdvertisement::OVERHEAD.should eq(134)
    end

    it "has positive HASHMAP_MAX_LEN" do
      RNS::ResourceAdvertisement::HASHMAP_MAX_LEN.should be > 0
    end

    it "has COLLISION_GUARD_SIZE" do
      expected = 2 * RNS::Resource::WINDOW_MAX + RNS::ResourceAdvertisement::HASHMAP_MAX_LEN
      RNS::ResourceAdvertisement::COLLISION_GUARD_SIZE.should eq(expected)
    end
  end

  describe "pack and unpack" do
    it "roundtrips basic advertisement" do
      link = create_resource_link
      data = Random::Secure.random_bytes(500)
      resource = RNS::Resource.new(data, link, advertise: false)

      adv = RNS::ResourceAdvertisement.new(resource)
      packed = adv.pack

      unpacked = RNS::ResourceAdvertisement.unpack(packed)
      unpacked.t.should eq(adv.t)
      unpacked.d.should eq(adv.d)
      unpacked.n.should eq(adv.n)
      unpacked.h.should eq(adv.h)
      unpacked.r.should eq(adv.r)
      unpacked.o.should eq(adv.o)
      unpacked.i.should eq(adv.i)
      unpacked.l.should eq(adv.l)
      unpacked.f.should eq(adv.f)
    end

    it "roundtrips flags correctly" do
      link = create_resource_link
      data = Bytes.new(500, 0x00_u8)
      resource = RNS::Resource.new(data, link, advertise: false, auto_compress: true)

      adv = RNS::ResourceAdvertisement.new(resource)
      packed = adv.pack
      unpacked = RNS::ResourceAdvertisement.unpack(packed)

      unpacked.e.should eq(adv.e)
      unpacked.c.should eq(adv.c)
      unpacked.s.should eq(adv.s)
      unpacked.u.should eq(adv.u)
      unpacked.p.should eq(adv.p)
      unpacked.x.should eq(adv.x)
    end

    it "roundtrips with request_id" do
      link = create_resource_link
      rid = Random::Secure.random_bytes(16)
      data = Random::Secure.random_bytes(200)
      resource = RNS::Resource.new(data, link, advertise: false, request_id: rid)

      adv = RNS::ResourceAdvertisement.new(resource)
      adv.u.should be_true
      adv.p.should be_false

      packed = adv.pack
      unpacked = RNS::ResourceAdvertisement.unpack(packed)
      unpacked.q.should eq(rid)
      unpacked.u.should be_true
      unpacked.p.should be_false
    end

    it "roundtrips response flag" do
      link = create_resource_link
      rid = Random::Secure.random_bytes(16)
      data = Random::Secure.random_bytes(200)
      resource = RNS::Resource.new(data, link, advertise: false, request_id: rid, is_response: true)

      adv = RNS::ResourceAdvertisement.new(resource)
      adv.u.should be_false
      adv.p.should be_true

      packed = adv.pack
      unpacked = RNS::ResourceAdvertisement.unpack(packed)
      unpacked.u.should be_false
      unpacked.p.should be_true
    end

    it "hashmap in advertisement matches resource parts" do
      link = create_resource_link
      data = Random::Secure.random_bytes(2000)
      resource = RNS::Resource.new(data, link, advertise: false)

      adv = RNS::ResourceAdvertisement.new(resource)
      packed = adv.pack
      unpacked = RNS::ResourceAdvertisement.unpack(packed)

      max_hashes = Math.min(resource.total_parts, RNS::ResourceAdvertisement::HASHMAP_MAX_LEN)
      unpacked.m.size.should eq(max_hashes * RNS::Resource::MAPHASH_LEN)
    end

    it "getters work" do
      link = create_resource_link
      data = Random::Secure.random_bytes(200)
      resource = RNS::Resource.new(data, link, advertise: false)

      adv = RNS::ResourceAdvertisement.new(resource)
      adv.get_transfer_size.should eq(resource.size)
      adv.get_data_size.should eq(resource.total_size)
      adv.get_parts.should eq(resource.sender_parts.size)
      adv.get_segments.should eq(resource.total_segments)
      adv.get_hash.should eq(resource.hash)
      adv.get_link.should be_nil
    end
  end

  describe "flag encoding" do
    it "encodes encrypted flag at bit 0" do
      link = create_resource_link
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false)
      adv = RNS::ResourceAdvertisement.new(resource)
      (adv.f & 0x01).should eq(resource.encrypted ? 1 : 0)
    end

    it "encodes compressed flag at bit 1" do
      link = create_resource_link
      data = Bytes.new(500, 0x00_u8)
      resource = RNS::Resource.new(data, link, advertise: false, auto_compress: true)
      adv = RNS::ResourceAdvertisement.new(resource)
      ((adv.f >> 1) & 0x01).should eq(resource.compressed ? 1 : 0)
    end

    it "encodes split flag at bit 2" do
      link = create_resource_link
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false)
      adv = RNS::ResourceAdvertisement.new(resource)
      ((adv.f >> 2) & 0x01).should eq(resource.split ? 1 : 0)
    end

    it "encodes request flag at bit 3" do
      link = create_resource_link
      rid = Random::Secure.random_bytes(16)
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false, request_id: rid)
      adv = RNS::ResourceAdvertisement.new(resource)
      ((adv.f >> 3) & 0x01).should eq(1)
    end

    it "encodes response flag at bit 4" do
      link = create_resource_link
      rid = Random::Secure.random_bytes(16)
      data = Random::Secure.random_bytes(100)
      resource = RNS::Resource.new(data, link, advertise: false, request_id: rid, is_response: true)
      adv = RNS::ResourceAdvertisement.new(resource)
      ((adv.f >> 4) & 0x01).should eq(1)
    end
  end

  describe "stress tests" do
    it "pack/unpack roundtrip for 30 different resources" do
      link = create_resource_link
      30.times do
        size = Random.rand(50..3000)
        data = Random::Secure.random_bytes(size)
        resource = RNS::Resource.new(data, link, advertise: false)

        adv = RNS::ResourceAdvertisement.new(resource)
        packed = adv.pack
        unpacked = RNS::ResourceAdvertisement.unpack(packed)

        unpacked.t.should eq(adv.t)
        unpacked.d.should eq(adv.d)
        unpacked.h.should eq(adv.h)
        unpacked.r.should eq(adv.r)
        unpacked.o.should eq(adv.o)
        unpacked.e.should eq(adv.e)
        unpacked.c.should eq(adv.c)
        unpacked.s.should eq(adv.s)
      end
    end
  end
end

describe "Reticulum path constants" do
  it "has resourcepath" do
    RNS::Reticulum.resourcepath.should contain("resources")
  end

  it "has storagepath" do
    RNS::Reticulum.storagepath.should contain("storage")
  end

  it "allows setting resourcepath" do
    old = RNS::Reticulum.resourcepath
    RNS::Reticulum.resourcepath = "/tmp/test_resources"
    RNS::Reticulum.resourcepath.should eq("/tmp/test_resources")
    RNS::Reticulum.resourcepath = old
  end
end
