require "socket"

module RNS
  module BackboneInterfaceConstants
    HW_MTU = 1048576
  end

  class BackboneInterface < Interface
    BITRATE_GUESS     = 1_000_000_000_i64
    DEFAULT_IFAC_SIZE =                16
    AUTOCONFIGURE_MTU = true

    getter bind_ip : String = ""
    getter bind_port : Int32 = 0
    property dir_in : Bool = true
    property dir_out : Bool = false
    property prefer_ipv6 : Bool = false

    @server : TCPServer? = nil
    @accept_fiber : Fiber? = nil
    @running : Bool = false
    @inbound_callback : Proc(Bytes, Interface, Nil)? = nil

    def initialize(configuration : Hash(String, String),
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback
      configure(configuration)
    end

    private def configure(c : Hash(String, String))
      name = c["name"]? || ""
      device = c["device"]?
      port = c["port"]?.try(&.to_i)
      bindip = c["listen_ip"]?
      bindport = c["listen_port"]?.try(&.to_i)
      prefer_ipv6 = c["prefer_ipv6"]?.try { |v| v.downcase == "true" } || false

      bindport = port if port

      @hw_mtu = BackboneInterfaceConstants::HW_MTU
      @online = false
      @dir_in = true
      @dir_out = false
      @name = name
      @mode = MODE_FULL
      @spawned_interfaces = [] of Interface
      @supports_discovery = true
      @prefer_ipv6 = prefer_ipv6

      unless bindport
        raise ArgumentError.new("No TCP port configured for interface \"#{name}\"")
      end
      @bind_port = bindport

      if device
        # Resolve address from network interface name
        bind_address = get_address_for_if(device, @bind_port, prefer_ipv6)
        bindip = bind_address[0]
      end

      unless bindip
        raise ArgumentError.new("No TCP bind IP configured for interface \"#{name}\"")
      end
      @bind_ip = bindip

      begin
        server = TCPServer.new(@bind_ip, @bind_port, reuse_port: true)
        # If bind_port was 0, get the actual port
        @bind_port = server.local_address.port
        @server = server
        @running = true
        @accept_fiber = spawn { accept_loop }
        @bitrate = BITRATE_GUESS
        @online = true
      rescue ex
        raise ArgumentError.new("Could not bind TCP socket for interface \"#{name}\": #{ex.message}")
      end
    end

    def self.autoconfigure_mtu? : Bool
      AUTOCONFIGURE_MTU
    end

    # Resolve bind address from a network interface name
    private def get_address_for_if(ifname : String, bind_port : Int32, prefer_ipv6 : Bool) : Tuple(String, Int32)
      ifaddr = NetInfo.ifaddresses(ifname)
      if ifaddr.empty?
        raise ArgumentError.new("No addresses available on specified kernel interface \"#{ifname}\" for BackboneInterface to bind to")
      end

      af_inet6 = NetInfo::AF_INET6.to_i32
      af_inet = NetInfo::AF_INET.to_i32

      if (prefer_ipv6 || !ifaddr.has_key?(af_inet)) && ifaddr.has_key?(af_inet6)
        addr = ifaddr[af_inet6].first.addr
        {addr, bind_port}
      elsif ifaddr.has_key?(af_inet)
        addr = ifaddr[af_inet].first.addr
        {addr, bind_port}
      else
        raise ArgumentError.new("No addresses available on specified kernel interface \"#{ifname}\" for BackboneInterface to bind to")
      end
    end

    private def accept_loop
      while @running
        if srv = @server
          begin
            client_socket = srv.accept
            spawn { incoming_connection(client_socket) }
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

    def incoming_connection(client_socket : TCPSocket)
      RNS.log("Accepting incoming backbone connection", RNS::LOG_VERBOSE)
      begin
        client_name = "Client on #{@name}"
        remote_ip = begin
          client_socket.remote_address.address
        rescue
          "unknown"
        end
        remote_port = begin
          client_socket.remote_address.port
        rescue
          0
        end

        spawned = BackboneClientInterface.new(
          connected_socket: client_socket,
          name: client_name,
          inbound_callback: @inbound_callback
        )

        spawned.dir_out = @dir_out
        spawned.dir_in = @dir_in
        spawned.target_ip = remote_ip
        spawned.target_port = remote_port
        spawned.parent_interface = self
        spawned.bitrate = @bitrate
        spawned.optimise_mtu

        spawned.ifac_size = @ifac_size
        spawned.ifac_netname = @ifac_netname
        spawned.ifac_netkey = @ifac_netkey
        spawned.announce_rate_target = @announce_rate_target
        spawned.announce_rate_grace = @announce_rate_grace
        spawned.announce_rate_penalty = @announce_rate_penalty
        spawned.mode = @mode
        spawned.hw_mtu = @hw_mtu
        spawned.online = true

        RNS.log("Spawned new BackboneClient Interface: #{spawned}", RNS::LOG_VERBOSE)

        if si = @spawned_interfaces
          si.reject! { |i| i.object_id == spawned.object_id }
          si << spawned
        end
      rescue ex
        RNS.log("An error occurred while accepting incoming connection on #{self}: #{ex.message}", RNS::LOG_ERROR)
        begin
          client_socket.close unless client_socket.closed?
        rescue ex
          RNS.log("Error closing client socket: #{ex.message}", RNS::LOG_DEBUG)
        end
      end
    end

    def clients : Int32
      (@spawned_interfaces || [] of Interface).size
    end

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
      # Server interface does not transmit directly
    end

    def detach
      @detached = true
      @online = false
      @running = false
      if srv = @server
        begin
          srv.close unless srv.closed?
        rescue ex
          RNS.log("Error while shutting down socket for #{self}: #{ex.message}", RNS::LOG_ERROR)
        end
        @server = nil
      end
    end

    def to_s(io : IO)
      ip_str = @bind_ip.includes?(":") ? "[#{@bind_ip}]" : @bind_ip
      io << "BackboneInterface[" << @name << "/" << ip_str << ":" << @bind_port << "]"
    end
  end

  class BackboneClientInterface < Interface
    BITRATE_GUESS           = 100_000_000_i64
    DEFAULT_IFAC_SIZE       =              16
    AUTOCONFIGURE_MTU       = true
    RECONNECT_WAIT          = 5
    RECONNECT_MAX_TRIES     = nil
    TCP_USER_TIMEOUT        = 24
    TCP_PROBE_AFTER         =  5
    TCP_PROBE_INTERVAL      =  2
    TCP_PROBES              = 12
    INITIAL_CONNECT_TIMEOUT =  5
    SYNCHRONOUS_START       = true

    getter? initiator : Bool = false
    property reconnecting : Bool = false
    property never_connected : Bool = true
    property wants_tunnel : Bool = false
    property i2p_tunneled : Bool = false
    property prefer_ipv6 : Bool = false
    property dir_in : Bool = true
    property dir_out : Bool = false
    property target_ip : String? = nil
    property target_port : Int32? = nil

    @socket : TCPSocket? = nil
    @read_fiber : Fiber? = nil
    @running : Bool = false
    @connect_timeout : Int32 = INITIAL_CONNECT_TIMEOUT
    @max_reconnect_tries : Int32? = nil
    @inbound_callback : Proc(Bytes, Interface, Nil)? = nil
    @write_mutex : Mutex = Mutex.new

    def initialize(configuration : Hash(String, String),
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback
      configure(configuration)
    end

    def initialize(connected_socket : TCPSocket, name : String = "",
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback
      @name = name
      @initiator = false
      @online = true
      @bitrate = BITRATE_GUESS
      @hw_mtu = BackboneInterfaceConstants::HW_MTU
      @supports_discovery = true
      @mode = MODE_FULL
      @socket = connected_socket
      set_socket_options(connected_socket)
      start_read_loop
    end

    def self.autoconfigure_mtu? : Bool
      AUTOCONFIGURE_MTU
    end

    private def configure(c : Hash(String, String))
      name = c["name"]? || ""
      target_ip = c["target_host"]?
      target_port = c["target_port"]?.try(&.to_i)
      i2p_tunneled = c["i2p_tunneled"]?.try { |v| v.downcase == "true" } || false
      connect_timeout = c["connect_timeout"]?.try(&.to_i)
      max_reconnect_tries = c["max_reconnect_tries"]?.try(&.to_i)
      prefer_ipv6 = c["prefer_ipv6"]?.try { |v| v.downcase == "true" } || false

      @hw_mtu = BackboneInterfaceConstants::HW_MTU
      @dir_in = true
      @dir_out = false
      @name = name
      @online = false
      @bitrate = BITRATE_GUESS
      @i2p_tunneled = i2p_tunneled
      @prefer_ipv6 = prefer_ipv6
      @supports_discovery = true
      @mode = MODE_FULL
      @max_reconnect_tries = max_reconnect_tries

      if ct = connect_timeout
        @connect_timeout = ct
      end

      if target_ip && target_port
        @target_ip = target_ip
        @target_port = target_port
        @initiator = true

        if SYNCHRONOUS_START
          initial_connect
        else
          spawn { initial_connect }
        end
      end
    end

    private def initial_connect
      if !connect(initial: true)
        spawn { reconnect }
      else
        start_read_loop
        @wants_tunnel = true
      end
    end

    def connect(initial : Bool = false) : Bool
      tip = @target_ip
      tport = @target_port
      return false unless tip && tport

      begin
        if initial
          RNS.log("Establishing TCP connection for #{self}...", RNS::LOG_DEBUG)
        end
        sock = TCPSocket.new(tip, tport, connect_timeout: @connect_timeout.seconds)
        sock.tcp_nodelay = true
        @socket = sock
        @online = true
        if initial
          RNS.log("TCP connection for #{self} established", RNS::LOG_DEBUG)
        end
      rescue ex
        if initial
          RNS.log("Initial connection for #{self} could not be established: #{ex.message}", RNS::LOG_ERROR)
          RNS.log("Leaving unconnected and retrying connection in #{RECONNECT_WAIT} seconds.", RNS::LOG_ERROR)
          return false
        else
          raise ex
        end
      end

      set_socket_options(@socket.not_nil!)
      @online = true
      @never_connected = false
      true
    end

    private def set_socket_options(sock : TCPSocket)
      sock.tcp_nodelay = true
      sock.keepalive = true
    rescue ex
      RNS.log("Error setting socket options: #{ex.message}", RNS::LOG_DEBUG)
    end

    def reconnect
      unless @initiator
        RNS.log("Attempt to reconnect on a non-initiator backbone interface.", RNS::LOG_ERROR)
        return
      end
      return if @reconnecting
      @reconnecting = true
      attempts = 0

      while !@online && !detached?
        sleep RECONNECT_WAIT.seconds
        attempts += 1
        if max = @max_reconnect_tries
          if attempts > max
            RNS.log("Max reconnection attempts reached for #{self}", RNS::LOG_ERROR)
            teardown
            break
          end
        end
        begin
          connect
        rescue ex
          RNS.log("Connection attempt for #{self} failed: #{ex.message}", RNS::LOG_DEBUG)
        end
      end

      if !@never_connected && @online
        RNS.log("Reconnected socket for #{self}.", RNS::LOG_INFO)
      end
      @reconnecting = false
      if @online
        start_read_loop
      end
    end

    def start_read_loop
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
        framed = HDLC.frame(data)
        @write_mutex.synchronize do
          if sock = @socket
            sock.write(framed)
            sock.flush
          end
        end
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
      buf = Bytes.new(BackboneInterfaceConstants::HW_MTU < 65536 ? BackboneInterfaceConstants::HW_MTU : 65536)

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
            if @initiator && !detached?
              RNS.log("Socket for #{self} closed, reconnecting...", RNS::LOG_WARNING)
              spawn { reconnect }
            else
              RNS.log("Socket for remote client #{self} closed.", RNS::LOG_VERBOSE)
              teardown
            end
            break
          end
        rescue ex
          @online = false
          RNS.log("Interface error for #{self}: #{ex.message}", RNS::LOG_WARNING)
          if @initiator && !detached?
            spawn { reconnect }
          else
            teardown
          end
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
        pos = flag_end
        last_end = pos
      end
      if last_end > 0
        remaining = data[last_end, data.size - last_end]
        frame_buffer.clear
        frame_buffer.write(remaining) if remaining.size > 0
      end
    end

    def teardown
      if @initiator && !detached?
        RNS.log("Interface #{self} torn down.", RNS::LOG_ERROR)
      else
        RNS.log("Interface #{self} torn down.", RNS::LOG_VERBOSE)
      end
      @online = false
      @running = false
      @dir_out = false
      @dir_in = false
      if pi = @parent_interface
        if si = pi.spawned_interfaces
          si.reject! { |i| i.object_id == self.object_id }
        end
      end
      close_socket
    end

    def detach
      @online = false
      @running = false
      @detached = true
      close_socket
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

    def inbound_callback=(cb : Proc(Bytes, Interface, Nil)?)
      @inbound_callback = cb
    end

    def to_s(io : IO)
      tip = @target_ip || ""
      tport = @target_port || 0
      ip_str = tip.includes?(":") ? "[#{tip}]" : tip
      io << "BackboneInterface[" << @name << "/" << ip_str << ":" << tport << "]"
    end
  end
end
