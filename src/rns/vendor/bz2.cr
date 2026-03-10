@[Link("bz2")]
lib LibBZ2
  BZ_OK             =  0
  BZ_RUN_OK         =  1
  BZ_FLUSH_OK       =  2
  BZ_FINISH_OK      =  3
  BZ_STREAM_END     =  4
  BZ_OUTBUFF_FULL   = -8

  fun compress = BZ2_bzBuffToBuffCompress(
    dest : UInt8*, dest_len : UInt32*,
    source : UInt8*, source_len : UInt32,
    block_size_100k : Int32, verbosity : Int32, work_factor : Int32
  ) : Int32

  fun decompress = BZ2_bzBuffToBuffDecompress(
    dest : UInt8*, dest_len : UInt32*,
    source : UInt8*, source_len : UInt32,
    small : Int32, verbosity : Int32
  ) : Int32
end

module RNS
  module BZip2
    class Error < Exception; end

    # Compress data using BZip2 (block_size_100k=9 for best compression, matching Python bz2.compress default)
    def self.compress(data : Bytes) : Bytes
      return Bytes.empty if data.empty?

      # BZip2 worst case: input + 1% + 600 bytes overhead
      dest_len = (data.size.to_f64 * 1.01 + 600).to_u32
      dest = Bytes.new(dest_len)

      result = LibBZ2.compress(
        dest.to_unsafe, pointerof(dest_len),
        data.to_unsafe, data.size.to_u32,
        9, 0, 0
      )

      unless result == LibBZ2::BZ_OK
        raise Error.new("BZip2 compression failed with code #{result}")
      end

      dest[0, dest_len].dup
    end

    # Decompress BZip2 data. Automatically grows buffer if needed.
    def self.decompress(data : Bytes) : Bytes
      return Bytes.empty if data.empty?

      # Start with 4x input or min 4KB
      dest_len = Math.max(data.size.to_u32 * 4, 4096_u32)

      loop do
        dest = Bytes.new(dest_len)
        actual_len = dest_len

        result = LibBZ2.decompress(
          dest.to_unsafe, pointerof(actual_len),
          data.to_unsafe, data.size.to_u32,
          0, 0
        )

        case result
        when LibBZ2::BZ_OK
          return dest[0, actual_len].dup
        when LibBZ2::BZ_OUTBUFF_FULL
          # Double buffer and retry
          dest_len = dest_len * 2
          raise Error.new("BZip2 decompression buffer exceeded 256MB") if dest_len > 256_u32 * 1024 * 1024
        else
          raise Error.new("BZip2 decompression failed with code #{result}")
        end
      end
    end
  end
end
