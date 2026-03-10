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
  end
end
