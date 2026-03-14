module RNS
  module Transport
    # ════════════════════════════════════════════════════════════════
    #  Announce Handling
    #
    #  Ported from RNS/Transport.py — announce processing, rate
    #  limiting, deduplication, validation, and rebroadcast logic.
    # ════════════════════════════════════════════════════════════════

    # Extracts a timebase value from a random blob (bytes 5..9).
    # The random blob is 10 bytes; bytes 5..9 encode an emission timestamp.
    def self.timebase_from_random_blob(random_blob : Bytes) : Int64
      return 0_i64 if random_blob.size < 10
      # Read 5 bytes big-endian as a 40-bit integer
      result = 0_i64
      (5..9).each do |i|
        result = (result << 8) | random_blob[i].to_i64
      end
      result
    end

    # Extracts the maximum timebase from an array of random blobs.
    def self.timebase_from_random_blobs(random_blobs : Array(Bytes)) : Int64
      timebase = 0_i64
      random_blobs.each do |blob|
        emitted = timebase_from_random_blob(blob)
        timebase = emitted if emitted > timebase
      end
      timebase
    end

    # Extracts the announce emission timebase from a packet's data.
    def self.announce_emitted(packet : Packet) : Int64
      offset = Identity::KEYSIZE // 8 + Identity::NAME_HASH_LENGTH // 8
      random_blob = packet.data[offset, 10]
      timebase_from_random_blob(random_blob)
    end

    # Adds a packet hash to the deduplication hashlist.
    def self.add_packet_hash(packet_hash : Bytes)
      @@packet_hashlist << packet_hash.hexstring
    end

    # Checks if a packet hash is in the deduplication hashlist.
    def self.packet_hash_in_list?(packet_hash : Bytes) : Bool
      hex = packet_hash.hexstring
      @@packet_hashlist.includes?(hex) || @@packet_hashlist_prev.includes?(hex)
    end

    # Filters packets for deduplication and validity.
    # Returns true if the packet should be processed.
    def self.packet_filter(packet : Packet) : Bool
      # Filter packets intended for other transport instances
      if packet.transport_id && packet.packet_type != Packet::ANNOUNCE
        our_hash = @@identity.try(&.hash)
        if our_hash && packet.transport_id != our_hash
          ph = packet.packet_hash
          RNS.log("Ignored packet #{ph ? RNS.prettyhexrep(ph) : "unknown"} in transport for other transport instance", RNS::LOG_EXTREME)
          return false
        end
      end

      return true if packet.context == Packet::KEEPALIVE
      return true if packet.context == Packet::RESOURCE_REQ
      return true if packet.context == Packet::RESOURCE_PRF
      return true if packet.context == Packet::RESOURCE
      return true if packet.context == Packet::CACHE_REQUEST
      return true if packet.context == Packet::CHANNEL

      if packet.destination_type == Destination::PLAIN
        if packet.packet_type != Packet::ANNOUNCE
          if packet.hops > 1
            pph = packet.packet_hash
            RNS.log("Dropped PLAIN packet #{pph ? RNS.prettyhexrep(pph) : "unknown"} with #{packet.hops} hops", RNS::LOG_DEBUG)
            return false
          else
            return true
          end
        else
          RNS.log("Dropped invalid PLAIN announce packet", RNS::LOG_DEBUG)
          return false
        end
      end

      if packet.destination_type == Destination::GROUP
        if packet.packet_type != Packet::ANNOUNCE
          if packet.hops > 1
            gph = packet.packet_hash
            RNS.log("Dropped GROUP packet #{gph ? RNS.prettyhexrep(gph) : "unknown"} with #{packet.hops} hops", RNS::LOG_DEBUG)
            return false
          else
            return true
          end
        else
          RNS.log("Dropped invalid GROUP announce packet", RNS::LOG_DEBUG)
          return false
        end
      end

      ph = packet.packet_hash
      if ph && !packet_hash_in_list?(ph)
        return true
      else
        if packet.packet_type == Packet::ANNOUNCE
          if packet.destination_type == Destination::SINGLE
            return true
          else
            RNS.log("Dropped invalid announce packet", RNS::LOG_DEBUG)
            return false
          end
        end
      end

      fph = packet.packet_hash
      RNS.log("Filtered packet with hash #{fph ? RNS.prettyhexrep(fph) : "unknown"}", RNS::LOG_EXTREME)
      false
    end

    # Processes an inbound announce packet. This is the core of the
    # announce handling logic from RNS/Transport.py's inbound() method.
    #
    # Returns true if the announce was valid and processed, false otherwise.
    def self.inbound_announce(packet : Packet) : Bool
      return false unless packet.packet_type == Packet::ANNOUNCE

      # Validate announce signature
      return false unless Identity.validate_announce(packet, only_validate_signature: true)

      # Check if this is for a local destination
      local_destination = @@destinations.find { |dest| dest.hash == packet.destination_hash }
      return false if local_destination

      # Perform full validation
      return false unless Identity.validate_announce(packet)

      destination_hash = packet.destination_hash.not_nil!
      dest_hex = destination_hash.hexstring

      # Determine received_from
      received_from = if packet.transport_id
                        transport_id = packet.transport_id.not_nil!

                        # Check if this is a next retransmission from another node
                        if @@announce_table.has_key?(dest_hex)
                          announce_entry = @@announce_table[dest_hex]

                          if packet.hops.to_i32 - 1 == announce_entry.hops
                            RNS.log("Heard a rebroadcast of announce for #{RNS.prettyhexrep(destination_hash)}", RNS::LOG_EXTREME)
                            new_local_rebroadcasts = announce_entry.local_rebroadcasts + 1
                            @@announce_table[dest_hex] = AnnounceEntry.new(
                              timestamp: announce_entry.timestamp,
                              retransmit_timeout: announce_entry.retransmit_timeout,
                              retries: announce_entry.retries,
                              received_from: announce_entry.received_from,
                              hops: announce_entry.hops,
                              packet: announce_entry.packet,
                              local_rebroadcasts: new_local_rebroadcasts,
                              block_rebroadcasts: announce_entry.block_rebroadcasts,
                              attached_interface: announce_entry.attached_interface,
                            )

                            if announce_entry.retries > 0
                              if new_local_rebroadcasts >= LOCAL_REBROADCASTS_MAX
                                RNS.log("Completed announce processing for #{RNS.prettyhexrep(destination_hash)}, local rebroadcast limit reached", RNS::LOG_EXTREME)
                                @@announce_table.delete(dest_hex)
                              end
                            end
                          end

                          if packet.hops.to_i32 - 1 == announce_entry.hops + 1 && announce_entry.retries > 0
                            now = Time.utc.to_unix_f
                            if now < announce_entry.retransmit_timeout
                              RNS.log("Rebroadcasted announce for #{RNS.prettyhexrep(destination_hash)} has been passed on to another node, no further tries needed", RNS::LOG_EXTREME)
                              @@announce_table.delete(dest_hex)
                            end
                          end
                        end

                        transport_id
                      else
                        destination_hash
                      end

      # Check if this announce should be inserted into tables
      should_add = false

      # Must not be for a local destination and hops within limit
      if !@@destinations.any? { |dest| dest.hash == destination_hash } && packet.hops < PATHFINDER_M + 1
        announce_emitted_val = announce_emitted(packet)

        offset = Identity::KEYSIZE // 8 + Identity::NAME_HASH_LENGTH // 8
        random_blob = packet.data[offset, 10]
        random_blobs = [] of Bytes

        @@inbound_announce_lock.synchronize do
          if @@path_table.has_key?(dest_hex)
            path_entry = @@path_table[dest_hex]
            random_blobs = path_entry.random_blobs.dup

            if packet.hops.to_i32 <= path_entry.hops
              # Equal or fewer hops — check for replay protection
              path_timebase = timebase_from_random_blobs(random_blobs)
              if !random_blobs.any? { |blob| blob == random_blob } && announce_emitted_val > path_timebase
                mark_path_unknown_state(destination_hash)
                should_add = true
              end
            else
              # More hops than known path — only accept if expired or more recent
              now = Time.utc.to_unix_f
              path_expires = path_entry.expires

              path_announce_emitted = 0_i64
              random_blobs.each do |path_random_blob|
                path_announce_emitted = Math.max(path_announce_emitted, timebase_from_random_blob(path_random_blob))
                break if path_announce_emitted >= announce_emitted_val
              end

              if now >= path_expires
                # Path has expired
                if !random_blobs.any? { |blob| blob == random_blob }
                  RNS.log("Replacing destination table entry for #{RNS.prettyhexrep(destination_hash)} with new announce due to expired path", RNS::LOG_DEBUG)
                  mark_path_unknown_state(destination_hash)
                  should_add = true
                end
              else
                if announce_emitted_val > path_announce_emitted
                  # More recently emitted
                  if !random_blobs.any? { |blob| blob == random_blob }
                    RNS.log("Replacing destination table entry for #{RNS.prettyhexrep(destination_hash)} with new announce, since it was more recently emitted", RNS::LOG_DEBUG)
                    mark_path_unknown_state(destination_hash)
                    should_add = true
                  end
                elsif announce_emitted_val == path_announce_emitted
                  # Same emission — accept if path was unresponsive
                  if path_is_unresponsive(destination_hash)
                    RNS.log("Replacing destination table entry for #{RNS.prettyhexrep(destination_hash)} with new announce, since previously tried path was unresponsive", RNS::LOG_DEBUG)
                    should_add = true
                  end
                end
              end
            end
          else
            # Unknown destination — should add
            should_add = true
          end

          if should_add
            now = Time.utc.to_unix_f

            # Rate limiting
            rate_blocked = false
            if packet.context != Packet::PATH_RESPONSE
              rate_blocked = check_announce_rate(dest_hex, now)
            end

            retries = 0_i32
            announce_hops = packet.hops.to_i32
            local_rebroadcasts = 0_i32
            block_rebroadcasts = false
            attached_interface : Bytes? = nil

            retransmit_timeout = now + (RNS.rand * PATHFINDER_RW)
            expires = now + PATHFINDER_E.to_f64

            # Update random blobs
            if !random_blobs.any? { |blob| blob == random_blob }
              random_blobs << random_blob.dup
              if random_blobs.size > MAX_RANDOM_BLOBS
                random_blobs = random_blobs[random_blobs.size - MAX_RANDOM_BLOBS..]
              end
            end

            # Insert into announce table for retransmission (when transport enabled)
            if packet.context != Packet::PATH_RESPONSE
              if rate_blocked
                RNS.log("Blocking rebroadcast of announce from #{RNS.prettyhexrep(destination_hash)} due to excessive announce rate", RNS::LOG_DEBUG)
              else
                @@announce_table[dest_hex] = AnnounceEntry.new(
                  timestamp: now,
                  retransmit_timeout: retransmit_timeout,
                  retries: retries,
                  received_from: received_from,
                  hops: announce_hops,
                  packet: packet,
                  local_rebroadcasts: local_rebroadcasts,
                  block_rebroadcasts: block_rebroadcasts,
                  attached_interface: attached_interface,
                )
              end
            end

            # Update path table
            packet_hash = packet.packet_hash || Bytes.empty
            @@path_table[dest_hex] = PathEntry.new(
              timestamp: now,
              next_hop: received_from,
              hops: announce_hops,
              expires: expires,
              random_blobs: random_blobs,
              receiving_interface: nil, # Will be interface hash when interfaces are implemented
              packet_hash: packet_hash,
            )

            RNS.log("Destination #{RNS.prettyhexrep(destination_hash)} is now #{announce_hops} hops away via #{RNS.prettyhexrep(received_from)}", RNS::LOG_DEBUG)

            retransmit_announce_to_local_clients(packet)

            # Call externally registered announce handler callbacks
            invoke_announce_handlers(packet, destination_hash)
          end
        end # synchronize
      end

      should_add
    rescue ex
      RNS.log("Error processing inbound announce: #{ex}", RNS::LOG_ERROR)
      false
    end

    private def self.retransmit_announce_to_local_clients(packet : Packet)
      return if @@local_client_interfaces.empty?

      announce_identity = Identity.recall(packet.destination_hash.not_nil!)
      transport_identity = @@identity
      receiving_interface = packet.receiving_interface
      return unless announce_identity && transport_identity

      announce_destination = Destination.new(
        announce_identity,
        Destination::OUT,
        Destination::SINGLE,
        "unknown",
        ["unknown"],
        register: false,
      )
      announce_destination.hash = packet.destination_hash.not_nil!
      announce_destination.hexhash = announce_destination.hash.hexstring

      @@local_client_interfaces.each do |local_interface|
        next if receiving_interface && local_interface.same?(receiving_interface)

        new_announce = Packet.new(
          announce_destination,
          packet.data,
          packet_type: Packet::ANNOUNCE,
          context: Packet::NONE,
          header_type: Packet::HEADER_2,
          transport_type: Transport::TRANSPORT,
          transport_id: transport_identity.hash,
          attached_interface: local_interface,
          create_receipt: false,
          context_flag: packet.context_flag,
        )
        new_announce.hops = packet.hops
        new_announce.pack
        transmit(local_interface.get_hash, new_announce.raw.not_nil!)
      end
    end

    # Checks announce rate limiting for a destination.
    # Returns true if the announce should be rate-blocked.
    def self.check_announce_rate(dest_hex : String, now : Float64) : Bool
      rate_blocked = false

      if !@@announce_rate_table.has_key?(dest_hex)
        @@announce_rate_table[dest_hex] = AnnounceRateEntry.new(
          last: now,
          rate_violations: 0,
          blocked_until: 0.0,
          timestamps: [now],
        )
      else
        rate_entry = @@announce_rate_table[dest_hex]
        new_timestamps = rate_entry.timestamps.dup
        new_timestamps << now

        while new_timestamps.size > MAX_RATE_TIMESTAMPS
          new_timestamps.shift
        end

        current_rate = now - rate_entry.last
        new_violations = rate_entry.rate_violations
        new_blocked_until = rate_entry.blocked_until
        new_last = rate_entry.last

        if now > rate_entry.blocked_until
          # Default rate target — in a full implementation this comes
          # from the receiving interface's announce_rate_target.
          # For now, we use a reasonable default.
          rate_target = 0.0
          rate_grace = 0

          if rate_target > 0.0
            if current_rate < rate_target
              new_violations += 1
            else
              new_violations = Math.max(0, new_violations - 1)
            end

            if new_violations > rate_grace
              rate_penalty = 0.0
              new_blocked_until = new_last + rate_target + rate_penalty
              rate_blocked = true
            else
              new_last = now
            end
          else
            new_last = now
          end
        else
          rate_blocked = true
        end

        @@announce_rate_table[dest_hex] = AnnounceRateEntry.new(
          last: new_last,
          rate_violations: new_violations,
          blocked_until: new_blocked_until,
          timestamps: new_timestamps,
        )
      end

      rate_blocked
    end

    # Invokes registered announce handler callbacks for a processed announce.
    def self.invoke_announce_handlers(packet : Packet, destination_hash : Bytes)
      @@announce_handlers.each do |handler|
        begin
          execute_callback = false
          announce_identity = Identity.recall(destination_hash)

          if handler.aspect_filter.nil?
            execute_callback = true
          else
            if announce_identity
              handler_expected_hash = Destination.hash_from_name_and_identity(handler.aspect_filter.not_nil!, announce_identity)
              execute_callback = (destination_hash == handler_expected_hash)
            end
          end

          # Path responses are only forwarded to handlers that opted in
          is_path_response = (packet.context == Packet::PATH_RESPONSE)
          if is_path_response && !handler.receive_path_responses
            execute_callback = false
          end

          if execute_callback
            spawn do
              handler.received_announce(
                destination_hash,
                announce_identity,
                Identity.recall_app_data(destination_hash),
                packet.packet_hash,
                is_path_response,
              )
            end
          end
        rescue ex
          RNS.log("Error while processing external announce callback: #{ex}", RNS::LOG_ERROR)
        end
      end
    end

    # Processes the announce retransmission table. Called periodically
    # by the Transport jobs loop. Returns an array of packets to send.
    def self.process_announce_table : Array(Packet)
      outgoing = [] of Packet
      completed_announces = [] of String

      @@announce_table.each do |dest_hex, announce_entry|
        if announce_entry.retries > 0 && announce_entry.retries >= LOCAL_REBROADCASTS_MAX
          RNS.log("Completed announce processing for #{dest_hex}, local rebroadcast limit reached", RNS::LOG_EXTREME)
          completed_announces << dest_hex
        elsif announce_entry.retries > PATHFINDER_R
          RNS.log("Completed announce processing for #{dest_hex}, retry limit reached", RNS::LOG_EXTREME)
          completed_announces << dest_hex
        else
          now = Time.utc.to_unix_f
          if now > announce_entry.retransmit_timeout
            new_retransmit_timeout = now + PATHFINDER_G + PATHFINDER_RW
            new_retries = announce_entry.retries + 1

            # Update the announce entry
            @@announce_table[dest_hex] = AnnounceEntry.new(
              timestamp: announce_entry.timestamp,
              retransmit_timeout: new_retransmit_timeout,
              retries: new_retries,
              received_from: announce_entry.received_from,
              hops: announce_entry.hops,
              packet: announce_entry.packet,
              local_rebroadcasts: announce_entry.local_rebroadcasts,
              block_rebroadcasts: announce_entry.block_rebroadcasts,
              attached_interface: announce_entry.attached_interface,
            )

            original_packet = announce_entry.packet
            block_rebroadcasts = announce_entry.block_rebroadcasts
            announce_context = block_rebroadcasts ? Packet::PATH_RESPONSE : Packet::NONE

            announce_identity = Identity.recall(original_packet.destination_hash.not_nil!)
            if announce_identity
              announce_destination = Destination.new(
                announce_identity,
                Destination::OUT,
                Destination::SINGLE,
                "unknown",
                ["unknown"],
                register: false,
              )
              announce_destination.hash = original_packet.destination_hash.not_nil!
              announce_destination.hexhash = announce_destination.hash.hexstring

              transport_identity = @@identity
              if transport_identity
                new_packet = Packet.new(
                  announce_destination,
                  original_packet.data,
                  packet_type: Packet::ANNOUNCE,
                  context: announce_context,
                  header_type: Packet::HEADER_2,
                  transport_type: Transport::TRANSPORT,
                  transport_id: transport_identity.hash,
                )
                new_packet.hops = announce_entry.hops.to_u8
                new_packet.context_flag = original_packet.context_flag

                if block_rebroadcasts
                  RNS.log("Rebroadcasting announce as path response for #{RNS.prettyhexrep(announce_destination.hash)} with hop count #{new_packet.hops}", RNS::LOG_DEBUG)
                else
                  RNS.log("Rebroadcasting announce for #{RNS.prettyhexrep(announce_destination.hash)} with hop count #{new_packet.hops}", RNS::LOG_DEBUG)
                end

                outgoing << new_packet
              end
            end

            # Handle held announces edge case
            if @@held_announces.has_key?(dest_hex)
              held_entry = @@held_announces.delete(dest_hex)
              if held_entry
                @@announce_table[dest_hex] = held_entry
                RNS.log("Reinserting held announce into table", RNS::LOG_DEBUG)
              end
            end
          end
        end
      end

      # Remove completed announces
      completed_announces.each do |dest_hex|
        @@announce_table.delete(dest_hex)
      end

      outgoing
    end

    # Marks the path for a destination as unknown, used when the
    # announce table entry should be reconsidered.
    def self.mark_path_unknown_for_destination(destination_hash : Bytes)
      mark_path_unknown_state(destination_hash)
    end

    # Drops all announce queues on all interfaces.
    # Currently a no-op since interface objects are not yet implemented.
    def self.drop_announce_queues
      # Will be implemented when Interface class is available
    end

    # Cleans the announce file cache. Removes cached announce files
    # that are no longer referenced by the path table or tunnel table.
    def self.clean_announce_cache(cache_path : String)
      return unless Dir.exists?(cache_path)

      announce_path = File.join(cache_path, "announces")
      return unless Dir.exists?(announce_path)

      active_paths = Set(String).new
      @@path_table.each_value { |entry| active_paths << entry.packet_hash.hexstring }

      @@tunnels.each_value do |tunnel_entry|
        tunnel_entry.paths.each_value { |path_entry| active_paths << path_entry.packet_hash.hexstring }
      end

      removed = 0
      Dir.each_child(announce_path) do |packet_hash_str|
        full_path = File.join(announce_path, packet_hash_str)
        if File.file?(full_path)
          unless active_paths.includes?(packet_hash_str)
            File.delete(full_path)
            removed += 1
          end
        end
      end

      RNS.log("Removed #{removed} cached announces", RNS::LOG_DEBUG) if removed > 0
    rescue ex
      RNS.log("Error cleaning announce cache: #{ex}", RNS::LOG_ERROR)
    end

    # Caches a packet to storage.
    def self.cache_packet(packet : Packet, cache_path : String, force_cache : Bool = false, packet_type : String? = nil)
      return unless force_cache

      begin
        ph = packet.get_hash
        packet_hash_str = ph.hexstring

        if packet_type == "announce"
          announce_dir = File.join(cache_path, "announces")
          Dir.mkdir_p(announce_dir) unless Dir.exists?(announce_dir)
          filepath = File.join(announce_dir, packet_hash_str)
        else
          filepath = File.join(cache_path, packet_hash_str)
        end

        raw = packet.raw
        return unless raw

        data = Array(MessagePack::Type).new
        data << raw.as(MessagePack::Type)
        data << nil.as(MessagePack::Type) # interface reference (nil for now)
        File.write(filepath, data.to_msgpack)
      rescue ex
        RNS.log("Error writing packet to cache: #{ex}", RNS::LOG_ERROR)
      end
    end
  end
end
