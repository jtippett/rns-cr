# ═══════════════════════════════════════════════════════════════════════
# RNS — Crystal port of the Reticulum Network Stack
#
# Public API entry point.  Requiring this file pulls in every module in
# dependency order and exposes the top-level convenience functions that
# match the Python RNS.__init__ surface.
# ═══════════════════════════════════════════════════════════════════════

# ── 1. Foundation ──────────────────────────────────────────────────────
require "./rns/version"
require "./rns/vendor/platform_utils"
require "./rns/vendor/config_obj"
require "./rns/log"
require "./rns/utilities"

# ── 2. Cryptography layer ─────────────────────────────────────────────
require "./rns/cryptography/hashes"
require "./rns/cryptography/hmac"
require "./rns/cryptography/hkdf"
require "./rns/cryptography/pkcs7"
require "./rns/cryptography/aes"
require "./rns/cryptography/x25519"
require "./rns/cryptography/ed25519"
require "./rns/cryptography/token"
require "./rns/cryptography/provider"

# ── 3. Core protocol ──────────────────────────────────────────────────
require "./rns/reticulum"
require "./rns/link_like"
require "./rns/transport"
require "./rns/transport/path_management"
require "./rns/transport/announce_handler"
require "./rns/transport/tunnel_management"
require "./rns/destination"
require "./rns/identity"
require "./rns/packet"

# ── 4. Communication layer ────────────────────────────────────────────
require "./rns/vendor/bz2"
require "./rns/channel"
require "./rns/link"
require "./rns/resource"
require "./rns/buffer"
require "./rns/resolver"

# ── 5. Interface system ───────────────────────────────────────────────
require "./rns/interfaces/interface"
require "./rns/interfaces/udp_interface"
require "./rns/interfaces/tcp_interface"
require "./rns/interfaces/local_interface"
require "./rns/interfaces/netinfo"
require "./rns/interfaces/auto_interface"
require "./rns/interfaces/serial_interface"
require "./rns/interfaces/kiss_interface"
require "./rns/interfaces/ax25_kiss_interface"
require "./rns/interfaces/backbone_interface"
require "./rns/interfaces/pipe_interface"
require "./rns/interfaces/i2p_interface"
require "./rns/interfaces/rnode_interface"
require "./rns/interfaces/rnode_multi_interface"
require "./rns/interfaces/weave_interface"

# ── 6. System integration ─────────────────────────────────────────────
require "./rns/discovery"

# ── 7. Utilities / CLI modules ────────────────────────────────────────
require "./rns/rnsd"
require "./rns/rnstatus"
require "./rns/rnpath"
require "./rns/rnprobe"
require "./rns/rnid"

# ═══════════════════════════════════════════════════════════════════════
# Module-level public API
#
# These match the functions/constants exported by Python's RNS.__init__
# ═══════════════════════════════════════════════════════════════════════

module RNS
  # ─── Exit management (matches Python RNS.exit) ────────────────────
  @@exit_called : Bool = false

  def self.version : String
    VERSION
  end

  def self.trace_exception(e : Exception)
    log("An unhandled #{e.class} exception occurred: #{e.message}", LOG_ERROR)
    if bt = e.backtrace?
      bt.each { |line| log(line, LOG_ERROR) }
    end
  end

  def self.precise_timestamp_str(time_s : Float64) : String
    Time.utc.to_s("%H:%M:%S.%3N")
  end

  def self.phyparams
    puts "Required Physical Layer MTU : #{Reticulum::MTU} bytes"
    puts "Plaintext Packet MDU        : #{Packet::PLAIN_MDU} bytes"
    puts "Encrypted Packet MDU        : #{Packet::ENCRYPTED_MDU} bytes"
    puts "Link Curve                  : #{Link::CURVE}"
    puts "Link Packet MDU             : #{Link::MDU} bytes"
    puts "Link Public Key Size        : #{Link::ECPUBSIZE * 8} bits"
    puts "Link Private Key Size       : #{Link::KEYSIZE * 8} bits"
  end

  def self.exit(code : Int32 = 0)
    unless @@exit_called
      @@exit_called = true
      Reticulum.exit_handler
      Process.exit(code)
    end
  end

  def self.exit_called? : Bool
    @@exit_called
  end

  # ─── Convenience aliases (match Python top-level imports) ─────────
  # Python's RNS.__init__ imports InterfaceAnnouncer at the top level.
  alias InterfaceAnnouncer = Discovery::InterfaceAnnouncer
end
