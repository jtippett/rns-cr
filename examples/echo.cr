##########################################################
# This RNS example demonstrates a simple client/server   #
# echo utility. A client can send an echo request to the #
# server, and the server will respond by proving receipt #
# of the packet.                                         #
##########################################################

require "../src/rns"

# Let's define an app name. We'll use this for all
# destinations we create. Since this echo example
# is part of a range of example utilities, we'll put
# them all within the app namespace "example_utilities"
APP_NAME = "example_utilities"

# We use a module to hold the reticulum instance reference
# so callbacks can access it for signal stats.
module EchoExample
  class_property reticulum : RNS::ReticulumInstance? = nil
end

##########################################################
#### Server Part #########################################
##########################################################

# This initialisation is executed when the user chooses
# to run as a server
def server(configpath : String?)
  # We must first initialise Reticulum
  EchoExample.reticulum = RNS::ReticulumInstance.new(configpath)

  # Randomly create a new identity for our echo server
  server_identity = RNS::Identity.new

  # We create a destination that clients can query. We want
  # to be able to verify echo replies to our clients, so we
  # create a "single" destination that can receive encrypted
  # messages. This way the client can send a request and be
  # certain that no-one else than this destination was able
  # to read it.
  echo_destination = RNS::Destination.new(
    server_identity,
    RNS::Destination::IN,
    RNS::Destination::SINGLE,
    APP_NAME,
    ["echo", "request"]
  )

  # We configure the destination to automatically prove all
  # packets addressed to it. By doing this, RNS will automatically
  # generate a proof for each incoming packet and transmit it
  # back to the sender of that packet.
  echo_destination.set_proof_strategy(RNS::Destination::PROVE_ALL)

  # Tell the destination which function in our program to
  # run when a packet is received. We do this so we can
  # print a log message when the server receives a request
  echo_destination.set_packet_callback(
    ->(message : Bytes, packet : RNS::Packet) {
      server_callback(message, packet)
    }
  )

  # Everything's ready!
  # Let's wait for client requests or user input
  announce_loop(echo_destination)
end

