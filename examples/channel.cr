##########################################################
# This RNS example demonstrates how to set up a link to  #
# a destination, and pass structured messages over it    #
# using a channel.                                       #
##########################################################

require "../src/rns"
require "msgpack"

# Let's define an app name. We'll use this for all
# destinations we create. Since this echo example
# is part of a range of example utilities, we'll put
# them all within the app namespace "example_utilities"
APP_NAME = "example_utilities"

##########################################################
#### Shared Objects ######################################
##########################################################

# Channel data must be structured in a subclass of
# MessageBase. This ensures that the channel will be able
# to serialize and deserialize the object and multiplex it
# with other objects. Both ends of a link will need the
# same object definitions to be able to communicate over
# a channel.

# Let's make a simple message class called StringMessage
# that will convey a string with a timestamp.

class StringMessage < RNS::MessageBase
  # The MSGTYPE class variable needs to be assigned a
  # 2 byte integer value. This identifier allows the
  # channel to look up your message's constructor when a
  # message arrives over the channel.
  #
  # MSGTYPE must be unique across all message types we
  # register with the channel. MSGTYPEs >= 0xf000 are
  # reserved for the system.
  class_getter msgtype : UInt16 = 0x0101_u16

  property data : String?
  property timestamp : Time

  def initialize(@data : String? = nil)
    @timestamp = Time.utc
  end

  # The pack function encodes the message contents into
  # a byte stream.
  def pack : Bytes
    {data: @data, timestamp: @timestamp.to_unix_f}.to_msgpack
  end

  # And the unpack function decodes a byte stream into
  # the message contents.
  def unpack(raw : Bytes)
    unpacked = MessagePack::IOUnpacker.new(IO::Memory.new(raw))
    result = unpacked.read
    if result.is_a?(Hash)
      if d = result["data"]?
        @data = d.as_s? || d.to_s
      end
      if ts = result["timestamp"]?
        @timestamp = Time.unix_ms((ts.as_f * 1000).to_i64)
      end
    end
  end
end

# We use a module to hold mutable state so callbacks
# can access it.
module ChannelExample
  class_property latest_client_link : RNS::Link? = nil
  class_property server_link : RNS::Link? = nil
  class_property server_channel : RNS::Channel(RNS::Packet)? = nil
  class_property client_channel : RNS::Channel(RNS::Packet)? = nil
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
    ["channelexample"]
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
    "Channel example " +
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
  ChannelExample.latest_client_link = link

  RNS.log("Client connected")
  link.set_link_closed_callback(
    ->(l : RNS::Link) { client_disconnected(l) }
  )

  # Register message types and add callback to channel
  channel = create_channel_for(link)
  channel.register_message_type(StringMessage)
  channel.add_message_handler(
    ->(message : RNS::MessageBase) {
      server_message_received(message)
    }
  )
  ChannelExample.server_channel = channel
end

def client_disconnected(link : RNS::Link)
  RNS.log("Client disconnected")
end

def server_message_received(message : RNS::MessageBase) : Bool
  # In a message handler, any deserializable message
  # that arrives over the link's channel will be passed
  # to all message handlers, unless a preceding handler
  # indicates it has handled the message.
  if message.is_a?(StringMessage)
    data = message.data || ""
    RNS.log("Received data on the link: " + data + " (message created at " + message.timestamp.to_s + ")")

    reply_message = StringMessage.new("I received \"" + data + "\" over the link")
    if ch = ChannelExample.server_channel
      ch.send(reply_message)
    end

    # Returning true indicates the message was handled
    # and subsequent handlers should be skipped.
    return true
  end

  false
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
    ["channelexample"]
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
  while ChannelExample.server_link.nil?
    sleep 0.1
  end

  should_quit = false
  while !should_quit
    begin
      print "> "
      text = gets

      if text.nil?
        should_quit = true
        ChannelExample.server_link.try &.teardown
        next
      end

      # Check if we should quit the example
      if text == "quit" || text == "q" || text == "exit"
        should_quit = true
        ChannelExample.server_link.try &.teardown
      end

      # If not, send the entered text over the channel
      if text != "" && !should_quit
        message = StringMessage.new(text)
        packed_size = message.pack.size
        if channel = ChannelExample.client_channel
          if channel.is_ready_to_send?
            if packed_size <= channel.mdu
              channel.send(message)
            else
              RNS.log(
                "Cannot send this packet, the data size of " +
                packed_size.to_s + " bytes exceeds the channel MDU of " +
                channel.mdu.to_s + " bytes",
                RNS::LOG_ERROR
              )
            end
          else
            RNS.log("Channel is not ready to send, please wait for " +
                     "pending messages to complete.", RNS::LOG_ERROR)
          end
        end
      end
    rescue ex
      RNS.log("Error while sending data over the link: " + ex.to_s)
      should_quit = true
      ChannelExample.server_link.try &.teardown
    end
  end
end

# This function is called when a link
# has been established with the server
def link_established(link : RNS::Link)
  # We store a reference to the link
  # instance for later use
  ChannelExample.server_link = link

  # Register messages and add handler to channel
  channel = create_channel_for(link)
  channel.register_message_type(StringMessage)
  channel.add_message_handler(
    ->(message : RNS::MessageBase) {
      client_message_received(message)
    }
  )
  ChannelExample.client_channel = channel

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

  sleep 1.5
  exit 0
end

# When a message is received over the channel, we
# simply print out the data.
def client_message_received(message : RNS::MessageBase) : Bool
  if message.is_a?(StringMessage)
    data = message.data || ""
    RNS.log("Received data on the link: " + data + " (message created at " + message.timestamp.to_s + ")")
    print "> "
    STDOUT.flush
  end

  false
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
      puts "Usage: channel [-s] [--config PATH] [DESTINATION]"
      puts ""
      puts "Simple channel example"
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
      puts "Usage: channel [-s] [--config PATH] [DESTINATION]"
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
