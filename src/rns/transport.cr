module RNS
  module Transport
    BROADCAST = 0x00_u8
    TRANSPORT = 0x01_u8
    RELAY     = 0x02_u8
    TUNNEL    = 0x03_u8

    @@destinations = [] of Destination

    def self.register_destination(destination : Destination)
      @@destinations << destination
    end

    def self.deregister_destination(destination : Destination)
      @@destinations.delete(destination)
    end

    def self.destinations
      @@destinations
    end

    def self.clear_destinations
      @@destinations.clear
    end
  end
end
