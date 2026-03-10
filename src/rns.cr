require "./rns/version"
require "./rns/vendor/platform_utils"
require "./rns/log"
require "./rns/utilities"
require "./rns/cryptography/hashes"
require "./rns/cryptography/hmac"
require "./rns/cryptography/hkdf"
require "./rns/cryptography/pkcs7"
require "./rns/cryptography/aes"

module RNS
  def self.version : String
    VERSION
  end
end
