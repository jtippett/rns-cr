require "socket"

module RNS
  module TCPInterfaceConstants
    HW_MTU = 262144
  end

  class TCPClientInterface < Interface
    BITRATE_GUESS           = 10_000_000_i64
    DEFAULT_IFAC_SIZE       =             16
    AUTOCONFIGURE_MTU       = true
    RECONNECT_WAIT          = 5
    RECONNECT_MAX_TRIES     = nil
    TCP_USER_TIMEOUT        = 24
    TCP_PROBE_AFTER         =  5
    TCP_PROBE_INTERVAL      =  2
    TCP_PROBES              = 12
    INITIAL_CONNECT_TIMEOUT =  5
    SYNCHRONOUS_START       = true
    I2P_USER_TIMEOUT        = 45
    I2P_PROBE_AFTER         = 10
    I2P_PROBE_INTERVAL      =  9
    I2P_PROBES              =  5

    getter? receives : Bool = false
    getter? initiator : Bool = false
    property reconnecting : Bool = false
    property never_connected : Bool = true
    property writing : Bool = false
    property kiss_framing : Bool = false
    property i2p_tunneled : Bool = false
    property wants_tunnel : Bool = false
    getter target_ip : String? = nil
    getter target_port : Int32? = nil
    property dir_in : Bool = true
    property dir_out : Bool = false

    @socket : TCPSocket? = nil
    @read_fiber : Fiber? = nil
    @running : Bool = false
    @connect_timeout : Int32 = INITIAL_CONNECT_TIMEOUT
    @max_reconnect_tries : Int32? = nil
    @inbound_callback : Proc(Bytes, Interface, Nil)? = nil
    @hdlc_remainder : Bytes? = nil

    def initialize(configuration : Hash(String, String),
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback
      configure(configuration)
    end

    def initialize(connected_socket : TCPSocket, name : String = "",
                   kiss_framing : Bool = false, i2p_tunneled : Bool = false,
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback
      @name = name
      @kiss_framing = kiss_framing
      @i2p_tunneled = i2p_tunneled
      @receives = true
      @initiator = false
      @socket = connected_socket
      @online = true
      @bitrate = BITRATE_GUESS
      @hw_mtu = TCPInterfaceConstants::HW_MTU
      @supports_discovery = true
      @mode = MODE_FULL
      set_socket_options(connected_socket)
      start_read_loop
    end

    private def configure(c : Hash(String, String))
      name = c["name"]? || ""
      target_ip = c["target_host"]?
      target_port = c["target_port"]?.try(&.to_i)
      kiss_framing = c["kiss_framing"]?.try { |v| v.downcase == "true" } || false
      i2p_tunneled = c["i2p_tunneled"]?.try { |v| v.downcase == "true" } || false
      connect_timeout = c["connect_timeout"]?.try(&.to_i)
      max_reconnect_tries = c["max_reconnect_tries"]?.try(&.to_i)
      fixed_mtu = c["fixed_mtu"]?.try(&.to_i)

      @hw_mtu = fixed_mtu ? fixed_mtu : TCPInterfaceConstants::HW_MTU
      @dir_in = true
      @dir_out = false
      @name = name
      @online = false
      @bitrate = BITRATE_GUESS
      @kiss_framing = kiss_framing
      @i2p_tunneled = i2p_tunneled
      @supports_discovery = true
      @mode = MODE_FULL
      @max_reconnect_tries = max_reconnect_tries

      if ct = connect_timeout
        @connect_timeout = ct
      end

      if target_ip && target_port
        @receives = true
        @target_ip = target_ip
        @target_port = target_port
        @initiator = true
        initial_connect
      end
    end

    private def initial_connect
      if !connect(initial: true)
        spawn { reconnect }
      else
        start_read_loop
        @wants_tunnel = true unless @kiss_framing
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
      @writing = false
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
        RNS.log("Attempt to reconnect on a non-initiator TCP interface.", RNS::LOG_ERROR)
        return
      end
      return if @reconnecting
      @reconnecting = true
      attempts = 0

      while !@online
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
      return unless @online && !detached?
      @rxb += data.size.to_i64
      if pi = @parent_interface
        pi.rxb += data.size.to_i64
      end
      if cb = @inbound_callback
        cb.call(data, self)
      end
    end

    def process_outgoing(data : Bytes)
      return unless @online && !detached?
      begin
        @writing = true
        framed = if @kiss_framing
                   KISS.frame(data)
                 else
                   HDLC.frame(data)
                 end
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
        teardown
      end
    end

    private def read_loop
      in_frame = false
      escape = false
      command = KISS::CMD_UNKNOWN
      frame_buffer = IO::Memory.new(4096)
      data_buffer = IO::Memory.new(4096)
      buf = Bytes.new(4096)

      while @running
        sock = @socket
        break unless sock
        begin
          bytes_read = sock.read(buf)
          if bytes_read > 0
            data_in = buf[0, bytes_read]
            if @kiss_framing
              i = 0
              while i < data_in.size
                b = data_in[i]
                i += 1
                if in_frame && b == KISS::FEND && command == KISS::CMD_DATA
                  in_frame = false
                  if data_buffer.pos > 0
                    process_incoming(data_buffer.to_slice.dup)
                  end
                elsif b == KISS::FEND
                  in_frame = true
                  command = KISS::CMD_UNKNOWN
                  data_buffer = IO::Memory.new(4096)
                elsif in_frame && data_buffer.pos < hw_mtu_value
                  if data_buffer.pos == 0 && command == KISS::CMD_UNKNOWN
                    command = b & 0x0F_u8
                  elsif command == KISS::CMD_DATA
                    if b == KISS::FESC
                      escape = true
                    else
                      if escape
                        if b == KISS::TFEND
                          data_buffer.write_byte(KISS::FEND)
                        elsif b == KISS::TFESC
                          data_buffer.write_byte(KISS::FESC)
                        else
                          data_buffer.write_byte(b)
                        end
                        escape = false
                      else
                        data_buffer.write_byte(b)
                      end
                    end
                  end
                end
              end
            else
              frame_buffer.write(data_in)
              process_hdlc_buffer(frame_buffer)
            end
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
        # Find FLAG
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

        # Find next FLAG
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
      # Keep unprocessed data
      if last_end > 0
        remaining = data[last_end, data.size - last_end]
        frame_buffer.clear
        frame_buffer.write(remaining) if remaining.size > 0
      end
    end

    private def hw_mtu_value : Int32
      @hw_mtu || TCPInterfaceConstants::HW_MTU
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

    def target_ip=(ip : String?)
      @target_ip = ip
    end

    def target_port=(port : Int32?)
      @target_port = port
    end

    def inbound_callback=(cb : Proc(Bytes, Interface, Nil)?)
      @inbound_callback = cb
    end

    def to_s(io : IO)
      tip = @target_ip || ""
      tport = @target_port || 0
      ip_str = tip.includes?(":") ? "[#{tip}]" : tip
      io << "TCPInterface[" << @name << "/" << ip_str << ":" << tport << "]"
    end
  end

  class TCPServerInterface < Interface
    BITRATE_GUESS     = 10_000_000_i64
    DEFAULT_IFAC_SIZE =             16
    AUTOCONFIGURE_MTU = true

    getter bind_ip : String = ""
    getter bind_port : Int32 = 0
    property i2p_tunneled : Bool = false
    property prefer_ipv6 : Bool = false
    property dir_in : Bool = true
    property dir_out : Bool = false

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
      port = c["port"]?.try(&.to_i)
      bindip = c["listen_ip"]?
      bindport = c["listen_port"]?.try(&.to_i)
      i2p_tunneled = c["i2p_tunneled"]?.try { |v| v.downcase == "true" } || false
      prefer_ipv6 = c["prefer_ipv6"]?.try { |v| v.downcase == "true" } || false

      bindport = port if port

      @name = name
      @online = false
      @spawned_interfaces = [] of Interface
      @dir_in = true
      @dir_out = false
      @i2p_tunneled = i2p_tunneled
      @prefer_ipv6 = prefer_ipv6
      @mode = MODE_FULL
      @hw_mtu = TCPInterfaceConstants::HW_MTU
      @bitrate = BITRATE_GUESS
      @supports_discovery = true

      unless bindport
        raise ArgumentError.new("No TCP port configured for interface \"#{name}\"")
      end
      @bind_port = bindport

      unless bindip
        raise ArgumentError.new("No TCP bind IP configured for interface \"#{name}\"")
      end
      @bind_ip = bindip

      begin
        server = TCPServer.new(@bind_ip, @bind_port, reuse_port: true)
        @server = server
        @running = true
        @accept_fiber = spawn { accept_loop }
        @online = true
      rescue ex
        raise ArgumentError.new("Could not bind TCP socket for interface \"#{name}\": #{ex.message}")
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
      RNS.log("Accepting incoming TCP connection", RNS::LOG_VERBOSE)
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

      spawned = TCPClientInterface.new(
        connected_socket: client_socket,
        name: client_name,
        kiss_framing: false,
        i2p_tunneled: @i2p_tunneled,
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

      RNS.log("Spawned new TCPClient Interface: #{spawned}", RNS::LOG_VERBOSE)

      if si = @spawned_interfaces
        si.reject! { |i| i.object_id == spawned.object_id }
        si << spawned
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
    end

    def detach
      @detached = true
      @online = false
      @running = false
      if srv = @server
        begin
          RNS.log("Detaching #{self}", RNS::LOG_DEBUG)
          srv.close unless srv.closed?
        rescue ex
          RNS.log("Error shutting down server for #{self}: #{ex.message}", RNS::LOG_ERROR)
        end
        @server = nil
      end
    end

    def to_s(io : IO)
      ip_str = @bind_ip.includes?(":") ? "[#{@bind_ip}]" : @bind_ip
      io << "TCPServerInterface[" << @name << "/" << ip_str << ":" << @bind_port << "]"
    end
  end
end
