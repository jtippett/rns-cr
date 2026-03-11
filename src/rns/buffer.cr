module RNS
  # ═══════════════════════════════════════════════════════════════
  # StreamDataMessage — Channel message type for binary stream data
  # Ports RNS/Buffer.py StreamDataMessage
  # ═══════════════════════════════════════════════════════════════

  class StreamDataMessage < MessageBase
    class_getter msgtype : UInt16 = SystemMessageTypes::SMT_STREAM_DATA

    STREAM_ID_MAX = 0x3fff # 16383 (14-bit stream id)
    OVERHEAD      = 2 + 6  # 2 for stream data header, 6 for channel envelope
    MAX_DATA_LEN  = Link::MDU - OVERHEAD

    property stream_id : Int32?
    property data : Bytes
    property eof : Bool
    property compressed : Bool

    def initialize(@stream_id : Int32? = nil, @data : Bytes = Bytes.new(0),
                   @eof : Bool = false, @compressed : Bool = false)
      if (sid = @stream_id) && sid > STREAM_ID_MAX
        raise ArgumentError.new("stream_id must be 0-16383")
      end
    end

    def pack : Bytes
      sid = @stream_id
      raise ArgumentError.new("stream_id") if sid.nil?

      header_val = (0x3fff & sid)
      header_val |= 0x8000 if @eof
      header_val |= 0x4000 if @compressed
      io = IO::Memory.new(2 + @data.size)
      io.write_bytes(header_val.to_u16, IO::ByteFormat::BigEndian)
      io.write(@data) if @data.size > 0
      io.to_slice.dup
    end

    def unpack(raw : Bytes)
      raise ArgumentError.new("StreamDataMessage requires at least 2 bytes") if raw.size < 2
      io = IO::Memory.new(raw)
      header = io.read_bytes(UInt16, IO::ByteFormat::BigEndian)
      @eof = (header & 0x8000) > 0
      @compressed = (header & 0x4000) > 0
      @stream_id = (header & 0x3fff).to_i32
      @data = raw[2..].dup

      if @compressed && @data.size > 0
        @data = BZip2.decompress(@data)
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # RawChannelReader — reads binary stream data from a Channel
  # Generic over TPacket to match Channel(TPacket).
  # Ports RNS/Buffer.py RawChannelReader.
  # ═══════════════════════════════════════════════════════════════

  class RawChannelReader(TPacket)
    @stream_id : Int32
    @channel : Channel(TPacket)
    @lock : Mutex
    @buffer : IO::Memory
    @eof : Bool
    @listeners : Array(Int32 -> Nil)
    @handler : MessageBase -> Bool
    @closed : Bool

    def initialize(@stream_id : Int32, @channel : Channel(TPacket))
      @lock = Mutex.new(:reentrant)
      @buffer = IO::Memory.new
      @eof = false
      @listeners = [] of (Int32 -> Nil)
      @closed = false

      # Register StreamDataMessage as system type and add our handler
      @channel._register_message_type(StreamDataMessage, is_system_type: true)
      @handler = ->(message : MessageBase) { _handle_message(message) }
      @channel.add_message_handler(@handler)
    end

    # Add a callback invoked when new data arrives.
    # Signature: (ready_bytes : Int32) -> Nil
    def add_ready_callback(cb : Int32 -> Nil)
      @lock.synchronize do
        @listeners << cb
      end
    end

    # Remove a previously added callback.
    def remove_ready_callback(cb : Int32 -> Nil)
      @lock.synchronize do
        @listeners.delete(cb)
      end
    end

    # Read up to `size` bytes from the internal buffer.
    # Returns Bytes if data available (possibly empty at EOF), nil if no data and not EOF.
    def read(size : Int32) : Bytes?
      @lock.synchronize do
        available = @buffer.size - @buffer.pos
        to_read = Math.min(size, available.to_i32)
        if to_read > 0
          result = Bytes.new(to_read)
          @buffer.read(result)
          _compact_buffer
          return result
        elsif @eof
          return Bytes.new(0)
        else
          return nil
        end
      end
    end

    # Read into a provided buffer (matching Python readinto).
    # Returns number of bytes read, or nil if no data available and not EOF.
    def readinto(buffer : Bytes) : Int32?
      ready = read(buffer.size)
      if ready
        ready.copy_to(buffer.to_unsafe, ready.size)
        return ready.size
      end
      nil
    end

    # Number of bytes available to read without blocking.
    def available : Int32
      @lock.synchronize do
        (@buffer.size - @buffer.pos).to_i32
      end
    end

    # Whether the stream has received EOF.
    def eof? : Bool
      @lock.synchronize { @eof }
    end

    def writable? : Bool
      false
    end

    def seekable? : Bool
      false
    end

    def readable? : Bool
      true
    end

    def closed? : Bool
      @closed
    end

    def close
      @lock.synchronize do
        @channel.remove_message_handler(@handler)
        @listeners.clear
        @closed = true
      end
    end

    private def _handle_message(message : MessageBase) : Bool
      if message.is_a?(StreamDataMessage)
        sdm = message.as(StreamDataMessage)
        if sdm.stream_id == @stream_id
          @lock.synchronize do
            if sdm.data.size > 0
              # Append data to end of buffer, preserving read position
              old_pos = @buffer.pos
              @buffer.seek(0, IO::Seek::End)
              @buffer.write(sdm.data)
              @buffer.seek(old_pos, IO::Seek::Set)
            end
            @eof = true if sdm.eof

            ready_bytes = (@buffer.size - @buffer.pos).to_i32
            @listeners.each do |listener|
              spawn do
                begin
                  listener.call(ready_bytes)
                rescue ex
                  RNS.log("Error calling RawChannelReader(#{@stream_id}) callback: #{ex}", RNS::LOG_ERROR)
                end
              end
            end
          end
          return true
        end
      end
      false
    end

    private def _compact_buffer
      remaining = @buffer.size - @buffer.pos
      if remaining > 0
        data = Bytes.new(remaining)
        @buffer.read(data)
        @buffer = IO::Memory.new
        @buffer.write(data)
        @buffer.seek(0, IO::Seek::Set)
      else
        @buffer = IO::Memory.new
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # RawChannelWriter — writes binary stream data over a Channel
  # Generic over TPacket to match Channel(TPacket).
  # Ports RNS/Buffer.py RawChannelWriter.
  # ═══════════════════════════════════════════════════════════════

  class RawChannelWriter(TPacket)
    MAX_CHUNK_LEN     = 1024 * 16 # 16 KiB
    COMPRESSION_TRIES = 4

    @stream_id : Int32
    @channel : Channel(TPacket)
    @eof : Bool

    def initialize(@stream_id : Int32, @channel : Channel(TPacket))
      @eof = false
    end

    # Write data to the channel. Returns number of bytes consumed, or 0 if not ready.
    def write(data : Bytes) : Int32
      begin
        comp_tries = COMPRESSION_TRIES
        comp_try = 1
        comp_success = false
        chunk_len = data.size

        if chunk_len > MAX_CHUNK_LEN
          chunk_len = MAX_CHUNK_LEN
          data = data[0, MAX_CHUNK_LEN]
        end

        compressed_chunk = Bytes.new(0)
        chunk_segment_length = 0

        while chunk_len > 32 && comp_try < comp_tries
          chunk_segment_length = chunk_len // comp_try
          compressed_chunk = BZip2.compress(data[0, chunk_segment_length])
          compressed_length = compressed_chunk.size
          if compressed_length < StreamDataMessage::MAX_DATA_LEN && compressed_length < chunk_segment_length
            comp_success = true
            break
          else
            comp_try += 1
          end
        end

        chunk : Bytes
        processed_length : Int32

        if comp_success
          chunk = compressed_chunk
          processed_length = chunk_segment_length
        else
          max_len = Math.min(data.size, StreamDataMessage::MAX_DATA_LEN)
          chunk = data[0, max_len].dup
          processed_length = chunk.size
        end

        message = StreamDataMessage.new(@stream_id, chunk, @eof, comp_success)
        @channel.send(message)
        return processed_length
      rescue ex : ChannelException
        if ex.type != CEType::ME_LINK_NOT_READY
          raise ex
        end
      end

      0
    end

    # Close the writer by sending an EOF message.
    def close
      begin
        timeout = Time.utc.to_unix_f + 15.0
      rescue
        timeout = Time.utc.to_unix_f + 15.0
      end

      while Time.utc.to_unix_f < timeout && !@channel.is_ready_to_send?
        sleep(50.milliseconds)
      end

      @eof = true
      write(Bytes.new(0))
    end

    def seekable? : Bool
      false
    end

    def readable? : Bool
      false
    end

    def writable? : Bool
      true
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Buffer — factory methods for creating buffered channel streams
  # Ports RNS/Buffer.py Buffer class.
  # ═══════════════════════════════════════════════════════════════

  module Buffer
    # Create a reader that receives binary data from a Channel.
    def self.create_reader(stream_id : Int32, channel : Channel(TPacket),
                           ready_callback : (Int32 -> Nil)? = nil) : RawChannelReader(TPacket) forall TPacket
      reader = RawChannelReader(TPacket).new(stream_id, channel)
      if cb = ready_callback
        reader.add_ready_callback(cb)
      end
      reader
    end

    # Create a writer that sends binary data over a Channel.
    def self.create_writer(stream_id : Int32, channel : Channel(TPacket)) : RawChannelWriter(TPacket) forall TPacket
      RawChannelWriter(TPacket).new(stream_id, channel)
    end

    # Create a bidirectional reader/writer pair over a Channel.
    def self.create_bidirectional_buffer(receive_stream_id : Int32, send_stream_id : Int32,
                                         channel : Channel(TPacket),
                                         ready_callback : (Int32 -> Nil)? = nil) : {RawChannelReader(TPacket), RawChannelWriter(TPacket)} forall TPacket
      reader = RawChannelReader(TPacket).new(receive_stream_id, channel)
      if cb = ready_callback
        reader.add_ready_callback(cb)
      end
      writer = RawChannelWriter(TPacket).new(send_stream_id, channel)
      {reader, writer}
    end
  end
end
