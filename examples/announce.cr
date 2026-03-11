##########################################################
# This RNS example demonstrates setting up announce      #
# callbacks, which will let an application receive a     #
# notification when an announce relevant for it arrives  #
##########################################################

require "../src/rns"

# Let's define an app name. We'll use this for all
# destinations we create. Since this basic example
# is part of a range of example utilities, we'll put
# them all within the app namespace "example_utilities"
APP_NAME = "example_utilities"

# We initialise two lists of strings to use as app_data
FRUITS     = ["Peach", "Quince", "Date", "Tangerine", "Pomelo", "Carambola", "Grape"]
NOBLE_GASES = ["Helium", "Neon", "Argon", "Krypton", "Xenon", "Radon", "Oganesson"]

# This initialisation is executed when the program is started
def program_setup(configpath : String?)
  # We must first initialise Reticulum
  reticulum = RNS::ReticulumInstance.new(configpath)

  # Randomly create a new identity for our example
  identity = RNS::Identity.new

  # Using the identity we just created, we create two destinations
  # in the "example_utilities.announcesample" application space.
  #
  # Destinations are endpoints in Reticulum, that can be addressed
  # and communicated with. Destinations can also announce their
  # existence, which will let the network know they are reachable
  # and automatically create paths to them, from anywhere else
  # in the network.
  destination_1 = RNS::Destination.new(
    identity,
    RNS::Destination::IN,
    RNS::Destination::SINGLE,
    APP_NAME,
    ["announcesample", "fruits"]
  )

  destination_2 = RNS::Destination.new(
    identity,
    RNS::Destination::IN,
    RNS::Destination::SINGLE,
    APP_NAME,
    ["announcesample", "noble_gases"]
  )

  # We configure the destinations to automatically prove all
  # packets addressed to it. By doing this, RNS will automatically
  # generate a proof for each incoming packet and transmit it
  # back to the sender of that packet. This will let anyone that
  # tries to communicate with the destination know whether their
  # communication was received correctly.
  destination_1.set_proof_strategy(RNS::Destination::PROVE_ALL)
  destination_2.set_proof_strategy(RNS::Destination::PROVE_ALL)

  # We create an announce handler and configure it to only ask for
  # announces from "example_utilities.announcesample.fruits".
  # Try changing the filter and see what happens.
  announce_handler = ExampleAnnounceHandler.new(
    aspect_filter: "example_utilities.announcesample.fruits"
  )

  # We register the announce handler with Reticulum
  RNS::Transport.register_announce_handler(announce_handler)

  # Everything's ready!
  # Let's hand over control to the announce loop
  announce_loop(destination_1, destination_2)
end

def announce_loop(destination_1 : RNS::Destination, destination_2 : RNS::Destination)
  # Let the user know that everything is ready
  RNS.log("Announce example running, hit enter to manually send an announce (Ctrl-C to quit)")

  # We enter a loop that runs until the user exits.
  # If the user hits enter, we will announce our server
  # destination on the network, which will let clients
  # know how to create messages directed towards it.
  loop do
    gets

    # Randomly select a fruit
    fruit = FRUITS.sample

    # Send the announce including the app data
    destination_1.announce(app_data: fruit.to_slice)
    RNS.log(
      "Sent announce from " +
      RNS.prettyhexrep(destination_1.hash) +
      " (" + destination_1.name + ")"
    )

    # Randomly select a noble gas
    noble_gas = NOBLE_GASES.sample

    # Send the announce including the app data
    destination_2.announce(app_data: noble_gas.to_slice)
    RNS.log(
      "Sent announce from " +
      RNS.prettyhexrep(destination_2.hash) +
      " (" + destination_2.name + ")"
    )
  end
end

# We will need to define an announce handler class that
# Reticulum can message when an announce arrives.
class ExampleAnnounceHandler
  include RNS::Transport::AnnounceHandler

  # The initialisation method takes the optional
  # aspect_filter argument. If aspect_filter is set to
  # nil, all announces will be passed to the instance.
  # If only some announces are wanted, it can be set to
  # an aspect string.
  getter aspect_filter : String?

  def initialize(@aspect_filter : String? = nil)
  end

  # This method will be called by Reticulum's Transport
  # system when an announce arrives that matches the
  # configured aspect filter. Filters must be specific,
  # and cannot use wildcards.
  def received_announce(destination_hash : Bytes, announced_identity : RNS::Identity?, app_data : Bytes?, announce_packet_hash : Bytes?)
    RNS.log(
      "Received an announce from " +
      RNS.prettyhexrep(destination_hash)
    )

    if ad = app_data
      RNS.log(
        "The announce contained the following app data: " +
        String.new(ad)
      )
    end
  end
end

##########################################################
#### Program Startup #####################################
##########################################################

# This part of the program gets run at startup,
# and parses input from the user, and then starts
# the desired program mode.
begin
  configarg : String? = nil

  i = 0
  while i < ARGV.size
    case ARGV[i]
    when "--config"
      i += 1
      configarg = ARGV[i]? || abort("--config requires a path argument")
    when "-h", "--help"
      puts "Usage: announce [--config PATH]"
      puts ""
      puts "Reticulum example that demonstrates announces and announce handlers"
      puts ""
      puts "Options:"
      puts "  --config PATH  path to alternative Reticulum config directory"
      puts "  -h, --help     show this help message"
      exit 0
    else
      STDERR.puts "Unknown argument: #{ARGV[i]}"
      exit 1
    end
    i += 1
  end

  program_setup(configarg)
rescue ex : Exception
  if ex.message == "Interrupted"
    puts ""
    exit 0
  end
  raise ex
end
