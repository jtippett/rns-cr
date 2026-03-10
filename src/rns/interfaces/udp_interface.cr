require "socket"

module RNS
  class UDPInterface < Interface
    BITRATE_GUESS    = 10_000_000_i64
    DEFAULT_IFAC_SIZE = 16

    getter? receives : Bool = false
    getter? forwards : Bool = false

    getter bind_ip : String = ""
    getter bind_port : Int32 = 0
    getter forward_ip : String = ""
    getter forward_port : Int32 = 0

    # Direction flags (instance-level, matching Python's self.IN / self.OUT)
    property dir_in : Bool = true
    property dir_out : Bool = false

    @socket : UDPSocket? = nil
    @receive_fiber : Fiber? = nil
    @running : Bool = false
    @inbound_callback : (Proc(Bytes, Interface, Nil))? = nil

    def initialize(configuration : Hash(String, String), &block : Bytes, Interface ->)
      super()
      @inbound_callback = block
      configure(configuration)
    end

    def initialize(configuration : Hash(String, String))
      super()
      configure(configuration)
    end

    private def configure(c : Hash(String, String))
      name        = c["name"]? || ""
      device      = c["device"]?
      port        = c["port"]?.try(&.to_i)
      bindip      = c["listen_ip"]?
      bindport    = c["listen_port"]?.try(&.to_i)
      forwardip   = c["forward_ip"]?
      forwardport = c["forward_port"]?.try(&.to_i)

      if p = port
        bindport = p if bindport.nil?
        forwardport = p if forwardport.nil?
      end

      @hw_mtu = 1064
      @dir_in = true
      @dir_out = false
      @name = name
      @online = false
      @bitrate = BITRATE_GUESS

      if bindip && bindport
        @receives = true
        @bind_ip = bindip
        @bind_port = bindport

        socket = UDPSocket.new
        socket.reuse_address = true
        socket.bind(@bind_ip, @bind_port)
        @socket = socket
        @running = true

        @receive_fiber = spawn do
          receive_loop
        end

        @online = true
      end

      if forwardip && forwardport
        @forwards = true
        @forward_ip = forwardip
        @forward_port = forwardport
      end
    end

    private def receive_loop
      buf = Bytes.new(2048)
      while @running
        if sock = @socket
          begin
            bytes_read, _addr = sock.receive(buf)
            if bytes_read > 0
              data = buf[0, bytes_read].dup
              process_incoming(data)
            end
          rescue ex : IO::Error
            break unless @running
          rescue ex
            break unless @running
          end
        else
          break
        end
      end
    end

    def process_incoming(data : Bytes)
      @rxb += data.size.to_i64
      if cb = @inbound_callback
        cb.call(data, self)
      end
    end

    def process_outgoing(data : Bytes)
      return unless @forwards

      begin
        udp_socket = UDPSocket.new
        udp_socket.broadcast = true
        udp_socket.send(data, Socket::IPAddress.new(@forward_ip, @forward_port))
        udp_socket.close
        @txb += data.size.to_i64
      rescue ex
        RNS.log("Could not transmit on #{self}. The contained exception was: #{ex.message}", RNS::LOG_ERROR)
      end
    end

    def teardown
      @running = false
      if sock = @socket
        begin
          sock.close unless sock.closed?
        rescue
        end
        @socket = nil
      end
      @online = false
    end

    def to_s(io : IO)
      if @receives
        io << "UDPInterface[" << @name << "/" << @bind_ip << ":" << @bind_port << "]"
      else
        io << "UDPInterface[" << @name << "]"
      end
    end
  end
end
