require "benchmark"
require "../src/rns"

# ═══════════════════════════════════════════════════════════════════════
# Resource Transfer Throughput Benchmarks
#
# Measures performance of:
#   - Data segmentation (splitting into SDU-sized chunks with hashing)
#   - ResourceAdvertisement pack/unpack (MessagePack serialization)
#   - Data hashing for integrity verification
#   - Simulated transfer throughput (segment + encrypt + hash pipeline)
#   - Compression overhead (bz2 compress/decompress)
# ═══════════════════════════════════════════════════════════════════════

puts "=" * 70
puts "RNS Resource Transfer Throughput Benchmarks"
puts "=" * 70
puts

# ── Constants ──────────────────────────────────────────────────────────
sdu = RNS::Packet::MDU.to_i
puts "  SDU (Segment Data Unit): #{sdu} bytes"
puts "  Max efficient size: #{RNS.prettysize(RNS::Resource::MAX_EFFICIENT_SIZE)}"
puts "  MAPHASH_LEN: #{RNS::Resource::MAPHASH_LEN} bytes"
puts

# ── Test data ──────────────────────────────────────────────────────────
data_1kb = Random::Secure.random_bytes(1024)
data_16kb = Random::Secure.random_bytes(16 * 1024)
data_64kb = Random::Secure.random_bytes(64 * 1024)
data_256kb = Random::Secure.random_bytes(256 * 1024)
data_1mb = Random::Secure.random_bytes(1024 * 1024)

# Pre-computed encryption key for simulated transfer
token_key = RNS::Cryptography::Token.generate_key
token = RNS::Cryptography::Token.new(token_key)

# ── 1. Data segmentation throughput ───────────────────────────────────
# Simulate splitting data into SDU-sized chunks with hash computation
# (core of Resource.send_part)

puts "─── Data Segmentation (split + hash) ───"

def segment_data(data : Bytes, sdu : Int32) : Array(Bytes)
  parts = [] of Bytes
  offset = 0
  while offset < data.size
    chunk_size = Math.min(sdu, data.size - offset)
    chunk = data[offset, chunk_size]
    parts << chunk
    offset += chunk_size
  end
  parts
end

def segment_with_hashes(data : Bytes, sdu : Int32) : {Array(Bytes), Array(Bytes)}
  parts = [] of Bytes
  hashes = [] of Bytes
  offset = 0
  while offset < data.size
    chunk_size = Math.min(sdu, data.size - offset)
    chunk = data[offset, chunk_size]
    parts << chunk
    full_hash = RNS::Identity.full_hash(chunk)
    hashes << full_hash[0, RNS::Resource::MAPHASH_LEN]
    offset += chunk_size
  end
  {parts, hashes}
end

Benchmark.ips do |x|
  x.report("Segment 1KB (#{(1024.0 / sdu).ceil.to_i} parts)") { segment_data(data_1kb, sdu) }
  x.report("Segment 16KB (#{(16384.0 / sdu).ceil.to_i} parts)") { segment_data(data_16kb, sdu) }
  x.report("Segment 64KB (#{(65536.0 / sdu).ceil.to_i} parts)") { segment_data(data_64kb, sdu) }
  x.report("Segment 256KB (#{(262144.0 / sdu).ceil.to_i} parts)") { segment_data(data_256kb, sdu) }
end
puts

puts "─── Segmentation + Hashing ───"
Benchmark.ips do |x|
  x.report("Seg+hash 1KB") { segment_with_hashes(data_1kb, sdu) }
  x.report("Seg+hash 16KB") { segment_with_hashes(data_16kb, sdu) }
  x.report("Seg+hash 64KB") { segment_with_hashes(data_64kb, sdu) }
  x.report("Seg+hash 256KB") { segment_with_hashes(data_256kb, sdu) }
end
puts

# ── 2. ResourceAdvertisement pack/unpack ──────────────────────────────
# Simulate what ResourceAdvertisement.pack produces

resource_hash = RNS::Identity.full_hash(data_16kb)
random_hash = Random::Secure.random_bytes(4)
num_parts = (16384.0 / sdu).ceil.to_i
hashmap = Random::Secure.random_bytes(num_parts * RNS::Resource::MAPHASH_LEN)

adv_data = {
  "t" => MessagePack::Any.new(16384_i64),
  "d" => MessagePack::Any.new(16384_i64),
  "n" => MessagePack::Any.new(num_parts.to_i64),
  "h" => MessagePack::Any.new(resource_hash),
  "r" => MessagePack::Any.new(random_hash),
  "o" => MessagePack::Any.new(resource_hash),
  "i" => MessagePack::Any.new(1_i64),
  "l" => MessagePack::Any.new(1_i64),
  "q" => MessagePack::Any.new(nil),
  "f" => MessagePack::Any.new(0_i64),
  "m" => MessagePack::Any.new(hashmap),
}

