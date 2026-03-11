##########################################################
# This RNS example demonstrates broadcasting unencrypted #
# information to any listening destinations.             #
##########################################################

require "../src/rns"

# Let's define an app name. We'll use this for all
# destinations we create. Since this basic example
# is part of a range of example utilities, we'll put
# them all within the app namespace "example_utilities"
APP_NAME = "example_utilities"

# This initialisation is executed when the program is started
def program_setup(configpath : String?, channel : String? = nil)
  # We must first initialise Reticulum
  reticulum = RNS::ReticulumInstance.new(configpath)

  # If the user did not select a "channel" we use
  # a default one called "public_information".
  # This "channel" is added to the destination name-
  # space, so the user can select different broadcast
  # channels.
  actual_channel = channel || "public_information"

  # We create a PLAIN destination. This is an unencrypted endpoint
  # that anyone can listen to and send information to.
  broadcast_destination = RNS::Destination.new(
    nil,
    RNS::Destination::IN,
    RNS::Destination::PLAIN,
    APP_NAME,
    ["broadcast", actual_channel]
  )

  # We specify a callback that will get called every time
  # the destination receives data.
  broadcast_destination.set_packet_callback(
    ->(data : Bytes, packet : RNS::Packet) {
      # Simply print out the received data
      puts ""
      print "Received data: " + String.new(data) + "\r\n> "
      STDOUT.flush
    }
  )

  # Everything's ready!
  # Let's hand over control to the main loop
  broadcast_loop(broadcast_destination)
end

def broadcast_loop(destination : RNS::Destination)
  # Let the user know that everything is ready
  RNS.log(
    "Broadcast example " +
    RNS.prettyhexrep(destination.hash) +
    " running, enter text and hit enter to broadcast (Ctrl-C to quit)"
  )

  # We enter a loop that runs until the user exits.
  # If the user hits enter, we will send the information
  # that the user entered into the prompt.
  loop do
    print "> "
    entered = gets

    if entered && entered != ""
      data = entered.to_slice
      packet = RNS::Packet.new(destination, data)
      packet.send
    end
  end
end

##########################################################
#### Program Startup #####################################
##########################################################

# This part of the program gets run at startup,
# and parses input from the user, and then starts
# the program.
begin
  configarg : String? = nil
  channelarg : String? = nil

  i = 0
  while i < ARGV.size
    case ARGV[i]
    when "--config"
      i += 1
      configarg = ARGV[i]? || abort("--config requires a path argument")
    when "--channel"
      i += 1
      channelarg = ARGV[i]? || abort("--channel requires a name argument")
    when "-h", "--help"
      puts "Usage: broadcast [--config PATH] [--channel NAME]"
      puts ""
      puts "Reticulum example demonstrating sending and receiving broadcasts"
      puts ""
      puts "Options:"
      puts "  --config PATH   path to alternative Reticulum config directory"
      puts "  --channel NAME  broadcast channel name"
      puts "  -h, --help      show this help message"
      exit 0
    else
      STDERR.puts "Unknown argument: #{ARGV[i]}"
      exit 1
    end
    i += 1
  end

  program_setup(configarg, channelarg)
rescue ex : Exception
  if ex.message == "Interrupted"
    puts ""
    exit 0
  end
  raise ex
end
