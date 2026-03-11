module RNS
  module Transport
    # ════════════════════════════════════════════════════════════════
    #  Tunnel Management
    #
    #  Ported from RNS/Transport.py — tunnel creation, restoration,
    #  synthesis, and validation logic.
    # ════════════════════════════════════════════════════════════════

    # Handles a tunnel establishment or restoration.
    # For new tunnels, creates an entry in the tunnels table.
    # For existing tunnels, restores paths and updates the interface.
    def self.handle_tunnel(tunnel_id : Bytes, interface_hash : Bytes?)
      expires = Time.utc.to_unix_f + DESTINATION_TIMEOUT.to_f64
      tunnel_hex = tunnel_id.hexstring

      if !@@tunnels.has_key?(tunnel_hex)
        RNS.log("Tunnel endpoint #{RNS.prettyhexrep(tunnel_id)} established.", RNS::LOG_DEBUG)
        paths = Hash(String, PathEntry).new
        tunnel_entry = TunnelEntry.new(
          tunnel_id: tunnel_id,
          interface: interface_hash,
          paths: paths,
          expires: expires,
        )
        @@tunnels[tunnel_hex] = tunnel_entry
      else
        RNS.log("Tunnel endpoint #{RNS.prettyhexrep(tunnel_id)} reappeared. Restoring paths...", RNS::LOG_DEBUG)
        tunnel_entry = @@tunnels[tunnel_hex]
        paths = tunnel_entry.paths

        # Update the tunnel entry with new interface and expiry
        @@tunnels[tunnel_hex] = TunnelEntry.new(
          tunnel_id: tunnel_entry.tunnel_id,
          interface: interface_hash,
          paths: paths,
          expires: expires,
        )

        deprecated_paths = [] of String

        paths.each do |dest_hex, path_entry|
          received_from = path_entry.next_hop
          announce_hops = path_entry.hops
          path_expires = path_entry.expires
          random_blobs = path_entry.random_blobs.dup.uniq(&.hexstring)
          packet_hash = path_entry.packet_hash

          new_entry = PathEntry.new(
            timestamp: Time.utc.to_unix_f,
            next_hop: received_from,
            hops: announce_hops,
            expires: path_expires,
            random_blobs: random_blobs,
            receiving_interface: interface_hash,
            packet_hash: packet_hash,
          )

          should_add = false
          if @@path_table.has_key?(dest_hex)
            old_entry = @@path_table[dest_hex]
            old_hops = old_entry.hops
            old_expires = old_entry.expires
            if announce_hops <= old_hops || Time.utc.to_unix_f > old_expires
              should_add = true
            else
              RNS.log("Did not restore path to #{dest_hex} because a newer path with fewer hops exists", RNS::LOG_DEBUG)
            end
          else
            if Time.utc.to_unix_f < path_expires
              should_add = true
            else
              RNS.log("Did not restore path to #{dest_hex} because it has expired", RNS::LOG_DEBUG)
            end
          end

          if should_add
            @@path_table[dest_hex] = new_entry
            RNS.log("Restored path to #{dest_hex} is now #{announce_hops} hops away via #{RNS.prettyhexrep(received_from)}", RNS::LOG_DEBUG)
          else
            deprecated_paths << dest_hex
          end
        end

        deprecated_paths.each do |dest_hex|
          RNS.log("Removing path to #{dest_hex} from tunnel #{RNS.prettyhexrep(tunnel_id)}", RNS::LOG_DEBUG)
          paths.delete(dest_hex)
        end
      end
    end

    # Voids the interface reference for a tunnel, keeping paths intact.
    def self.void_tunnel_interface(tunnel_id : Bytes)
      tunnel_hex = tunnel_id.hexstring
      if @@tunnels.has_key?(tunnel_hex)
        old = @@tunnels[tunnel_hex]
        RNS.log("Voiding tunnel interface for #{RNS.prettyhexrep(tunnel_id)}", RNS::LOG_EXTREME)
        @@tunnels[tunnel_hex] = TunnelEntry.new(
          tunnel_id: old.tunnel_id,
          interface: nil,
          paths: old.paths,
          expires: old.expires,
        )
      end
    end

    # Validates and processes a tunnel synthesis request.
    # Called when a tunnel synthesis DATA packet is received.
    # data format: public_key + interface_hash + random_hash + signature
    def self.tunnel_synthesize_handler(data : Bytes, packet : Packet)
      expected_length = Identity::KEYSIZE // 8 + Identity::HASHLENGTH // 8 + Reticulum::TRUNCATED_HASHLENGTH // 8 + Identity::SIGLENGTH // 8

      if data.size == expected_length
        public_key = data[0, Identity::KEYSIZE // 8]
        interface_hash_start = Identity::KEYSIZE // 8
        interface_hash = data[interface_hash_start, Identity::HASHLENGTH // 8]

        tunnel_id_data = Bytes.new(public_key.size + interface_hash.size)
        public_key.copy_to(tunnel_id_data)
        interface_hash.copy_to(tunnel_id_data + public_key.size)
        tunnel_id = Identity.full_hash(tunnel_id_data)

        random_hash_start = interface_hash_start + Identity::HASHLENGTH // 8
        random_hash = data[random_hash_start, Reticulum::TRUNCATED_HASHLENGTH // 8]

        sig_start = random_hash_start + Reticulum::TRUNCATED_HASHLENGTH // 8
        signature = data[sig_start, Identity::SIGLENGTH // 8]

        signed_data = Bytes.new(tunnel_id_data.size + random_hash.size)
        tunnel_id_data.copy_to(signed_data)
        random_hash.copy_to(signed_data + tunnel_id_data.size)

        remote_identity = Identity.new(create_keys: false)
        remote_identity.load_public_key(public_key)

        if remote_identity.validate(signature, signed_data)
          # Use nil for interface hash since we receive this from a packet
          # In full implementation, would use packet.receiving_interface
          handle_tunnel(tunnel_id, nil)
        end
      end
    rescue ex
      RNS.log("An error occurred while validating tunnel establishment packet: #{ex}", RNS::LOG_DEBUG)
    end

    # Creates and returns a tunnel synthesis packet data payload.
    # Returns {tunnel_id, data} or nil if no identity is set.
    def self.synthesize_tunnel_data(interface_hash : Bytes) : {Bytes, Bytes}?
      transport_identity = @@identity
      return nil unless transport_identity

      public_key = transport_identity.get_public_key
      random_hash = Identity.get_random_hash

      tunnel_id_data = Bytes.new(public_key.size + interface_hash.size)
      public_key.copy_to(tunnel_id_data)
      interface_hash.copy_to(tunnel_id_data + public_key.size)
      tunnel_id = Identity.full_hash(tunnel_id_data)

      signed_data = Bytes.new(tunnel_id_data.size + random_hash.size)
      tunnel_id_data.copy_to(signed_data)
      random_hash.copy_to(signed_data + tunnel_id_data.size)

      signature = transport_identity.sign(signed_data)

      data = Bytes.new(signed_data.size + signature.size)
      signed_data.copy_to(data)
      signature.copy_to(data + signed_data.size)

      {tunnel_id, data}
    end
  end
end
