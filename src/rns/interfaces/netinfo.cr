require "socket"

module RNS
  # Network interface information module.
  # Provides interface enumeration, address lookup, and name-to-index mapping
  # using POSIX getifaddrs. Ports the functionality of RNS/Interfaces/util/netinfo.py.
  module NetInfo
    AF_INET  = Socket::Family::INET.value
    AF_INET6 = Socket::Family::INET6.value

    INET6_ADDRSTRLEN = 46

    # LibC bindings for interface enumeration
    lib LibNet
      # Minimal sockaddr for reading sa_family
      struct Sockaddr
        {% if flag?(:darwin) %}
          sa_len : UInt8
        {% end %}
        sa_family : UInt8
      end

      struct Ifaddrs
        ifa_next : Ifaddrs*
        ifa_name : UInt8*
        ifa_flags : UInt32
        ifa_addr : Sockaddr*
        ifa_netmask : Sockaddr*
        ifa_broadaddr : Void*
        ifa_data : Void*
      end

      fun getifaddrs(ifap : Ifaddrs**) : Int32
      fun freeifaddrs(ifa : Ifaddrs*) : Void
      fun if_nametoindex(ifname : UInt8*) : UInt32
      fun inet_ntop(af : Int32, src : Void*, dst : UInt8*, size : UInt32) : UInt8*
    end

    # Address information record matching Python netinfo's dict format
    record AddressInfo, addr : String

    # Get list of all network interface names
    def self.interfaces : Array(String)
      names = [] of String
      each_ifaddr do |name, _family, _addr|
        names << name unless names.includes?(name)
      end
      names
    end

    # Map interface names to their OS indexes
    def self.interface_names_to_indexes : Hash(String, UInt32)
      result = {} of String => UInt32
      interfaces.each do |name|
        idx = interface_name_to_index(name)
        result[name] = idx if idx > 0
      end
      result
    end

    # Get OS index for an interface name
    def self.interface_name_to_index(ifname : String) : UInt32
      LibNet.if_nametoindex(ifname).to_u32
    end

    # Get display name for an interface (on POSIX, same as name)
    def self.interface_name_to_nice_name(ifname : String) : String?
      ifname
    end

    # Get addresses for an interface, grouped by address family.
    # Returns Hash mapping AF_INET/AF_INET6 to arrays of AddressInfo.
    def self.ifaddresses(ifname : String) : Hash(Int32, Array(AddressInfo))
      result = {} of Int32 => Array(AddressInfo)
      ipv4s = [] of AddressInfo
      ipv6s = [] of AddressInfo

      each_ifaddr do |name, family, addr_str|
        next unless name == ifname
        if family == AF_INET6.to_i32
          ipv6s << AddressInfo.new(addr: addr_str)
        elsif family == AF_INET.to_i32
          ipv4s << AddressInfo.new(addr: addr_str)
        end
      end

      result[AF_INET.to_i32] = ipv4s unless ipv4s.empty?
      result[AF_INET6.to_i32] = ipv6s unless ipv6s.empty?
      result
    end

    # Iterate over all interface addresses, yielding (name, family, address_string)
    private def self.each_ifaddr(&block : String, Int32, String ->)
      ifap = Pointer(LibNet::Ifaddrs).null
      ret = LibNet.getifaddrs(pointerof(ifap))
      raise "getifaddrs failed" if ret != 0

      begin
        ifa = ifap
        while ifa
          entry = ifa.value
          name = String.new(entry.ifa_name)

          if addr = entry.ifa_addr
            family = addr.value.sa_family.to_i32

            if family == AF_INET6.to_i32
              # IPv6: extract 16-byte address at offset 8 in sockaddr_in6
              # (offset 8 works on both macOS [len+family+port+flowinfo] and Linux [family+port+flowinfo])
              in6_addr_ptr = (addr.as(Pointer(UInt8)) + 8)
              addr_bytes = Bytes.new(16)
              addr_bytes.copy_from(in6_addr_ptr, 16)
              addr_str = format_ipv6(addr_bytes)
              yield name, family, addr_str
            elsif family == AF_INET.to_i32
              # IPv4: extract 4-byte address at offset 4 in sockaddr_in
              in_addr_ptr = (addr.as(Pointer(UInt8)) + 4)
              addr_str = "#{in_addr_ptr[0]}.#{in_addr_ptr[1]}.#{in_addr_ptr[2]}.#{in_addr_ptr[3]}"
              yield name, family, addr_str
            end
          end

          ifa = entry.ifa_next
        end
      ensure
        LibNet.freeifaddrs(ifap)
      end
    end

    # Format 16 bytes as a compressed IPv6 address string
    def self.format_ipv6(bytes : Bytes) : String
      raise ArgumentError.new("IPv6 address must be 16 bytes") unless bytes.size == 16

      # Parse into 8 groups of 16-bit values
      groups = Array(UInt16).new(8) do |i|
        (bytes[i * 2].to_u16 << 8) | bytes[i * 2 + 1].to_u16
      end

      # Find longest run of consecutive zero groups (for :: compression)
      best_start = -1
      best_len = 0
      cur_start = -1
      cur_len = 0

      groups.each_with_index do |g, i|
        if g == 0
          if cur_start == -1
            cur_start = i
            cur_len = 1
          else
            cur_len += 1
          end
          if cur_len > best_len
            best_start = cur_start
            best_len = cur_len
          end
        else
          cur_start = -1
          cur_len = 0
        end
      end

      if best_len >= 2
        before = groups[0...best_start].map { |g| "%x" % g }.join(":")
        after = groups[(best_start + best_len)..].map { |g| "%x" % g }.join(":")
        if before.empty? && after.empty?
          "::"
        elsif before.empty?
          "::#{after}"
        elsif after.empty?
          "#{before}::"
        else
          "#{before}::#{after}"
        end
      else
        groups.map { |g| "%x" % g }.join(":")
      end
    end

    # Descope a link-local IPv6 address: remove %ifname suffix and
    # embedded scope specifiers (NetBSD/OpenBSD style fe80:XXXX::)
    def self.descope_linklocal(link_local_addr : String) : String
      # Drop scope specifier expressed as %ifname (macOS)
      addr = link_local_addr.split("%")[0]
      # Drop embedded scope specifier (NetBSD, OpenBSD)
      addr = addr.gsub(/fe80:[0-9a-f]*::/, "fe80::")
      addr
    end
  end
end
