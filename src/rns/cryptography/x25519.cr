require "ed25519"

module RNS
  module Cryptography
    class X25519PublicKey
      @public_bytes : Bytes

      def initialize(@public_bytes : Bytes)
      end

      def self.from_public_bytes(data : Bytes) : X25519PublicKey
        raise ArgumentError.new("X25519 public key must be 32 bytes, got #{data.size}") unless data.size == 32
        # Mask the most significant bit per RFC 7748 Section 5
        clamped = data.dup
        clamped[31] &= 127_u8
        X25519PublicKey.new(clamped)
      end

      def public_bytes : Bytes
        @public_bytes.dup
      end
    end

    class X25519PrivateKey
      MIN_EXEC_TIME = 0.002.seconds
      MAX_EXEC_TIME = 0.5.seconds
      DELAY_WINDOW  = 10.seconds

      @@t_clear : Time::Instant? = nil
      @@t_max : Time::Span = Time::Span.zero

      @private_bytes : Bytes

      def initialize(@private_bytes : Bytes)
      end

      def self.generate : X25519PrivateKey
        from_private_bytes(Random::Secure.random_bytes(32))
      end

      def self.from_private_bytes(data : Bytes) : X25519PrivateKey
        raise ArgumentError.new("X25519 private key must be 32 bytes, got #{data.size}") unless data.size == 32
        # Clamp the scalar per RFC 7748 / Curve25519 spec
        clamped = data.dup
        clamped[0] &= 248_u8    # Clear 3 least significant bits
        clamped[31] &= 127_u8   # Clear most significant bit (bit 255)
        clamped[31] |= 64_u8    # Set second most significant bit (bit 254)
        X25519PrivateKey.new(clamped)
      end

      def private_bytes : Bytes
        @private_bytes.dup
      end

      def public_key : X25519PublicKey
        pub_bytes = Ed25519::Curve25519.scalar_mult_base(@private_bytes)
        X25519PublicKey.from_public_bytes(pub_bytes)
      end

      def exchange(peer_public_key : X25519PublicKey) : Bytes
        exchange_raw(peer_public_key.public_bytes)
      end

      def exchange(peer_public_key : Bytes) : Bytes
        exchange_raw(peer_public_key)
      end

      private def exchange_raw(peer_public_bytes : Bytes) : Bytes
        start = Time.instant

        shared = Ed25519::Curve25519.scalar_mult(@private_bytes, peer_public_bytes)

        finish = Time.instant
        duration = finish - start

        t_clear = @@t_clear
        if t_clear.nil?
          @@t_clear = finish + DELAY_WINDOW
        end

        t_clear = @@t_clear.not_nil!
        if finish > t_clear
          @@t_clear = finish + DELAY_WINDOW
          @@t_max = Time::Span.zero
        end

        if duration < @@t_max || duration < MIN_EXEC_TIME
          target_duration = @@t_max

          if target_duration > MAX_EXEC_TIME
            target_duration = MAX_EXEC_TIME
          end

          if target_duration < MIN_EXEC_TIME
            target_duration = MIN_EXEC_TIME
          end

          elapsed = Time.instant - start
          remaining = target_duration - elapsed
          sleep(remaining) if remaining > Time::Span.zero
        elsif duration > @@t_max
          @@t_max = duration
        end

        shared
      end
    end
  end
end
