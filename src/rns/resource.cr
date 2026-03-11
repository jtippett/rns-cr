require "msgpack"

module RNS
  class Resource
    # ─── Window constants ──────────────────────────────────────────
    WINDOW                   =  4
    WINDOW_MIN               =  2
    WINDOW_MAX_SLOW          = 10
    WINDOW_MAX_VERY_SLOW     =  4
    WINDOW_MAX_FAST          = 75
    WINDOW_MAX               = WINDOW_MAX_FAST
    FAST_RATE_THRESHOLD      = WINDOW_MAX_SLOW - WINDOW - 2 # 4
    VERY_SLOW_RATE_THRESHOLD = 2
    WINDOW_FLEXIBILITY       = 4

    # ─── Rate constants ────────────────────────────────────────────
    RATE_FAST      = (50 * 1000) / 8 # 50 Kbps in bytes/sec = 6250
    RATE_VERY_SLOW = (2 * 1000) / 8  # 2 Kbps in bytes/sec = 250

    # ─── Size constants ────────────────────────────────────────────
    MAPHASH_LEN      = 4
    SDU              = Packet::MDU
    RANDOM_HASH_SIZE = 4

    MAX_EFFICIENT_SIZE      = 1 * 1024 * 1024 - 1 # 1048575 (0xFFFFF)
    RESPONSE_MAX_GRACE_TIME = 10
    METADATA_MAX_SIZE       = 16 * 1024 * 1024 - 1 # 16777215 (0xFFFFFF)
    AUTO_COMPRESS_MAX_SIZE  = 64 * 1024 * 1024

    # ─── Timeout and retry constants ───────────────────────────────
    PART_TIMEOUT_FACTOR           =    4
    PART_TIMEOUT_FACTOR_AFTER_RTT =    2
    PROOF_TIMEOUT_FACTOR          =    3
    MAX_RETRIES                   =   16
    MAX_ADV_RETRIES               =    4
    SENDER_GRACE_TIME             = 10.0
    PROCESSING_GRACE              =  1.0
    RETRY_GRACE_TIME              = 0.25
    PER_RETRY_DELAY               =  0.5
    WATCHDOG_MAX_SLEEP            =  1.0

    # ─── Hashmap flags ─────────────────────────────────────────────
    HASHMAP_IS_NOT_EXHAUSTED = 0x00_u8
    HASHMAP_IS_EXHAUSTED     = 0xFF_u8

    # ─── Status constants ──────────────────────────────────────────
    STATUS_NONE    = 0x00_u8
    QUEUED         = 0x01_u8
    ADVERTISED     = 0x02_u8
    TRANSFERRING   = 0x03_u8
    AWAITING_PROOF = 0x04_u8
    ASSEMBLING     = 0x05_u8
    COMPLETE       = 0x06_u8
    FAILED         = 0x07_u8
    CORRUPT        = 0x08_u8
    REJECTED       = 0x00_u8 # Same as STATUS_NONE in Python

    # ─── Instance properties ───────────────────────────────────────
    property status : UInt8
    property link : Link?
    property hash : Bytes
    property original_hash : Bytes
    property random_hash : Bytes
    property size : Int64       # encrypted transfer size
    property total_size : Int64 # uncompressed data size
    property uncompressed_size : Int64
    property flags : UInt8
    property encrypted : Bool
    property compressed : Bool
    property split : Bool
    property has_metadata : Bool
    property segment_index : Int32
    property total_segments : Int32
    property total_parts : Int32
    property sent_parts : Int32
    property received_count : Int32
    property outstanding_parts : Int32
    property window : Int32
    property window_max : Int32
    property window_min : Int32
    property window_flexibility : Int32
    property initiator : Bool
    property callback : Proc(Resource, Nil)?
    property progress_callback_proc : Proc(Resource, Nil)?
    property sdu : Int32
    property max_retries : Int32
    property max_adv_retries : Int32
    property retries_left : Int32
    property timeout_factor : Float64
    property part_timeout_factor : Float64
    property sender_grace_time : Float64
    property rtt : Float64?
    property rtt_rxd_bytes : Int64
    property req_sent : Float64
    property req_resp : Float64?
    property req_sent_bytes : Int32
    property req_resp_rtt_rate : Float64
    property rtt_rxd_bytes_at_part_req : Int64
    property req_data_rtt_rate : Float64
    property eifr : Float64?
    property previous_eifr : Float64?
    property fast_rate_rounds : Int32
    property very_slow_rate_rounds : Int32
    property request_id : Bytes?
    property is_response : Bool
    property auto_compress : Bool
    property auto_compress_limit : Int64
    property auto_compress_option : Bool | Int64
    property last_activity : Float64
    property started_transferring : Float64?
    property adv_sent : Float64
    property last_part_sent : Float64
    property timeout : Float64
    property storagepath : String
    property meta_storagepath : String
    property metadata : Bytes?
    property metadata_size : Int32
    property data : Bytes?

    # Sender-side parts (Packet objects with map_hash)
    property sender_parts : Array(Packet)
    # Receiver-side parts (nil or data bytes)
    property receiver_parts : Array(Bytes?)
    # Hashmap (sender: concatenated bytes, receiver: array of Bytes?)
    property hashmap_raw_bytes : Bytes # sender: full hashmap bytes
    property hashmap : Array(Bytes?)   # receiver: per-part map hashes
    property hashmap_height : Int32
    property waiting_for_hmu : Bool
    property receiving_part : Bool
    property consecutive_completed_height : Int32
    property expected_proof : Bytes
    property truncated_hash : Bytes
    property hmu_retry_ok : Bool
    property watchdog_lock : Bool
    property receiver_min_consecutive_height : Int32
    property req_hashlist : Array(Bytes)

    @watchdog_job_id : Int32
    @receive_lock : Mutex
    @assembly_lock : Bool
    @preparing_next_segment : Bool
    @next_segment : Resource?
    @input_file : IO?
    @advertisement_packet : Packet?

    # ─── Static methods ────────────────────────────────────────────

    def self.reject(advertisement_packet : Packet)
      adv = ResourceAdvertisement.unpack(advertisement_packet.plaintext || advertisement_packet.data)
      link = advertisement_packet.destination.as?(Link)
      if link
        reject_packet = Packet.new(link, adv.h, context: Packet::RESOURCE_RCL)
        reject_packet.send
      end
    rescue ex
      RNS.log("An error occurred while rejecting advertised resource: #{ex}", RNS::LOG_ERROR)
    end

    def self.accept(advertisement_packet : Packet, callback : Proc(Resource, Nil)? = nil,
                    progress_callback : Proc(Resource, Nil)? = nil, request_id : Bytes? = nil) : Resource?
      begin
        plaintext = advertisement_packet.plaintext || advertisement_packet.data
        adv = ResourceAdvertisement.unpack(plaintext)
        link = advertisement_packet.destination.as?(Link)
        return nil unless link

        resource = Resource.new_receiver(link, request_id: request_id)
        resource.status = TRANSFERRING
        resource.flags = adv.f
        resource.size = adv.t
        resource.total_size = adv.d
        resource.uncompressed_size = adv.d
        resource.hash = adv.h
        resource.original_hash = adv.o
        resource.random_hash = adv.r
        resource.encrypted = (adv.f & 0x01) != 0
        resource.compressed = (adv.f >> 1 & 0x01) != 0
        resource.initiator = false
        resource.callback = callback
        resource.progress_callback_proc = progress_callback
        resource.total_parts = (resource.size.to_f64 / resource.sdu.to_f64).ceil.to_i32
        resource.received_count = 0
        resource.outstanding_parts = 0
        resource.receiver_parts = Array(Bytes?).new(resource.total_parts, nil)
        resource.window = WINDOW
        resource.window_max = WINDOW_MAX_SLOW
        resource.window_min = WINDOW_MIN
        resource.window_flexibility = WINDOW_FLEXIBILITY
        resource.last_activity = Time.utc.to_unix_f
        resource.started_transferring = resource.last_activity
        resource.storagepath = File.join(Reticulum.resourcepath, resource.original_hash.hexstring)
        resource.meta_storagepath = resource.storagepath + ".meta"
        resource.segment_index = adv.i
        resource.total_segments = adv.l

        resource.split = adv.l > 1
        resource.has_metadata = adv.x

        resource.hashmap = Array(Bytes?).new(resource.total_parts, nil)
        resource.hashmap_height = 0
        resource.waiting_for_hmu = false
        resource.receiving_part = false
        resource.consecutive_completed_height = -1

        # Use previous window/eifr from link if available
        prev_window = link.get_last_resource_window
        prev_eifr = link.get_last_resource_eifr
        resource.window = prev_window if prev_window
        resource.previous_eifr = prev_eifr if prev_eifr

        if link.has_incoming_resource?(resource.hash)
          RNS.log("Ignoring resource advertisement for #{RNS.prettyhexrep(resource.hash)}, resource already transferring", RNS::LOG_DEBUG)
          nil
        else
          link.register_incoming_resource(resource.hash)

          RNS.log("Accepting resource advertisement for #{RNS.prettyhexrep(resource.hash)}. Transfer size is #{RNS.prettysize(resource.size)} in #{resource.total_parts} parts.", RNS::LOG_DEBUG)

          if cb = link.callbacks.resource_started
            begin
              cb.call(resource.hash)
            rescue ex
              RNS.log("Error while executing resource started callback from #{resource}: #{ex}", RNS::LOG_ERROR)
            end
          end

          resource.hashmap_update(0, adv.m)
          resource.watchdog_job
          resource
        end
      rescue ex
        RNS.log("Could not decode resource advertisement, dropping resource", RNS::LOG_DEBUG)
        nil
      end
    end

    # ─── Private receiver constructor ──────────────────────────────
    # Used by Resource.accept to create a receiver-side resource
    protected def self.new_receiver(link : Link, request_id : Bytes? = nil) : Resource
      resource = Resource.allocate
      resource._init_receiver(link, request_id)
      resource
    end

    protected def _init_receiver(link : Link, request_id : Bytes?)
      @status = STATUS_NONE
      @link = link
      @hash = Bytes.empty
      @original_hash = Bytes.empty
      @random_hash = Bytes.empty
      @size = 0_i64
      @total_size = 0_i64
      @uncompressed_size = 0_i64
      @flags = 0_u8
      @encrypted = false
      @compressed = false
      @split = false
      @has_metadata = false
      @segment_index = 1
      @total_segments = 1
      @total_parts = 0
      @sent_parts = 0
      @received_count = 0
      @outstanding_parts = 0
      @window = WINDOW
      @window_max = WINDOW_MAX_SLOW
      @window_min = WINDOW_MIN
      @window_flexibility = WINDOW_FLEXIBILITY
      @initiator = false
      @callback = nil
      @progress_callback_proc = nil
      @sdu = link.mdu > 0 ? link.mdu : SDU
      if m = link.mtu
        if m > 0
          @sdu = m - Reticulum::HEADER_MAXSIZE - Reticulum::IFAC_MIN_SIZE
        end
      end
      @max_retries = MAX_RETRIES
      @max_adv_retries = MAX_ADV_RETRIES
      @retries_left = @max_retries
      @timeout_factor = link.traffic_timeout_factor.to_f64
      @part_timeout_factor = PART_TIMEOUT_FACTOR.to_f64
      @sender_grace_time = SENDER_GRACE_TIME
      @rtt = nil
      @rtt_rxd_bytes = 0_i64
      @req_sent = 0.0
      @req_resp = nil
      @req_sent_bytes = 0
      @req_resp_rtt_rate = 0.0
      @rtt_rxd_bytes_at_part_req = 0_i64
      @req_data_rtt_rate = 0.0
      @eifr = nil
      @previous_eifr = nil
      @fast_rate_rounds = 0
      @very_slow_rate_rounds = 0
      @request_id = request_id
      @is_response = false
      @auto_compress = false
      @auto_compress_limit = AUTO_COMPRESS_MAX_SIZE.to_i64
      @auto_compress_option = false
      @last_activity = Time.utc.to_unix_f
      @started_transferring = nil
      @adv_sent = 0.0
      @last_part_sent = 0.0
      link_rtt = link.rtt || 0.5
      @timeout = link_rtt * @timeout_factor
      @storagepath = ""
      @meta_storagepath = ""
      @metadata = nil
      @metadata_size = 0
      @data = nil
      @sender_parts = [] of Packet
      @receiver_parts = [] of Bytes?
      @hashmap_raw_bytes = Bytes.empty
      @hashmap = [] of Bytes?
      @hashmap_height = 0
      @waiting_for_hmu = false
      @receiving_part = false
      @consecutive_completed_height = -1
      @expected_proof = Bytes.empty
      @truncated_hash = Bytes.empty
      @hmu_retry_ok = false
      @watchdog_lock = false
      @receiver_min_consecutive_height = 0
      @req_hashlist = [] of Bytes
      @watchdog_job_id = 0
      @receive_lock = Mutex.new
      @assembly_lock = false
      @preparing_next_segment = false
      @next_segment = nil
      @input_file = nil
      @advertisement_packet = nil
    end

    # ─── Sender constructor ────────────────────────────────────────
    def initialize(data : Bytes | IO | Nil, link : Link,
                   metadata : MessagePack::Any? = nil,
                   advertise : Bool = true,
                   auto_compress : Bool | Int64 = true,
                   callback : Proc(Resource, Nil)? = nil,
                   progress_callback : Proc(Resource, Nil)? = nil,
                   timeout : Float64? = nil,
                   segment_index : Int32 = 1,
                   original_hash : Bytes? = nil,
                   request_id : Bytes? = nil,
                   is_response : Bool = false,
                   sent_metadata_size : Int32 = 0)
      @status = STATUS_NONE
      @link = link
      @hash = Bytes.empty
      @original_hash = Bytes.empty
      @random_hash = Bytes.empty
      @size = 0_i64
      @total_size = 0_i64
      @uncompressed_size = 0_i64
      @flags = 0_u8
      @encrypted = false
      @compressed = false
      @split = false
      @has_metadata = false
      @segment_index = segment_index
      @total_segments = 1
      @total_parts = 0
      @sent_parts = 0
      @received_count = 0
      @outstanding_parts = 0
      @window = WINDOW
      @window_max = WINDOW_MAX_SLOW
      @window_min = WINDOW_MIN
      @window_flexibility = WINDOW_FLEXIBILITY
      @initiator = false
      @callback = callback
      @progress_callback_proc = progress_callback
      @sdu = SDU
      if m = link.mtu
        if m > 0
          @sdu = m - Reticulum::HEADER_MAXSIZE - Reticulum::IFAC_MIN_SIZE
        end
      else
        @sdu = link.mdu > 0 ? link.mdu : SDU
      end
      @max_retries = MAX_RETRIES
      @max_adv_retries = MAX_ADV_RETRIES
      @retries_left = @max_retries
      @timeout_factor = link.traffic_timeout_factor.to_f64
      @part_timeout_factor = PART_TIMEOUT_FACTOR.to_f64
      @sender_grace_time = SENDER_GRACE_TIME
      @rtt = nil
      @rtt_rxd_bytes = 0_i64
      @req_sent = 0.0
      @req_resp = nil
      @req_sent_bytes = 0
      @req_resp_rtt_rate = 0.0
      @rtt_rxd_bytes_at_part_req = 0_i64
      @req_data_rtt_rate = 0.0
      @eifr = nil
      @previous_eifr = nil
      @fast_rate_rounds = 0
      @very_slow_rate_rounds = 0
      @request_id = request_id
      @is_response = is_response
      @auto_compress = false
      @auto_compress_limit = AUTO_COMPRESS_MAX_SIZE.to_i64
      @auto_compress_option = auto_compress
      @last_activity = Time.utc.to_unix_f
      @started_transferring = nil
      @adv_sent = 0.0
      @last_part_sent = 0.0
      link_rtt = link.rtt || 0.5
      @timeout = timeout || (link_rtt * @timeout_factor)
      @storagepath = ""
      @meta_storagepath = ""
      @metadata = nil
      @metadata_size = sent_metadata_size
      @data = nil
      @sender_parts = [] of Packet
      @receiver_parts = [] of Bytes?
      @hashmap_raw_bytes = Bytes.empty
      @hashmap = [] of Bytes?
      @hashmap_height = 0
      @waiting_for_hmu = false
      @receiving_part = false
      @consecutive_completed_height = -1
      @expected_proof = Bytes.empty
      @truncated_hash = Bytes.empty
      @hmu_retry_ok = false
      @watchdog_lock = false
      @receiver_min_consecutive_height = 0
      @req_hashlist = [] of Bytes
      @watchdog_job_id = 0
      @receive_lock = Mutex.new
      @assembly_lock = false
      @preparing_next_segment = false
      @next_segment = nil
      @input_file = nil
      @advertisement_packet = nil

      # Handle auto_compress option
      case auto_compress
      when Bool
        @auto_compress = auto_compress
      when Int64
        @auto_compress = true
        @auto_compress_limit = auto_compress
      end

      # Handle metadata
      if metadata
        packed_metadata = metadata.to_msgpack
        if packed_metadata.size > METADATA_MAX_SIZE
          raise "Resource metadata size exceeded"
        end
        # Pack metadata size as 3 big-endian bytes + packed metadata
        meta_size_bytes = Bytes.new(3)
        meta_size_bytes[0] = ((packed_metadata.size >> 16) & 0xFF).to_u8
        meta_size_bytes[1] = ((packed_metadata.size >> 8) & 0xFF).to_u8
        meta_size_bytes[2] = (packed_metadata.size & 0xFF).to_u8
        @metadata = Bytes.new(3 + packed_metadata.size).tap do |buf|
          meta_size_bytes.copy_to(buf)
          packed_metadata.copy_to(buf + 3)
        end
        @metadata_size = @metadata.not_nil!.size
        @has_metadata = true
      else
        @metadata = Bytes.empty
        @has_metadata = sent_metadata_size > 0
      end

      # Process input data
      data_size : Int64? = nil
      resource_data : Bytes? = nil

      if data
        case data
        when IO
          data_size = data.is_a?(File) ? File.size(data.as(File).path) : nil
          @total_size = (data_size || 0_i64) + @metadata_size
          @input_file = data

          if @total_size <= MAX_EFFICIENT_SIZE
            @total_segments = 1
            @segment_index = 1
            @split = false
            resource_data = data.gets_to_end.to_slice
            data.close if data.responds_to?(:close)
          else
            @total_segments = ((@total_size - 1) // MAX_EFFICIENT_SIZE + 1).to_i32
            @segment_index = segment_index
            @split = true
            seek_index = segment_index - 1
            first_read_size = MAX_EFFICIENT_SIZE - @metadata_size

            if segment_index == 1
              seek_position = 0_i64
              segment_read_size = first_read_size
            else
              seek_position = first_read_size + ((seek_index - 1).to_i64 * MAX_EFFICIENT_SIZE)
              segment_read_size = MAX_EFFICIENT_SIZE.to_i64
            end

            if data.responds_to?(:seek)
              data.seek(seek_position)
            end
            buf = Bytes.new(segment_read_size)
            bytes_read = data.read(buf)
            resource_data = buf[0, bytes_read]
          end
        when Bytes
          data_size = data.size.to_i64
          @total_size = data_size + @metadata_size
          resource_data = data
          @total_segments = 1
          @segment_index = 1
          @split = false
        end
      end

      if resource_data
        # Combine metadata + data
        combined_data = if @has_metadata && @metadata && !@metadata.not_nil!.empty?
                          meta = @metadata.not_nil!
                          buf = Bytes.new(meta.size + resource_data.size)
                          meta.copy_to(buf)
                          resource_data.copy_to(buf + meta.size)
                          buf
                        else
                          resource_data
                        end

        @initiator = true
        uncompressed_data = combined_data

        # Compression
        if @auto_compress && (data_size || 0_i64) <= @auto_compress_limit
          RNS.log("Compressing resource data...", RNS::LOG_EXTREME)
          compressed_data = BZip2.compress(uncompressed_data)
          RNS.log("Compression completed", RNS::LOG_EXTREME)
        else
          compressed_data = uncompressed_data
        end

        @uncompressed_size = uncompressed_data.size.to_i64
        compressed_size = compressed_data.size.to_i64

        # Determine whether to use compressed or uncompressed
        if compressed_size < @uncompressed_size && @auto_compress
          # Use compressed
          random_prefix = Identity.get_random_hash[0, RANDOM_HASH_SIZE]
          encrypted_input = Bytes.new(RANDOM_HASH_SIZE + compressed_data.size)
          random_prefix.copy_to(encrypted_input)
          compressed_data.copy_to(encrypted_input + RANDOM_HASH_SIZE)
          @compressed = true
        else
          # Use uncompressed
          random_prefix = Identity.get_random_hash[0, RANDOM_HASH_SIZE]
          encrypted_input = Bytes.new(RANDOM_HASH_SIZE + uncompressed_data.size)
          random_prefix.copy_to(encrypted_input)
          uncompressed_data.copy_to(encrypted_input + RANDOM_HASH_SIZE)
          @compressed = false
        end

        # Encrypt
        @data = link.encrypt_data(encrypted_input)
        @encrypted = true
        @size = @data.not_nil!.size.to_i64
        @sent_parts = 0

        hashmap_entries = (@size.to_f64 / @sdu.to_f64).ceil.to_i32
        @total_parts = hashmap_entries

        # Build parts and hashmap, retry on hash collision
        hashmap_ok = false
        hashmap_io = IO::Memory.new
        while !hashmap_ok
          @random_hash = Identity.get_random_hash[0, RANDOM_HASH_SIZE]
          @hash = Identity.full_hash(concat_bytes(uncompressed_data, @random_hash))
          @truncated_hash = Identity.truncated_hash(concat_bytes(uncompressed_data, @random_hash))
          @expected_proof = Identity.full_hash(concat_bytes(uncompressed_data, @hash))

          if original_hash.nil?
            @original_hash = @hash
          else
            @original_hash = original_hash
          end

          @sender_parts = [] of Packet
          hashmap_io = IO::Memory.new
          collision_guard_list = [] of Bytes

          hashmap_entries.times do |i|
            encrypted_data = @data.not_nil!
            part_start = i * @sdu
            part_end = Math.min((i + 1) * @sdu, encrypted_data.size)
            part_data = encrypted_data[part_start...part_end]
            map_hash = get_map_hash(part_data)

            if collision_guard_list.any? { |h| h == map_hash }
              RNS.log("Found hash collision in resource map, remapping...", RNS::LOG_DEBUG)
              hashmap_ok = false
              break
            else
              hashmap_ok = true
              collision_guard_list << map_hash
              if collision_guard_list.size > ResourceAdvertisement::COLLISION_GUARD_SIZE
                collision_guard_list.shift
              end

              part = Packet.new(link, part_data, context: Packet::RESOURCE)
              part.pack
              part.map_hash = map_hash

              hashmap_io.write(map_hash)
              @sender_parts << part
            end
          end
        end

        @hashmap_raw_bytes = hashmap_io.to_slice.dup
        @data = nil # Free encrypted data

        if advertise
          self.advertise
        end
      else
        # Receiver side — receive_lock needed
        @receive_lock = Mutex.new
      end
    end

    # ─── Hashmap management ────────────────────────────────────────

    def hashmap_update_packet(plaintext : Bytes)
      return if @status == FAILED
      @last_activity = Time.utc.to_unix_f
      @retries_left = @max_retries

      hash_len = Identity::HASHLENGTH // 8
      update_data = plaintext[hash_len..]
      arr = MessagePack::Any.from_msgpack(update_data)
      raw = arr.as_a
      segment = raw[0].as_i.to_i32
      hashmap_bytes = raw[1].raw.as(Bytes)
      hashmap_update(segment, hashmap_bytes)
    end

    def hashmap_update(segment : Int32, hashmap_bytes : Bytes)
      return if @status == FAILED
      @status = TRANSFERRING
      seg_len = ResourceAdvertisement::HASHMAP_MAX_LEN
      hashes = hashmap_bytes.size // MAPHASH_LEN

      hashes.times do |i|
        idx = i + segment * seg_len
        if idx < @hashmap.size && @hashmap[idx].nil?
          @hashmap_height += 1
        end
        if idx < @hashmap.size
          @hashmap[idx] = hashmap_bytes[i * MAPHASH_LEN, MAPHASH_LEN].dup
        end
      end

      @waiting_for_hmu = false
      request_next
    end

    def get_map_hash(data : Bytes) : Bytes
      Identity.full_hash(concat_bytes(data, @random_hash))[0, MAPHASH_LEN]
    end

    # ─── Advertise ─────────────────────────────────────────────────

    def advertise
      spawn { advertise_job }

      if @segment_index < @total_segments
        spawn { prepare_next_segment }
      end
    end

    private def advertise_job
      link = @link
      return unless link

      @advertisement_packet = Packet.new(link, ResourceAdvertisement.new(self).pack, context: Packet::RESOURCE_ADV)

      while !link.ready_for_new_resource?
        @status = QUEUED
        sleep 0.25.seconds
      end

      begin
        @advertisement_packet.not_nil!.send
        @last_activity = Time.utc.to_unix_f
        @started_transferring = @last_activity
        @adv_sent = @last_activity
        @rtt = nil
        @status = ADVERTISED
        @retries_left = @max_adv_retries
        link.register_outgoing_resource(@hash)
        RNS.log("Sent resource advertisement for #{RNS.prettyhexrep(@hash)}", RNS::LOG_EXTREME)
      rescue ex
        RNS.log("Could not advertise resource, the contained exception was: #{ex}", RNS::LOG_ERROR)
        cancel
        return
      end

      watchdog_job
    end

    # ─── EIFR calculation ──────────────────────────────────────────

    def update_eifr
      link = @link
      return unless link

      rtt_val = @rtt || link.rtt || 0.5

      if @req_data_rtt_rate != 0.0
        expected_inflight_rate = @req_data_rtt_rate * 8
      elsif prev = @previous_eifr
        expected_inflight_rate = prev
      else
        expected_inflight_rate = link.establishment_cost.to_f64 * 8 / rtt_val
      end

      @eifr = expected_inflight_rate
      link.expected_rate = @eifr
    end

    # ─── Watchdog ──────────────────────────────────────────────────

    def watchdog_job
      spawn { _watchdog_job }
    end

    private def _watchdog_job
      @watchdog_job_id += 1
      this_job_id = @watchdog_job_id

      while @status < ASSEMBLING && this_job_id == @watchdog_job_id
        while @watchdog_lock
          sleep 0.025.seconds
        end

        sleep_time : Float64? = nil

        if @status == ADVERTISED
          sleep_time = (@adv_sent + @timeout + PROCESSING_GRACE) - Time.utc.to_unix_f
          if sleep_time.not_nil! < 0
            if @retries_left <= 0
              RNS.log("Resource transfer timeout after sending advertisement", RNS::LOG_DEBUG)
              cancel
              sleep_time = 0.001
            else
              begin
                RNS.log("No part requests received, retrying resource advertisement...", RNS::LOG_DEBUG)
                @retries_left -= 1
                link = @link
                if link
                  @advertisement_packet = Packet.new(link, ResourceAdvertisement.new(self).pack, context: Packet::RESOURCE_ADV)
                  @advertisement_packet.not_nil!.send
                  @last_activity = Time.utc.to_unix_f
                  @adv_sent = @last_activity
                  sleep_time = 0.001
                end
              rescue ex
                RNS.log("Could not resend advertisement packet, cancelling resource: #{ex}", RNS::LOG_VERBOSE)
                cancel
              end
            end
          end
        elsif @status == TRANSFERRING
          if !@initiator
            retries_used = @max_retries - @retries_left
            extra_wait = retries_used.to_f64 * PER_RETRY_DELAY

            update_eifr
            eifr_val = @eifr || 1.0
            expected_tof_remaining = (@outstanding_parts.to_f64 * @sdu.to_f64 * 8) / eifr_val

            if @req_resp_rtt_rate != 0.0
              sleep_time = @last_activity + @part_timeout_factor * expected_tof_remaining + RETRY_GRACE_TIME + extra_wait - Time.utc.to_unix_f
            else
              sleep_time = @last_activity + @part_timeout_factor * ((3.0 * @sdu.to_f64) / eifr_val) + RETRY_GRACE_TIME + extra_wait - Time.utc.to_unix_f
            end

            if sleep_time.not_nil! < 0
              if @retries_left > 0
                RNS.log("Timed out waiting for #{@outstanding_parts} part(s), requesting retry on #{self}", RNS::LOG_DEBUG)
                if @window > @window_min
                  @window -= 1
                  if @window_max > @window_min
                    @window_max -= 1
                    if (@window_max - @window) > (@window_flexibility - 1)
                      @window_max -= 1
                    end
                  end
                end

                sleep_time = 0.001
                @retries_left -= 1
                @waiting_for_hmu = false
                request_next
              else
                cancel
                sleep_time = 0.001
              end
            end
          else
            max_extra_wait = (0...MAX_RETRIES).sum { |r| (r + 1).to_f64 * PER_RETRY_DELAY }
            rtt_val = @rtt || 0.5
            max_wait = rtt_val * @timeout_factor * @max_retries + @sender_grace_time + max_extra_wait
            sleep_time = @last_activity + max_wait - Time.utc.to_unix_f
            if sleep_time.not_nil! < 0
              RNS.log("Resource timed out waiting for part requests", RNS::LOG_DEBUG)
              cancel
              sleep_time = 0.001
            end
          end
        elsif @status == AWAITING_PROOF
          @timeout_factor = PROOF_TIMEOUT_FACTOR.to_f64
          rtt_val = @rtt || 0.5
          sleep_time = @last_part_sent + (rtt_val * @timeout_factor + @sender_grace_time) - Time.utc.to_unix_f
          if sleep_time.not_nil! < 0
            if @retries_left <= 0
              RNS.log("Resource timed out waiting for proof", RNS::LOG_DEBUG)
              cancel
              sleep_time = 0.001
            else
              RNS.log("All parts sent, but no resource proof received, querying network cache...", RNS::LOG_DEBUG)
              @retries_left -= 1
              link = @link
              if link
                expected_data = concat_bytes(@hash, @expected_proof)
                expected_proof_packet = Packet.new(link, expected_data, packet_type: Packet::PROOF, context: Packet::RESOURCE_PRF)
                expected_proof_packet.pack
                Transport.cache_request(expected_proof_packet.packet_hash.not_nil!, link)
              end
              @last_part_sent = Time.utc.to_unix_f
              sleep_time = 0.001
            end
          end
        elsif @status == REJECTED
          sleep_time = 0.001
        end

        if sleep_time == 0.0
          RNS.log("Warning! Link watchdog sleep time of 0!", RNS::LOG_DEBUG)
        end
        if sleep_time.nil? || sleep_time < 0
          RNS.log("Timing error, cancelling resource transfer.", RNS::LOG_ERROR)
          cancel
        end

        if st = sleep_time
          sleep Math.min(st, WATCHDOG_MAX_SLEEP).seconds
        end
      end
    end

    # ─── Assembly (receiver side) ──────────────────────────────────

    def assemble
      return if @status == FAILED
      begin
        @status = ASSEMBLING
        stream = IO::Memory.new
        @receiver_parts.each do |part|
          stream.write(part.not_nil!) if part
        end
        raw_stream = stream.to_slice

        link = @link
        return unless link

        decrypted = if @encrypted
                      link.decrypt_data(raw_stream) || raw_stream
                    else
                      raw_stream
                    end

        # Strip random hash prefix
        data = decrypted[RANDOM_HASH_SIZE..]

        # Decompress if needed
        data = if @compressed
                 BZip2.decompress(data)
               else
                 data
               end

        calculated_hash = Identity.full_hash(concat_bytes(data, @random_hash))
        if calculated_hash == @hash
          if @has_metadata && @segment_index == 1
            metadata_size = (data[0].to_i32 << 16) | (data[1].to_i32 << 8) | data[2].to_i32
            packed_metadata = data[3, metadata_size]
            begin
              Dir.mkdir_p(File.dirname(@meta_storagepath))
              File.write(@meta_storagepath, packed_metadata)
            rescue ex
              RNS.log("Error writing metadata: #{ex}", RNS::LOG_ERROR)
            end
            data = data[3 + metadata_size..]
          end

          begin
            Dir.mkdir_p(File.dirname(@storagepath))
            File.open(@storagepath, "ab", &.write(data))
          rescue ex
            RNS.log("Error writing resource data: #{ex}", RNS::LOG_ERROR)
          end
          @status = COMPLETE
          @data = data
          prove
        else
          @status = CORRUPT
        end
      rescue ex
        RNS.log("Error while assembling received resource: #{ex}", RNS::LOG_ERROR)
        @status = CORRUPT
      end

      link = @link
      if link
        link.resource_concluded(@hash, @size, @started_transferring || Time.utc.to_unix_f,
          window: @window, eifr: @eifr, incoming: true)
      end

      if @segment_index == @total_segments
        if cb = @callback
          if !File.exists?(@meta_storagepath)
            @metadata = nil
          else
            begin
              raw = File.read(@meta_storagepath).to_slice
              @metadata = raw
              File.delete(@meta_storagepath)
            rescue ex
              RNS.log("Error while cleaning up resource metadata file: #{ex}", RNS::LOG_ERROR)
            end
          end

          begin
            @data = File.exists?(@storagepath) ? File.read(@storagepath).to_slice : @data
            cb.call(self)
          rescue ex
            RNS.log("Error while executing resource assembled callback from #{self}: #{ex}", RNS::LOG_ERROR)
          end

          begin
            File.delete(@storagepath) if File.exists?(@storagepath)
          rescue ex
            RNS.log("Error while cleaning up resource files: #{ex}", RNS::LOG_ERROR)
          end
        end
      end
    end

    # ─── Prove (receiver sends proof) ──────────────────────────────

    def prove
      return if @status == FAILED
      begin
        data = @data
        return unless data
        proof = Identity.full_hash(concat_bytes(data, @hash))
        proof_data = concat_bytes(@hash, proof)
        link = @link
        return unless link
        proof_packet = Packet.new(link, proof_data, packet_type: Packet::PROOF, context: Packet::RESOURCE_PRF)
        proof_packet.send
        Transport.cache(proof_packet, force_cache: true)
      rescue ex
        RNS.log("Could not send proof packet, cancelling resource: #{ex}", RNS::LOG_DEBUG)
        cancel
      end
    end

    # ─── Prepare next segment (sender) ─────────────────────────────

    private def prepare_next_segment
      RNS.log("Preparing segment #{@segment_index + 1} of #{@total_segments} for resource #{self}", RNS::LOG_DEBUG)
      @preparing_next_segment = true
      link = @link
      return unless link
      input = @input_file
      return unless input

      @next_segment = Resource.new(
        input, link,
        callback: @callback,
        advertise: false,
        auto_compress: @auto_compress_option,
        progress_callback: @progress_callback_proc,
        segment_index: @segment_index + 1,
        original_hash: @original_hash,
        request_id: @request_id,
        is_response: @is_response,
        sent_metadata_size: @metadata_size,
      )
    end

    # ─── Validate proof (sender side) ──────────────────────────────

    def validate_proof(proof_data : Bytes)
      return if @status == FAILED
      hash_len = Identity::HASHLENGTH // 8
      if proof_data.size == hash_len * 2
        if proof_data[hash_len..] == @expected_proof
          @status = COMPLETE
          link = @link
          if link
            link.resource_concluded(@hash, @size, @started_transferring || Time.utc.to_unix_f,
              window: nil, eifr: nil, incoming: false)
          end

          if @segment_index == @total_segments
            if cb = @callback
              begin
                cb.call(self)
              rescue ex
                RNS.log("Error while executing resource concluded callback from #{self}: #{ex}", RNS::LOG_ERROR)
              ensure
                close_input_file
              end
            else
              close_input_file
            end
          else
            # Recursively advertise next segment
            if !@preparing_next_segment
              RNS.log("Next segment preparation for resource #{self} was not started yet, manually preparing now.", RNS::LOG_WARNING)
              prepare_next_segment
            end

            while @next_segment.nil?
              sleep 0.05.seconds
            end

            @data = nil
            @metadata = nil
            @sender_parts.clear
            @input_file = nil
            @link = nil
            @req_hashlist.clear
            @hashmap.clear
            @hashmap_raw_bytes = Bytes.empty

            @next_segment.not_nil!.advertise
          end
        end
      end
    end

    private def close_input_file
      if f = @input_file
        f.close if f.responds_to?(:close)
      end
    rescue ex
      RNS.log("Error closing input file: #{ex.message}", RNS::LOG_DEBUG)
    end

    # ─── Receive part (receiver side) ──────────────────────────────

    def receive_part(packet : Packet)
      @receive_lock.synchronize do
        @receiving_part = true
        @last_activity = Time.utc.to_unix_f
        @retries_left = @max_retries

        if @req_resp.nil?
          @req_resp = @last_activity
          rtt = @last_activity - @req_sent

          @part_timeout_factor = PART_TIMEOUT_FACTOR_AFTER_RTT.to_f64
          if @rtt.nil?
            @rtt = @link.try(&.rtt) || 0.5
            watchdog_job
          elsif rtt < @rtt.not_nil!
            @rtt = Math.max(@rtt.not_nil! - @rtt.not_nil! * 0.05, rtt)
          elsif rtt > @rtt.not_nil!
            @rtt = Math.min(@rtt.not_nil! + @rtt.not_nil! * 0.05, rtt)
          end

          if rtt > 0
            req_resp_cost = (packet.raw.try(&.size) || 0) + @req_sent_bytes
            @req_resp_rtt_rate = req_resp_cost.to_f64 / rtt

            if @req_resp_rtt_rate > RATE_FAST && @fast_rate_rounds < FAST_RATE_THRESHOLD
              @fast_rate_rounds += 1
              if @fast_rate_rounds == FAST_RATE_THRESHOLD
                @window_max = WINDOW_MAX_FAST
              end
            end
          end
        end

        if @status != FAILED
          @status = TRANSFERRING
          part_data = packet.data
          part_hash = get_map_hash(part_data)

          consecutive_index = @consecutive_completed_height >= 0 ? @consecutive_completed_height : 0
          i = consecutive_index
          range_end = Math.min(consecutive_index + @window, @hashmap.size)

          (consecutive_index...range_end).each do |idx|
            map_hash = @hashmap[idx]?
            if map_hash && map_hash == part_hash
              if @receiver_parts[idx]?.nil?
                @receiver_parts[idx] = part_data.dup
                @rtt_rxd_bytes += part_data.size
                @received_count += 1
                @outstanding_parts -= 1

                # Update consecutive completed height
                if idx == @consecutive_completed_height + 1
                  @consecutive_completed_height = idx
                end

                cp = @consecutive_completed_height + 1
                while cp < @receiver_parts.size && !@receiver_parts[cp]?.nil?
                  @consecutive_completed_height = cp
                  cp += 1
                end

                if cb = @progress_callback_proc
                  begin
                    cb.call(self)
                  rescue ex
                    RNS.log("Error while executing progress callback: #{ex}", RNS::LOG_ERROR)
                  end
                end
              end
            end
            i += 1
          end

          @receiving_part = false

          if @received_count == @total_parts && !@assembly_lock
            @assembly_lock = true
            spawn { assemble }
          elsif @outstanding_parts == 0
            if @window < @window_max
              @window += 1
              if (@window - @window_min) > (@window_flexibility - 1)
                @window_min += 1
              end
            end

            if @req_sent != 0.0
              rtt = Time.utc.to_unix_f - @req_sent
              req_transferred = @rtt_rxd_bytes - @rtt_rxd_bytes_at_part_req

              if rtt != 0.0
                @req_data_rtt_rate = req_transferred.to_f64 / rtt
                update_eifr
                @rtt_rxd_bytes_at_part_req = @rtt_rxd_bytes

                if @req_data_rtt_rate > RATE_FAST && @fast_rate_rounds < FAST_RATE_THRESHOLD
                  @fast_rate_rounds += 1
                  if @fast_rate_rounds == FAST_RATE_THRESHOLD
                    @window_max = WINDOW_MAX_FAST
                  end
                end

                if @fast_rate_rounds == 0 && @req_data_rtt_rate < RATE_VERY_SLOW && @very_slow_rate_rounds < VERY_SLOW_RATE_THRESHOLD
                  @very_slow_rate_rounds += 1
                  if @very_slow_rate_rounds == VERY_SLOW_RATE_THRESHOLD
                    @window_max = WINDOW_MAX_VERY_SLOW
                  end
                end
              end
            end

            request_next
          end
        else
          @receiving_part = false
        end
      end
    end

    # ─── Request next parts (receiver) ─────────────────────────────

    def request_next
      while @receiving_part
        sleep 0.001.seconds
      end

      return if @status == FAILED
      return if @waiting_for_hmu

      link = @link
      return unless link

      @outstanding_parts = 0
      hashmap_exhausted = HASHMAP_IS_NOT_EXHAUSTED
      requested_hashes = IO::Memory.new

      pn = @consecutive_completed_height + 1
      search_start = pn
      search_size = @window
      i = 0

      search_start.upto(Math.min(search_start + search_size - 1, @receiver_parts.size - 1)) do |idx|
        if @receiver_parts[idx]?.nil?
          part_hash = @hashmap[idx]?
          if part_hash
            requested_hashes.write(part_hash)
            @outstanding_parts += 1
            i += 1
          else
            hashmap_exhausted = HASHMAP_IS_EXHAUSTED
          end
        end

        pn += 1
        break if i >= @window || hashmap_exhausted == HASHMAP_IS_EXHAUSTED
      end

      hmu_part = IO::Memory.new
      hmu_part.write_byte(hashmap_exhausted)
      if hashmap_exhausted == HASHMAP_IS_EXHAUSTED
        last_map_hash = @hashmap[@hashmap_height - 1]
        if last_map_hash
          hmu_part.write(last_map_hash)
        end
        @waiting_for_hmu = true
      end

      request_data_io = IO::Memory.new
      request_data_io.write(hmu_part.to_slice)
      request_data_io.write(@hash)
      request_data_io.write(requested_hashes.to_slice)

      request_packet = Packet.new(link, request_data_io.to_slice, context: Packet::RESOURCE_REQ)

      begin
        request_packet.send
        @last_activity = Time.utc.to_unix_f
        @req_sent = @last_activity
        @req_sent_bytes = request_packet.raw.try(&.size) || 0
        @req_resp = nil
      rescue ex
        RNS.log("Could not send resource request packet, cancelling resource: #{ex}", RNS::LOG_DEBUG)
        cancel
      end
    end

    # ─── Request (sender responds to part request) ─────────────────

    def request(request_data : Bytes)
      return if @status == FAILED
      link = @link
      return unless link

      rtt = Time.utc.to_unix_f - @adv_sent
      @rtt = rtt if @rtt.nil?

      if @status != TRANSFERRING
        @status = TRANSFERRING
        watchdog_job
      end

      @retries_left = @max_retries

      wants_more_hashmap = request_data[0] == HASHMAP_IS_EXHAUSTED
      pad = wants_more_hashmap ? (1 + MAPHASH_LEN) : 1

      hash_len = Identity::HASHLENGTH // 8
      requested_hashes_raw = request_data[(pad + hash_len)..]

      # Parse requested map hashes
      map_hashes = [] of Bytes
      num_hashes = requested_hashes_raw.size // MAPHASH_LEN
      num_hashes.times do |i|
        map_hashes << requested_hashes_raw[i * MAPHASH_LEN, MAPHASH_LEN]
      end

      # Find and send requested parts
      search_start = @receiver_min_consecutive_height
      search_end = Math.min(@receiver_min_consecutive_height + ResourceAdvertisement::COLLISION_GUARD_SIZE, @sender_parts.size)

      requested_parts = @sender_parts[search_start...search_end].select do |part|
        mh = part.map_hash
        mh && map_hashes.any? { |h| h == mh }
      end

      requested_parts.each do |part|
        begin
          if !part.sent
            part.send
            @sent_parts += 1
          else
            part.resend
          end

          @last_activity = Time.utc.to_unix_f
          @last_part_sent = @last_activity
        rescue ex
          RNS.log("Resource could not send parts, cancelling transfer: #{ex}", RNS::LOG_DEBUG)
          cancel
        end
      end

      # Handle hashmap update request
      if wants_more_hashmap
        last_map_hash = request_data[1, MAPHASH_LEN]

        part_index = @receiver_min_consecutive_height
        search_start_hmu = part_index
        search_end_hmu = Math.min(@receiver_min_consecutive_height + ResourceAdvertisement::COLLISION_GUARD_SIZE, @sender_parts.size)

        @sender_parts[search_start_hmu...search_end_hmu].each do |part|
          part_index += 1
          if part.map_hash == last_map_hash
            break
          end
        end

        @receiver_min_consecutive_height = Math.max(part_index - 1 - WINDOW_MAX, 0)

        if part_index % ResourceAdvertisement::HASHMAP_MAX_LEN != 0
          RNS.log("Resource sequencing error, cancelling transfer!", RNS::LOG_ERROR)
          cancel
          return
        else
          segment = part_index // ResourceAdvertisement::HASHMAP_MAX_LEN
        end

        hashmap_start = segment * ResourceAdvertisement::HASHMAP_MAX_LEN
        hashmap_end = Math.min((segment + 1) * ResourceAdvertisement::HASHMAP_MAX_LEN, @sender_parts.size)

        hashmap_io = IO::Memory.new
        (hashmap_start...hashmap_end).each do |idx|
          start_pos = idx * MAPHASH_LEN
          end_pos = Math.min((idx + 1) * MAPHASH_LEN, @hashmap_raw_bytes.size)
          hashmap_io.write(@hashmap_raw_bytes[start_pos...end_pos]) if start_pos < @hashmap_raw_bytes.size
        end

        hmu_data_io = IO::Memory.new
        hmu_data_io.write(@hash)
        packed = [segment, hashmap_io.to_slice].to_msgpack
        hmu_data_io.write(packed)

        hmu_packet = Packet.new(link, hmu_data_io.to_slice, context: Packet::RESOURCE_HMU)
        begin
          hmu_packet.send
          @last_activity = Time.utc.to_unix_f
        rescue ex
          RNS.log("Could not send resource HMU packet, cancelling resource: #{ex}", RNS::LOG_DEBUG)
          cancel
        end
      end

      if @sent_parts == @sender_parts.size
        @status = AWAITING_PROOF
        @retries_left = 3
      end

      if cb = @progress_callback_proc
        begin
          cb.call(self)
        rescue ex
          RNS.log("Error while executing progress callback: #{ex}", RNS::LOG_ERROR)
        end
      end
    end

    # ─── Cancel ────────────────────────────────────────────────────

    def cancel
      if @status < COMPLETE
        @status = FAILED
        link = @link
        if @initiator
          if link && link.status == LinkLike::ACTIVE
            begin
              cancel_packet = Packet.new(link, @hash, context: Packet::RESOURCE_ICL)
              cancel_packet.send
            rescue ex
              RNS.log("Could not send resource cancel packet: #{ex}", RNS::LOG_ERROR)
            end
          end
          link.try(&.cancel_outgoing_resource(@hash))
        else
          link.try(&.cancel_incoming_resource(@hash))
        end

        if cb = @callback
          begin
            link.try(&.resource_concluded(@hash, @size, @started_transferring || Time.utc.to_unix_f,
              window: @window, eifr: @eifr, incoming: !@initiator))
            cb.call(self)
          rescue ex
            RNS.log("Error while executing callbacks on resource cancel from #{self}: #{ex}", RNS::LOG_ERROR)
          end
        end
      end
    end

    def _rejected
      if @status < COMPLETE
        if @initiator
          @status = REJECTED
          @link.try(&.cancel_outgoing_resource(@hash))
          if cb = @callback
            begin
              @link.try(&.resource_concluded(@hash, @size, @started_transferring || Time.utc.to_unix_f,
                window: nil, eifr: nil, incoming: false))
              spawn { cb.call(self) }
            rescue ex
              RNS.log("Error while executing callbacks on resource reject from #{self}: #{ex}", RNS::LOG_ERROR)
            end
          end
        end
      end
    end

    # ─── Callback setters ──────────────────────────────────────────

    def set_callback(callback : Proc(Resource, Nil)?)
      @callback = callback
    end

    def set_progress_callback(callback : Proc(Resource, Nil)?)
      @progress_callback_proc = callback
    end

    # ─── Progress ──────────────────────────────────────────────────

    def get_progress : Float64
      if @status == COMPLETE && @segment_index == @total_segments
        return 1.0
      end

      processed_parts : Float64
      progress_total_parts : Float64

      if @initiator
        if !@split
          processed_parts = @sent_parts.to_f64
          progress_total_parts = @total_parts.to_f64
        else
          processed_segments = @segment_index - 1
          max_parts_per_segment = (MAX_EFFICIENT_SIZE.to_f64 / @sdu.to_f64).ceil
          current_segment_parts = @total_parts.to_f64
          previously_processed_parts = processed_segments.to_f64 * max_parts_per_segment

          current_segment_factor = if current_segment_parts < max_parts_per_segment
                                     max_parts_per_segment / current_segment_parts
                                   else
                                     1.0
                                   end

          processed_parts = previously_processed_parts + @sent_parts.to_f64 * current_segment_factor
          progress_total_parts = @total_segments.to_f64 * max_parts_per_segment
        end
      else
        if !@split
          processed_parts = @received_count.to_f64
          progress_total_parts = @total_parts.to_f64
        else
          processed_segments = @segment_index - 1
          max_parts_per_segment = (MAX_EFFICIENT_SIZE.to_f64 / @sdu.to_f64).ceil
          current_segment_parts = @total_parts.to_f64
          previously_processed_parts = processed_segments.to_f64 * max_parts_per_segment

          current_segment_factor = if current_segment_parts < max_parts_per_segment
                                     max_parts_per_segment / current_segment_parts
                                   else
                                     1.0
                                   end

          processed_parts = previously_processed_parts + @received_count.to_f64 * current_segment_factor
          progress_total_parts = @total_segments.to_f64 * max_parts_per_segment
        end
      end

      progress_total_parts = 1.0 if progress_total_parts == 0.0
      Math.min(1.0, processed_parts / progress_total_parts)
    end

    def get_segment_progress : Float64
      if @status == COMPLETE && @segment_index == @total_segments
        return 1.0
      end

      processed_parts = @initiator ? @sent_parts : @received_count
      return 0.0 if @total_parts == 0
      Math.min(1.0, processed_parts.to_f64 / @total_parts.to_f64)
    end

    def get_transfer_size : Int64
      @size
    end

    def get_data_size : Int64
      @total_size
    end

    def get_parts : Int32
      @total_parts
    end

    def get_segments : Int32
      @total_segments
    end

    def get_hash : Bytes
      @hash
    end

    def is_compressed? : Bool
      @compressed
    end

    def to_s(io : IO)
      io << "<" << @hash.hexstring[0, 12] << ">"
    end

    # ─── Helper ────────────────────────────────────────────────────

    private def concat_bytes(a : Bytes, b : Bytes) : Bytes
      result = Bytes.new(a.size + b.size)
      a.copy_to(result)
      b.copy_to(result + a.size)
      result
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # ResourceAdvertisement — pack/unpack resource metadata
  # ═══════════════════════════════════════════════════════════════

  class ResourceAdvertisement
    OVERHEAD             = 134
    HASHMAP_MAX_LEN      = ((Link::MDU - OVERHEAD) // Resource::MAPHASH_LEN).to_i32
    COLLISION_GUARD_SIZE = 2 * Resource::WINDOW_MAX + HASHMAP_MAX_LEN

    # Fields matching Python's single-letter attributes
    property t : Int64  # Transfer size
    property d : Int64  # Total uncompressed data size
    property n : Int32  # Number of parts
    property h : Bytes  # Resource hash
    property r : Bytes  # Random hash
    property o : Bytes  # Original hash (first segment)
    property m : Bytes  # Hashmap (packed bytes)
    property f : UInt8  # Flags
    property i : Int32  # Segment index
    property l : Int32  # Total segments
    property q : Bytes? # Request ID
    property e : Bool   # Encrypted
    property c : Bool   # Compressed
    property s : Bool   # Split
    property u : Bool   # Is request
    property p : Bool   # Is response
    property x : Bool   # Has metadata
    property link : Link?

    def initialize(resource : Resource)
      @link = nil
      @t = resource.size
      @d = resource.total_size
      @n = resource.sender_parts.size
      @h = resource.hash
      @r = resource.random_hash
      @o = resource.original_hash
      @c = resource.compressed
      @e = resource.encrypted
      @s = resource.split
      @x = resource.has_metadata
      @i = resource.segment_index
      @l = resource.total_segments
      @q = resource.request_id
      @u = false
      @p = false

      if @q
        if !resource.is_response
          @u = true
          @p = false
        else
          @u = false
          @p = true
        end
      end

      # Build hashmap bytes from resource sender_parts
      hashmap_io = IO::Memory.new
      resource.sender_parts.each do |part|
        if mh = part.map_hash
          hashmap_io.write(mh)
        end
      end
      @m = hashmap_io.to_slice.dup

      # Compute flags
      @f = 0x00_u8
      @f |= 0x01_u8 if @e
      @f |= 0x02_u8 if @c
      @f |= 0x04_u8 if @s
      @f |= 0x08_u8 if @u
      @f |= 0x10_u8 if @p
      @f |= 0x20_u8 if @x
    end

    # Bare constructor for unpack
    def initialize
      @link = nil
      @t = 0_i64
      @d = 0_i64
      @n = 0
      @h = Bytes.empty
      @r = Bytes.empty
      @o = Bytes.empty
      @m = Bytes.empty
      @f = 0_u8
      @i = 1
      @l = 1
      @q = nil
      @e = false
      @c = false
      @s = false
      @u = false
      @p = false
      @x = false
    end

    def self.is_request?(advertisement_packet : Packet) : Bool
      adv = unpack(advertisement_packet.plaintext || advertisement_packet.data)
      adv.q != nil && adv.u
    end

    def self.is_response?(advertisement_packet : Packet) : Bool
      adv = unpack(advertisement_packet.plaintext || advertisement_packet.data)
      adv.q != nil && adv.p
    end

    def self.read_request_id(advertisement_packet : Packet) : Bytes?
      adv = unpack(advertisement_packet.plaintext || advertisement_packet.data)
      adv.q
    end

    def self.read_transfer_size(advertisement_packet : Packet) : Int64
      adv = unpack(advertisement_packet.plaintext || advertisement_packet.data)
      adv.t
    end

    def self.read_size(advertisement_packet : Packet) : Int64
      adv = unpack(advertisement_packet.plaintext || advertisement_packet.data)
      adv.d
    end

    def get_transfer_size : Int64
      @t
    end

    def get_data_size : Int64
      @d
    end

    def get_parts : Int32
      @n
    end

    def get_segments : Int32
      @l
    end

    def get_hash : Bytes
      @h
    end

    def is_compressed? : Bool
      @c
    end

    def has_metadata? : Bool
      @x
    end

    def get_link : Link?
      @link
    end

    def pack(segment : Int32 = 0) : Bytes
      hashmap_start = segment * HASHMAP_MAX_LEN
      hashmap_end = Math.min((segment + 1) * HASHMAP_MAX_LEN, @n)

      hashmap = IO::Memory.new
      (hashmap_start...hashmap_end).each do |idx|
        start_pos = idx * Resource::MAPHASH_LEN
        end_pos = Math.min((idx + 1) * Resource::MAPHASH_LEN, @m.size)
        hashmap.write(@m[start_pos...end_pos]) if start_pos < @m.size
      end

      dictionary = {
        "t" => MessagePack::Any.new(@t.as(Int64)),
        "d" => MessagePack::Any.new(@d.as(Int64)),
        "n" => MessagePack::Any.new(@n.to_i64),
        "h" => MessagePack::Any.new(@h),
        "r" => MessagePack::Any.new(@r),
        "o" => MessagePack::Any.new(@o),
        "i" => MessagePack::Any.new(@i.to_i64),
        "l" => MessagePack::Any.new(@l.to_i64),
        "q" => @q ? MessagePack::Any.new(@q.not_nil!) : MessagePack::Any.new(nil),
        "f" => MessagePack::Any.new(@f.to_i64),
        "m" => MessagePack::Any.new(hashmap.to_slice),
      }

      dictionary.to_msgpack
    end

    def self.unpack(data : Bytes) : ResourceAdvertisement
      dict = MessagePack::Any.from_msgpack(data)

      adv = ResourceAdvertisement.new
      adv.t = dict["t"].as_i64
      adv.d = dict["d"].as_i64
      adv.n = dict["n"].as_i.to_i32
      adv.h = dict["h"].raw.as(Bytes)
      adv.r = dict["r"].raw.as(Bytes)
      adv.o = dict["o"].raw.as(Bytes)
      adv.m = dict["m"].raw.as(Bytes)
      adv.f = dict["f"].as_i.to_u8
      adv.i = dict["i"].as_i.to_i32
      adv.l = dict["l"].as_i.to_i32

      q_val = dict["q"]?
      if q_val && !q_val.raw.nil?
        if q_val.raw.is_a?(Slice(UInt8))
          adv.q = q_val.raw.as(Bytes)
        end
      end

      adv.e = (adv.f & 0x01) == 0x01
      adv.c = ((adv.f >> 1) & 0x01) == 0x01
      adv.s = ((adv.f >> 2) & 0x01) == 0x01
      adv.u = ((adv.f >> 3) & 0x01) == 0x01
      adv.p = ((adv.f >> 4) & 0x01) == 0x01
      adv.x = ((adv.f >> 5) & 0x01) == 0x01

      adv
    end
  end
end
