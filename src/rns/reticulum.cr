module RNS
  module Reticulum
    MTU              = 500
    LINK_MTU_DISCOVERY = true

    TRUNCATED_HASHLENGTH = 128 # bits
    IFAC_MIN_SIZE        =   1

    HEADER_MINSIZE = 2 + 1 + (TRUNCATED_HASHLENGTH // 8) * 1  # 19
    HEADER_MAXSIZE = 2 + 1 + (TRUNCATED_HASHLENGTH // 8) * 2  # 35

    MDU = MTU - HEADER_MAXSIZE - IFAC_MIN_SIZE  # 464

    DEFAULT_PER_HOP_TIMEOUT = 6

    # Default paths — overridden by Reticulum class at init time
    @@configdir : String = File.join(Path.home.to_s, ".reticulum")
    @@storagepath : String = File.join(@@configdir, "storage")
    @@cachepath : String = File.join(@@configdir, "storage", "cache")
    @@resourcepath : String = File.join(@@configdir, "storage", "resources")

    def self.configdir; @@configdir; end
    def self.configdir=(v); @@configdir = v; end
    def self.storagepath; @@storagepath; end
    def self.storagepath=(v); @@storagepath = v; end
    def self.cachepath; @@cachepath; end
    def self.cachepath=(v); @@cachepath = v; end
    def self.resourcepath; @@resourcepath; end
    def self.resourcepath=(v); @@resourcepath = v; end
  end
end
