require "./spec_helper"
require "benchmark"

# ═══════════════════════════════════════════════════════════════════════
# Benchmark Validation Specs
#
# These specs verify that all benchmark code compiles and runs correctly
# by exercising the same code paths with minimal iterations.
# They do NOT measure performance — just validate correctness.
# ═══════════════════════════════════════════════════════════════════════

describe "Benchmarks" do
  describe "crypto operations" do
    it "SHA-256 hashing works at various sizes" do
      [16, 256, 1024, 65536].each do |size|
        data = Random::Secure.random_bytes(size)
        result = RNS::Cryptography.sha256(data)
        result.size.should eq 32
      end
    end

    it "SHA-512 hashing works at various sizes" do
      [16, 256, 1024, 65536].each do |size|
        data = Random::Secure.random_bytes(size)
        result = RNS::Cryptography.sha512(data)
        result.size.should eq 64
      end
    end

    it "truncated and full hash work" do
      data = Random::Secure.random_bytes(64)
      RNS::Cryptography.truncated_hash(data).size.should eq 16
      RNS::Cryptography.full_hash(data).size.should eq 32
    end

    it "HMAC-SHA256 works at various sizes" do
      key = Random::Secure.random_bytes(32)
      [16, 256, 1024].each do |size|
        data = Random::Secure.random_bytes(size)
        result = RNS::Cryptography::HMAC.digest(key, data)
        result.size.should eq 32
      end
    end

    it "HKDF key derivation works" do
      ikm = Random::Secure.random_bytes(32)
      salt = Random::Secure.random_bytes(32)
      info = "benchmark context".to_slice
      [32, 64, 128].each do |length|
        result = RNS::Cryptography.hkdf(length, ikm, salt, info)
        result.size.should eq length
      end
    end

    it "AES-256-CBC encrypt/decrypt roundtrips" do
      key = Random::Secure.random_bytes(32)
      iv = Random::Secure.random_bytes(16)
      [16, 256, 1024].each do |size|
        data = Random::Secure.random_bytes(size)
        encrypted = RNS::Cryptography::AES256CBC.encrypt(data, key, iv)
        decrypted = RNS::Cryptography::AES256CBC.decrypt(encrypted, key, iv)
        decrypted.should eq data
      end
    end

    it "Token encrypt/decrypt roundtrips" do
      token_key = RNS::Cryptography::Token.generate_key
      token = RNS::Cryptography::Token.new(token_key)
      [16, 256, 1024].each do |size|
        data = Random::Secure.random_bytes(size)
        encrypted = token.encrypt(data)
        decrypted = token.decrypt(encrypted)
        decrypted.should eq data
      end
    end

    it "Ed25519 sign/verify roundtrips" do
      priv = RNS::Cryptography::Ed25519PrivateKey.generate
      pub = priv.public_key
      msg = Random::Secure.random_bytes(256)
      sig = priv.sign(msg)
      # verify raises on failure, returns nil on success
      pub.verify(sig, msg)
      # If we get here without exception, verification succeeded
    end

    it "X25519 key exchange produces matching shared secrets" do
      priv1 = RNS::Cryptography::X25519PrivateKey.generate
      priv2 = RNS::Cryptography::X25519PrivateKey.generate
      shared1 = priv1.exchange(priv2.public_key)
      shared2 = priv2.exchange(priv1.public_key)
      shared1.should eq shared2
    end

    it "SHA-256 throughput measurement runs" do
      data = Random::Secure.random_bytes(1024)
      iterations = 0
      elapsed = Time.measure do
        100.times do
          RNS::Cryptography.sha256(data)
          iterations += 1
        end
      end
      throughput = (1024.0 * iterations) / elapsed.total_seconds / (1024 * 1024)
      throughput.should be > 0
    end
  end

  describe "packet encoding/decoding" do
    it "creates and packs plaintext packets" do
      plain_dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.truncated_hash(Random::Secure.random_bytes(32)),
        type: RNS::Destination::PLAIN,
      )
      data = Random::Secure.random_bytes(128)
      pkt = RNS::Packet.new(plain_dest, data, RNS::Packet::DATA, RNS::Packet::NONE,
        create_receipt: false)
      pkt.pack
      pkt.raw.should_not be_nil
    end

    it "creates and packs encrypted packets" do
      identity = RNS::Identity.new
      single_dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.truncated_hash(Random::Secure.random_bytes(32)),
        type: RNS::Destination::SINGLE,
        identity: identity,
      )
      data = Random::Secure.random_bytes(32)
      pkt = RNS::Packet.new(single_dest, data, RNS::Packet::DATA, RNS::Packet::NONE,
        create_receipt: false)
      pkt.pack
      pkt.raw.should_not be_nil
    end

    it "unpacks packed packets" do
      plain_dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.truncated_hash(Random::Secure.random_bytes(32)),
        type: RNS::Destination::PLAIN,
      )
      data = Random::Secure.random_bytes(128)
      pkt = RNS::Packet.new(plain_dest, data, RNS::Packet::DATA, RNS::Packet::NONE,
        create_receipt: false)
      pkt.pack
      raw = pkt.raw.not_nil!.dup

      pkt2 = RNS::Packet.new(nil, raw, create_receipt: false)
      pkt2.unpack
      pkt2.data.should_not be_nil
    end

    it "computes packet hash" do
      plain_dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.truncated_hash(Random::Secure.random_bytes(32)),
        type: RNS::Destination::PLAIN,
      )
      pkt = RNS::Packet.new(plain_dest, Random::Secure.random_bytes(128),
        RNS::Packet::DATA, RNS::Packet::NONE, create_receipt: false)
      pkt.pack
      pkt.get_hash.should_not be_nil
    end

    it "Identity encrypt/decrypt roundtrips" do
      identity = RNS::Identity.new
      [32, 128].each do |size|
        data = Random::Secure.random_bytes(size)
        encrypted = identity.encrypt(data)
        decrypted = identity.decrypt(encrypted)
        decrypted.should_not be_nil
        decrypted.not_nil!.should eq data
      end
    end

    it "pack/unpack roundtrip throughput runs" do
      plain_dest = RNS::Destination::Stub.new(
        hash: RNS::Identity.truncated_hash(Random::Secure.random_bytes(32)),
        type: RNS::Destination::PLAIN,
      )
      payload = Random::Secure.random_bytes(128)
      iterations = 100

      elapsed = Time.measure do
        iterations.times do
          pkt = RNS::Packet.new(plain_dest, payload, RNS::Packet::DATA, RNS::Packet::NONE,
            create_receipt: false)
          pkt.pack
          raw = pkt.raw.not_nil!.dup
          pkt2 = RNS::Packet.new(nil, raw, create_receipt: false)
          pkt2.unpack
        end
      end
      rate = iterations.to_f64 / elapsed.total_seconds
      rate.should be > 0
    end
  end

  describe "link establishment" do
    it "X25519 keypair generation works" do
      priv = RNS::Cryptography::X25519PrivateKey.generate
      pub = priv.public_key
      pub.public_bytes.size.should eq 32
    end

    it "ECDH exchange produces shared secret" do
      priv1 = RNS::Cryptography::X25519PrivateKey.generate
      priv2 = RNS::Cryptography::X25519PrivateKey.generate
      shared = priv1.exchange(priv2.public_key)
      shared.size.should eq 32
    end

    it "HKDF derives link keys from shared secret" do
      shared = Random::Secure.random_bytes(32)
      link_id = RNS::Identity.truncated_hash(Random::Secure.random_bytes(64))
      derived = RNS::Cryptography.hkdf(64, shared, link_id, nil)
      derived.size.should eq 64
    end

    it "full handshake simulation runs" do
      link_id = RNS::Identity.truncated_hash(Random::Secure.random_bytes(64))

      # Initiator keygen
      i_prv = RNS::Cryptography::X25519PrivateKey.generate
      i_pub = i_prv.public_key
      i_sig = RNS::Cryptography::Ed25519PrivateKey.generate
      i_sig_pub = i_sig.public_key

      # Responder keygen + ECDH + derive
      r_prv = RNS::Cryptography::X25519PrivateKey.generate
      r_pub = r_prv.public_key
      r_shared = r_prv.exchange(i_pub)
      r_derived = RNS::Cryptography.hkdf(64, r_shared, link_id, nil)

      # Responder signs proof
      r_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
      proof_data = Random::Secure.random_bytes(128)
      sig = r_sig_prv.sign(proof_data)

      # Initiator verifies proof + ECDH + derive
      i_shared = i_prv.exchange(r_pub)
      i_derived = RNS::Cryptography.hkdf(64, i_shared, link_id, nil)

      # Both sides derive same key
      r_derived.should eq i_derived
    end

    it "link encrypt/decrypt over derived key works" do
      shared = Random::Secure.random_bytes(32)
      link_id = RNS::Identity.truncated_hash(Random::Secure.random_bytes(64))
      derived = RNS::Cryptography.hkdf(64, shared, link_id, nil)
      token = RNS::Cryptography::Token.new(derived)

      data = Random::Secure.random_bytes(128)
      encrypted = token.encrypt(data)
      decrypted = token.decrypt(encrypted)
      decrypted.should eq data
    end

    it "handshake throughput measurement runs" do
      link_id = RNS::Identity.truncated_hash(Random::Secure.random_bytes(64))
      iterations = 10

      elapsed = Time.measure do
        iterations.times do
          i_prv = RNS::Cryptography::X25519PrivateKey.generate
          i_pub = i_prv.public_key

          r_prv = RNS::Cryptography::X25519PrivateKey.generate
          r_pub = r_prv.public_key
          r_shared = r_prv.exchange(i_pub)
          RNS::Cryptography.hkdf(64, r_shared, link_id, nil)

          i_shared = i_prv.exchange(r_pub)
          RNS::Cryptography.hkdf(64, i_shared, link_id, nil)
        end
      end
      rate = iterations.to_f64 / elapsed.total_seconds
      rate.should be > 0
    end
  end

  describe "resource transfer" do
    it "data segmentation works" do
      sdu = RNS::Packet::MDU.to_i
      data = Random::Secure.random_bytes(16 * 1024)
      parts = [] of Bytes
      offset = 0
      while offset < data.size
        chunk_size = Math.min(sdu, data.size - offset)
        parts << data[offset, chunk_size]
        offset += chunk_size
      end
      parts.size.should eq (16384.0 / sdu).ceil.to_i
      # Reassemble and verify
      reassembled = IO::Memory.new
      parts.each { |p| reassembled.write(p) }
      reassembled.to_slice.should eq data
    end

    it "segmentation with hashing works" do
      sdu = RNS::Packet::MDU.to_i
      data = Random::Secure.random_bytes(4 * 1024)
      hashes = [] of Bytes
      offset = 0
      while offset < data.size
        chunk_size = Math.min(sdu, data.size - offset)
        chunk = data[offset, chunk_size]
        full_hash = RNS::Identity.full_hash(chunk)
        hashes << full_hash[0, RNS::Resource::MAPHASH_LEN]
        offset += chunk_size
      end
      hashes.size.should be > 0
      hashes.each { |h| h.size.should eq RNS::Resource::MAPHASH_LEN }
    end

    it "ResourceAdvertisement MessagePack roundtrips" do
      resource_hash = RNS::Identity.full_hash(Random::Secure.random_bytes(64))
      random_hash = Random::Secure.random_bytes(4)
      hashmap = Random::Secure.random_bytes(40)

      adv_data = {
        "t" => MessagePack::Any.new(16384_i64),
        "d" => MessagePack::Any.new(16384_i64),
        "n" => MessagePack::Any.new(35_i64),
        "h" => MessagePack::Any.new(resource_hash),
        "r" => MessagePack::Any.new(random_hash),
        "o" => MessagePack::Any.new(resource_hash),
        "i" => MessagePack::Any.new(1_i64),
        "l" => MessagePack::Any.new(1_i64),
        "q" => MessagePack::Any.new(nil),
        "f" => MessagePack::Any.new(0_i64),
        "m" => MessagePack::Any.new(hashmap),
      }

      packed = adv_data.to_msgpack
      unpacked = MessagePack::Any.from_msgpack(packed)
      unpacked["t"].as_i64.should eq 16384_i64
      unpacked["n"].as_i64.should eq 35_i64
    end

    it "simulated transfer pipeline runs" do
      sdu = RNS::Packet::MDU.to_i
      token_key = RNS::Cryptography::Token.generate_key
      token = RNS::Cryptography::Token.new(token_key)
      data = Random::Secure.random_bytes(4 * 1024)

      total_encrypted = 0_i64
      offset = 0
      while offset < data.size
        chunk_size = Math.min(sdu, data.size - offset)
        chunk = data[offset, chunk_size]
        RNS::Identity.full_hash(chunk)
        encrypted = token.encrypt(chunk)
        total_encrypted += encrypted.size
        offset += chunk_size
      end
      total_encrypted.should be > data.size
    end

    it "data reassembly works" do
      sdu = RNS::Packet::MDU.to_i
      data = Random::Secure.random_bytes(64 * 1024)
      parts = [] of Bytes
      offset = 0
      while offset < data.size
        chunk_size = Math.min(sdu, data.size - offset)
        parts << data[offset, chunk_size]
        offset += chunk_size
      end

      total = parts.sum(&.size)
      result = Bytes.new(total)
      result_offset = 0
      parts.each do |part|
        part.copy_to(result + result_offset)
        result_offset += part.size
      end
      result.should eq data
    end

    it "window sizing exercise runs" do
      sdu = RNS::Packet::MDU.to_i
      token_key = RNS::Cryptography::Token.generate_key
      token = RNS::Cryptography::Token.new(token_key)

      [RNS::Resource::WINDOW_MIN, RNS::Resource::WINDOW, RNS::Resource::WINDOW_MAX_SLOW].each do |window|
        parts_data = (0...window).map { Random::Secure.random_bytes(sdu) }
        parts_data.each do |part|
          encrypted = token.encrypt(part)
          encrypted.size.should be > part.size
        end
      end
    end
  end

  describe "Benchmark.ips compatibility" do
    it "Benchmark.ips can be called" do
      # Verify the Benchmark module works for our usage
      Benchmark.ips(warmup: 10.milliseconds, calculation: 10.milliseconds) do |x|
        x.report("noop") { 1 + 1 }
      end
    end
  end
end
