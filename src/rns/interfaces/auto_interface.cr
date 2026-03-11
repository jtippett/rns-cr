require "socket"
require "./netinfo"

module RNS
  # AutoInterface implements zero-configuration peer discovery and data transfer
  # using IPv6 multicast. Ports RNS/Interfaces/AutoInterface.py (663 LOC).
  #
  # Discovery works by:
  # 1. Each interface periodically sends a peering hash (group_id + link-local addr)
  #    to a multicast group on the discovery port
  # 2. When a peer's peering hash is received and validated, an AutoInterfacePeer
  #    is spawned for unicast data transfer on the data port
  # 3. Peers are tracked with timeouts and removed when they go silent
  # 4. Reverse peering packets are sent unicast to keep peers alive
  class AutoInterface < Interface
    HW_MTU    = 1196
    FIXED_MTU = true

    DEFAULT_DISCOVERY_PORT = 29716
    DEFAULT_DATA_PORT      = 42671
    DEFAULT_GROUP_ID       = "reticulum".encode("UTF-8")
    DEFAULT_IFAC_SIZE      = 16

    SCOPE_LINK         = "2"
    SCOPE_ADMIN        = "4"
    SCOPE_SITE         = "5"
    SCOPE_ORGANISATION = "8"
    SCOPE_GLOBAL       = "e"

    MULTICAST_PERMANENT_ADDRESS_TYPE = "0"
    MULTICAST_TEMPORARY_ADDRESS_TYPE = "1"

    PEERING_TIMEOUT    = 22.0
    ANNOUNCE_INTERVAL  =  1.6
    PEER_JOB_INTERVAL  =  4.0
    MCAST_ECHO_TIMEOUT =  6.5

    ALL_IGNORE_IFS     = ["lo0"]
    DARWIN_IGNORE_IFS  = ["awdl0", "llw0", "lo0", "en5"]
    ANDROID_IGNORE_IFS = ["dummy0", "lo", "tun0"]

    BITRATE_GUESS = 10_000_000_i64

    MULTI_IF_DEQUE_LEN =   48
    MULTI_IF_DEQUE_TTL = 0.75

    # IPv6 multicast socket options
    IPPROTO_IPV6        = 41
    IPV6_JOIN_GROUP     = {% if flag?(:darwin) %} 12 {% elsif flag?(:linux) %} 20 {% else %} 12 {% end %}
    IPV6_MULTICAST_IF   = {% if flag?(:darwin) %} 9 {% elsif flag?(:linux) %} 17 {% else %} 9 {% end %}
    IPV6_MULTICAST_LOOP = {% if flag?(:darwin) %} 11 {% elsif flag?(:linux) %} 19 {% else %} 11 {% end %}

    # Peer entry: [ifname, last_heard, last_outbound]
    alias PeerEntry = {String, Float64, Float64}

    # Properties
    property peers : Hash(String, PeerEntry) = {} of String => PeerEntry
    property link_local_addresses : Array(String) = [] of String
    property adopted_interfaces : Hash(String, String) = {} of String => String
    property multicast_echoes : Hash(String, Float64) = {} of String => Float64
    property initial_echoes : Hash(String, Float64) = {} of String => Float64
    property timed_out_interfaces : Hash(String, Bool) = {} of String => Bool
    property carrier_changed : Bool = false

    getter group_id : Bytes
    getter discovery_port : Int32
    getter unicast_discovery_port : Int32
    getter data_port : Int32
    getter discovery_scope : String
    getter multicast_address_type : String
    getter mcast_discovery_address : String
    getter group_hash : Bytes
    getter announce_interval : Float64
    getter peer_job_interval : Float64
    getter peering_timeout : Float64
    getter multicast_echo_timeout : Float64
    getter reverse_peering_interval : Float64

    getter allowed_interfaces : Array(String) = [] of String
    getter ignored_interfaces : Array(String) = [] of String

    property dir_in : Bool = true
    property dir_out : Bool = false

    property? receives : Bool = false
    property? final_init_done : Bool = false

    property outbound_udp_socket : UDPSocket? = nil
    property write_lock : Mutex = Mutex.new
    @mif_deque : Array(Bytes) = [] of Bytes
    @mif_deque_times : Array({Bytes, Float64}) = [] of {Bytes, Float64}
    @peer_spawned_interfaces : Hash(String, AutoInterfacePeer) = {} of String => AutoInterfacePeer
    @interface_sockets : Hash(String, UDPSocket) = {} of String => UDPSocket
    @running : Bool = false
    @inbound_callback : Proc(Bytes, Interface, Nil)? = nil

    # Owner reference (Reticulum instance or similar object that calls inbound)
    property owner_inbound : Proc(Bytes, Interface, Nil)? = nil

    def initialize(configuration : Hash(String, String),
                   inbound_callback : Proc(Bytes, Interface, Nil)? = nil)
      super()
      @inbound_callback = inbound_callback

      name = configuration["name"]? || "AutoInterface"
      group_id_str = configuration["group_id"]?
      discovery_scope_str = configuration["discovery_scope"]?
      discovery_port_str = configuration["discovery_port"]?
      multicast_address_type_str = configuration["multicast_address_type"]?
      data_port_str = configuration["data_port"]?
      allowed = configuration["devices"]?
      ignored = configuration["ignored_devices"]?
      configured_bitrate = configuration["configured_bitrate"]?.try(&.to_i64)

      @hw_mtu = HW_MTU
      @dir_in = true
      @dir_out = false
      @name = name
      @online = false
      @bitrate = BITRATE_GUESS

      @announce_interval = ANNOUNCE_INTERVAL
      @peer_job_interval = PEER_JOB_INTERVAL
      @peering_timeout = PEERING_TIMEOUT
      @multicast_echo_timeout = MCAST_ECHO_TIMEOUT

      # Increase peering timeout on Android
      if RNS::PlatformUtils.is_android?
        @peering_timeout *= 1.25
      end

      @reverse_peering_interval = @announce_interval * 3.25

      # Parse allowed/ignored interfaces
      if allowed
        @allowed_interfaces = allowed.split(",").map(&.strip)
      end
      if ignored
        @ignored_interfaces = ignored.split(",").map(&.strip)
      end

      # Group ID
      if gid = group_id_str
        @group_id = gid.encode("UTF-8")
      else
        @group_id = DEFAULT_GROUP_ID
      end

      # Discovery port
      if dp = discovery_port_str
        @discovery_port = dp.to_i
      else
        @discovery_port = DEFAULT_DISCOVERY_PORT
      end
      @unicast_discovery_port = @discovery_port + 1

      # Multicast address type
      if mat = multicast_address_type_str
        case mat.downcase
        when "permanent"
          @multicast_address_type = MULTICAST_PERMANENT_ADDRESS_TYPE
        when "temporary"
          @multicast_address_type = MULTICAST_TEMPORARY_ADDRESS_TYPE
        else
          @multicast_address_type = MULTICAST_TEMPORARY_ADDRESS_TYPE
        end
      else
        @multicast_address_type = MULTICAST_TEMPORARY_ADDRESS_TYPE
      end

      # Data port
      if dp = data_port_str
        @data_port = dp.to_i
      else
        @data_port = DEFAULT_DATA_PORT
      end

      # Discovery scope
      if ds = discovery_scope_str
        case ds.downcase
        when "link"         then @discovery_scope = SCOPE_LINK
        when "admin"        then @discovery_scope = SCOPE_ADMIN
        when "site"         then @discovery_scope = SCOPE_SITE
        when "organisation" then @discovery_scope = SCOPE_ORGANISATION
        when "global"       then @discovery_scope = SCOPE_GLOBAL
        else                     @discovery_scope = SCOPE_LINK
        end
      else
        @discovery_scope = SCOPE_LINK
      end

      # Compute group hash and multicast discovery address
      @group_hash = RNS::Identity.full_hash(@group_id)
      @mcast_discovery_address = compute_mcast_address(@group_hash)

      # Enumerate network interfaces and find suitable ones
      suitable_interfaces = 0
      begin
        NetInfo.interfaces.each do |ifname|
          begin
            if should_skip_interface?(ifname)
              RNS.log("#{self} skipping interface #{ifname}", RNS::LOG_EXTREME)
              next
            end

            if @allowed_interfaces.size > 0 && !@allowed_interfaces.includes?(ifname)
              RNS.log("#{self} ignoring interface #{ifname} since it was not allowed", RNS::LOG_EXTREME)
              next
            end

            addresses = NetInfo.ifaddresses(ifname)
            af_inet6 = NetInfo::AF_INET6.to_i32
            if addresses.has_key?(af_inet6)
              link_local_addr : String? = nil
              addresses[af_inet6].each do |address|
                if address.addr.starts_with?("fe80:")
                  link_local_addr = NetInfo.descope_linklocal(address.addr)
                  @link_local_addresses << link_local_addr
                  @adopted_interfaces[ifname] = link_local_addr
                  @multicast_echoes[ifname] = Time.utc.to_unix_f
                  RNS.log("#{self} Selecting link-local address #{link_local_addr} for interface #{ifname}", RNS::LOG_EXTREME)
                end
              end

              if link_local_addr.nil?
                RNS.log("#{self} No link-local IPv6 address configured for #{ifname}, skipping interface", RNS::LOG_EXTREME)
              else
                # Start discovery listeners
                start_discovery_listeners(ifname, link_local_addr.not_nil!)
                suitable_interfaces += 1
              end
            end
          rescue ex
            RNS.log("Could not configure the system interface #{ifname} for use with #{self}, skipping it. The contained exception was: #{ex.message}", RNS::LOG_ERROR)
          end
        end
      rescue ex
        RNS.log("Error enumerating network interfaces: #{ex.message}", RNS::LOG_ERROR)
      end

      if suitable_interfaces == 0
        RNS.log("#{self} could not autoconfigure. This interface currently provides no connectivity.", RNS::LOG_WARNING)
      else
        @receives = true
        if cb = configured_bitrate
          @bitrate = cb
        else
          @bitrate = BITRATE_GUESS
        end
      end
    end

    # Start discovery and data listeners, peer jobs, and go online
    def final_init
      peering_wait = @announce_interval * 1.2
      RNS.log("#{self} discovering peers for #{peering_wait.round(2)} seconds...", RNS::LOG_VERBOSE)

      @adopted_interfaces.each do |ifname, link_local_addr|
        start_data_listener(ifname, link_local_addr)
      end

      @running = true
      spawn { peer_jobs }

      sleep peering_wait.seconds

      @online = true
      @final_init_done = true
    end

    # Handle incoming discovery packets
    def discovery_handler(socket : UDPSocket, ifname : String, announce : Bool = true)
      if announce
        spawn { announce_handler(ifname) }
      end

      buf = Bytes.new(1024)
      loop do
        begin
          bytes_read, addr = socket.receive(buf)
          break if bytes_read <= 0

          if @final_init_done
            data = buf[0, bytes_read]
            peer_addr = addr.address
            hash_len = RNS::Identity::HASHLENGTH // 8
            if data.size >= hash_len
              peering_hash = data[0, hash_len]
              expected_hash = RNS::Identity.full_hash(
                concat_bytes(@group_id, peer_addr.encode("UTF-8"))
              )
              if peering_hash == expected_hash
                add_peer(peer_addr, ifname)
              else
                RNS.log("#{self} received peering packet on #{ifname} from #{peer_addr}, but authentication hash was incorrect.", RNS::LOG_DEBUG)
              end
            end
          end
        rescue ex : IO::Error
          break
        rescue ex
          RNS.log("Error in discovery handler for #{self} on #{ifname}: #{ex.message}", RNS::LOG_ERROR)
          break
        end
      end
    end

    # Periodic peer maintenance
    def peer_jobs
      while @running
        sleep @peer_job_interval.seconds
        now = Time.utc.to_unix_f

        # Check for timed out peers
        timed_out_peers = [] of String
        @peers.each do |peer_addr, entry|
          last_heard = entry[1]
          if now > last_heard + @peering_timeout
            timed_out_peers << peer_addr
          end
        end

        # Remove timed out peers
        timed_out_peers.each do |peer_addr|
          removed_peer = @peers.delete(peer_addr)
          if si = @peer_spawned_interfaces[peer_addr]?
            si.detach
            si.teardown
          end
          if rp = removed_peer
            RNS.log("#{self} removed peer #{peer_addr} on #{rp[0]}", RNS::LOG_DEBUG)
          end
        end

        # Send reverse peering packets
        @peers.each do |peer_addr, entry|
          begin
            ifname = entry[0]
            last_outbound = entry[2]
            if now > last_outbound + @reverse_peering_interval
              reverse_announce(ifname, peer_addr)
              @peers[peer_addr] = {entry[0], entry[1], Time.utc.to_unix_f}
            end
          rescue ex
            RNS.log("Error while sending reverse peering packet to #{peer_addr}: #{ex.message}", RNS::LOG_ERROR)
          end
        end

        # Check multicast echo timeouts for each adopted interface
        @adopted_interfaces.each_key do |ifname|
          last_multicast_echo = @multicast_echoes[ifname]? || 0.0
          multicast_echo_received = @initial_echoes.has_key?(ifname)

          if now - last_multicast_echo > @multicast_echo_timeout
            if @timed_out_interfaces.has_key?(ifname) && !@timed_out_interfaces[ifname]
              @carrier_changed = true
              RNS.log("Multicast echo timeout for #{ifname}. Carrier lost.", RNS::LOG_WARNING)
            end
            @timed_out_interfaces[ifname] = true
          else
            if @timed_out_interfaces.has_key?(ifname) && @timed_out_interfaces[ifname]
              @carrier_changed = true
              RNS.log("#{self} Carrier recovered on #{ifname}", RNS::LOG_WARNING)
            end
            @timed_out_interfaces[ifname] = false
          end

          unless multicast_echo_received
            RNS.log("#{self} No multicast echoes received on #{ifname}. The networking hardware or a firewall may be blocking multicast traffic.", RNS::LOG_ERROR)
          end
        end
      end
    end

    # Periodically send multicast peering announcements
    def announce_handler(ifname : String)
      while @running
        peer_announce(ifname)
        sleep @announce_interval.seconds
      end
    end

    # Send a reverse (unicast) peering announcement to a specific peer
    def reverse_announce(ifname : String, peer_addr : String)
      link_local_address = @adopted_interfaces[ifname]
      discovery_token = RNS::Identity.full_hash(
        concat_bytes(@group_id, link_local_address.encode("UTF-8"))
      )
      sock = UDPSocket.new(Socket::Family::INET6)
      begin
        target = "#{peer_addr}%#{ifname}"
        addr = Socket::IPAddress.new(target, @unicast_discovery_port)
        sock.send(discovery_token, addr)
      ensure
        sock.close
      end
    rescue ex
      RNS.log("Could not send reverse peering packet to #{peer_addr} on #{ifname}: #{ex.message}", RNS::LOG_ERROR)
    end

    # Send a multicast peering announcement on an interface
    def peer_announce(ifname : String)
      link_local_address = @adopted_interfaces[ifname]
      discovery_token = RNS::Identity.full_hash(
        concat_bytes(@group_id, link_local_address.encode("UTF-8"))
      )
      sock = UDPSocket.new(Socket::Family::INET6)
      begin
        if_index = NetInfo.interface_name_to_index(ifname)
        # Set multicast interface
        if_bytes = Bytes.new(4)
        IO::ByteFormat::LittleEndian.encode(if_index.to_u32, if_bytes)
        LibC.setsockopt(sock.fd, IPPROTO_IPV6, IPV6_MULTICAST_IF, if_bytes.to_unsafe.as(Void*), if_bytes.size.to_u32)
        addr = Socket::IPAddress.new(@mcast_discovery_address, @discovery_port)
        sock.send(discovery_token, addr)
      ensure
        sock.close
      end
    rescue ex
      if (@timed_out_interfaces.has_key?(ifname) && !@timed_out_interfaces[ifname]) || !@timed_out_interfaces.has_key?(ifname)
        RNS.log("#{self} Detected possible carrier loss on #{ifname}: #{ex.message}", RNS::LOG_WARNING)
      end
    end

    # Number of active peer connections
    def peer_count : Int32
      @peer_spawned_interfaces.size
    end

    # Add or refresh a peer
    def add_peer(addr : String, ifname : String)
      if @link_local_addresses.includes?(addr)
        # This is our own echo — record multicast echo receipt
        echo_ifname : String? = nil
        @adopted_interfaces.each do |iface_name, iface_addr|
          if iface_addr == addr
            echo_ifname = iface_name
          end
        end

        if eif = echo_ifname
          @multicast_echoes[eif] = Time.utc.to_unix_f
          unless @initial_echoes.has_key?(eif)
            @initial_echoes[eif] = Time.utc.to_unix_f
          end
        else
          RNS.log("#{self} received multicast echo on unexpected interface", RNS::LOG_WARNING)
        end
      else
        if @peers.has_key?(addr)
          refresh_peer(addr)
        else
          now = Time.utc.to_unix_f
          @peers[addr] = {ifname, now, now}

          spawned = AutoInterfacePeer.new(self, addr, ifname)
          spawned.dir_out = @dir_out
          spawned.dir_in = @dir_in
          spawned.parent_interface = self
          spawned.bitrate = @bitrate

          spawned.ifac_size = @ifac_size
          spawned.ifac_netname = @ifac_netname
          spawned.ifac_netkey = @ifac_netkey
          if spawned.ifac_netname != nil || spawned.ifac_netkey != nil
            ifac_origin = Bytes.empty
            if nn = spawned.ifac_netname
              ifac_origin = concat_bytes(ifac_origin, RNS::Identity.full_hash(nn.encode("UTF-8")))
            end
            if nk = spawned.ifac_netkey
              ifac_origin = concat_bytes(ifac_origin, RNS::Identity.full_hash(nk.encode("UTF-8")))
            end

            ifac_origin_hash = RNS::Identity.full_hash(ifac_origin)
            spawned.ifac_key = RNS::Cryptography.hkdf(
              length: 64,
              derive_from: ifac_origin_hash,
              salt: Reticulum::IFAC_SALT,
              context: nil
            )
            if ik = spawned.ifac_key
              spawned.ifac_identity = RNS::Identity.from_bytes(ik)
              if ii = spawned.ifac_identity
                spawned.ifac_signature = ii.sign(RNS::Identity.full_hash(ik))
              end
            end
          end

          spawned.announce_rate_target = @announce_rate_target
          spawned.announce_rate_grace = @announce_rate_grace
          spawned.announce_rate_penalty = @announce_rate_penalty
          spawned.mode = @mode
          spawned.hw_mtu = HW_MTU
          spawned.online = true
          Transport.register_interface(spawned.get_hash)

          if old_spawned = @peer_spawned_interfaces[addr]?
            old_spawned.detach
            old_spawned.teardown
          end
          @peer_spawned_interfaces[addr] = spawned

          RNS.log("#{self} added peer #{addr} on #{ifname}", RNS::LOG_DEBUG)
        end
      end
    end

    # Update a peer's last_heard timestamp
    def refresh_peer(addr : String)
      if entry = @peers[addr]?
        @peers[addr] = {entry[0], Time.utc.to_unix_f, entry[2]}
      end
    rescue ex
      RNS.log("An error occurred while refreshing peer #{addr} on #{self}: #{ex.message}", RNS::LOG_ERROR)
    end

    # Route incoming data to the appropriate spawned peer interface
    def process_incoming(data : Bytes, addr : String? = nil)
      if @online && addr
        if si = @peer_spawned_interfaces[addr]?
          si.process_incoming(data, addr)
        end
      end
    end

    def process_outgoing(data : Bytes)
      # AutoInterface itself doesn't send data — spawned peers handle it
    end

    def detach
      @online = false
      @running = false
      @detached = true

      @interface_sockets.each_value do |sock|
        sock.close rescue nil
      end
      @interface_sockets.clear
    end

    def to_s(io : IO)
      io << "AutoInterface[" << @name << "]"
    end

    # --- Internal helpers ---

    # Compute the IPv6 multicast discovery address from the group hash.
    # Matches Python: "ff" + address_type + scope + ":" + formatted_hash
    def compute_mcast_address(group_hash : Bytes) : String
      g = group_hash
      gt = "0"
      gt += ":#{"%02x" % (g[3].to_u16 + (g[2].to_u16 << 8))}"
      gt += ":#{"%02x" % (g[5].to_u16 + (g[4].to_u16 << 8))}"
      gt += ":#{"%02x" % (g[7].to_u16 + (g[6].to_u16 << 8))}"
      gt += ":#{"%02x" % (g[9].to_u16 + (g[8].to_u16 << 8))}"
      gt += ":#{"%02x" % (g[11].to_u16 + (g[10].to_u16 << 8))}"
      gt += ":#{"%02x" % (g[13].to_u16 + (g[12].to_u16 << 8))}"
      "ff#{@multicast_address_type}#{@discovery_scope}:#{gt}"
    end

    # Check whether an interface should be skipped based on platform rules
    private def should_skip_interface?(ifname : String) : Bool
      if RNS::PlatformUtils.is_darwin?
        return true if DARWIN_IGNORE_IFS.includes?(ifname) && !@allowed_interfaces.includes?(ifname)
        return true if ifname == "lo0"
      end

      if RNS::PlatformUtils.is_android?
        return true if ANDROID_IGNORE_IFS.includes?(ifname) && !@allowed_interfaces.includes?(ifname)
      end

      return true if @ignored_interfaces.includes?(ifname)
      return true if ALL_IGNORE_IFS.includes?(ifname)

      false
    end

    # Start multicast and unicast discovery listeners on an interface
    private def start_discovery_listeners(ifname : String, link_local_addr : String)
      if_index = NetInfo.interface_name_to_index(ifname)

      # Set up unicast discovery socket
      begin
        unicast_sock = UDPSocket.new(Socket::Family::INET6)
        unicast_sock.reuse_address = true
        target = "#{link_local_addr}%#{ifname}"
        unicast_sock.bind(target, @unicast_discovery_port)

        spawn { discovery_handler(unicast_sock, ifname, announce: false) }
        RNS.log("#{self} Creating unicast discovery listener on #{ifname} with address #{link_local_addr}", RNS::LOG_EXTREME)
      rescue ex
        RNS.log("Could not create unicast discovery listener on #{ifname}: #{ex.message}", RNS::LOG_ERROR)
      end

      # Set up multicast discovery socket
      begin
        mcast_sock = UDPSocket.new(Socket::Family::INET6)
        mcast_sock.reuse_address = true

        if_bytes = Bytes.new(4)
        IO::ByteFormat::LittleEndian.encode(if_index.to_u32, if_bytes)
        LibC.setsockopt(mcast_sock.fd, IPPROTO_IPV6, IPV6_MULTICAST_IF, if_bytes.to_unsafe.as(Void*), if_bytes.size.to_u32)

        # Join multicast group
        mcast_group_bytes = ipv6_pton(@mcast_discovery_address)
        join_request = Bytes.new(20) # 16 bytes addr + 4 bytes interface index
        join_request.copy_from(mcast_group_bytes)
        IO::ByteFormat::LittleEndian.encode(if_index.to_u32, join_request[16, 4])
        LibC.setsockopt(mcast_sock.fd, IPPROTO_IPV6, IPV6_JOIN_GROUP, join_request.to_unsafe.as(Void*), join_request.size.to_u32)

        # Bind multicast socket
        if @discovery_scope == SCOPE_LINK
          mcast_sock.bind("#{@mcast_discovery_address}%#{ifname}", @discovery_port)
        else
          mcast_sock.bind(@mcast_discovery_address, @discovery_port)
        end

        spawn { discovery_handler(mcast_sock, ifname, announce: true) }
        RNS.log("#{self} Creating multicast discovery listener on #{ifname} with address #{@mcast_discovery_address}", RNS::LOG_EXTREME)
      rescue ex
        RNS.log("Could not create multicast discovery listener on #{ifname}: #{ex.message}", RNS::LOG_ERROR)
      end
    end

    # Start data listener (UDP server) on an interface
    private def start_data_listener(ifname : String, link_local_addr : String)
      if_index = NetInfo.interface_name_to_index(ifname)
      local_addr = "#{link_local_addr}%#{ifname}"
      sock = UDPSocket.new(Socket::Family::INET6)
      sock.reuse_address = true
      sock.bind(local_addr, @data_port)
      @interface_sockets[ifname] = sock

      spawn do
        buf = Bytes.new(2048)
        loop do
          begin
            bytes_read, remote_addr = sock.receive(buf)
            break if bytes_read <= 0
            data = buf[0, bytes_read].dup
            peer_addr = remote_addr.address
            process_incoming(data, peer_addr)
          rescue ex : IO::Error
            break
          rescue ex
            RNS.log("Error in data listener for #{self} on #{ifname}: #{ex.message}", RNS::LOG_ERROR)
            break
          end
        end
      end
    rescue ex
      RNS.log("Could not start data listener on #{ifname}: #{ex.message}", RNS::LOG_ERROR)
    end

    # Convert IPv6 string to 16-byte binary representation
    private def ipv6_pton(addr : String) : Bytes
      # Strip scope identifier if present
      clean = addr.split("%")[0]
      result = Bytes.new(16)
      # Use Crystal's Socket to parse
      begin
        ip = Socket::IPAddress.new(clean, 0)
        # Extract the raw address bytes from the sockaddr
        sa = ip.to_unsafe
        # For IPv6, the address is at offset 8 in sockaddr_in6
        raw = sa.as(Pointer(UInt8)) + 8
        result.copy_from(raw, 16)
      rescue
        # Manual fallback: expand the IPv6 address
        parts = expand_ipv6(clean)
        parts.each_with_index do |group, i|
          result[i * 2] = ((group >> 8) & 0xff).to_u8
          result[i * 2 + 1] = (group & 0xff).to_u8
        end
      end
      result
    end

    # Expand a compressed IPv6 address into 8 16-bit groups
    private def expand_ipv6(addr : String) : Array(UInt16)
      if addr.includes?("::")
        parts = addr.split("::")
        left = parts[0].empty? ? [] of UInt16 : parts[0].split(":").map(&.to_u16(16))
        right = parts.size > 1 && !parts[1].empty? ? parts[1].split(":").map(&.to_u16(16)) : [] of UInt16
        zeros = Array(UInt16).new(8 - left.size - right.size, 0_u16)
        left + zeros + right
      else
        addr.split(":").map(&.to_u16(16))
      end
    end

    # Concatenate two Bytes objects
    private def concat_bytes(a : Bytes, b : Bytes) : Bytes
      result = Bytes.new(a.size + b.size)
      result.copy_from(a) if a.size > 0
      (result + a.size).copy_from(b) if b.size > 0
      result
    end

    # Add to multi-interface deduplication deque
    def mif_deque_add(data_hash : Bytes)
      @mif_deque << data_hash
      @mif_deque_times << {data_hash, Time.utc.to_unix_f}
      while @mif_deque.size > MULTI_IF_DEQUE_LEN
        @mif_deque.shift
      end
      while @mif_deque_times.size > MULTI_IF_DEQUE_LEN
        @mif_deque_times.shift
      end
    end

    # Check if data hash is in the multi-interface deque and still valid
    def mif_deque_hit?(data_hash : Bytes) : Bool
      return false unless @mif_deque.any? { |h| h == data_hash }
      @mif_deque_times.any? do |entry|
        entry[0] == data_hash && Time.utc.to_unix_f < entry[1] + MULTI_IF_DEQUE_TTL
      end
    end

    # Expose spawned peer interfaces (for testing and Transport integration)
    def spawned_peer_interfaces : Hash(String, AutoInterfacePeer)
      @peer_spawned_interfaces
    end
  end

  # AutoInterfacePeer represents a single discovered peer.
  # Each peer communicates via unicast UDP on the data port.
  # Ports the AutoInterfacePeer class from RNS/Interfaces/AutoInterface.py.
  class AutoInterfacePeer < Interface
    getter owner : AutoInterface
    getter addr : String
    getter ifname : String

    property dir_in : Bool = true
    property dir_out : Bool = false

    @peer_addr : String? = nil
    @addr_info : Socket::IPAddress? = nil
    @inbound_callback : Proc(Bytes, Interface, Nil)? = nil

    def initialize(@owner : AutoInterface, @addr : String, @ifname : String)
      super()
      @hw_mtu = @owner.hw_mtu
      @parent_interface = @owner
    end

    def process_incoming(data : Bytes, addr : String? = nil)
      return unless @online && @owner.online

      data_hash = RNS::Identity.full_hash(data)
      deque_hit = @owner.mif_deque_hit?(data_hash)

      unless deque_hit
        @owner.refresh_peer(@addr)
        @owner.mif_deque_add(data_hash)
        @rxb += data.size.to_i64
        @owner.rxb += data.size.to_i64
        if cb = @owner.owner_inbound
          cb.call(data, self)
        end
      end
    end

    def process_outgoing(data : Bytes)
      return unless @online

      @owner.write_lock.synchronize do
        begin
          if @owner.outbound_udp_socket.nil?
            @owner.outbound_udp_socket = UDPSocket.new(Socket::Family::INET6)
          end

          if @peer_addr.nil?
            @peer_addr = "#{@addr}%#{@ifname}"
          end

          if @addr_info.nil?
            @addr_info = Socket::IPAddress.new(@peer_addr.not_nil!, @owner.data_port)
          end

          if sock = @owner.outbound_udp_socket
            sock.send(data, @addr_info.not_nil!)
            @txb += data.size.to_i64
            @owner.txb += data.size.to_i64
          end
        rescue ex
          RNS.log("Could not transmit on #{self}. The contained exception was: #{ex.message}", RNS::LOG_ERROR)
        end
      end
    end

    def detach
      @online = false
      @detached = true
    end

    def teardown
      if detached?
        RNS.log("The interface #{self} is being torn down.", RNS::LOG_VERBOSE)
      else
        RNS.log("The interface #{self} experienced an unrecoverable error and is being torn down.", RNS::LOG_ERROR)
        if Reticulum.panic_on_interface_error
          RNS.panic
        end
      end

      @online = false
      @dir_out = false
      @dir_in = false

      @owner.spawned_peer_interfaces.delete(@addr)
      Transport.deregister_interface(get_hash)
    end

    def to_s(io : IO)
      io << "AutoInterfacePeer[" << @ifname << "/" << @addr << "]"
    end
  end
end
