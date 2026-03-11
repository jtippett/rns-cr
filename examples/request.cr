##########################################################
# This RNS example demonstrates how to perform requests  #
# and receive responses over a link.                     #
##########################################################

require "../src/rns"

# Let's define an app name. We'll use this for all
# destinations we create. Since this echo example
# is part of a range of example utilities, we'll put
# them all within the app namespace "example_utilities"
APP_NAME = "example_utilities"

# We use a module to hold mutable state so callbacks
# can access it.
module RequestExample
  class_property latest_client_link : RNS::Link? = nil
  class_property server_link : RNS::Link? = nil
end

##########################################################
#### Server Part #########################################
##########################################################

RANDOM_TEXTS = [
  "They looked up",
  "On each full moon",
  "Becky was upset",
  "I'll stay away from it",
  "The pet shop stocks everything",
]

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
    ["requestexample"]
  )

  # We configure a function that will get called every time
  # a new client creates a link to this destination.
  server_destination.set_link_established_callback(
    ->(link : RNS::Link) {
      client_connected(link)
    }
  )

  # We register a request handler for handling incoming
  # requests over any established links.
  server_destination.register_request_handler(
    "/random/text",
    response_generator: ->(path : String, data : Bytes?, request_id : Bytes, link_id : Bytes, remote_identity : RNS::Identity?, requested_at : Float64) {
      RNS.log("Generating response to request " + RNS.prettyhexrep(request_id) + " on link " + RNS.prettyhexrep(link_id))
      result = RANDOM_TEXTS[Random.rand(RANDOM_TEXTS.size)]
      result.to_slice.as(Bytes?)
    },
    allow: RNS::Destination::ALLOW_ALL
  )

  # Everything's ready!
  # Let's wait for client requests or user input
  server_loop(server_destination)
end

def server_loop(destination : RNS::Destination)
  # Let the user know that everything is ready
  RNS.log(
    "Request example " +
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
  RequestExample.latest_client_link = link
end

def client_disconnected(link : RNS::Link)
  RNS.log("Client disconnected")
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
    ["requestexample"]
  )

  # And create a link
  link = RNS::Link.new(server_destination)

  # We'll set up functions to inform the
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
  while RequestExample.server_link.nil?
    sleep 0.1
  end

  should_quit = false
  while !should_quit
    begin
      print "> "
      text = gets

      if text.nil?
        should_quit = true
        RequestExample.server_link.try &.teardown
        next
      end

      # Check if we should quit the example
      if text == "quit" || text == "q" || text == "exit"
        should_quit = true
        RequestExample.server_link.try &.teardown
      else
        if link = RequestExample.server_link
          link.request(
            "/random/text",
            data: nil,
            response_callback: ->(receipt : RNS::RequestReceipt) {
              got_response(receipt)
              nil
            },
            failed_callback: ->(receipt : RNS::RequestReceipt) {
              request_failed(receipt)
              nil
            }
          )
        end
      end
    rescue ex
      RNS.log("Error while sending request over the link: " + ex.to_s)
      should_quit = true
      RequestExample.server_link.try &.teardown
    end
  end
end

def got_response(request_receipt : RNS::RequestReceipt)
  request_id = request_receipt.request_id
  response = request_receipt.response

  RNS.log("Got response for request " + RNS.prettyhexrep(request_id) + ": " + response.to_s)
end

def request_failed(request_receipt : RNS::RequestReceipt)
  RNS.log("The request " + RNS.prettyhexrep(request_receipt.request_id) + " failed.")
end

# This function is called when a link
# has been established with the server
def link_established(link : RNS::Link)
  # We store a reference to the link
  # instance for later use
  RequestExample.server_link = link

  # Inform the user that the server is connected
  RNS.log("Link established with server, hit enter to perform a request, or type in \"quit\" to quit")
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
      puts "Usage: request [-s] [--config PATH] [DESTINATION]"
      puts ""
      puts "Simple request/response example"
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
      puts "Usage: request [-s] [--config PATH] [DESTINATION]"
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
