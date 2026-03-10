require "../../spec_helper"

describe RNS::Cryptography::X25519PublicKey do
  describe ".from_public_bytes" do
    it "creates a public key from 32 bytes" do
      bytes = Random::Secure.random_bytes(32)
      key = RNS::Cryptography::X25519PublicKey.from_public_bytes(bytes)
      key.should be_a(RNS::Cryptography::X25519PublicKey)
    end

    it "raises on invalid length" do
      expect_raises(ArgumentError) do
        RNS::Cryptography::X25519PublicKey.from_public_bytes(Random::Secure.random_bytes(16))
      end
    end
  end

  describe "#public_bytes" do
    it "returns 32 bytes" do
      bytes = Random::Secure.random_bytes(32)
      key = RNS::Cryptography::X25519PublicKey.from_public_bytes(bytes)
      key.public_bytes.size.should eq(32)
    end

    it "roundtrips the public key bytes" do
      bytes = Random::Secure.random_bytes(32)
      key = RNS::Cryptography::X25519PublicKey.from_public_bytes(bytes)
      # Note: high bit of byte 31 is masked by X25519 spec
      expected = bytes.dup
      expected[31] &= 127_u8
      key.public_bytes.should eq(expected)
    end
  end
end

describe RNS::Cryptography::X25519PrivateKey do
  describe ".generate" do
    it "generates a private key" do
      key = RNS::Cryptography::X25519PrivateKey.generate
      key.should be_a(RNS::Cryptography::X25519PrivateKey)
    end

    it "generates unique keys each time" do
      key1 = RNS::Cryptography::X25519PrivateKey.generate
      key2 = RNS::Cryptography::X25519PrivateKey.generate
      key1.private_bytes.should_not eq(key2.private_bytes)
    end
  end

  describe ".from_private_bytes" do
    it "creates a private key from 32 bytes" do
      bytes = Random::Secure.random_bytes(32)
      key = RNS::Cryptography::X25519PrivateKey.from_private_bytes(bytes)
      key.should be_a(RNS::Cryptography::X25519PrivateKey)
    end

    it "raises on invalid length" do
      expect_raises(ArgumentError) do
        RNS::Cryptography::X25519PrivateKey.from_private_bytes(Random::Secure.random_bytes(16))
      end
    end

    it "clamps the private key (3 LSBs cleared, bit 255 cleared, bit 254 set)" do
      # All 0xFF bytes — clamping should modify byte 0 and byte 31
      bytes = Bytes.new(32, 0xFF_u8)
      key = RNS::Cryptography::X25519PrivateKey.from_private_bytes(bytes)
      result = key.private_bytes
      # Byte 0: 0xFF & 0xF8 = 0xF8
      (result[0] & 0x07).should eq(0)
      # Byte 31: bit 7 cleared, bit 6 set → 0xFF & 0x7F | 0x40 = 0x7F
      (result[31] & 0x80).should eq(0)
      (result[31] & 0x40).should eq(0x40)
    end
  end

  describe "#private_bytes" do
    it "returns 32 bytes" do
      key = RNS::Cryptography::X25519PrivateKey.generate
      key.private_bytes.size.should eq(32)
    end

    it "returns clamped bytes consistently" do
      key = RNS::Cryptography::X25519PrivateKey.generate
      key.private_bytes.should eq(key.private_bytes)
    end
  end

  describe "#public_key" do
    it "derives a public key from private key" do
      priv = RNS::Cryptography::X25519PrivateKey.generate
      pub = priv.public_key
      pub.should be_a(RNS::Cryptography::X25519PublicKey)
      pub.public_bytes.size.should eq(32)
    end

    it "derives the same public key each time" do
      priv = RNS::Cryptography::X25519PrivateKey.generate
      pub1 = priv.public_key
      pub2 = priv.public_key
      pub1.public_bytes.should eq(pub2.public_bytes)
    end
  end

  describe "#exchange" do
    it "two parties derive the same shared secret" do
      alice_priv = RNS::Cryptography::X25519PrivateKey.generate
      bob_priv = RNS::Cryptography::X25519PrivateKey.generate

      alice_pub = alice_priv.public_key
      bob_pub = bob_priv.public_key

      shared_alice = alice_priv.exchange(bob_pub)
      shared_bob = bob_priv.exchange(alice_pub)

      shared_alice.should eq(shared_bob)
      shared_alice.size.should eq(32)
    end

    it "different key pairs produce different shared secrets" do
      alice = RNS::Cryptography::X25519PrivateKey.generate
      bob1 = RNS::Cryptography::X25519PrivateKey.generate
      bob2 = RNS::Cryptography::X25519PrivateKey.generate

      shared1 = alice.exchange(bob1.public_key)
      shared2 = alice.exchange(bob2.public_key)
      shared1.should_not eq(shared2)
    end

    it "accepts raw bytes as peer_public_key" do
      alice = RNS::Cryptography::X25519PrivateKey.generate
      bob = RNS::Cryptography::X25519PrivateKey.generate

      shared1 = alice.exchange(bob.public_key)
      shared2 = alice.exchange(bob.public_key.public_bytes)
      shared1.should eq(shared2)
    end
  end

  describe "RFC 7748 test vectors" do
    it "derives correct public key for Alice (Section 6.1)" do
      alice_priv_hex = "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a"
      alice_pub_hex = "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"

      priv = RNS::Cryptography::X25519PrivateKey.from_private_bytes(alice_priv_hex.hexbytes)
      pub = priv.public_key
      pub.public_bytes.should eq(alice_pub_hex.hexbytes)
    end

    it "derives correct public key for Bob (Section 6.1)" do
      bob_priv_hex = "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb"
      bob_pub_hex = "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f"

      priv = RNS::Cryptography::X25519PrivateKey.from_private_bytes(bob_priv_hex.hexbytes)
      pub = priv.public_key
      pub.public_bytes.should eq(bob_pub_hex.hexbytes)
    end

    it "computes correct shared secret (Section 6.1)" do
      alice_priv_hex = "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a"
      bob_priv_hex = "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb"
      expected_shared_hex = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"

      alice_priv = RNS::Cryptography::X25519PrivateKey.from_private_bytes(alice_priv_hex.hexbytes)
      bob_priv = RNS::Cryptography::X25519PrivateKey.from_private_bytes(bob_priv_hex.hexbytes)

      alice_pub = alice_priv.public_key
      bob_pub = bob_priv.public_key

      shared_alice = alice_priv.exchange(bob_pub)
      shared_bob = bob_priv.exchange(alice_pub)

      shared_alice.should eq(expected_shared_hex.hexbytes)
      shared_bob.should eq(expected_shared_hex.hexbytes)
      shared_alice.should eq(shared_bob)
    end

    it "passes iterated test vector (1 iteration, Section 5.2)" do
      # Starting values: both k and u = basepoint (9)
      k_hex = "0900000000000000000000000000000000000000000000000000000000000000"
      u_hex = "0900000000000000000000000000000000000000000000000000000000000000"
      expected_hex = "422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079"

      k = k_hex.hexbytes
      u = u_hex.hexbytes

      # 1 iteration: result = X25519(k, u), then k = result, u = old_k
      priv = RNS::Cryptography::X25519PrivateKey.from_private_bytes(k)
      pub = RNS::Cryptography::X25519PublicKey.from_public_bytes(u)
      result = priv.exchange(pub)

      result.should eq(expected_hex.hexbytes)
    end

    it "passes iterated test vector (1000 iterations, Section 5.2)" do
      k_hex = "0900000000000000000000000000000000000000000000000000000000000000"
      u_hex = "0900000000000000000000000000000000000000000000000000000000000000"
      expected_hex = "684cf59ba83309552800ef566f2f4d3c1c3887c49360e3875f2eb94d99532c51"

      k = k_hex.hexbytes
      u = u_hex.hexbytes

      1000.times do
        priv = RNS::Cryptography::X25519PrivateKey.from_private_bytes(k)
        pub = RNS::Cryptography::X25519PublicKey.from_public_bytes(u)
        result = priv.exchange(pub)
        u = k.dup
        k = result
      end

      k.should eq(expected_hex.hexbytes)
    end
  end

  describe "key serialization roundtrip" do
    it "private key roundtrips through bytes" do
      original = RNS::Cryptography::X25519PrivateKey.generate
      bytes = original.private_bytes
      restored = RNS::Cryptography::X25519PrivateKey.from_private_bytes(bytes)
      restored.private_bytes.should eq(bytes)
    end

    it "public key roundtrips through bytes" do
      priv = RNS::Cryptography::X25519PrivateKey.generate
      original_pub = priv.public_key
      bytes = original_pub.public_bytes
      restored_pub = RNS::Cryptography::X25519PublicKey.from_public_bytes(bytes)
      restored_pub.public_bytes.should eq(bytes)
    end

    it "restored private key derives same public key" do
      original = RNS::Cryptography::X25519PrivateKey.generate
      pub1 = original.public_key.public_bytes
      restored = RNS::Cryptography::X25519PrivateKey.from_private_bytes(original.private_bytes)
      pub2 = restored.public_key.public_bytes
      pub1.should eq(pub2)
    end

    it "restored private key produces same shared secret" do
      alice = RNS::Cryptography::X25519PrivateKey.generate
      bob = RNS::Cryptography::X25519PrivateKey.generate

      shared1 = alice.exchange(bob.public_key)

      alice_restored = RNS::Cryptography::X25519PrivateKey.from_private_bytes(alice.private_bytes)
      shared2 = alice_restored.exchange(bob.public_key)

      shared1.should eq(shared2)
    end
  end

  describe "100 random key exchange roundtrips" do
    it "all produce matching shared secrets" do
      100.times do
        alice = RNS::Cryptography::X25519PrivateKey.generate
        bob = RNS::Cryptography::X25519PrivateKey.generate

        shared_a = alice.exchange(bob.public_key)
        shared_b = bob.exchange(alice.public_key)

        shared_a.should eq(shared_b)
        shared_a.size.should eq(32)
      end
    end
  end
end
