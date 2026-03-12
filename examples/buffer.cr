##########################################################
# This RNS example demonstrates how to set up a link to  #
# a destination, and pass binary data over it using a    #
# channel buffer.                                        #
##########################################################

require "../src/rns"

# Let's define an app name. We'll use this for all
# destinations we create. Since this echo example
# is part of a range of example utilities, we'll put
# them all within the app namespace "example_utilities"
APP_NAME = "example_utilities"

# We use a module to hold mutable state so callbacks
# can access it.
module BufferExample
  class_property latest_client_link : RNS::Link? = nil
  class_property server_link : RNS::Link? = nil
  class_property server_reader : RNS::RawChannelReader(RNS::Packet)? = nil
  class_property server_writer : RNS::RawChannelWriter(RNS::Packet)? = nil
  class_property client_reader : RNS::RawChannelReader(RNS::Packet)? = nil
  class_property client_writer : RNS::RawChannelWriter(RNS::Packet)? = nil
end

# Helper to create a Channel from a Link.
# Note: Link#get_channel is deferred; create manually.
def create_channel_for(link : RNS::Link) : RNS::Channel(RNS::Packet)
  outlet = RNS::LinkChannelOutlet.new(link)
  RNS::Channel(RNS::Packet).new(outlet)
end

##########################################################
#### Server Part #########################################
##########################################################

# This initialisation is executed when the user chooses
# to run as a server
def server(configpath : String?)
  # We must first initialise Reticulum
  reticulum = RNS::ReticulumInstance.new(configpath)

  # Randomly create a new identity for our example
  server_identity = RNS::Identity.new

  # We create a destination that clients can connect to. We
  # want clients to create links to this destination, so we
  # need to create a "single" destination type.
  server_destination = RNS::Destination.new(
    server_identity,
    RNS::Destination::IN,
    RNS::Destination::SINGLE,
    APP_NAME,
    ["bufferexample"]
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
    "Link buffer example " +
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
  BufferExample.latest_client_link = link

  RNS.log("Client connected")
  link.set_link_closed_callback(
    ->(l : RNS::Link) { client_disconnected(l) }
  )

  # If a new connection is received, the old reader
  # needs to be disconnected.
  BufferExample.server_reader.try &.close

  # Create buffer objects.
  #   The stream_id parameter to these functions is
  #   a bit like a file descriptor, except that it
  #   is unique to the *receiver*.
  #
  #   In this example, both the reader and the writer
  #   use stream_id = 0, but there are actually two
  #   separate unidirectional streams flowing in
  #   opposite directions.
  channel = create_channel_for(link)
  reader, writer = RNS::Buffer.create_bidirectional_buffer(
    0, 0, channel,
    ready_callback: ->(ready_bytes : Int32) {
      server_buffer_ready(ready_bytes)
      nil
    }
  )
  BufferExample.server_reader = reader
  BufferExample.server_writer = writer
end

def client_disconnected(link : RNS::Link)
  RNS.log("Client disconnected")
end

def server_buffer_ready(ready_bytes : Int32)
  if reader = BufferExample.server_reader
    data = reader.read(ready_bytes)
    if data
      text = String.new(data)
      RNS.log("Received data over the buffer: " + text)

      if writer = BufferExample.server_writer
        reply_message = "I received \"" + text + "\" over the buffer"
        writer.write(reply_message.to_slice)
      end
    end
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
    ["bufferexample"]
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
  while BufferExample.server_link.nil?
    sleep(100.milliseconds)
  end

  should_quit = false
  while !should_quit
    begin
      print "> "
      text = gets

      if text.nil?
        should_quit = true
        BufferExample.server_link.try &.teardown
        next
      end

      # Check if we should quit the example
      if text == "quit" || text == "q" || text == "exit"
        should_quit = true
        BufferExample.server_link.try &.teardown
      else
        # Otherwise, encode the text and write it to the buffer.
        if writer = BufferExample.client_writer
          writer.write(text.to_slice)
        end
      end
    rescue ex
      RNS.log("Error while sending data over the link buffer: " + ex.to_s)
      should_quit = true
      BufferExample.server_link.try &.teardown
    end
  end
end

# This function is called when a link
# has been established with the server
def link_established(link : RNS::Link)
  # We store a reference to the link
  # instance for later use
  BufferExample.server_link = link

  # Create buffer, see client_connected() for
  # more detail about setting up the buffer.
  channel = create_channel_for(link)
  reader, writer = RNS::Buffer.create_bidirectional_buffer(
    0, 0, channel,
    ready_callback: ->(ready_bytes : Int32) {
      client_buffer_ready(ready_bytes)
      nil
    }
  )
  BufferExample.client_reader = reader
  BufferExample.client_writer = writer

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

# When the buffer has new data, read it and write it to the terminal.
def client_buffer_ready(ready_bytes : Int32)
  if reader = BufferExample.client_reader
    data = reader.read(ready_bytes)
    if data
      RNS.log("Received data over the link buffer: " + String.new(data))
      print "> "
      STDOUT.flush
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
      puts "Usage: buffer [-s] [--config PATH] [DESTINATION]"
      puts ""
      puts "Simple buffer example"
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
      puts "Usage: buffer [-s] [--config PATH] [DESTINATION]"
      puts ""
    end
  end
end
