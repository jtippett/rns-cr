require "socket"

module RNS
  class LocalClientInterface < Interface
    RECONNECT_WAIT    = 8
    AUTOCONFIGURE_MTU = true
    HW_MTU_DEFAULT    = 262144

    getter? receives : Bool = false
    property reconnecting : Bool = false
    property never_connected : Bool = true
    property writing : Bool = false
    property is_connected_to_shared_instance : Bool = false
    getter target_ip : String? = nil
    getter target_port : Int32? = nil
    getter socket_path : String? = nil
    property dir_in : Bool = true
    property dir_out : Bool = false
    property force_bitrate : Bool = false

    @socket : Socket? = nil
    @read_fiber : Fiber? = nil
    @running : Bool = false
    @inbound_callback : Proc(Bytes, Interface, Nil)? = nil
    @send_mutex : Mutex = Mutex.new

    # Constructor for initiator client — connects to shared instance via TCP or Unix socket
    def initialize(target_port : Int32? = nil, socket_path : String? = nil,
                   name : String = "",
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback
      @name = name
      @hw_mtu = HW_MTU_DEFAULT
      @mode = MODE_FULL
      @bitrate = 1_000_000_000_i64
      @online = false
      @dir_in = true
      @dir_out = false

      if sp = socket_path
        @socket_path = sp
        @receives = true
        connect
      elsif tp = target_port
        @receives = true
        @target_ip = "127.0.0.1"
        @target_port = tp
        connect
      end

      @online = true
      start_read_loop unless @socket.nil?
    end

    # Constructor for server-spawned client — wraps an already-connected socket
    def initialize(connected_socket : Socket, name : String = "",
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback
      @name = name
      @receives = true
      @socket = connected_socket
      @is_connected_to_shared_instance = false
      @hw_mtu = HW_MTU_DEFAULT
      @mode = MODE_FULL
      @bitrate = 1_000_000_000_i64
      @online = true
      @dir_in = true
      @dir_out = false

      if connected_socket.is_a?(TCPSocket)
        connected_socket.tcp_nodelay = true
      end

      start_read_loop
    end

    def should_ingress_limit? : Bool
      false
    end

    def connect : Bool
      if sp = @socket_path
        sock = UNIXSocket.new(sp)
        @socket = sock
      elsif (tip = @target_ip) && (tport = @target_port)
        sock = TCPSocket.new(tip, tport)
        sock.tcp_nodelay = true
        @socket = sock
      else
        return false
      end

      @online = true
      @is_connected_to_shared_instance = true
      @never_connected = false
      true
    end

    def reconnect
      unless @is_connected_to_shared_instance
        RNS.log("Attempt to reconnect on a non-initiator shared local interface.", RNS::LOG_ERROR)
        return
      end
      return if @reconnecting
      @reconnecting = true

      while !@online
        sleep RECONNECT_WAIT.seconds
        begin
          connect
        rescue ex
          RNS.log("Connection attempt for #{self} failed: #{ex.message}", RNS::LOG_DEBUG)
        end
      end

      if !@never_connected
        RNS.log("Reconnected socket for #{self}.", RNS::LOG_INFO)
      end

      @reconnecting = false
      start_read_loop

      # Notify transport of reconnection after a delay
      spawn do
        sleep (RECONNECT_WAIT + 2).seconds
        Transport.shared_connection_reappeared
      end
    end

    private def start_read_loop
      @running = true
      @read_fiber = spawn { read_loop }
    end

    def process_incoming(data : Bytes)
      return if !@online || detached?
      @rxb += data.size.to_i64
      if pi = @parent_interface
        pi.rxb += data.size.to_i64
      end
      if cb = @inbound_callback
        cb.call(data, self)
      end
    end

    def process_outgoing(data : Bytes)
      return if !@online || detached?
      begin
        @writing = true

        if @force_bitrate
          @send_mutex.synchronize do
            s = data.size.to_f64 / @bitrate.to_f64 * 8
            sleep s.seconds
          end
        end

        framed = HDLC.frame(data)
        if sock = @socket
          sock.write(framed)
          sock.flush
        end
        @writing = false
        @txb += framed.size.to_i64
        if pi = @parent_interface
          pi.txb += framed.size.to_i64
        end
      rescue ex
        RNS.log("Exception while transmitting via #{self}, tearing down", RNS::LOG_ERROR)
        RNS.log("The contained exception was: #{ex.message}", RNS::LOG_ERROR)
        teardown
      end
    end

    private def read_loop
      frame_buffer = IO::Memory.new(4096)
      buf = Bytes.new(4096)

      while @running
        sock = @socket
        break unless sock
        begin
          bytes_read = sock.read(buf)
          if bytes_read > 0
            data_in = buf[0, bytes_read]
            frame_buffer.write(data_in)
            process_hdlc_buffer(frame_buffer)
          else
            @online = false
            if @is_connected_to_shared_instance && !detached?
              RNS.log("Socket for #{self} was closed, attempting to reconnect...", RNS::LOG_WARNING)
              Transport.shared_connection_disappeared
              spawn { reconnect }
            else
              teardown(nowarning: true)
            end
            break
          end
        rescue ex
          @online = false
          RNS.log("An interface error occurred: #{ex.message}", RNS::LOG_ERROR)
          RNS.log("Tearing down #{self}", RNS::LOG_ERROR)
          teardown
          break
        end
      end
    end

    private def process_hdlc_buffer(frame_buffer : IO::Memory)
      data = frame_buffer.to_slice
      pos = 0
      last_end = 0
      while pos < data.size
        flag_start = -1
        j = pos
        while j < data.size
          if data[j] == HDLC::FLAG
            flag_start = j
            break
          end
          j += 1
        end
        break if flag_start == -1

        flag_end = -1
        j = flag_start + 1
        while j < data.size
          if data[j] == HDLC::FLAG
            flag_end = j
            break
          end
          j += 1
        end
        break if flag_end == -1

        frame = data[flag_start + 1, flag_end - flag_start - 1]
        unescaped = HDLC.unescape(frame)
        if unescaped.size > Reticulum::HEADER_MINSIZE
          process_incoming(unescaped)
        end
        pos = flag_end + 1
        last_end = pos
      end
      if last_end > 0
        remaining = data[last_end, data.size - last_end]
        frame_buffer.clear
        frame_buffer.write(remaining) if remaining.size > 0
      end
    end

    def teardown(nowarning : Bool = false)
      @online = false
      @dir_out = false
      @dir_in = false
      @running = false

      if pi = @parent_interface
        if si = pi.spawned_interfaces
          si.reject! { |i| i.object_id == self.object_id }
        end
      end

      unless nowarning
        RNS.log("The interface #{self} experienced an unrecoverable error and is being torn down.", RNS::LOG_ERROR)
      end

      close_socket
    end

    def detach
      if sock = @socket
        RNS.log("Detaching #{self}", RNS::LOG_DEBUG)
        @detached = true
        @online = false
        @running = false

        begin
          sock.close unless sock.closed?
        rescue ex
          RNS.log("Error while closing socket for #{self}: #{ex.message}", RNS::LOG_ERROR)
        end
        @socket = nil
      end
    end

    private def close_socket
      if sock = @socket
        begin
          sock.close unless sock.closed?
        rescue ex
          RNS.log("Error closing socket: #{ex.message}", RNS::LOG_DEBUG)
        end
        @socket = nil
      end
    end

    def target_ip=(ip : String?)
      @target_ip = ip
    end

    def target_port=(port : Int32?)
      @target_port = port
    end

    def socket_path=(path : String?)
      @socket_path = path
    end

    def inbound_callback=(cb : Proc(Bytes, Interface, Nil)?)
      @inbound_callback = cb
    end

    def to_s(io : IO)
      if sp = @socket_path
        io << "LocalInterface[" << sp.gsub("\0", "") << "]"
      else
        io << "LocalInterface[" << (@target_port || 0) << "]"
      end
    end
  end

  class LocalServerInterface < Interface
    AUTOCONFIGURE_MTU = true
    HW_MTU_DEFAULT    = 262144

    getter bind_ip : String? = nil
    getter bind_port : Int32? = nil
    getter socket_path : String? = nil
    property is_local_shared_instance : Bool = true
    property dir_in : Bool = true
    property dir_out : Bool = false
    property clients : Int32 = 0

    @tcp_server : TCPServer? = nil
    @unix_server : UNIXServer? = nil
    @accept_fiber : Fiber? = nil
    @running : Bool = false
    @inbound_callback : Proc(Bytes, Interface, Nil)? = nil

    # TCP server constructor — binds to 127.0.0.1:port
    def initialize(bindport : Int32,
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback
      @name = "Reticulum"
      @mode = MODE_FULL
      @hw_mtu = HW_MTU_DEFAULT
      @bitrate = 1_000_000_000_i64
      @online = false
      @spawned_interfaces = [] of Interface
      @dir_in = true
      @dir_out = false

      @receives = true
      @bind_ip = "127.0.0.1"
      @bind_port = bindport

      begin
        server = TCPServer.new("127.0.0.1", bindport, reuse_port: true)
        @tcp_server = server
        @running = true
        @accept_fiber = spawn { accept_loop_tcp }
        @online = true
      rescue ex
        raise ArgumentError.new("Could not bind local TCP socket on port #{bindport}: #{ex.message}")
      end
    end

    # Unix domain socket server constructor
    def initialize(socket_path : String,
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback
      @name = "Reticulum"
      @mode = MODE_FULL
      @hw_mtu = HW_MTU_DEFAULT
      @bitrate = 1_000_000_000_i64
      @online = false
      @spawned_interfaces = [] of Interface
      @dir_in = true
      @dir_out = false

      @receives = true
      @socket_path = socket_path

      begin
        # Remove stale socket file if it exists
        File.delete?(socket_path) if File.exists?(socket_path)
        server = UNIXServer.new(socket_path)
        @unix_server = server
        @running = true
        @accept_fiber = spawn { accept_loop_unix }
        @online = true
      rescue ex
        raise ArgumentError.new("Could not bind local Unix socket at #{socket_path}: #{ex.message}")
      end
    end

    private def accept_loop_tcp
      while @running
        if srv = @tcp_server
          begin
            client_socket = srv.accept
            spawn { incoming_connection_tcp(client_socket) }
          rescue ex : IO::Error
            break unless @running
          rescue ex
            RNS.log("Error accepting on #{self}: #{ex.message}", RNS::LOG_ERROR)
            break unless @running
          end
        else
          break
        end
      end
    end

    private def accept_loop_unix
      while @running
        if srv = @unix_server
          begin
            client_socket = srv.accept
            spawn { incoming_connection_unix(client_socket) }
          rescue ex : IO::Error
            break unless @running
          rescue ex
            RNS.log("Error accepting on #{self}: #{ex.message}", RNS::LOG_ERROR)
            break unless @running
          end
        else
          break
        end
      end
    end

    def incoming_connection_tcp(client_socket : TCPSocket)
      remote_port = begin
        client_socket.remote_address.port
      rescue
        0
      end
      interface_name = remote_port.to_s

      spawned = LocalClientInterface.new(
        connected_socket: client_socket,
        name: interface_name,
        inbound_callback: @inbound_callback
      )

      spawned.dir_out = @dir_out
      spawned.dir_in = @dir_in
      spawned.target_ip = begin
        client_socket.remote_address.address
      rescue
        "127.0.0.1"
      end
      spawned.target_port = remote_port
      spawned.parent_interface = self
      spawned.bitrate = @bitrate
      spawned.force_bitrate = @force_bitrate

      if si = @spawned_interfaces
        si << spawned
      end
      @clients += 1

      RNS.log("Spawned new LocalClient Interface: #{spawned}", RNS::LOG_VERBOSE)
    end

    def incoming_connection_unix(client_socket : UNIXSocket)
      interface_name = "#{@clients}@#{@socket_path}"

      spawned = LocalClientInterface.new(
        connected_socket: client_socket,
        name: interface_name,
        inbound_callback: @inbound_callback
      )

      spawned.dir_out = @dir_out
      spawned.dir_in = @dir_in
      spawned.socket_path = @socket_path
      spawned.parent_interface = self
      spawned.bitrate = @bitrate
      spawned.force_bitrate = @force_bitrate

      if si = @spawned_interfaces
        si << spawned
      end
      @clients += 1

      RNS.log("Spawned new LocalClient Interface: #{spawned}", RNS::LOG_VERBOSE)
    end

    property force_bitrate : Bool = false

    def received_announce(from_spawned = false)
      if from_spawned
        ia_freq_deque << Time.utc.to_unix_f
        ia_freq_deque.shift if ia_freq_deque.size > IA_FREQ_SAMPLES
      end
    end

    def sent_announce(from_spawned = false)
      if from_spawned
        oa_freq_deque << Time.utc.to_unix_f
        oa_freq_deque.shift if oa_freq_deque.size > OA_FREQ_SAMPLES
      end
    end

    def process_outgoing(data : Bytes)
      # Server doesn't send data directly — spawned clients handle outgoing
    end

    def detach
      @detached = true
      @online = false
      @running = false

      if srv = @tcp_server
        begin
          RNS.log("Detaching #{self}", RNS::LOG_DEBUG)
          srv.close unless srv.closed?
        rescue ex
          RNS.log("Error shutting down server for #{self}: #{ex.message}", RNS::LOG_ERROR)
        end
        @tcp_server = nil
      end

      if srv = @unix_server
        begin
          RNS.log("Detaching #{self}", RNS::LOG_DEBUG)
          srv.close unless srv.closed?
        rescue ex
          RNS.log("Error shutting down server for #{self}: #{ex.message}", RNS::LOG_ERROR)
        end
        @unix_server = nil
      end

      # Clean up socket file
      if sp = @socket_path
        File.delete?(sp) if File.exists?(sp)
      end
    end

    def to_s(io : IO)
      if sp = @socket_path
        io << "Shared Instance[" << sp.gsub("\0", "") << "]"
      else
        io << "Shared Instance[" << (@bind_port || 0) << "]"
      end
    end
  end
end
