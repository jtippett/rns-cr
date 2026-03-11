module RNS
  # Interface that communicates with external programs via stdin/stdout pipes.
  # Uses HDLC framing for packetization, matching RNS/Interfaces/PipeInterface.py.
  class PipeInterface < Interface
    MAX_CHUNK         =         32768
    BITRATE_GUESS     = 1_000_000_i64
    DEFAULT_IFAC_SIZE =             8

    property command : String = ""
    property respawn_delay : Float64 = 5.0

    @process : Process? = nil
    @pipe_is_open : Bool = false
    @running : Bool = false
    @read_fiber : Fiber? = nil
    @inbound_callback : Proc(Bytes, Interface, Nil)? = nil
    @timeout : Int32 = 100

    def initialize(configuration : Hash(String, String),
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback
      configure(configuration)
    end

    # Constructor for testing: create with explicit parameters, optionally without spawning
    def initialize(name : String, command : String,
                   respawn_delay : Float64 = 5.0,
                   spawn_process : Bool = true,
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback
      @name = name
      @command = command
      @respawn_delay = respawn_delay
      @hw_mtu = 1064
      @bitrate = BITRATE_GUESS
      @timeout = 100

      if spawn_process
        open_pipe
        if @pipe_is_open
          configure_pipe
        else
          raise IO::Error.new("Could not connect pipe")
        end
      end
    end

    private def configure(c : Hash(String, String))
      name = c["name"]? || ""
      command = c["command"]?
      respawn_delay = c["respawn_delay"]?.try(&.to_f) || 5.0

      raise ArgumentError.new("No command specified for PipeInterface") unless command

      @hw_mtu = 1064
      @name = name
      @command = command
      @respawn_delay = respawn_delay
      @timeout = 100
      @online = false
      @bitrate = BITRATE_GUESS

      begin
        open_pipe
      rescue ex
        RNS.log("Could not connect pipe for interface #{self}", RNS::LOG_ERROR)
        raise ex
      end

      if @pipe_is_open
        configure_pipe
      else
        raise IO::Error.new("Could not connect pipe")
      end
    end

    def open_pipe
      RNS.log("Connecting subprocess pipe for #{self}...", RNS::LOG_VERBOSE)

      begin
        process = Process.new(
          @command,
          shell: true,
          input: Process::Redirect::Pipe,
          output: Process::Redirect::Pipe,
          error: Process::Redirect::Close
        )
        @process = process
        @pipe_is_open = true
      rescue ex
        @pipe_is_open = false
        raise ex
      end
    end

    def configure_pipe
      sleep 0.01.seconds
      @running = true
      @read_fiber = spawn { read_loop }
      @online = true
      RNS.log("Subprocess pipe for #{self} is now connected", RNS::LOG_VERBOSE)
    end

    def process_incoming(data : Bytes)
      @rxb += data.size.to_i64
      if cb = @inbound_callback
        cb.call(data, self)
      end
    end

    def process_outgoing(data : Bytes)
      return unless @online

      if process = @process
        framed = HDLC.frame(data)
        begin
          process.input.write(framed)
          process.input.flush
          @txb += framed.size.to_i64
        rescue ex
          raise IO::Error.new("Pipe interface write error: #{ex.message}")
        end
      end
    end

    private def read_loop
      begin
        in_frame = false
        escape = false
        data_buffer = IO::Memory.new(1024)
        _last_read_ms = (Time.utc.to_unix_f * 1000).to_i64
        buf = Bytes.new(1)

        while @running
          process = @process
          break unless process

          begin
            bytes_read = process.output.read(buf)
            if bytes_read == 0
              # Check if process has terminated
              if process.terminated?
                break
              end
              sleep 0.01.seconds
              next
            end

            byte = buf[0]
            _last_read_ms = (Time.utc.to_unix_f * 1000).to_i64

            if in_frame && byte == HDLC::FLAG
              in_frame = false
              if data_buffer.pos > 0
                process_incoming(data_buffer.to_slice.dup)
              end
            elsif byte == HDLC::FLAG
              in_frame = true
              data_buffer = IO::Memory.new(1024)
            elsif in_frame && data_buffer.pos < hw_mtu_value
              if byte == HDLC::ESC
                escape = true
              else
                if escape
                  byte = HDLC::FLAG if byte == (HDLC::FLAG ^ HDLC::ESC_MASK)
                  byte = HDLC::ESC if byte == (HDLC::ESC ^ HDLC::ESC_MASK)
                  escape = false
                end
                data_buffer.write_byte(byte)
              end
            end
          rescue ex : IO::Error
            break
          end
        end

        RNS.log("Subprocess terminated on #{self}")
        kill_process
      rescue ex
        @online = false
        kill_process

        RNS.log("A pipe error occurred, the contained exception was: #{ex.message}", RNS::LOG_ERROR)
        RNS.log("The interface #{self} experienced an unrecoverable error and is now offline.", RNS::LOG_ERROR)

        if Reticulum.panic_on_interface_error
          RNS.panic
        end

        RNS.log("Reticulum will attempt to reconnect the interface periodically.", RNS::LOG_ERROR)
      end

      @online = false
      spawn { reconnect_pipe } if @running
    end

    def reconnect_pipe
      while !@online && @running
        begin
          sleep @respawn_delay.seconds
          RNS.log("Attempting to respawn subprocess for #{self}...", RNS::LOG_VERBOSE)
          open_pipe
          if @pipe_is_open
            configure_pipe
          end
        rescue ex
          RNS.log("Error while spawning subprocess, the contained exception was: #{ex.message}", RNS::LOG_ERROR)
        end
      end

      if @online
        RNS.log("Reconnected pipe for #{self}")
      end
    end

    def kill_process
      if process = @process
        begin
          process.terminate unless process.terminated?
        rescue ex
          RNS.log("Error terminating process: #{ex.message}", RNS::LOG_DEBUG)
        end
        @process = nil
      end
      @pipe_is_open = false
    end

    def teardown
      @running = false
      @online = false
      kill_process
    end

    def detach
      @detached = true
      teardown
    end

    def pipe_is_open? : Bool
      @pipe_is_open
    end

    private def hw_mtu_value : Int32
      @hw_mtu || 1064
    end

    def to_s(io : IO)
      io << "PipeInterface[" << @name << "]"
    end
  end
end
