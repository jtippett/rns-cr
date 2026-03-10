module RNS
  module Transport
    # ════════════════════════════════════════════════════════════════
    #  Path Management
    # ════════════════════════════════════════════════════════════════

    # Helper to extract an integer from MessagePack::Type which may be
    # UInt8, Int8, UInt16, Int16, UInt32, Int32, UInt64, or Int64.
    private def self.msgpack_to_i64(val : MessagePack::Type) : Int64
      case val
      when Int8   then val.to_i64
      when UInt8  then val.to_i64
      when Int16  then val.to_i64
      when UInt16 then val.to_i64
      when Int32  then val.to_i64
      when UInt32 then val.to_i64
      when Int64  then val
      when UInt64 then val.to_i64
      else             raise TypeCastError.new("Cannot convert #{val.class} to Int64")
      end
    end

    # Helper to extract a Float64 from MessagePack::Type which may be
    # Float32, Float64, or an integer type.
    private def self.msgpack_to_f64(val : MessagePack::Type) : Float64
      case val
      when Float64 then val
      when Float32 then val.to_f64
      else              msgpack_to_i64(val).to_f64
      end
    end

    # Returns true if a path to the destination is known.
    def self.has_path(destination_hash : Bytes) : Bool
      @@path_table.has_key?(destination_hash.hexstring)
    end

    # Returns the number of hops to the specified destination,
    # or PATHFINDER_M if the number of hops is unknown.
    def self.hops_to(destination_hash : Bytes) : Int32
      key = destination_hash.hexstring
      if @@path_table.has_key?(key)
        @@path_table[key].hops
      else
        PATHFINDER_M
      end
    end

    # Returns the next hop hash for the specified destination, or nil if unknown.
    def self.next_hop(destination_hash : Bytes) : Bytes?
      key = destination_hash.hexstring
      if @@path_table.has_key?(key)
        @@path_table[key].next_hop
      else
        nil
      end
    end

    # Returns the receiving interface hash for the specified destination, or nil if unknown.
    def self.next_hop_interface(destination_hash : Bytes) : Bytes?
      key = destination_hash.hexstring
      if @@path_table.has_key?(key)
        @@path_table[key].receiving_interface
      else
        nil
      end
    end

    # Returns the first hop timeout for the specified destination.
    # Without interface bitrate info (not yet available), returns DEFAULT_PER_HOP_TIMEOUT.
    def self.first_hop_timeout(destination_hash : Bytes) : Float64
      Reticulum::DEFAULT_PER_HOP_TIMEOUT.to_f64
    end

    # Expires the path to the specified destination by setting its
    # timestamp to 0, which will cause it to be culled on the next
    # jobs pass. Returns true if a path existed, false otherwise.
    def self.expire_path(destination_hash : Bytes) : Bool
      key = destination_hash.hexstring
      if @@path_table.has_key?(key)
        old = @@path_table[key]
        @@path_table[key] = PathEntry.new(
          timestamp: 0.0,
          next_hop: old.next_hop,
          hops: old.hops,
          expires: old.expires,
          random_blobs: old.random_blobs,
          receiving_interface: old.receiving_interface,
          packet_hash: old.packet_hash,
        )
        @@tables_last_culled = 0.0
        true
      else
        false
      end
    end

    # Marks the path to the specified destination as unresponsive.
    def self.mark_path_unresponsive(destination_hash : Bytes) : Bool
      key = destination_hash.hexstring
      if @@path_table.has_key?(key)
        @@path_states[key] = STATE_UNRESPONSIVE
        true
      else
        false
      end
    end

    # Marks the path to the specified destination as responsive.
    def self.mark_path_responsive(destination_hash : Bytes) : Bool
      key = destination_hash.hexstring
      if @@path_table.has_key?(key)
        @@path_states[key] = STATE_RESPONSIVE
        true
      else
        false
      end
    end

    # Marks the path to the specified destination as unknown state.
    def self.mark_path_unknown_state(destination_hash : Bytes) : Bool
      key = destination_hash.hexstring
      if @@path_table.has_key?(key)
        @@path_states[key] = STATE_UNKNOWN
        true
      else
        false
      end
    end

    # Returns true if the path to the specified destination is marked
    # as unresponsive.
    def self.path_is_unresponsive(destination_hash : Bytes) : Bool
      key = destination_hash.hexstring
      if @@path_states.has_key?(key)
        @@path_states[key] == STATE_UNRESPONSIVE
      else
        false
      end
    end

    # Requests a path to the destination from the network.
    # Creates a path request packet and broadcasts it.
    def self.request_path(destination_hash : Bytes, on_interface : Bytes? = nil, tag : Bytes? = nil, recursive : Bool = false)
      request_tag = tag || Identity.get_random_hash

      transport_id = @@identity
      if transport_id
        path_request_data = Bytes.new(destination_hash.size + transport_id.hash.not_nil!.size + request_tag.size)
        destination_hash.copy_to(path_request_data)
        transport_id.hash.not_nil!.copy_to(path_request_data + destination_hash.size)
        request_tag.copy_to(path_request_data + destination_hash.size + transport_id.hash.not_nil!.size)
      else
        path_request_data = Bytes.new(destination_hash.size + request_tag.size)
        destination_hash.copy_to(path_request_data)
        request_tag.copy_to(path_request_data + destination_hash.size)
      end

      path_request_dst = Destination.new(
        nil,
        Destination::OUT,
        Destination::PLAIN,
        APP_NAME,
        ["path", "request"],
        register: false,
      )

      packet = Packet.new(
        path_request_dst,
        path_request_data,
        packet_type: Packet::DATA,
        transport_type: Transport::BROADCAST,
        header_type: Packet::HEADER_1,
      )

      packet.send
      @@path_requests[destination_hash.hexstring] = Time.utc.to_unix_f
    end

    # Inserts or updates a path table entry for the given destination hash.
    def self.update_path(destination_hash : Bytes, next_hop : Bytes, hops : Int32,
                         expires : Float64, receiving_interface : Bytes? = nil,
                         packet_hash : Bytes = Bytes.empty,
                         random_blobs : Array(Bytes) = [] of Bytes)
      key = destination_hash.hexstring
      entry = PathEntry.new(
        timestamp: Time.utc.to_unix_f,
        next_hop: next_hop,
        hops: hops,
        expires: expires,
        random_blobs: random_blobs,
        receiving_interface: receiving_interface,
        packet_hash: packet_hash,
      )
      @@path_table[key] = entry
    end

    # Removes a path table entry for the given destination hash.
    # Returns true if the entry existed, false otherwise.
    def self.remove_path(destination_hash : Bytes) : Bool
      key = destination_hash.hexstring
      if @@path_table.has_key?(key)
        @@path_table.delete(key)
        @@path_states.delete(key)
        true
      else
        false
      end
    end

    # Saves the path table to disk using MessagePack serialization.
    # Each entry is serialized as:
    #   [destination_hash, timestamp, received_from, hops, expires, random_blobs, interface_hash, packet_hash]
    def self.save_path_table(storage_path : String) : Bool
      if @@saving_path_table
        wait_start = Time.utc.to_unix_f
        while @@saving_path_table
          sleep(200.milliseconds)
          if Time.utc.to_unix_f > wait_start + 5.0
            RNS.log("Could not save path table to storage, waiting for previous save operation timed out.", RNS::LOG_ERROR)
            return false
          end
        end
      end

      begin
        @@saving_path_table = true
        save_start = Time.utc.to_unix_f
        RNS.log("Saving path table to storage...", RNS::LOG_DEBUG)

        serialised_destinations = [] of Array(MessagePack::Type)

        @@path_table.each do |hex_key, entry|
          begin
            destination_hash = hex_key.hexbytes
            serialised_entry = Array(MessagePack::Type).new
            serialised_entry << destination_hash.as(MessagePack::Type)
            serialised_entry << entry.timestamp.as(MessagePack::Type)
            serialised_entry << entry.next_hop.as(MessagePack::Type)
            serialised_entry << entry.hops.to_i64.as(MessagePack::Type)
            serialised_entry << entry.expires.as(MessagePack::Type)

            # Serialize random_blobs - persist up to PERSIST_RANDOM_BLOBS
            blobs_to_save = entry.random_blobs[0, Math.min(entry.random_blobs.size, PERSIST_RANDOM_BLOBS)]
            blob_array = Array(MessagePack::Type).new
            blobs_to_save.each { |b| blob_array << b.as(MessagePack::Type) }
            serialised_entry << blob_array.as(MessagePack::Type)

            iface_hash = entry.receiving_interface
            if iface_hash
              serialised_entry << iface_hash.as(MessagePack::Type)
            else
              serialised_entry << nil.as(MessagePack::Type)
            end
            serialised_entry << entry.packet_hash.as(MessagePack::Type)

            serialised_destinations << serialised_entry
          rescue ex
            RNS.log("Skipping persist for path table entry due to error: #{ex}", RNS::LOG_ERROR)
          end
        end

        path_table_path = File.join(storage_path, "destination_table")
        File.write(path_table_path, serialised_destinations.to_msgpack)

        save_time = Time.utc.to_unix_f - save_start
        time_str = save_time < 1 ? "#{(save_time * 1000).round(2)}ms" : "#{save_time.round(2)}s"
        RNS.log("Saved #{serialised_destinations.size} path table entries in #{time_str}", RNS::LOG_DEBUG)

        true
      rescue ex
        RNS.log("Could not save path table to storage, the contained exception was: #{ex}", RNS::LOG_ERROR)
        false
      ensure
        @@saving_path_table = false
      end
    end

    # Loads the path table from disk.
    # Returns the number of entries loaded, or -1 on error.
    def self.load_path_table(storage_path : String) : Int32
      path_table_path = File.join(storage_path, "destination_table")
      return 0 unless File.exists?(path_table_path)

      begin
        data = File.read(path_table_path).to_slice
        entries = Array(Array(MessagePack::Type)).from_msgpack(data)

        loaded = 0
        entries.each do |entry|
          begin
            destination_hash = entry[0].as(Bytes)
            timestamp = msgpack_to_f64(entry[1])
            received_from = entry[2].as(Bytes)
            hops = msgpack_to_i64(entry[3]).to_i32
            expires = msgpack_to_f64(entry[4])

            # Deserialize random_blobs
            random_blobs = [] of Bytes
            blob_data = entry[5]
            if blob_data.is_a?(Array)
              blob_data.each do |b|
                random_blobs << b.as(Bytes) if b.is_a?(Bytes)
              end
            end

            interface_hash = entry[6].as?(Bytes)
            packet_hash = entry[7].as(Bytes)

            key = destination_hash.hexstring
            @@path_table[key] = PathEntry.new(
              timestamp: timestamp,
              next_hop: received_from,
              hops: hops + 1,  # Increment hops as per Python behavior
              expires: expires,
              random_blobs: random_blobs,
              receiving_interface: interface_hash,
              packet_hash: packet_hash,
            )
            loaded += 1
          rescue ex
            RNS.log("Skipping path table entry during load due to error: #{ex}", RNS::LOG_ERROR)
          end
        end

        RNS.log("Loaded #{loaded} path table entries from storage", RNS::LOG_DEBUG)
        loaded
      rescue ex
        RNS.log("Could not load path table from storage: #{ex}", RNS::LOG_ERROR)
        -1
      end
    end

    # Saves the packet hashlist to disk using MessagePack.
    def self.save_packet_hashlist(storage_path : String) : Bool
      if @@saving_packet_hashlist
        wait_start = Time.utc.to_unix_f
        while @@saving_packet_hashlist
          sleep(200.milliseconds)
          if Time.utc.to_unix_f > wait_start + 5.0
            RNS.log("Could not save packet hashlist to storage, waiting for previous save operation timed out.", RNS::LOG_ERROR)
            return false
          end
        end
      end

      begin
        @@saving_packet_hashlist = true
        save_start = Time.utc.to_unix_f
        RNS.log("Saving packet hashlist to storage...", RNS::LOG_DEBUG)

        hash_array = Array(MessagePack::Type).new
        @@packet_hashlist.each { |h| hash_array << h.hexbytes.as(MessagePack::Type) }

        hashlist_path = File.join(storage_path, "packet_hashlist")
        File.write(hashlist_path, hash_array.to_msgpack)

        save_time = Time.utc.to_unix_f - save_start
        time_str = save_time < 1 ? "#{(save_time * 1000).round(2)}ms" : "#{save_time.round(2)}s"
        RNS.log("Saved packet hashlist in #{time_str}", RNS::LOG_DEBUG)

        true
      rescue ex
        RNS.log("Could not save packet hashlist to storage: #{ex}", RNS::LOG_ERROR)
        false
      ensure
        @@saving_packet_hashlist = false
      end
    end

    # Loads the packet hashlist from disk.
    def self.load_packet_hashlist(storage_path : String) : Int32
      hashlist_path = File.join(storage_path, "packet_hashlist")
      return 0 unless File.exists?(hashlist_path)

      begin
        data = File.read(hashlist_path).to_slice
        entries = Array(MessagePack::Type).from_msgpack(data)

        entries.each do |entry|
          if entry.is_a?(Bytes)
            @@packet_hashlist << entry.hexstring
          end
        end

        RNS.log("Loaded #{@@packet_hashlist.size} packet hashes from storage", RNS::LOG_DEBUG)
        @@packet_hashlist.size
      rescue ex
        RNS.log("Could not load packet hashlist from storage: #{ex}", RNS::LOG_ERROR)
        -1
      end
    end

    # Saves the tunnel table to disk using MessagePack.
    def self.save_tunnel_table(storage_path : String) : Bool
      if @@saving_tunnel_table
        wait_start = Time.utc.to_unix_f
        while @@saving_tunnel_table
          sleep(200.milliseconds)
          if Time.utc.to_unix_f > wait_start + 5.0
            RNS.log("Could not save tunnel table to storage, waiting for previous save operation timed out.", RNS::LOG_ERROR)
            return false
          end
        end
      end

      begin
        @@saving_tunnel_table = true
        save_start = Time.utc.to_unix_f
        RNS.log("Saving tunnel table to storage...", RNS::LOG_DEBUG)

        serialised_tunnels = [] of Array(MessagePack::Type)

        @@tunnels.each do |_hex_key, te|
          begin
            serialised_paths = [] of Array(MessagePack::Type)

            te.paths.each do |dest_hex, pe|
              path_entry = Array(MessagePack::Type).new
              path_entry << dest_hex.hexbytes.as(MessagePack::Type)
              path_entry << pe.timestamp.as(MessagePack::Type)
              path_entry << pe.next_hop.as(MessagePack::Type)
              path_entry << pe.hops.to_i64.as(MessagePack::Type)
              path_entry << pe.expires.as(MessagePack::Type)

              blob_array = Array(MessagePack::Type).new
              pe.random_blobs.each { |b| blob_array << b.as(MessagePack::Type) }
              path_entry << blob_array.as(MessagePack::Type)

              iface = pe.receiving_interface
              path_entry << (iface ? iface.as(MessagePack::Type) : nil.as(MessagePack::Type))
              path_entry << pe.packet_hash.as(MessagePack::Type)

              serialised_paths << path_entry
            end

            tunnel_entry = Array(MessagePack::Type).new
            tunnel_entry << te.tunnel_id.as(MessagePack::Type)
            tunnel_entry << (te.interface ? te.interface.as(MessagePack::Type) : nil.as(MessagePack::Type))

            paths_mp = Array(MessagePack::Type).new
            serialised_paths.each { |sp| paths_mp << sp.as(MessagePack::Type) }
            tunnel_entry << paths_mp.as(MessagePack::Type)
            tunnel_entry << te.expires.as(MessagePack::Type)

            serialised_tunnels << tunnel_entry
          rescue ex
            RNS.log("Skipping persist for tunnel table entry due to error: #{ex}", RNS::LOG_ERROR)
          end
        end

        tunnel_table_path = File.join(storage_path, "tunnels")
        File.write(tunnel_table_path, serialised_tunnels.to_msgpack)

        save_time = Time.utc.to_unix_f - save_start
        time_str = save_time < 1 ? "#{(save_time * 1000).round(2)}ms" : "#{save_time.round(2)}s"
        RNS.log("Saved #{serialised_tunnels.size} tunnel table entries in #{time_str}", RNS::LOG_DEBUG)

        true
      rescue ex
        RNS.log("Could not save tunnel table to storage: #{ex}", RNS::LOG_ERROR)
        false
      ensure
        @@saving_tunnel_table = false
      end
    end

    # Calls all persistence methods.
    def self.persist_data(storage_path : String)
      save_path_table(storage_path)
      save_packet_hashlist(storage_path)
      save_tunnel_table(storage_path)
    end

    # Utility to find an interface hash in the interfaces list.
    def self.find_interface_from_hash(interface_hash : Bytes) : Bytes?
      @@interfaces.each do |iface_hash|
        return iface_hash if iface_hash == interface_hash
      end
      nil
    end

    # Register an interface (by hash). Full interface support will come with Interface implementation.
    def self.register_interface(interface_hash : Bytes)
      @@interfaces << interface_hash
    end

    # Deregister an interface (by hash).
    def self.deregister_interface(interface_hash : Bytes)
      @@interfaces.delete(interface_hash)
    end
  end
end
