require "benchmark"
require "../src/rns"

# ═══════════════════════════════════════════════════════════════════════
# Cryptography Benchmarks
#
# Measures throughput and ops/sec for all crypto primitives used by RNS:
#   - SHA-256 / SHA-512 hashing
#   - HMAC-SHA256
#   - HKDF key derivation
#   - AES-256-CBC encrypt/decrypt
#   - Token (Fernet-like) encrypt/decrypt
#   - Ed25519 sign/verify
#   - X25519 key generation and exchange
# ═══════════════════════════════════════════════════════════════════════

puts "=" * 70
puts "RNS Cryptography Benchmarks"
puts "=" * 70
puts

# ── Test data ──────────────────────────────────────────────────────────
data_16b = Random::Secure.random_bytes(16)
data_64b = Random::Secure.random_bytes(64)
data_256b = Random::Secure.random_bytes(256)
data_1kb = Random::Secure.random_bytes(1024)
data_4kb = Random::Secure.random_bytes(4096)
data_64kb = Random::Secure.random_bytes(65536)
data_1mb = Random::Secure.random_bytes(1_048_576)

# ── 1. Hash throughput ─────────────────────────────────────────────────
puts "─── SHA-256 Throughput ───"
Benchmark.ips do |x|
  x.report("SHA-256 16B") { RNS::Cryptography.sha256(data_16b) }
  x.report("SHA-256 256B") { RNS::Cryptography.sha256(data_256b) }
  x.report("SHA-256 1KB") { RNS::Cryptography.sha256(data_1kb) }
  x.report("SHA-256 64KB") { RNS::Cryptography.sha256(data_64kb) }
  x.report("SHA-256 1MB") { RNS::Cryptography.sha256(data_1mb) }
end
puts

puts "─── SHA-512 Throughput ───"
Benchmark.ips do |x|
  x.report("SHA-512 16B") { RNS::Cryptography.sha512(data_16b) }
  x.report("SHA-512 256B") { RNS::Cryptography.sha512(data_256b) }
  x.report("SHA-512 1KB") { RNS::Cryptography.sha512(data_1kb) }
  x.report("SHA-512 64KB") { RNS::Cryptography.sha512(data_64kb) }
  x.report("SHA-512 1MB") { RNS::Cryptography.sha512(data_1mb) }
end
puts

puts "─── Truncated Hash ───"
Benchmark.ips do |x|
  x.report("truncated_hash 64B") { RNS::Cryptography.truncated_hash(data_64b) }
  x.report("full_hash 64B") { RNS::Cryptography.full_hash(data_64b) }
end
puts

# ── 2. HMAC throughput ─────────────────────────────────────────────────
hmac_key = Random::Secure.random_bytes(32)

puts "─── HMAC-SHA256 Throughput ───"
Benchmark.ips do |x|
  x.report("HMAC 16B") { RNS::Cryptography::HMAC.digest(hmac_key, data_16b) }
  x.report("HMAC 256B") { RNS::Cryptography::HMAC.digest(hmac_key, data_256b) }
  x.report("HMAC 1KB") { RNS::Cryptography::HMAC.digest(hmac_key, data_1kb) }
  x.report("HMAC 64KB") { RNS::Cryptography::HMAC.digest(hmac_key, data_64kb) }
end
puts

# ── 3. HKDF key derivation ────────────────────────────────────────────
hkdf_ikm = Random::Secure.random_bytes(32)
hkdf_salt = Random::Secure.random_bytes(32)
hkdf_info = "benchmark context".to_slice

puts "─── HKDF Key Derivation ───"
Benchmark.ips do |x|
  x.report("HKDF 32B output") { RNS::Cryptography.hkdf(32, hkdf_ikm, hkdf_salt, hkdf_info) }
  x.report("HKDF 64B output") { RNS::Cryptography.hkdf(64, hkdf_ikm, hkdf_salt, hkdf_info) }
  x.report("HKDF 128B output") { RNS::Cryptography.hkdf(128, hkdf_ikm, hkdf_salt, hkdf_info) }
end
puts

# ── 4. AES-256-CBC encrypt/decrypt ─────────────────────────────────────
aes_key = Random::Secure.random_bytes(32)
aes_iv = Random::Secure.random_bytes(16)
# Pre-pad data to block size for raw AES (no PKCS7 in raw AES benchmark)
aes_data_16b = Random::Secure.random_bytes(16)
aes_data_256b = Random::Secure.random_bytes(256)
aes_data_1kb = Random::Secure.random_bytes(1024)
aes_data_4kb = Random::Secure.random_bytes(4096)

aes_enc_16b = RNS::Cryptography::AES256CBC.encrypt(aes_data_16b, aes_key, aes_iv)
aes_enc_256b = RNS::Cryptography::AES256CBC.encrypt(aes_data_256b, aes_key, aes_iv)
aes_enc_1kb = RNS::Cryptography::AES256CBC.encrypt(aes_data_1kb, aes_key, aes_iv)
aes_enc_4kb = RNS::Cryptography::AES256CBC.encrypt(aes_data_4kb, aes_key, aes_iv)

