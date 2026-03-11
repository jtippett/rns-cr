require "benchmark"
require "../src/rns"

# ═══════════════════════════════════════════════════════════════════════
# Packet Encoding/Decoding Benchmarks
#
# Measures performance of:
#   - Packet creation and packing (header + data encoding)
#   - Packet unpacking (header + data decoding)
#   - Packet hash computation
#   - Identity encrypt/decrypt (used during packet encryption)
# ═══════════════════════════════════════════════════════════════════════

puts "=" * 70
puts "RNS Packet Encoding/Decoding Benchmarks"
puts "=" * 70
puts

# ── Setup ──────────────────────────────────────────────────────────────
identity = RNS::Identity.new

# Use Destination::Stub for benchmark isolation (no Transport registration)
plain_dest = RNS::Destination::Stub.new(
  hash: RNS::Identity.truncated_hash(Random::Secure.random_bytes(32)),
  type: RNS::Destination::PLAIN,
)

single_dest = RNS::Destination::Stub.new(
  hash: RNS::Identity.truncated_hash(Random::Secure.random_bytes(32)),
  type: RNS::Destination::SINGLE,
  identity: identity,
)

# Various payload sizes within MTU limits
small_data = Random::Secure.random_bytes(32)
medium_data = Random::Secure.random_bytes(128)
max_plain = Random::Secure.random_bytes(RNS::Packet::PLAIN_MDU.to_i)
max_enc = Random::Secure.random_bytes([RNS::Packet::ENCRYPTED_MDU.to_i, 1].max)

# ── 1. Plaintext packet pack ──────────────────────────────────────────
puts "─── Plaintext Packet Pack ───"
Benchmark.ips do |x|
  x.report("Pack plain 32B") do
    pkt = RNS::Packet.new(plain_dest, small_data, RNS::Packet::DATA, RNS::Packet::NONE,
      create_receipt: false)
    pkt.pack
  end
  x.report("Pack plain 128B") do
    pkt = RNS::Packet.new(plain_dest, medium_data, RNS::Packet::DATA, RNS::Packet::NONE,
      create_receipt: false)
    pkt.pack
  end
  x.report("Pack plain max MDU") do
    pkt = RNS::Packet.new(plain_dest, max_plain, RNS::Packet::DATA, RNS::Packet::NONE,
      create_receipt: false)
    pkt.pack
  end
end
puts

# ── 2. Encrypted packet pack ─────────────────────────────────────────
puts "─── Encrypted Packet Pack (SINGLE dest) ───"
Benchmark.ips do |x|
  x.report("Pack encrypted 32B") do
    pkt = RNS::Packet.new(single_dest, small_data, RNS::Packet::DATA, RNS::Packet::NONE,
      create_receipt: false)
    pkt.pack
  end
  x.report("Pack encrypted 128B") do
    pkt = RNS::Packet.new(single_dest, medium_data, RNS::Packet::DATA, RNS::Packet::NONE,
      create_receipt: false)
    pkt.pack
  end
  x.report("Pack encrypted max") do
    pkt = RNS::Packet.new(single_dest, max_enc, RNS::Packet::DATA, RNS::Packet::NONE,
      create_receipt: false)
    pkt.pack
  end
end
puts

# ── 3. Packet unpack ──────────────────────────────────────────────────
# Pre-pack some packets for unpack benchmarking
packed_plain = begin
  pkt = RNS::Packet.new(plain_dest, medium_data, RNS::Packet::DATA, RNS::Packet::NONE,
    create_receipt: false)
  pkt.pack
  pkt.raw.not_nil!.dup
end

packed_small = begin
  pkt = RNS::Packet.new(plain_dest, small_data, RNS::Packet::DATA, RNS::Packet::NONE,
    create_receipt: false)
  pkt.pack
  pkt.raw.not_nil!.dup
end

puts "─── Packet Unpack ───"
Benchmark.ips do |x|
  x.report("Unpack 32B payload") do
    pkt = RNS::Packet.new(nil, packed_small, create_receipt: false)
    pkt.unpack
  end
  x.report("Unpack 128B payload") do
    pkt = RNS::Packet.new(nil, packed_plain, create_receipt: false)
    pkt.unpack
  end
end
puts

# ── 4. Packet hash computation ────────────────────────────────────────
hash_pkt = RNS::Packet.new(plain_dest, medium_data, RNS::Packet::DATA, RNS::Packet::NONE,
  create_receipt: false)
hash_pkt.pack

puts "─── Packet Hash Computation ───"
Benchmark.ips do |x|
  x.report("get_hash") { hash_pkt.get_hash }
  x.report("get_truncated_hash") { hash_pkt.get_truncated_hash }
  x.report("get_hashable_part") { hash_pkt.get_hashable_part }
end
puts

# ── 5. Identity encrypt/decrypt (used by SINGLE packets) ─────────────
puts "─── Identity Encrypt/Decrypt ───"
enc_data_32 = identity.encrypt(small_data)
enc_data_128 = identity.encrypt(medium_data)

Benchmark.ips do |x|
  x.report("Identity encrypt 32B") { identity.encrypt(small_data) }
  x.report("Identity encrypt 128B") { identity.encrypt(medium_data) }
  x.report("Identity decrypt 32B") { identity.decrypt(enc_data_32) }
  x.report("Identity decrypt 128B") { identity.decrypt(enc_data_128) }
end
puts

# ── 6. Identity creation ──────────────────────────────────────────────
puts "─── Identity Creation ───"
Benchmark.ips do |x|
  x.report("Identity.new (keygen)") { RNS::Identity.new }
  x.report("Identity hash") { RNS::Identity.full_hash(small_data) }
  x.report("Identity truncated_hash") { RNS::Identity.truncated_hash(small_data) }
  x.report("Identity get_random_hash") { RNS::Identity.get_random_hash }
end
puts

# ── 7. Pack/unpack roundtrip throughput ───────────────────────────────
puts "─── Pack/Unpack Roundtrip Throughput ───"
iterations = 10_000
data_payload = Random::Secure.random_bytes(128)

elapsed = Time.measure do
  iterations.times do
    pkt = RNS::Packet.new(plain_dest, data_payload, RNS::Packet::DATA, RNS::Packet::NONE,
      create_receipt: false)
    pkt.pack
    raw = pkt.raw.not_nil!.dup
    pkt2 = RNS::Packet.new(nil, raw, create_receipt: false)
    pkt2.unpack
  end
end
rate = iterations.to_f64 / elapsed.total_seconds
puts "  #{iterations} pack/unpack roundtrips in #{elapsed.total_milliseconds.round(1)}ms"
puts "  Rate: #{rate.round(0)} roundtrips/sec"
puts "  Throughput: #{(rate * 128 / (1024 * 1024)).round(2)} MB/s payload"
puts

puts "=" * 70
puts "Packet benchmarks complete."
puts "=" * 70
