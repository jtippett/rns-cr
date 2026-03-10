require "./rns/version"
require "./rns/vendor/platform_utils"
require "./rns/log"
require "./rns/utilities"
require "./rns/cryptography/hashes"
require "./rns/cryptography/hmac"
require "./rns/cryptography/hkdf"
require "./rns/cryptography/pkcs7"
require "./rns/cryptography/aes"
require "./rns/cryptography/x25519"
require "./rns/cryptography/ed25519"
require "./rns/cryptography/token"
require "./rns/cryptography/provider"
require "./rns/reticulum"
require "./rns/transport"
require "./rns/transport/path_management"
require "./rns/transport/announce_handler"
require "./rns/destination"
require "./rns/identity"
require "./rns/packet"

module RNS
  def self.version : String
    VERSION
  end
end
