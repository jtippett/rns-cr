require "../../spec_helper"
require "file_utils"

# Integration test: Resource (file) transfer over an established Link

private def create_ft_link : RNS::Link
  identity = RNS::Identity.new
  owner = RNS::Destination.new(identity, RNS::Destination::IN, RNS::Destination::SINGLE,
    "filetest", ["transfer"], register: false)
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

private def with_ft_resourcepath(&)
  dir = File.tempname("rns_ft_test", "")
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

describe "Integration: File Transfer (Resource)" do
  before_each do
    RNS::Transport.reset
    RNS::Identity.known_destinations.clear
    RNS::Identity.known_ratchets.clear
  end

  describe "Resource creation from data" do
    it "creates a resource from small data" do
      with_ft_resourcepath do
        link = create_ft_link
        data = "Small test file content".to_slice
        resource = RNS::Resource.new(data, link, advertise: false)
        resource.should_not be_nil
        resource.total_size.should eq(data.size)
        resource.total_parts.should be >= 1
      end
    end

    it "creates a resource from medium data (1 KB)" do
      with_ft_resourcepath do
        link = create_ft_link
        data = Random::Secure.random_bytes(1024)
        resource = RNS::Resource.new(data, link, advertise: false)
        resource.total_parts.should be >= 1
        resource.total_size.should eq(1024)
      end
    end

    it "creates a resource from large data (64 KB)" do
      with_ft_resourcepath do
        link = create_ft_link
        data = Random::Secure.random_bytes(65536)
        resource = RNS::Resource.new(data, link, advertise: false)
        resource.total_parts.should be > 1
        resource.total_size.should eq(65536)
      end
    end

    it "segments data into correctly sized parts" do
      with_ft_resourcepath do
        link = create_ft_link
        data = Random::Secure.random_bytes(5000)
        resource = RNS::Resource.new(data, link, advertise: false)
        sdu = resource.sdu
        resource.sender_parts.each do |part|
          part.data.size.should be <= sdu
        end
      end
    end

    it "resource hash is non-empty" do
      with_ft_resourcepath do
        link = create_ft_link
        data = "Consistent hash test".to_slice
        resource = RNS::Resource.new(data, link, advertise: false)
        resource.hash.size.should be > 0
        resource.original_hash.size.should be > 0
      end
    end
  end

  describe "ResourceAdvertisement" do
    it "packs and unpacks advertisement" do
      with_ft_resourcepath do
        link = create_ft_link
        data = Random::Secure.random_bytes(2048)
        resource = RNS::Resource.new(data, link, advertise: false)
        adv = RNS::ResourceAdvertisement.new(resource)
        packed = adv.pack
        packed.should_not be_nil
        packed.size.should be > 0
      end
    end

    it "advertisement roundtrip preserves fields" do
      with_ft_resourcepath do
        link = create_ft_link
        data = Random::Secure.random_bytes(4096)
        resource = RNS::Resource.new(data, link, advertise: false)
        adv = RNS::ResourceAdvertisement.new(resource)
        packed = adv.pack
        unpacked = RNS::ResourceAdvertisement.unpack(packed)

        unpacked.h.should eq(adv.h)
        unpacked.o.should eq(adv.o)
        unpacked.t.should eq(adv.t)
        unpacked.l.should eq(adv.l)
        unpacked.i.should eq(adv.i)
        unpacked.n.should eq(adv.n)
      end
    end

    it "advertisement flag encoding is correct" do
      with_ft_resourcepath do
        link = create_ft_link
        data = Random::Secure.random_bytes(1024)
        resource = RNS::Resource.new(data, link, advertise: false)
        adv = RNS::ResourceAdvertisement.new(resource)
        packed = adv.pack
        unpacked = RNS::ResourceAdvertisement.unpack(packed)

        unpacked.e.should eq(adv.e)
        unpacked.c.should eq(adv.c)
        unpacked.u.should eq(adv.u)
        unpacked.p.should eq(adv.p)
      end
    end
  end

  describe "Data integrity" do
    it "resource parts are non-empty and within SDU" do
      with_ft_resourcepath do
        link = create_ft_link
        original_data = "The quick brown fox jumps over the lazy dog. " * 20
        resource = RNS::Resource.new(original_data.to_slice, link, advertise: false)
        resource.sender_parts.size.should eq(resource.total_parts)
        resource.sender_parts.each(&.data.size.should(be > 0))
      end
    end

    it "different data produces different resource hashes" do
      with_ft_resourcepath do
        link = create_ft_link
        r1 = RNS::Resource.new("Data set one".to_slice, link, advertise: false)
        r2 = RNS::Resource.new("Data set two".to_slice, link, advertise: false)
        r1.hash.should_not eq(r2.hash)
      end
    end

    it "resource with metadata sets has_metadata flag" do
      with_ft_resourcepath do
        link = create_ft_link
        metadata = MessagePack::Any.new("test_metadata")
        resource = RNS::Resource.new("File content".to_slice, link, metadata: metadata, advertise: false)
        resource.has_metadata.should be_true
      end
    end
  end

  describe "Resource proof" do
    it "validate_proof accepts correct proof" do
      with_ft_resourcepath do
        link = create_ft_link
        resource = RNS::Resource.new(Random::Secure.random_bytes(512), link, advertise: false)
        # valid proof_data must be 64 bytes (hash_len*2 = 32*2) with the last 32 bytes == expected_proof
        proof_data = Bytes.new(resource.hash.size + resource.expected_proof.size)
        resource.hash.copy_to(proof_data)
        resource.expected_proof.copy_to(proof_data + resource.hash.size)
        resource.validate_proof(proof_data)
        resource.status.should eq(RNS::Resource::COMPLETE)
      end
    end

    it "validate_proof rejects incorrect proof" do
      with_ft_resourcepath do
        link = create_ft_link
        resource = RNS::Resource.new(Random::Secure.random_bytes(512), link, advertise: false)
        resource.validate_proof(Random::Secure.random_bytes(64))
        resource.status.should_not eq(RNS::Resource::COMPLETE)
      end
    end
  end

  describe "Resource window management" do
    it "starts with correct initial window" do
      with_ft_resourcepath do
        link = create_ft_link
        resource = RNS::Resource.new(Random::Secure.random_bytes(8192), link, advertise: false)
        resource.window.should eq(RNS::Resource::WINDOW)
        resource.window_min.should eq(RNS::Resource::WINDOW_MIN)
        resource.window_max.should eq(RNS::Resource::WINDOW_MAX_SLOW)
      end
    end
  end

  describe "Resource callbacks" do
    it "accepts progress callback" do
      with_ft_resourcepath do
        link = create_ft_link
        resource = RNS::Resource.new(Random::Secure.random_bytes(256), link, advertise: false,
          progress_callback: ->(_r : RNS::Resource) { })
        resource.should_not be_nil
      end
    end

    it "accepts concluded callback" do
      with_ft_resourcepath do
        link = create_ft_link
        resource = RNS::Resource.new(Random::Secure.random_bytes(256), link, advertise: false,
          callback: ->(_r : RNS::Resource) { })
        resource.should_not be_nil
      end
    end
  end

  describe "BZip2 compression integration" do
    it "compresses and decompresses resource-like data" do
      original = "A" * 10000
      compressed = RNS::BZip2.compress(original.to_slice)
      compressed.size.should be < original.size
      RNS::BZip2.decompress(compressed).should eq(original.to_slice)
    end

    it "handles random data (low compressibility)" do
      original = Random::Secure.random_bytes(4096)
      RNS::BZip2.decompress(RNS::BZip2.compress(original)).should eq(original)
    end
  end

  describe "Stress tests" do
    it "creates 20 resources of varying sizes" do
      with_ft_resourcepath do
        link = create_ft_link
        [64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768,
         100, 200, 500, 1000, 3000, 5000, 10000, 20000, 40000, 50000].each do |size|
          resource = RNS::Resource.new(Random::Secure.random_bytes(size), link, advertise: false)
          resource.total_size.should eq(size)
          resource.total_parts.should be >= 1
        end
      end
    end

    it "validates 50 resource proofs" do
      with_ft_resourcepath do
        link = create_ft_link
        50.times do
          resource = RNS::Resource.new(Random::Secure.random_bytes(Random.rand(64..4096)), link, advertise: false)
          correct_proof = Bytes.new(resource.hash.size + resource.expected_proof.size)
          resource.hash.copy_to(correct_proof)
          resource.expected_proof.copy_to(correct_proof + resource.hash.size)
          resource.validate_proof(correct_proof)
          resource.status.should eq(RNS::Resource::COMPLETE)
        end
      end
    end

    it "advertisement roundtrip for 30 resources" do
      with_ft_resourcepath do
        link = create_ft_link
        30.times do
          resource = RNS::Resource.new(Random::Secure.random_bytes(Random.rand(128..8192)), link, advertise: false)
          adv = RNS::ResourceAdvertisement.new(resource)
          unpacked = RNS::ResourceAdvertisement.unpack(adv.pack)
          unpacked.h.should eq(adv.h)
          unpacked.n.should eq(adv.n)
        end
      end
    end
  end
end
