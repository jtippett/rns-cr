require "benchmark"
require "../src/rns"

# ═══════════════════════════════════════════════════════════════════════
# Link Establishment Benchmarks
#
# Measures performance of the computational parts of link establishment:
#   - ECDH key pair generation
#   - ECDH key exchange (shared secret derivation)
#   - HKDF symmetric key derivation
#   - Link encrypt/decrypt over derived keys
#   - Full handshake simulation (without network I/O)
#   - Link sign/verify operations
# ═══════════════════════════════════════════════════════════════════════

puts "=" * 70
puts "RNS Link Establishment Benchmarks"
puts "=" * 70
puts

# ── Setup: Simulate a link handshake without Transport/network ─────────
# We create the crypto objects directly to benchmark the computational
# cost of link establishment independent of network latency.

# Simulate initiator and responder key pairs
initiator_prv = RNS::Cryptography::X25519PrivateKey.generate
initiator_pub = initiator_prv.public_key
initiator_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
initiator_sig_pub = initiator_sig_prv.public_key

responder_prv = RNS::Cryptography::X25519PrivateKey.generate
responder_pub = responder_prv.public_key
responder_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
responder_sig_pub = responder_sig_prv.public_key

# Pre-compute a shared secret and derived key for encrypt/decrypt tests
shared_key = initiator_prv.exchange(responder_pub)
link_id = RNS::Identity.truncated_hash(Random::Secure.random_bytes(64))
derived_key = RNS::Cryptography.hkdf(
  length: 64, # AES-256-CBC mode = 64 bytes
  derive_from: shared_key,
  salt: link_id,
  context: nil
)
token = RNS::Cryptography::Token.new(derived_key)

# Test data
small_data = Random::Secure.random_bytes(32)
medium_data = Random::Secure.random_bytes(128)
link_mdu = Random::Secure.random_bytes(RNS::Link::MDU.to_i.clamp(1, 383))

# Pre-encrypt for decrypt benchmarks
encrypted_small = token.encrypt(small_data)
encrypted_medium = token.encrypt(medium_data)
encrypted_mdu = token.encrypt(link_mdu)

# ── 1. Key generation cost ────────────────────────────────────────────
puts "─── Key Generation (per-link cost) ───"
Benchmark.ips do |x|
  x.report("X25519 keypair") do
    k = RNS::Cryptography::X25519PrivateKey.generate
    k.public_key
  end
  x.report("Ed25519 keypair") do
    k = RNS::Cryptography::Ed25519PrivateKey.generate
    k.public_key
  end
  x.report("Both keypairs (link init)") do
    xk = RNS::Cryptography::X25519PrivateKey.generate
    xk.public_key
    ek = RNS::Cryptography::Ed25519PrivateKey.generate
    ek.public_key
  end
end
puts

# ── 2. ECDH exchange ──────────────────────────────────────────────────
puts "─── ECDH Key Exchange ───"
Benchmark.ips do |x|
  x.report("X25519 exchange") { initiator_prv.exchange(responder_pub) }
end
puts

# ── 3. Key derivation ─────────────────────────────────────────────────
puts "─── HKDF Key Derivation (link keys) ───"
Benchmark.ips do |x|
  x.report("HKDF 32B (AES-128)") do
    RNS::Cryptography.hkdf(32, shared_key, link_id, nil)
  end
  x.report("HKDF 64B (AES-256)") do
    RNS::Cryptography.hkdf(64, shared_key, link_id, nil)
  end
end
puts

# ── 4. Full handshake simulation ──────────────────────────────────────
puts "─── Full Handshake Simulation (compute only) ───"
Benchmark.ips do |x|
  x.report("Initiator side") do
    # Generate ephemeral keypair
    prv = RNS::Cryptography::X25519PrivateKey.generate
    prv.public_key
    sig = RNS::Cryptography::Ed25519PrivateKey.generate
    sig.public_key
  end

  x.report("Responder side") do
    # Generate ephemeral keypair + ECDH + derive keys
    prv = RNS::Cryptography::X25519PrivateKey.generate
    prv.public_key
    sk = prv.exchange(initiator_pub)
    RNS::Cryptography.hkdf(64, sk, link_id, nil)
  end

  x.report("Complete handshake") do
    # Initiator keygen
    i_prv = RNS::Cryptography::X25519PrivateKey.generate
    i_pub = i_prv.public_key
    i_sig = RNS::Cryptography::Ed25519PrivateKey.generate
    i_sig.public_key

    # Responder keygen + ECDH + derive
    r_prv = RNS::Cryptography::X25519PrivateKey.generate
    r_pub = r_prv.public_key
    r_shared = r_prv.exchange(i_pub)
    r_derived = RNS::Cryptography.hkdf(64, r_shared, link_id, nil)

    # Responder signs proof
    r_sig_prv = RNS::Cryptography::Ed25519PrivateKey.generate
    proof_data = Random::Secure.random_bytes(128)
    r_sig_prv.sign(proof_data)

    # Initiator verifies proof + ECDH + derive
    i_shared = i_prv.exchange(r_pub)
    RNS::Cryptography.hkdf(64, i_shared, link_id, nil)
  end
end
puts

# ── 5. Link encrypt/decrypt ───────────────────────────────────────────
puts "─── Link Encrypt (over derived key) ───"
Benchmark.ips do |x|
  x.report("Encrypt 32B") { token.encrypt(small_data) }
  x.report("Encrypt 128B") { token.encrypt(medium_data) }
  x.report("Encrypt MDU (#{link_mdu.size}B)") { token.encrypt(link_mdu) }
end
puts

puts "─── Link Decrypt (over derived key) ───"
Benchmark.ips do |x|
  x.report("Decrypt 32B") { token.decrypt(encrypted_small) }
  x.report("Decrypt 128B") { token.decrypt(encrypted_medium) }
  x.report("Decrypt MDU (#{link_mdu.size}B)") { token.decrypt(encrypted_mdu) }
end
puts

# ── 6. Link sign/verify ───────────────────────────────────────────────
message = Random::Secure.random_bytes(256)
signature = initiator_sig_prv.sign(message)

puts "─── Link Sign/Verify ───"
Benchmark.ips do |x|
  x.report("Ed25519 sign") { initiator_sig_prv.sign(message) }
  x.report("Ed25519 verify") { initiator_sig_pub.verify(signature, message) }
end
puts

# ── 7. Handshake throughput measurement ───────────────────────────────
puts "─── Handshake Throughput ───"
iterations = 1000
elapsed = Time.measure do
  iterations.times do
    # Full handshake compute simulation
    i_prv = RNS::Cryptography::X25519PrivateKey.generate
    i_pub = i_prv.public_key
    i_sig = RNS::Cryptography::Ed25519PrivateKey.generate
    i_sig_pub = i_sig.public_key

    r_prv = RNS::Cryptography::X25519PrivateKey.generate
    r_pub = r_prv.public_key
    r_shared = r_prv.exchange(i_pub)
    r_derived = RNS::Cryptography.hkdf(64, r_shared, link_id, nil)

    i_shared = i_prv.exchange(r_pub)
    i_derived = RNS::Cryptography.hkdf(64, i_shared, link_id, nil)
  end
end
rate = iterations.to_f64 / elapsed.total_seconds
puts "  #{iterations} complete handshakes in #{elapsed.total_milliseconds.round(1)}ms"
puts "  Rate: #{rate.round(1)} handshakes/sec"
puts "  Avg: #{(elapsed.total_milliseconds / iterations).round(3)}ms per handshake"
puts

puts "=" * 70
puts "Link benchmarks complete."
puts "=" * 70
