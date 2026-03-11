##########################################################
# This RNS example demonstrates a simple speedtest       #
# program to measure link throughput.                    #
#                                                        #
# The current configuration is suited for testing fast   #
# links. If you want to measure slow links like LoRa or  #
# packet radio, you must significantly lower the         #
# data_cap variable, which defines how much data is sent #
# for each test.                                         #
##########################################################

require "../src/rns"

# Let's define an app name. We'll use this for all
# destinations we create.
APP_NAME = "example_utilities"

# We use a module to hold mutable state so callbacks
# can access it.
module SpeedtestExample
  class_property latest_client_link : RNS::Link? = nil
  class_property server_link : RNS::Link? = nil
  class_property first_packet_at : Float64 = 0.0
  class_property last_packet_at : Float64 = 0.0
  class_property received_data : Int64 = 0_i64
  class_property rc : Int32 = 0
  class_property data_cap : Int64 = (2 * 1024 * 1024).to_i64
  class_property printed : Bool = false
  class_property should_quit : Bool = false
end

##########################################################
#### Server Part #########################################
##########################################################

# This initialisation is executed when the user chooses
# to run as a server
def server(configpath : String?)
  # We must first initialise Reticulum
  reticulum = RNS::ReticulumInstance.new(configpath)

  # Randomly create a new identity for our link example
  server_identity = RNS::Identity.new

  # We create a destination that clients can connect to. We
  # want clients to create links to this destination, so we
  # need to create a "single" destination type.
  server_destination = RNS::Destination.new(
    server_identity,
    RNS::Destination::IN,
    RNS::Destination::SINGLE,
    APP_NAME,
    ["speedtest"]
  )

  # We configure a function that will get called every time
  # a new client creates a link to this destination.
  server_destination.set_link_established_callback(
    ->(link : RNS::Link) {
      client_connected(link)
    }
  )

  # Everything's ready!
  # Let's wait for client requests or user input
  server_loop(server_destination)
end

def server_loop(destination : RNS::Destination)
  # Let the user know that everything is ready
  RNS.log(
    "Speedtest " +
    RNS.prettyhexrep(destination.hash) +
    " running, waiting for a connection."
  )

  RNS.log("Hit enter to manually send an announce (Ctrl-C to quit)")

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

# When a client establishes a link to our server
# destination, this function will be called with
# a reference to the link.
def client_connected(link : RNS::Link)
  RNS.log("Client connected")
  SpeedtestExample.first_packet_at = Time.utc.to_unix_f
  SpeedtestExample.rc = 0
  link.set_link_closed_callback(
    ->(l : RNS::Link) { client_disconnected(l) }
  )
  link.set_packet_callback(
    ->(message : Bytes, packet : RNS::Packet) {
      server_packet_received(message, packet)
    }
  )
  SpeedtestExample.latest_client_link = link
end

def client_disconnected(link : RNS::Link)
  RNS.log("Client disconnected")
end

# A convenience function for printing a human-
# readable file size
def size_str(num : Float64, suffix : String = "B") : String
  units = ["", "Ki", "Mi", "Gi", "Ti", "Pi", "Ei", "Zi"]
  last_unit = "Yi"

  actual_num = num
  actual_units = units
  if suffix == "b"
    actual_num *= 8
    actual_units = ["", "K", "M", "G", "T", "P", "E", "Z"]
    last_unit = "Y"
  end

  actual_units.each do |unit|
    if actual_num.abs < 1024.0
      return "%3.2f %s%s" % [actual_num, unit, suffix]
    end
    actual_num /= 1024.0
  end
  "%.2f %s%s" % [actual_num, last_unit, suffix]
end

def server_packet_received(message : Bytes, packet : RNS::Packet)
  SpeedtestExample.received_data += packet.data.size

  SpeedtestExample.rc += 1
  if SpeedtestExample.rc >= 50
    RNS.log(size_str(SpeedtestExample.received_data.to_f))
    SpeedtestExample.rc = 0
  end

  if SpeedtestExample.received_data > SpeedtestExample.data_cap
    rcv_d = SpeedtestExample.received_data
    SpeedtestExample.received_data = 0_i64
    SpeedtestExample.rc = 0

    SpeedtestExample.last_packet_at = Time.utc.to_unix_f

    # Print statistics
    download_time = SpeedtestExample.last_packet_at - SpeedtestExample.first_packet_at
    hours = (download_time / 3600).to_i
    rem = download_time % 3600
    minutes = (rem / 60).to_i
    seconds = rem % 60
    timestring = "%02d:%02d:%05.2f" % [hours, minutes, seconds]

    puts ""
    puts ""
    puts "--- Statistics -----"
    puts "\tTime taken       : #{timestring}"
    puts "\tData transferred : #{size_str(rcv_d.to_f)}"
    puts "\tTransfer rate    : #{size_str(rcv_d.to_f / download_time, suffix: "b")}/s"
    puts ""

    STDOUT.flush
    SpeedtestExample.latest_client_link.try &.teardown
    sleep 0.2
    SpeedtestExample.rc = 0
    SpeedtestExample.received_data = 0_i64
  end
end

##########################################################
#### Client Part #########################################
##########################################################