puts "─── AES-256-CBC Encrypt ───"
Benchmark.ips do |x|
  x.report("AES encrypt 16B") { RNS::Cryptography::AES256CBC.encrypt(aes_data_16b, aes_key, aes_iv) }
  x.report("AES encrypt 256B") { RNS::Cryptography::AES256CBC.encrypt(aes_data_256b, aes_key, aes_iv) }
  x.report("AES encrypt 1KB") { RNS::Cryptography::AES256CBC.encrypt(aes_data_1kb, aes_key, aes_iv) }
  x.report("AES encrypt 4KB") { RNS::Cryptography::AES256CBC.encrypt(aes_data_4kb, aes_key, aes_iv) }
end
puts

puts "─── AES-256-CBC Decrypt ───"
Benchmark.ips do |x|
  x.report("AES decrypt 16B") { RNS::Cryptography::AES256CBC.decrypt(aes_enc_16b, aes_key, aes_iv) }
  x.report("AES decrypt 256B") { RNS::Cryptography::AES256CBC.decrypt(aes_enc_256b, aes_key, aes_iv) }
  x.report("AES decrypt 1KB") { RNS::Cryptography::AES256CBC.decrypt(aes_enc_1kb, aes_key, aes_iv) }
  x.report("AES decrypt 4KB") { RNS::Cryptography::AES256CBC.decrypt(aes_enc_4kb, aes_key, aes_iv) }
end
puts

# ── 5. Token (Fernet-like) encrypt/decrypt ────────────────────────────
token_key = RNS::Cryptography::Token.generate_key
token = RNS::Cryptography::Token.new(token_key)
token_enc_16b = token.encrypt(data_16b)
token_enc_256b = token.encrypt(data_256b)
token_enc_1kb = token.encrypt(data_1kb)

puts "─── Token Encrypt (AES-256-CBC + HMAC) ───"
Benchmark.ips do |x|
  x.report("Token encrypt 16B") { token.encrypt(data_16b) }
  x.report("Token encrypt 256B") { token.encrypt(data_256b) }
  x.report("Token encrypt 1KB") { token.encrypt(data_1kb) }
end
puts

puts "─── Token Decrypt (AES-256-CBC + HMAC) ───"
Benchmark.ips do |x|
  x.report("Token decrypt 16B") { token.decrypt(token_enc_16b) }
  x.report("Token decrypt 256B") { token.decrypt(token_enc_256b) }
  x.report("Token decrypt 1KB") { token.decrypt(token_enc_1kb) }
end
puts

# ── 6. Ed25519 sign/verify ─────────────────────────────────────────────
ed_priv = RNS::Cryptography::Ed25519PrivateKey.generate
ed_pub = ed_priv.public_key
ed_msg = Random::Secure.random_bytes(256)
ed_sig = ed_priv.sign(ed_msg)

puts "─── Ed25519 Sign/Verify ───"
Benchmark.ips do |x|
  x.report("Ed25519 sign 256B") { ed_priv.sign(ed_msg) }
  x.report("Ed25519 verify 256B") { ed_pub.verify(ed_sig, ed_msg) }
  x.report("Ed25519 keygen") { RNS::Cryptography::Ed25519PrivateKey.generate }
end
puts

# ── 7. X25519 key exchange ─────────────────────────────────────────────
x_priv1 = RNS::Cryptography::X25519PrivateKey.generate
x_priv2 = RNS::Cryptography::X25519PrivateKey.generate
x_pub2 = x_priv2.public_key

puts "─── X25519 Key Exchange ───"
Benchmark.ips do |x|
  x.report("X25519 keygen") { RNS::Cryptography::X25519PrivateKey.generate }
  x.report("X25519 pub from priv") { x_priv1.public_key }
  x.report("X25519 exchange") { x_priv1.exchange(x_pub2) }
end
puts

# ── Summary throughput calculation ─────────────────────────────────────
puts "─── SHA-256 Throughput (MB/s) ───"
[16, 256, 1024, 65536, 1_048_576].each do |size|
  data = Random::Secure.random_bytes(size)
  iterations = 0
  elapsed = Time.measure do
    100_000.times do
      RNS::Cryptography.sha256(data)
      iterations += 1
      break if iterations >= 100_000
    end
  end
  throughput = (size.to_f64 * iterations) / elapsed.total_seconds / (1024 * 1024)
  puts "  #{RNS.prettysize(size).rjust(8)}: #{throughput.round(1)} MB/s (#{iterations} ops in #{elapsed.total_milliseconds.round(1)}ms)"
end
puts

puts "=" * 70
puts "Crypto benchmarks complete."
puts "=" * 70
