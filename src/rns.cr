require "./rns/version"
require "./rns/vendor/platform_utils"
require "./rns/log"
require "./rns/utilities"

module RNS
  def self.version : String
    VERSION
  end
end
