require "socket"

module RNS
  # I2P SAM protocol exception types matching Python i2plib.exceptions
  module I2PExceptions
    class I2PError < Exception; end

    class CantReachPeer < I2PError; end

    class DuplicatedDest < I2PError; end

    class DuplicatedId < I2PError; end

    class InvalidId < I2PError; end

    class InvalidKey < I2PError; end

    class KeyNotFound < I2PError; end

    class PeerNotFound < I2PError; end

    class Timeout < I2PError; end

    def self.from_sam_result(result : String) : I2PError?
      return CantReachPeer.new("Can't reach peer") if result.includes?("CANT_REACH_PEER")
      return DuplicatedDest.new("Duplicated destination") if result.includes?("DUPLICATED_DEST")
      return DuplicatedId.new("Duplicated ID") if result.includes?("DUPLICATED_ID")
      return InvalidId.new("Invalid stream session ID") if result.includes?("INVALID_ID")
      return InvalidKey.new("Invalid key") if result.includes?("INVALID_KEY")
      return KeyNotFound.new("Key not found") if result.includes?("KEY_NOT_FOUND")
      return PeerNotFound.new("Peer not found") if result.includes?("PEER_NOT_FOUND")
      return Timeout.new("Timeout") if result.includes?("TIMEOUT")
      return I2PError.new("Unspecified I2P error") if result.includes?("RESULT=I2P_ERROR")
      nil
    end
  end

  # SAM protocol client for communicating with the I2P router.
  # Implements the SAM v3 bridge protocol used by i2plib.
  class SAMClient
    DEFAULT_SAM_HOST = "127.0.0.1"
    DEFAULT_SAM_PORT = 7656
    SAM_BUFSIZE      = 4096

    property sam_host : String
    property sam_port : Int32

    def initialize(@sam_host = DEFAULT_SAM_HOST, @sam_port = DEFAULT_SAM_PORT)
    end

    # Open a SAM connection and perform the handshake
    def connect : TCPSocket
      sock = TCPSocket.new(@sam_host, @sam_port, connect_timeout: 10.seconds)
      sock.tcp_nodelay = true
      sock.write("HELLO VERSION MIN=3.1 MAX=3.1\n".to_slice)
      sock.flush
      reply = read_reply(sock)
      unless reply.includes?("RESULT=OK")
        sock.close
        raise I2PExceptions::I2PError.new("SAM handshake failed: #{reply}")
      end
      sock
    end

    # Generate a new I2P destination keypair
    def generate_destination : {public_key: String, private_key: String}
      sock = connect
      begin
        sock.write("DEST GENERATE\n".to_slice)
        sock.flush
        reply = read_reply(sock)
        pub = extract_value(reply, "PUB")
        priv = extract_value(reply, "PRIV")
        unless pub && priv
          raise I2PExceptions::I2PError.new("Failed to generate destination: #{reply}")
        end
        {public_key: pub, private_key: priv}
      ensure
        sock.close rescue nil
      end
    end

    # Create a SAM session (STREAM)
    def create_session(session_id : String, destination : String = "TRANSIENT",
                       options : String = "") : TCPSocket
      sock = connect
      cmd = "SESSION CREATE STYLE=STREAM ID=#{session_id} DESTINATION=#{destination}"
      cmd += " #{options}" unless options.empty?
      cmd += "\n"
      sock.write(cmd.to_slice)
      sock.flush
      reply = read_reply(sock)
      unless reply.includes?("RESULT=OK")
        sock.close
        exc = I2PExceptions.from_sam_result(reply)
        raise exc || I2PExceptions::I2PError.new("Session creation failed: #{reply}")
      end
      sock
    end

    # Connect to a remote I2P destination via a stream session
    def stream_connect(session_id : String, destination : String) : TCPSocket
      sock = connect
      sock.write("STREAM CONNECT ID=#{session_id} DESTINATION=#{destination} SILENT=false\n".to_slice)
      sock.flush
      reply = read_reply(sock)
      unless reply.includes?("RESULT=OK")
        sock.close
        exc = I2PExceptions.from_sam_result(reply)
        raise exc || I2PExceptions::I2PError.new("Stream connect failed: #{reply}")
      end
      sock
    end

    # Accept an incoming stream connection
    def stream_accept(session_id : String) : TCPSocket
      sock = connect
      sock.write("STREAM ACCEPT ID=#{session_id} SILENT=false\n".to_slice)
      sock.flush
      reply = read_reply(sock)
      unless reply.includes?("RESULT=OK")
        sock.close
        exc = I2PExceptions.from_sam_result(reply)
        raise exc || I2PExceptions::I2PError.new("Stream accept failed: #{reply}")
      end
      sock
    end

    # Look up an I2P destination to get the full base64 key
    def naming_lookup(name : String) : String?
      sock = connect
      begin
        sock.write("NAMING LOOKUP NAME=#{name}\n".to_slice)
        sock.flush
        reply = read_reply(sock)
        if reply.includes?("RESULT=OK")
          extract_value(reply, "VALUE")
        else
          nil
        end
      ensure
        sock.close rescue nil
      end
    end

    private def read_reply(sock : TCPSocket) : String
      buf = Bytes.new(SAM_BUFSIZE)
      bytes_read = sock.read(buf)
      String.new(buf[0, bytes_read]).strip
    end

    private def extract_value(reply : String, key : String) : String?
      # SAM replies use KEY=VALUE pairs
      reply.split(' ').each do |part|
        if part.starts_with?("#{key}=")
          return part[key.size + 1..]
        end
      end
      nil
    end
  end

  # I2PController manages I2P tunnel creation and lifecycle via SAM protocol.
  # Maps Python's I2PController which uses asyncio + i2plib.
  class I2PController
    property client_tunnels : Hash(String, Bool)
    property server_tunnels : Hash(String, Bool)
    property ready : Bool
    getter storagepath : String
    getter sam : SAMClient

    @session_counter : Int32 = 0
    @session_mutex : Mutex = Mutex.new

    def initialize(rns_storagepath : String,
                   sam_host : String = SAMClient::DEFAULT_SAM_HOST,
                   sam_port : Int32 = SAMClient::DEFAULT_SAM_PORT)
      @client_tunnels = {} of String => Bool
      @server_tunnels = {} of String => Bool
      @ready = false
      @storagepath = File.join(rns_storagepath, "i2p")
      @sam = SAMClient.new(sam_host, sam_port)
      Dir.mkdir_p(@storagepath) unless Dir.exists?(@storagepath)
    end

    def start
      @ready = true
    end

    def stop
      @ready = false
    end

    def get_free_port : Int32
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port
      server.close
      port
    end

    private def next_session_id : String
      @session_mutex.synchronize do
        @session_counter += 1
        "rns_#{@session_counter}_#{Time.utc.to_unix}"
      end
    end

    # Set up a client tunnel: creates a local TCP listener that forwards
    # connections through I2P to the remote destination.
    def client_tunnel(owner : I2PInterfacePeer, i2p_destination : String) : Bool
      @client_tunnels[i2p_destination] = false

      begin
        RNS.log("Bringing up I2P tunnel to #{owner}, this may take a while...", RNS::LOG_INFO)

        session_id = next_session_id
        # Create a SAM stream session for this tunnel
        session_sock = @sam.create_session(session_id)

        # Connect to the remote I2P destination
        stream_sock = @sam.stream_connect(session_id, i2p_destination)

        # Close old socket on owner if present
        if old_sock = owner.socket
          old_sock.close rescue nil
        end

        owner.socket = stream_sock
        @client_tunnels[i2p_destination] = true
        owner.awaiting_i2p_tunnel = false

        RNS.log("#{owner} tunnel setup complete", RNS::LOG_VERBOSE)
        true
      rescue ex : IO::Error | Socket::Error | I2PExceptions::I2PError
        RNS.log("Error setting up I2P client tunnel: #{ex.message}", RNS::LOG_ERROR)
        log_i2p_exception(ex, i2p_destination)
        RNS.log("Resetting I2P tunnel and retrying later", RNS::LOG_ERROR)
        @client_tunnels[i2p_destination] = false
        false
      end
    end

    # Set up a server tunnel: creates an I2P destination and listens for
    # incoming connections, forwarding them to owner's bind address.
    def server_tunnel(owner : I2PInterface) : Bool
      # Wait for Transport identity
      while Transport.identity.nil?
        sleep 1.second
      end

      transport_identity = Transport.identity.not_nil!

      # Old format key path
      i2p_dest_hash_of = Identity.full_hash(Identity.full_hash(owner.name.to_slice))
      i2p_keyfile_of = File.join(@storagepath, RNS.hexrep(i2p_dest_hash_of, delimit: false) + ".i2p")

      # New format key path
      ti_hash = transport_identity.hash || Bytes.new(0)
      i2p_dest_hash_nf = Identity.full_hash(
        Identity.full_hash(owner.name.to_slice) + Identity.full_hash(ti_hash)
      )
      i2p_keyfile_nf = File.join(@storagepath, RNS.hexrep(i2p_dest_hash_nf, delimit: false) + ".i2p")

      # Use old format if key already exists
      i2p_keyfile = File.exists?(i2p_keyfile_of) ? i2p_keyfile_of : i2p_keyfile_nf

      begin
        private_key : String
        if File.exists?(i2p_keyfile)
          private_key = File.read(i2p_keyfile).strip
        else
          dest = @sam.generate_destination
          private_key = dest[:private_key]
          File.write(i2p_keyfile, private_key)
        end

        # Create a SAM stream session with the stored key
        session_id = next_session_id
        RNS.log("#{owner} Bringing up I2P endpoint, this may take a while...", RNS::LOG_INFO)
        session_sock = @sam.create_session(session_id, destination: private_key)

        # Get the base32 address via naming lookup
        b32 = @sam.naming_lookup("ME")
        if b32_addr = b32
          # Compute base32 from the public key
          owner.b32 = compute_b32(b32_addr)
        end

        @server_tunnels[owner.b32 || "unknown"] = true
        owner.online = true
        RNS.log("#{owner} endpoint setup complete. Now reachable via I2P.", RNS::LOG_VERBOSE)

        # Accept loop: listen for incoming stream connections
        spawn do
          while owner.online && @ready
            begin
              accepted_sock = @sam.stream_accept(session_id)
              owner.incoming_connection(accepted_sock)
            rescue ex
              RNS.log("Error accepting I2P connection for #{owner}: #{ex.message}", RNS::LOG_ERROR)
              sleep 1.second
            end
          end
        end

        true
      rescue ex : IO::Error | Socket::Error | I2PExceptions::I2PError
        RNS.log("Error setting up I2P server tunnel: #{ex.message}", RNS::LOG_ERROR)
        log_i2p_exception(ex)
        RNS.log("Resetting I2P tunnel and retrying later", RNS::LOG_ERROR)
        false
      end
    end

    private def compute_b32(full_dest : String) : String
      # In the real I2P SAM protocol, the base32 address is the SHA-256 hash
      # of the destination, encoded in base32. For our purposes, we compute it.
      hash = OpenSSL::Digest.new("SHA256")
      hash.update(full_dest)
      digest = hash.final
      Base32.encode(digest).downcase.rstrip('=')
    rescue
      # Fallback: use truncated hex of full_hash
      RNS.hexrep(Identity.full_hash(full_dest.to_slice)[0, 16], delimit: false).downcase
    end

    private def log_i2p_exception(ex : Exception, dest : String? = nil)
      case ex
      when I2PExceptions::CantReachPeer
        RNS.log("The I2P daemon can't reach peer #{dest}", RNS::LOG_ERROR)
      when I2PExceptions::DuplicatedDest
        RNS.log("The I2P daemon reported that the destination is already in use", RNS::LOG_ERROR)
      when I2PExceptions::DuplicatedId
        RNS.log("The I2P daemon reported that the ID is already in use", RNS::LOG_ERROR)
      when I2PExceptions::InvalidId
        RNS.log("The I2P daemon reported that the stream session ID doesn't exist", RNS::LOG_ERROR)
      when I2PExceptions::InvalidKey
        RNS.log("The I2P daemon reported that the key for #{dest} is invalid", RNS::LOG_ERROR)
      when I2PExceptions::KeyNotFound
        RNS.log("The I2P daemon could not find the key for #{dest}", RNS::LOG_ERROR)
      when I2PExceptions::PeerNotFound
        RNS.log("The I2P daemon could not find the peer #{dest}", RNS::LOG_ERROR)
      when I2PExceptions::Timeout
        RNS.log("I2P daemon timed out while setting up tunnel to #{dest}", RNS::LOG_ERROR)
      when I2PExceptions::I2PError
        RNS.log("The I2P daemon experienced an unspecified error", RNS::LOG_ERROR)
      end
    end

    def to_s(io : IO)
      io << "I2PController"
    end
  end

  # Base32 encoder (RFC 4648) — minimal implementation for I2P address computation
  module Base32
    ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

    def self.encode(data : Bytes) : String
      return "" if data.empty?
      result = IO::Memory.new
      buffer = 0_u64
      bits_left = 0

      data.each do |byte|
        buffer = (buffer << 8) | byte
        bits_left += 8
        while bits_left >= 5
          bits_left -= 5
          result << ALPHABET[((buffer >> bits_left) & 0x1f).to_i]
        end
      end

      if bits_left > 0
        buffer <<= (5 - bits_left)
        result << ALPHABET[(buffer & 0x1f).to_i]
      end

      result.to_s
    end
  end

  class I2PInterfacePeer < Interface
    RECONNECT_WAIT      = 15
    RECONNECT_MAX_TRIES = nil

    # I2P TCP socket timeouts (matching Python I2PInterfacePeer constants)
    I2P_USER_TIMEOUT   = 45
    I2P_PROBE_AFTER    = 10
    I2P_PROBE_INTERVAL =  9
    I2P_PROBES         =  5
    I2P_READ_TIMEOUT   = (I2P_PROBE_INTERVAL * I2P_PROBES + I2P_PROBE_AFTER) * 2

    TUNNEL_STATE_INIT   = 0x00_u8
    TUNNEL_STATE_ACTIVE = 0x01_u8
    TUNNEL_STATE_STALE  = 0x02_u8

    property socket : TCPSocket? = nil
    property initiator : Bool = false
    property reconnecting : Bool = false
    property never_connected : Bool = true
    property writing : Bool = false
    property kiss_framing : Bool = false
    property i2p_tunneled : Bool = true
    property i2p_dest : String? = nil
    property i2p_tunnel_ready : Bool = false
    property i2p_tunnel_state : UInt8 = TUNNEL_STATE_INIT
    property awaiting_i2p_tunnel : Bool = false
    property wants_tunnel : Bool = false
    property last_read : Float64 = 0.0
    property last_write : Float64 = 0.0
    property wd_reset : Bool = false
    property dir_in : Bool = true
    property dir_out : Bool = false
    property parent_count : Bool = true
    property max_reconnect_tries : Int32? = nil

    @target_ip : String? = nil
    @target_port : Int32? = nil
    @bind_ip : String = "127.0.0.1"
    @bind_port : Int32 = 0
    @running : Bool = false
    @read_fiber : Fiber? = nil
    @wd_fiber : Fiber? = nil
    @inbound_callback : Proc(Bytes, Interface, Nil)? = nil
    @write_mutex : Mutex = Mutex.new

    # Constructor for server-spawned peer (connected_socket provided)
    def initialize(parent_interface : Interface, owner_callback : Proc(Bytes, Interface, Nil)?,
                   name : String, connected_socket : TCPSocket,
                   max_reconnect_tries : Int32? = nil)
      super()
      @hw_mtu = 1064
      @dir_in = true
      @dir_out = false
      @parent_interface = parent_interface
      @parent_count = true
      @name = name
      @initiator = false
      @reconnecting = false
      @never_connected = true
      @writing = false
      @online = false
      @kiss_framing = false
      @i2p_tunneled = true
      @mode = MODE_FULL
      @bitrate = I2PInterface::BITRATE_GUESS
      @last_read = 0.0
      @last_write = 0.0
      @wd_reset = false
      @i2p_tunnel_state = TUNNEL_STATE_INIT
      @inbound_callback = owner_callback
      @max_reconnect_tries = max_reconnect_tries

      inherit_ifac_from(parent_interface)

      @announce_rate_target = nil
      @announce_rate_grace = nil
      @announce_rate_penalty = nil

      @socket = connected_socket
      set_socket_options(connected_socket)
    end

    # Constructor for initiator peer (target_i2p_dest provided)
    def initialize(parent_interface : I2PInterface, owner_callback : Proc(Bytes, Interface, Nil)?,
                   name : String, target_i2p_dest : String,
                   max_reconnect_tries : Int32? = nil)
      super()
      @hw_mtu = 1064
      @dir_in = true
      @dir_out = false
      @parent_interface = parent_interface
      @parent_count = true
      @name = name
      @initiator = true
      @reconnecting = false
      @never_connected = true
      @writing = false
      @online = false
      @kiss_framing = false
      @i2p_tunneled = true
      @i2p_dest = target_i2p_dest
      @mode = MODE_FULL
      @bitrate = I2PInterface::BITRATE_GUESS
      @last_read = 0.0
      @last_write = 0.0
      @wd_reset = false
      @i2p_tunnel_state = TUNNEL_STATE_INIT
      @inbound_callback = owner_callback
      @max_reconnect_tries = max_reconnect_tries

      inherit_ifac_from(parent_interface)

      @announce_rate_target = nil
      @announce_rate_grace = nil
      @announce_rate_penalty = nil

      @awaiting_i2p_tunnel = true
      @bind_ip = "127.0.0.1"

      # Start tunnel setup fiber
      spawn { tunnel_job(parent_interface, target_i2p_dest) }

      # Start wait + connect fiber
      spawn { wait_job }
    end

    # Minimal constructor for testing without actual I2P connections
    def initialize(name : String, initiator : Bool = false,
                   kiss_framing : Bool = false,
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @hw_mtu = 1064
      @name = name
      @initiator = initiator
      @kiss_framing = kiss_framing
      @i2p_tunneled = true
      @mode = MODE_FULL
      @bitrate = I2PInterface::BITRATE_GUESS
      @inbound_callback = inbound_callback
    end

    private def inherit_ifac_from(parent : Interface)
      @ifac_size = parent.ifac_size
      @ifac_netname = parent.ifac_netname
      @ifac_netkey = parent.ifac_netkey
      if @ifac_netname || @ifac_netkey
        ifac_origin = Bytes.empty
        if nn = @ifac_netname
          ifac_origin = ifac_origin + Identity.full_hash(nn.encode("UTF-8"))
        end
        if nk = @ifac_netkey
          ifac_origin = ifac_origin + Identity.full_hash(nk.encode("UTF-8"))
        end
        ifac_origin_hash = Identity.full_hash(ifac_origin)
        @ifac_key = Cryptography.hkdf(
          length: 64,
          derive_from: ifac_origin_hash,
          salt: Reticulum::IFAC_SALT,
          context: nil
        )
        if key = @ifac_key
          @ifac_identity = Identity.from_bytes(key)
          if ident = @ifac_identity
            @ifac_signature = ident.sign(Identity.full_hash(key))
          end
        end
      end
    end

    private def tunnel_job(parent_interface : I2PInterface, target_i2p_dest : String)
      while @awaiting_i2p_tunnel
        begin
          @bind_port = parent_interface.i2p.get_free_port
          @target_ip = @bind_ip
          @target_port = @bind_port

          unless parent_interface.i2p.client_tunnel(self, target_i2p_dest)
            RNS.log("#{self} I2P control process experienced an error, requesting new tunnel...", RNS::LOG_ERROR)
            @awaiting_i2p_tunnel = true
          end
        rescue ex
          RNS.log("Error while configuring #{self}: #{ex.message}", RNS::LOG_ERROR)
          RNS.log("Check that I2P is installed and running, and that SAM is enabled. Retrying tunnel setup later.", RNS::LOG_ERROR)
        end
        sleep 8.seconds
      end
    end

    private def wait_job
      while @awaiting_i2p_tunnel
        sleep 250.milliseconds
      end
      sleep 2.seconds

      @wants_tunnel = true unless @kiss_framing

      if !connect(initial: true)
        spawn { reconnect }
      else
        start_read_loop
      end
    end

    private def set_socket_options(sock : TCPSocket)
      sock.tcp_nodelay = true
      sock.keepalive = true
    rescue ex
      RNS.log("Error setting socket options: #{ex.message}", RNS::LOG_DEBUG)
    end

    def connect(initial : Bool = false) : Bool
      tip = @target_ip
      tport = @target_port

      # If we have a direct I2P socket (from SAM), use it directly
      if sock = @socket
        unless sock.closed?
          @online = true
          @writing = false
          @never_connected = false
          return true
        end
      end

      return false unless tip && tport

      begin
        sock = TCPSocket.new(tip, tport, connect_timeout: 10.seconds)
        @socket = sock
        @online = true
      rescue ex
        if initial
          unless @awaiting_i2p_tunnel
            RNS.log("Initial connection for #{self} could not be established: #{ex.message}", RNS::LOG_ERROR)
            RNS.log("Leaving unconnected and retrying connection in #{RECONNECT_WAIT} seconds.", RNS::LOG_ERROR)
          end
          return false
        else
          raise ex
        end
      end

      set_socket_options(sock.not_nil!)
      @online = true
      @writing = false
      @never_connected = false

      if !@kiss_framing && @wants_tunnel
        # Would call Transport.synthesize_tunnel(self) here
      end

      true
    end

    def reconnect
      if @initiator
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
            if !@awaiting_i2p_tunnel
              RNS.log("Connection attempt for #{self} failed: #{ex.message}", RNS::LOG_DEBUG)
            else
              RNS.log("#{self} still waiting for I2P tunnel to appear", RNS::LOG_VERBOSE)
            end
          end
        end

        if !@never_connected && @online
          RNS.log("#{self} Re-established connection via I2P tunnel", RNS::LOG_INFO)
        end

        @reconnecting = false
        if @online
          start_read_loop
          if !@kiss_framing
            # Would call Transport.synthesize_tunnel(self) here
          end
        end
      else
        RNS.log("Attempt to reconnect on a non-initiator I2P interface. This should not happen.", RNS::LOG_ERROR)
      end
    end

    def start_read_loop
      @running = true
      @read_fiber = spawn { read_loop }
    end

    def process_incoming(data : Bytes)
      @rxb += data.size.to_i64
      if pi = @parent_interface
        pi.rxb += data.size.to_i64 if @parent_count
      end
      if cb = @inbound_callback
        cb.call(data, self)
      end
    end

    def process_outgoing(data : Bytes)
      return unless @online
      @write_mutex.synchronize do
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
          @last_write = Time.utc.to_unix_f

          if pi = @parent_interface
            pi.txb += framed.size.to_i64 if @parent_count
          end
        rescue ex
          RNS.log("Exception while transmitting via #{self}, tearing down", RNS::LOG_ERROR)
          RNS.log("The contained exception was: #{ex.message}", RNS::LOG_ERROR)
          teardown
        end
      end
    end

    def read_watchdog
      while @wd_reset
        sleep 250.milliseconds
      end

      should_run = true
      begin
        while should_run && !@wd_reset
          sleep 1.second

          if (Time.utc.to_unix_f - @last_read > I2P_PROBE_AFTER * 2)
            if @i2p_tunnel_state != TUNNEL_STATE_STALE
              RNS.log("I2P tunnel became unresponsive", RNS::LOG_DEBUG)
            end
            @i2p_tunnel_state = TUNNEL_STATE_STALE
          else
            @i2p_tunnel_state = TUNNEL_STATE_ACTIVE
          end

          if (Time.utc.to_unix_f - @last_write > I2P_PROBE_AFTER * 1)
            begin
              if sock = @socket
                sock.write(Bytes[HDLC::FLAG, HDLC::FLAG])
                sock.flush
              end
            rescue ex
              RNS.log("Error sending I2P keepalive: #{ex.message}", RNS::LOG_ERROR)
              shutdown_socket
              should_run = false
            end
          end

          if (Time.utc.to_unix_f - @last_read > I2P_READ_TIMEOUT)
            RNS.log("I2P socket is unresponsive, restarting...", RNS::LOG_WARNING)
            shutdown_socket
            should_run = false
          end

          @wd_reset = false
        end
      ensure
        @wd_reset = false
      end
    end

    private def read_loop
      @last_read = Time.utc.to_unix_f
      @last_write = Time.utc.to_unix_f

      @wd_fiber = spawn { read_watchdog }

      in_frame = false
      escape = false
      command = KISS::CMD_UNKNOWN
      data_buffer = IO::Memory.new(4096)
      buf = Bytes.new(4096)

      while @running
        sock = @socket
        break unless sock

        begin
          bytes_read = sock.read(buf)
          if bytes_read > 0
            data_in = buf[0, bytes_read]
            @last_read = Time.utc.to_unix_f

            i = 0
            while i < data_in.size
              b = data_in[i]
              i += 1

              if @kiss_framing
                # KISS framing read loop
                if in_frame && b == KISS::FEND && command == KISS::CMD_DATA
                  in_frame = false
                  if data_buffer.pos > 0
                    process_incoming(data_buffer.to_slice.dup)
                  end
                elsif b == KISS::FEND
                  in_frame = true
                  command = KISS::CMD_UNKNOWN
                  data_buffer = IO::Memory.new(4096)
                elsif in_frame && data_buffer.pos < hw_mtu_val
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
              else
                # HDLC framing read loop
                if in_frame && b == HDLC::FLAG
                  in_frame = false
                  if data_buffer.pos > 0
                    process_incoming(data_buffer.to_slice.dup)
                  end
                elsif b == HDLC::FLAG
                  in_frame = true
                  data_buffer = IO::Memory.new(4096)
                elsif in_frame && data_buffer.pos < hw_mtu_val
                  if b == HDLC::ESC
                    escape = true
                  else
                    if escape
                      if b == (HDLC::FLAG ^ HDLC::ESC_MASK)
                        data_buffer.write_byte(HDLC::FLAG)
                      elsif b == (HDLC::ESC ^ HDLC::ESC_MASK)
                        data_buffer.write_byte(HDLC::ESC)
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
            # Socket closed
            @online = false
            @wd_reset = true
            sleep 2.seconds
            @wd_reset = false

            if @initiator && !detached?
              RNS.log("Socket for #{self} was closed, attempting to reconnect...", RNS::LOG_WARNING)
              spawn { reconnect }
            else
              RNS.log("Socket for remote client #{self} was closed.", RNS::LOG_VERBOSE)
              teardown
            end
            break
          end
        rescue ex
          @online = false
          RNS.log("Interface error for #{self}: #{ex.message}", RNS::LOG_WARNING)

          if @initiator && !detached?
            RNS.log("Attempting to reconnect...", RNS::LOG_WARNING)
            spawn { reconnect }
          else
            teardown
          end
          break
        end
      end
    end

    private def hw_mtu_val : Int32
      @hw_mtu || 1064
    end

    def shutdown_socket
      if sock = @socket
        begin
          sock.close unless sock.closed?
        rescue ex
          RNS.log("Error closing socket: #{ex.message}", RNS::LOG_DEBUG)
        end
        @socket = nil
      end
    end

    def teardown
      if @initiator && !detached?
        RNS.log("Interface #{self} experienced an unrecoverable error and is torn down.", RNS::LOG_ERROR)
        if Reticulum.panic_on_interface_error
          RNS.panic
        end
      else
        RNS.log("Interface #{self} is being torn down.", RNS::LOG_VERBOSE)
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

      shutdown_socket
    end

    def detach
      RNS.log("Detaching #{self}", RNS::LOG_DEBUG)
      @detached = true
      shutdown_socket
    end

    def to_s(io : IO)
      io << "I2PInterfacePeer[" << @name << "]"
    end
  end

  class I2PInterface < Interface
    BITRATE_GUESS     = 256_000_i64
    DEFAULT_IFAC_SIZE =          16

    getter i2p : I2PController
    property b32 : String? = nil
    property connectable : Bool = false
    property dir_in : Bool = true
    property dir_out : Bool = false
    property bind_ip : String = "127.0.0.1"
    property bind_port : Int32 = 0

    @server : TCPServer? = nil
    @accept_fiber : Fiber? = nil
    @running : Bool = false
    @inbound_callback : Proc(Bytes, Interface, Nil)? = nil

    def clients : Int32
      (@spawned_interfaces || [] of Interface).size
    end

    # Full constructor matching Python I2PInterface.__init__
    def initialize(configuration : Hash(String, String),
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback

      name = configuration["name"]? || ""
      rns_storagepath = configuration["storagepath"]? || Reticulum.storagepath
      peers_str = configuration["peers"]?
      connectable = configuration["connectable"]?.try { |v| v.downcase == "true" } || false
      ifac_size = configuration["ifac_size"]?.try(&.to_i)
      ifac_netname = configuration["ifac_netname"]?
      ifac_netkey = configuration["ifac_netkey"]?
      sam_host = configuration["sam_host"]? || SAMClient::DEFAULT_SAM_HOST
      sam_port = configuration["sam_port"]?.try(&.to_i) || SAMClient::DEFAULT_SAM_PORT

      @hw_mtu = 1064
      @online = false
      @spawned_interfaces = [] of Interface
      @connectable = connectable
      @i2p_tunneled = true
      @mode = MODE_FULL
      @name = name
      @dir_in = true
      @dir_out = false
      @bitrate = BITRATE_GUESS
      @ifac_size = ifac_size || DEFAULT_IFAC_SIZE
      @ifac_netname = ifac_netname
      @ifac_netkey = ifac_netkey
      @supports_discovery = true

      @i2p = I2PController.new(rns_storagepath, sam_host, sam_port)

      # Start I2P controller
      spawn { @i2p.start }
      sleep 250.milliseconds

      unless @i2p.ready
        RNS.log("I2P controller did not become available in time, waiting...", RNS::LOG_VERBOSE)
        while !@i2p.ready
          sleep 250.milliseconds
        end
        RNS.log("I2P controller ready, continuing setup", RNS::LOG_VERBOSE)
      end

      # Start TCP server for incoming connections
      @bind_port = @i2p.get_free_port
      begin
        server = TCPServer.new(@bind_ip, @bind_port, reuse_port: true)
        @server = server
        @running = true
        @accept_fiber = spawn { accept_loop(server) }
        @online = true
      rescue ex
        RNS.log("Could not start I2P TCP server: #{ex.message}", RNS::LOG_ERROR)
      end

      # Set up server tunnel if connectable
      if @connectable
        spawn { server_tunnel_job }
      end

      # Connect to configured peers
      if peers_str
        peers = peers_str.split(",").map(&.strip)
        peers.each do |peer_addr|
          next if peer_addr.empty?
          interface_name = "#{@name} to #{peer_addr}"
          peer_interface = I2PInterfacePeer.new(self, @inbound_callback, interface_name, peer_addr)
          peer_interface.dir_out = true
          peer_interface.dir_in = true
          peer_interface.parent_count = false
        end
      end
    end

    # Minimal constructor for testing
    def initialize(name : String, storagepath : String? = nil,
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @name = name
      @hw_mtu = 1064
      @online = false
      @spawned_interfaces = [] of Interface
      @i2p_tunneled = true
      @mode = MODE_FULL
      @dir_in = true
      @dir_out = false
      @bitrate = BITRATE_GUESS
      @supports_discovery = true
      @inbound_callback = inbound_callback
      sp = storagepath || Reticulum.storagepath
      @i2p = I2PController.new(sp)
    end

    private def accept_loop(server : TCPServer)
      while @running
        begin
          client = server.accept
          spawn { incoming_connection(client) }
        rescue ex
          break unless @running
          RNS.log("Error accepting connection on #{self}: #{ex.message}", RNS::LOG_ERROR)
        end
      end
    end

    def incoming_connection(socket : TCPSocket)
      RNS.log("Accepting incoming I2P connection", RNS::LOG_VERBOSE)
      interface_name = "Connected peer on #{@name}"
      spawned = I2PInterfacePeer.new(self, @inbound_callback, interface_name, socket)
      spawned.dir_out = true
      spawned.dir_in = true
      spawned.parent_interface = self
      spawned.online = true
      spawned.bitrate = @bitrate

      spawned.ifac_size = @ifac_size
      spawned.ifac_netname = @ifac_netname
      spawned.ifac_netkey = @ifac_netkey
      spawned.announce_rate_target = @announce_rate_target
      spawned.announce_rate_grace = @announce_rate_grace
      spawned.announce_rate_penalty = @announce_rate_penalty
      spawned.mode = @mode
      spawned.hw_mtu = @hw_mtu

      RNS.log("Spawned new I2PInterface Peer: #{spawned}", RNS::LOG_VERBOSE)

      if si = @spawned_interfaces
        si.reject! { |i| i.object_id == spawned.object_id }
        si << spawned
      end

      spawned.start_read_loop
    end

    private def server_tunnel_job
      while true
        begin
          unless @i2p.server_tunnel(self)
            RNS.log("#{self} I2P control process experienced an error, requesting new tunnel...", RNS::LOG_ERROR)
            @online = false
          end
        rescue ex
          RNS.log("Error while configuring #{self}: #{ex.message}", RNS::LOG_ERROR)
          RNS.log("Check that I2P is installed and running, and that SAM is enabled. Retrying tunnel setup later.", RNS::LOG_ERROR)
        end
        sleep 15.seconds
      end
    end

    def process_outgoing(data : Bytes)
      # No-op — data is sent through spawned peer interfaces
    end

    def received_announce(from_spawned : Bool = false)
      if from_spawned
        @ia_freq_deque.push(Time.utc.to_unix_f)
        while @ia_freq_deque.size > IA_FREQ_SAMPLES
          @ia_freq_deque.shift
        end
      end
    end

    def sent_announce(from_spawned : Bool = false)
      if from_spawned
        @oa_freq_deque.push(Time.utc.to_unix_f)
        while @oa_freq_deque.size > OA_FREQ_SAMPLES
          @oa_freq_deque.shift
        end
      end
    end

    def detach
      RNS.log("Detaching #{self}", RNS::LOG_DEBUG)
      @running = false
      @i2p.stop
      if server = @server
        server.close rescue nil
        @server = nil
      end
      @online = false
    end

    def to_s(io : IO)
      io << "I2PInterface[" << @name << "]"
    end
  end
end