# This initialisation is executed when the user chooses
# to run as a client
def client(destination_hexhash : String, configpath : String?)
  # We need a binary representation of the destination
  # hash that was entered on the command line
  begin
    dest_len = (RNS::Reticulum::TRUNCATED_HASHLENGTH // 8) * 2
    if destination_hexhash.size != dest_len
      raise ArgumentError.new(
        "Destination length is invalid, must be #{dest_len} hexadecimal characters (#{dest_len // 2} bytes)."
      )
    end

    destination_hash = destination_hexhash.hexbytes
  rescue ex
    RNS.log("Invalid destination entered. Check your input!\n")
    exit 0
  end

  # We must first initialise Reticulum
  reticulum = RNS::ReticulumInstance.new(configpath)

  # Check if we know a path to the destination
  unless RNS::Transport.has_path(destination_hash)
    RNS.log("Destination is not yet known. Requesting path and waiting for announce to arrive...")
    RNS::Transport.request_path(destination_hash)
    while !RNS::Transport.has_path(destination_hash)
      sleep 0.1
    end
  end

  # Recall the server identity
  server_identity = RNS::Identity.recall(destination_hash)

  # Inform the user that we'll begin connecting
  RNS.log("Establishing link with server...")

  # When the server identity is known, we set
  # up a destination
  server_destination = RNS::Destination.new(
    server_identity,
    RNS::Destination::OUT,
    RNS::Destination::SINGLE,
    APP_NAME,
    ["speedtest"]
  )

  # And create a link
  link = RNS::Link.new(server_destination)

  # We'll also set up functions to inform the
  # user when the link is established or closed
  link.set_link_established_callback(
    ->(l : RNS::Link) { link_established(l) }
  )
  link.set_link_closed_callback(
    ->(l : RNS::Link) { link_closed(l) }
  )

  # Everything is set up, so let's enter a loop
  # for the user to interact with the example
  client_loop
end

def client_loop
  # Wait for the link to become active
  while SpeedtestExample.server_link.nil?
    sleep 0.1
  end

  SpeedtestExample.should_quit = false
  while !SpeedtestExample.should_quit
    sleep 0.2
  end
end

# This function is called when a link
# has been established with the server
def link_established(link : RNS::Link)
  # We store a reference to the link
  # instance for later use
  SpeedtestExample.server_link = link
  data_sent = 0_i64

  # Inform the user that the server is connected
  RNS.log("Link established with server, sending...")
  rd = Random::Secure.random_bytes(link.mdu)
  started = Time.utc.to_unix_f
  data_cap = SpeedtestExample.data_cap

  while link.status == RNS::Link::ACTIVE && data_sent < (data_cap * 1.25).to_i64
    RNS::Packet.new(link, rd, create_receipt: false).send
    data_sent += rd.size

    if data_sent > data_cap && !SpeedtestExample.printed
      SpeedtestExample.printed = true
      ended = Time.utc.to_unix_f
      # Print statistics
      download_time = ended - started
      hours = (download_time / 3600).to_i
      rem = download_time % 3600
      minutes = (rem / 60).to_i
      seconds = rem % 60
      timestring = "%02d:%02d:%05.2f" % [hours, minutes, seconds]
      puts ""
      puts ""
      puts "--- Statistics -----"
      puts "\tTime taken       : #{timestring}"
      puts "\tData transferred : #{size_str(data_sent.to_f)}"
      puts "\tTransfer rate    : #{size_str(data_sent.to_f / download_time, suffix: "b")}/s"
      puts ""

      STDOUT.flush
      sleep 0.1
    end
  end
end

# When a link is closed, we'll inform the
# user, and exit the program
def link_closed(link : RNS::Link)
  if link.teardown_reason == RNS::Link::TIMEOUT
    RNS.log("The link timed out, exiting now")
  elsif link.teardown_reason == RNS::Link::DESTINATION_CLOSED
    RNS.log("The link was closed by the server, exiting now")
  else
    RNS.log("Link closed, exiting now")
  end

  SpeedtestExample.should_quit = true
  sleep 1.5
  exit 0
end

##########################################################
#### Program Startup #####################################
##########################################################

# This part of the program gets run at startup,
# and parses input from the user, and then starts
# the desired program mode.
begin
  server_mode = false
  configarg : String? = nil
  destination_arg : String? = nil

  i = 0
  while i < ARGV.size
    case ARGV[i]
    when "-s", "--server"
      server_mode = true
    when "--config"
      i += 1
      configarg = ARGV[i]? || abort("--config requires a path argument")
    when "-h", "--help"
      puts "Usage: speedtest [-s] [--config PATH] [DESTINATION]"
      puts ""
      puts "Speedtest example"
      puts ""
      puts "Options:"
      puts "  -s, --server    wait for incoming requests from clients"
      puts "  --config PATH   path to alternative Reticulum config directory"
      puts "  -h, --help      show this help message"
      puts ""
      puts "Arguments:"
      puts "  DESTINATION     hexadecimal hash of the server destination"
      exit 0
    else
      destination_arg = ARGV[i]
    end
    i += 1
  end

  if server_mode
    server(configarg)
  else
    if dest = destination_arg
      client(dest, configarg)
    else
      puts ""
      puts "Usage: speedtest [-s] [--config PATH] [DESTINATION]"
      puts ""
    end
  end
rescue ex : Exception
  if ex.message == "Interrupted"
    puts ""
    exit 0
  end
  raise ex
end