def announce_loop(destination : RNS::Destination)
  # Let the user know that everything is ready
  RNS.log(
    "Echo server " +
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

def server_callback(message : Bytes, packet : RNS::Packet)
  # Tell the user that we received an echo request, and
  # that we are going to send a reply to the requester.
  # Sending the proof is handled automatically, since we
  # set up the destination to prove all incoming packets.

  reception_stats = ""
  ret = EchoExample.reticulum

  if ret && ret.is_connected_to_shared_instance
    # When connected to a shared instance, retrieve stats
    # from the shared instance (not yet implemented)
  else
    if rssi = packet.rssi
      reception_stats += " [RSSI #{rssi} dBm]"
    end

    if snr = packet.snr
      reception_stats += " [SNR #{snr} dB]"
    end
  end

  RNS.log("Received packet from echo client, proof sent" + reception_stats)
end

##########################################################
#### Client Part #########################################
##########################################################

# This initialisation is executed when the user chooses
# to run as a client
def client(destination_hexhash : String, configpath : String?, timeout : Float64? = nil)
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
  EchoExample.reticulum = RNS::ReticulumInstance.new(configpath)

  # We override the loglevel to provide feedback when
  # an announce is received
  if RNS.loglevel < RNS::LOG_INFO
    RNS.loglevel = RNS::LOG_INFO
  end

  # Tell the user that the client is ready!
  RNS.log(
    "Echo client ready, hit enter to send echo request to " +
    destination_hexhash +
    " (Ctrl-C to quit)"
  )

  # We enter a loop that runs until the user exits.
  # If the user hits enter, we will try to send an
  # echo request to the destination specified on the
  # command line.
  loop do
    gets

    # Let's first check if RNS knows a path to the destination.
    # If it does, we'll load the server identity and create a packet
    if RNS::Transport.has_path(destination_hash)
      # To address the server, we need to know its public
      # key, so we check if Reticulum knows this destination.
      # This is done by calling the "recall" method of the
      # Identity module. If the destination is known, it will
      # return an Identity instance that can be used in
      # outgoing destinations.
      server_identity = RNS::Identity.recall(destination_hash)

      if server_identity
        # We got the correct identity instance from the
        # recall method, so let's create an outgoing
        # destination. We use the naming convention:
        # example_utilities.echo.request
        # This matches the naming we specified in the
        # server part of the code.
        request_destination = RNS::Destination.new(
          server_identity,
          RNS::Destination::OUT,
          RNS::Destination::SINGLE,
          APP_NAME,
          ["echo", "request"]
        )

        # The destination is ready, so let's create a packet.
        # We set the destination to the request_destination
        # that was just created, and the only data we add
        # is a random hash.
        echo_request = RNS::Packet.new(request_destination, RNS::Identity.get_random_hash)

        # Send the packet! If the packet is successfully
        # sent, it will return a PacketReceipt instance.
        echo_request.send

        # If the user specified a timeout, we set this
        # timeout on the packet receipt, and configure
        # a callback function, that will get called if
        # the packet times out.
        if receipt = echo_request.receipt
          if t = timeout
            receipt.set_timeout(t)
            receipt.set_timeout_callback(
              ->(r : RNS::PacketReceipt) { packet_timed_out(r) }
            )
          end

          # We can then set a delivery callback on the receipt.
          # This will get automatically called when a proof for
          # this specific packet is received from the destination.
          receipt.set_delivery_callback(
            ->(r : RNS::PacketReceipt) { packet_delivered(r) }
          )
        end

        # Tell the user that the echo request was sent
        RNS.log("Sent echo request to " + RNS.prettyhexrep(request_destination.hash))
      end
    else
      # If we do not know this destination, tell the
      # user to wait for an announce to arrive.
      RNS.log("Destination is not yet known. Requesting path...")
      RNS.log("Hit enter to manually retry once an announce is received.")
      RNS::Transport.request_path(destination_hash)
    end
  end
end

# This function is called when our reply destination
# receives a proof packet.
def packet_delivered(receipt : RNS::PacketReceipt)
  if receipt.status == RNS::PacketReceipt::DELIVERED
    rtt = receipt.get_rtt
    if rtt >= 1.0
      rtt = rtt.round(3)
      rttstring = "#{rtt} seconds"
    else
      rtt = (rtt * 1000).round(3)
      rttstring = "#{rtt} milliseconds"
    end

    reception_stats = ""
    ret = EchoExample.reticulum

    if ret && ret.is_connected_to_shared_instance
      # Signal stats from shared instance (not yet implemented)
    else
      if proof_packet = receipt.proof_packet
        if rssi = proof_packet.rssi
          reception_stats += " [RSSI #{rssi} dBm]"
        end

        if snr = proof_packet.snr
          reception_stats += " [SNR #{snr} dB]"
        end
      end
    end

    dest = receipt.destination
    dest_hash = dest ? dest.hash : Bytes.new(0)
    RNS.log(
      "Valid reply received from " +
      RNS.prettyhexrep(dest_hash) +
      ", round-trip time is " + rttstring +
      reception_stats
    )
  end
end

# This function is called if a packet times out.
def packet_timed_out(receipt : RNS::PacketReceipt)
  if receipt.status == RNS::PacketReceipt::FAILED
    RNS.log("Packet " + RNS.prettyhexrep(receipt.hash) + " timed out")
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
  timeoutarg : Float64? = nil
  destination_arg : String? = nil

  i = 0
  while i < ARGV.size
    case ARGV[i]
    when "-s", "--server"
      server_mode = true
    when "-t", "--timeout"
      i += 1
      timeoutarg = (ARGV[i]? || abort("--timeout requires a value")).to_f
    when "--config"
      i += 1
      configarg = ARGV[i]? || abort("--config requires a path argument")
    when "-h", "--help"
      puts "Usage: echo [-s] [-t TIMEOUT] [--config PATH] [DESTINATION]"
      puts ""
      puts "Simple echo server and client utility"
      puts ""
      puts "Options:"
      puts "  -s, --server       wait for incoming packets from clients"
      puts "  -t, --timeout SEC  set a reply timeout in seconds"
      puts "  --config PATH      path to alternative Reticulum config directory"
      puts "  -h, --help         show this help message"
      puts ""
      puts "Arguments:"
      puts "  DESTINATION        hexadecimal hash of the server destination"
      exit 0
    else
      destination_arg = ARGV[i]
    end
    i += 1
  end

  if server_mode
    server(configarg)
  else
    if destination_arg
      client(destination_arg, configarg, timeout: timeoutarg)
    else
      puts ""
      puts "Usage: echo [-s] [-t TIMEOUT] [--config PATH] [DESTINATION]"
      puts ""
    end
  end
end