packed_adv = adv_data.to_msgpack

puts "─── ResourceAdvertisement Pack/Unpack ───"
Benchmark.ips do |x|
  x.report("Adv pack") { adv_data.to_msgpack }
  x.report("Adv unpack") { MessagePack::Any.from_msgpack(packed_adv) }
end
puts

# ── 3. Integrity hash computation ─────────────────────────────────────
puts "─── Integrity Hash (per-part) ───"
chunk = Random::Secure.random_bytes(sdu)

Benchmark.ips do |x|
  x.report("SHA-256 per SDU") { RNS::Cryptography.sha256(chunk) }
  x.report("Map hash (4B truncate)") do
    h = RNS::Identity.full_hash(chunk)
    h[0, RNS::Resource::MAPHASH_LEN]
  end
  x.report("Truncated hash (16B)") { RNS::Identity.truncated_hash(chunk) }
end
puts

# ── 4. Simulated transfer pipeline (segment + encrypt + hash) ─────────
puts "─── Simulated Transfer Pipeline ───"

def simulate_transfer(data : Bytes, sdu : Int32, token : RNS::Cryptography::Token)
  total_encrypted = 0_i64
  offset = 0
  while offset < data.size
    chunk_size = Math.min(sdu, data.size - offset)
    chunk = data[offset, chunk_size]

    # Compute map hash
    RNS::Identity.full_hash(chunk)

    # Encrypt (as would happen during packet.send)
    encrypted = token.encrypt(chunk)
    total_encrypted += encrypted.size

    offset += chunk_size
  end
  total_encrypted
end

[data_1kb, data_16kb, data_64kb, data_256kb, data_1mb].each_with_index do |data, i|
  labels = ["1KB", "16KB", "64KB", "256KB", "1MB"]
  label = labels[i]
  num_parts = (data.size.to_f64 / sdu).ceil.to_i

  iterations = case i
               when 4 then 10   # 1MB - fewer iterations
               when 3 then 50   # 256KB
               when 2 then 200  # 64KB
               when 1 then 500  # 16KB
               else        2000 # 1KB
               end

  elapsed = Time.measure do
    iterations.times do
      simulate_transfer(data, sdu, token)
    end
  end

  avg_time = elapsed.total_milliseconds / iterations
  throughput = (data.size.to_f64 * iterations) / elapsed.total_seconds / (1024 * 1024)

  puts "  #{label.rjust(5)} (#{num_parts.to_s.rjust(4)} parts): " \
       "#{avg_time.round(2).to_s.rjust(8)}ms avg, " \
       "#{throughput.round(1).to_s.rjust(7)} MB/s throughput"
end
puts

# ── 5. Window sizing impact ───────────────────────────────────────────
puts "─── Window Impact (parts sent per round) ───"
[RNS::Resource::WINDOW_MIN, RNS::Resource::WINDOW, RNS::Resource::WINDOW_MAX_SLOW,
 RNS::Resource::WINDOW_MAX_FAST].each do |window|
  parts_data = (0...window).map { Random::Secure.random_bytes(sdu) }

  elapsed = Time.measure do
    1000.times do
      parts_data.each do |part|
        token.encrypt(part)
      end
    end
  end

  avg_per_round = elapsed.total_milliseconds / 1000
  throughput = (sdu.to_f64 * window * 1000) / elapsed.total_seconds / (1024 * 1024)
  puts "  Window #{window.to_s.rjust(2)}: #{avg_per_round.round(2).to_s.rjust(8)}ms/round, " \
       "#{throughput.round(1).to_s.rjust(7)} MB/s, " \
       "#{(sdu * window)} bytes/round"
end
puts

# ── 6. Data reassembly (simulated receiver) ───────────────────────────
puts "─── Data Reassembly ───"

# Pre-segment data
segments_16kb = segment_data(data_16kb, sdu)
segments_64kb = segment_data(data_64kb, sdu)
segments_256kb = segment_data(data_256kb, sdu)

def reassemble(parts : Array(Bytes)) : Bytes
  total = parts.sum(&.size)
  result = Bytes.new(total)
  offset = 0
  parts.each do |part|
    part.copy_to(result + offset)
    offset += part.size
  end
  result
end

Benchmark.ips do |x|
  x.report("Reassemble 16KB (#{segments_16kb.size} parts)") { reassemble(segments_16kb) }
  x.report("Reassemble 64KB (#{segments_64kb.size} parts)") { reassemble(segments_64kb) }
  x.report("Reassemble 256KB (#{segments_256kb.size} parts)") { reassemble(segments_256kb) }
end
puts

puts "=" * 70
puts "Resource benchmarks complete."
puts "=" * 70
