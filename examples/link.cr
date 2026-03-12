##########################################################
# This RNS example demonstrates how to set up a link to  #
# a destination, and pass data back and forth over it.   #
##########################################################

require "../src/rns"

# Let's define an app name. We'll use this for all
# destinations we create. Since this echo example
# is part of a range of example utilities, we'll put
# them all within the app namespace "example_utilities"
APP_NAME = "example_utilities"

# We use a module to hold mutable state so callbacks
# can access it.
module LinkExample
  class_property latest_client_link : RNS::Link? = nil
  class_property server_link : RNS::Link? = nil
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
    ["linkexample"]
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
    "Link example " +
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
  link.set_link_closed_callback(
    ->(l : RNS::Link) { client_disconnected(l) }
  )
  link.set_packet_callback(
    ->(message : Bytes, packet : RNS::Packet) {
      server_packet_received(message, packet)
    }
  )
  LinkExample.latest_client_link = link
end

def client_disconnected(link : RNS::Link)
  RNS.log("Client disconnected")
end

def server_packet_received(message : Bytes, packet : RNS::Packet)
  # When data is received over any active link,
  # it will all be directed to the last client
  # that connected.
  text = String.new(message)
  RNS.log("Received data on the link: " + text)

  if client_link = LinkExample.latest_client_link
    reply_text = "I received \"" + text + "\" over the link"
    RNS::Packet.new(client_link, reply_text.to_slice).send
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
    RNS.log("Invalid destination entered. Check your input!")
    RNS.log("#{ex.message}\n")
    exit 0
  end

  # We must first initialise Reticulum
  reticulum = RNS::ReticulumInstance.new(configpath)

  # Check if we know a path to the destination
  unless RNS::Transport.has_path(destination_hash)
    RNS.log("Destination is not yet known. Requesting path and waiting for announce to arrive...")
    RNS::Transport.request_path(destination_hash)
    while !RNS::Transport.has_path(destination_hash)
      sleep(100.milliseconds)
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
    ["linkexample"]
  )

  # And create a link
  link = RNS::Link.new(server_destination)

  # We set a callback that will get executed
  # every time a packet is received over the link
  link.set_packet_callback(
    ->(message : Bytes, packet : RNS::Packet) {
      client_packet_received(message, packet)
    }
  )

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
  while LinkExample.server_link.nil?
    sleep(100.milliseconds)
  end

  should_quit = false
  while !should_quit
    begin
      print "> "
      text = gets

      if text.nil?
        should_quit = true
        LinkExample.server_link.try &.teardown
        next
      end

      # Check if we should quit the example
      if text == "quit" || text == "q" || text == "exit"
        should_quit = true
        LinkExample.server_link.try &.teardown
      end

      # If not, send the entered text over the link
      if text != "" && !should_quit
        data = text.to_slice
        if data.size <= RNS::Link::MDU
          if link = LinkExample.server_link
            RNS::Packet.new(link, data).send
          end
        else
          RNS.log(
            "Cannot send this packet, the data size of " +
            data.size.to_s + " bytes exceeds the link packet MDU of " +
            RNS::Link::MDU.to_s + " bytes",
            RNS::LOG_ERROR
          )
        end
      end
    rescue ex
      RNS.log("Error while sending data over the link: " + ex.to_s)
      should_quit = true
      LinkExample.server_link.try &.teardown
    end
  end
end

# This function is called when a link
# has been established with the server
def link_established(link : RNS::Link)
  # We store a reference to the link
  # instance for later use
  LinkExample.server_link = link

  # Inform the user that the server is connected
  RNS.log("Link established with server, enter some text to send, or \"quit\" to quit")
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

  sleep(1.5.seconds)
  exit 0
end

# When a packet is received over the link, we
# simply print out the data.
def client_packet_received(message : Bytes, packet : RNS::Packet)
  text = String.new(message)
  RNS.log("Received data on the link: " + text)
  print "> "
  STDOUT.flush
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
      puts "Usage: link [-s] [--config PATH] [DESTINATION]"
      puts ""
      puts "Simple link example"
      puts ""
      puts "Options:"
      puts "  -s, --server    wait for incoming link requests from clients"
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
      puts "Usage: link [-s] [--config PATH] [DESTINATION]"
      puts ""
    end
  end
end
