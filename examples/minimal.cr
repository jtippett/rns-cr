##########################################################
# This RNS example demonstrates a minimal setup, that    #
# will start up the Reticulum Network Stack, generate a  #
# new destination, and let the user send an announce.    #
##########################################################

require "../src/rns"

# Let's define an app name. We'll use this for all
# destinations we create. Since this basic example
# is part of a range of example utilities, we'll put
# them all within the app namespace "example_utilities"
APP_NAME = "example_utilities"

# This initialisation is executed when the program is started
def program_setup(configpath : String?)
  # We must first initialise Reticulum
  reticulum = RNS::ReticulumInstance.new(configpath)

  # Randomly create a new identity for our example
  identity = RNS::Identity.new

  # Using the identity we just created, we create a destination.
  # Destinations are endpoints in Reticulum, that can be addressed
  # and communicated with. Destinations can also announce their
  # existence, which will let the network know they are reachable
  # and automatically create paths to them, from anywhere else
  # in the network.
  destination = RNS::Destination.new(
    identity,
    RNS::Destination::IN,
    RNS::Destination::SINGLE,
    APP_NAME,
    ["minimalsample"]
  )

  # We configure the destination to automatically prove all
  # packets addressed to it. By doing this, RNS will automatically
  # generate a proof for each incoming packet and transmit it
  # back to the sender of that packet. This will let anyone that
  # tries to communicate with the destination know whether their
  # communication was received correctly.
  destination.set_proof_strategy(RNS::Destination::PROVE_ALL)

  # Everything's ready!
  # Let's hand over control to the announce loop
  announce_loop(destination)
end

def announce_loop(destination : RNS::Destination)
  # Let the user know that everything is ready
  RNS.log(
    "Minimal example " +
    RNS.prettyhexrep(destination.hash) +
    " running, hit enter to manually send an announce (Ctrl-C to quit)"
  )

  # We enter a loop that runs until the user exits.
  # If the user hits enter, we will announce our server
  # destination on the network, which will let clients
  # know how to create messages directed towards it.
  loop do
    gets
    destination.announce
    RNS.log("Sent announce from " + RNS.prettyhexrep(destination.hash))
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
      puts "Usage: minimal [--config PATH]"
      puts ""
      puts "Minimal example to start Reticulum and create a destination"
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
