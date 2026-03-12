##########################################################
# This RNS example demonstrates a simple filetransfer    #
# server and client program. The server will serve a     #
# directory of files, and the clients can list and       #
# download files from the server.                        #
#                                                        #
# Please note that using RNS Resources for large file    #
# transfers is not recommended, since compression,       #
# encryption and hashmap sequencing can take a long time  #
# on systems with slow CPUs, which will probably result  #
# in the client timing out before the resource sender    #
# can complete preparing the resource.                   #
#                                                        #
# If you need to transfer large files, use the Bundle    #
# class instead, which will automatically slice the data #
# into chunks suitable for packing as a Resource.        #
##########################################################

require "../src/rns"
require "msgpack"

# Let's define an app name. We'll use this for all
# destinations we create. Since this echo example
# is part of a range of example utilities, we'll put
# them all within the app namespace "example_utilities"
APP_NAME = "example_utilities"

# We'll also define a default timeout, in seconds
APP_TIMEOUT = 45.0

# We use a module to hold mutable state so callbacks
# can access it.
module FiletransferExample
  class_property serve_path : String? = nil
  class_property latest_client_link : RNS::Link? = nil
  class_property server_files : Array(String) = [] of String
  class_property server_link : RNS::Link? = nil
  class_property current_download : RNS::Resource? = nil
  class_property current_filename : String? = nil
  class_property menu_mode : String? = nil
  class_property download_started : Float64 = 0.0
  class_property download_finished : Float64 = 0.0
  class_property download_time : Float64 = 0.0
  class_property transfer_size : Int64 = 0_i64
  class_property file_size : Int64 = 0_i64
end

##########################################################
#### Server Part #########################################
##########################################################

# This initialisation is executed when the user chooses
# to run as a server
def server(configpath : String?, path : String)
  # We must first initialise Reticulum
  reticulum = RNS::ReticulumInstance.new(configpath)

  # Randomly create a new identity for our file server
  server_identity = RNS::Identity.new

  FiletransferExample.serve_path = path

  # We create a destination that clients can connect to. We
  # want clients to create links to this destination, so we
  # need to create a "single" destination type.
  server_destination = RNS::Destination.new(
    server_identity,
    RNS::Destination::IN,
    RNS::Destination::SINGLE,
    APP_NAME,
    ["filetransfer", "server"]
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
  announce_loop(server_destination)
end

def announce_loop(destination : RNS::Destination)
  # Let the user know that everything is ready
  RNS.log("File server " + RNS.prettyhexrep(destination.hash) + " running")
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

# Here's a convenience function for listing all files
# in our served directory
def list_files : Array(String)
  path = FiletransferExample.serve_path
  return [] of String unless path

  Dir.entries(path).select { |file|
    full_path = File.join(path, file)
    File.file?(full_path) && !file.starts_with?(".")
  }.sort
end

# When a client establishes a link to our server
# destination, this function will be called with
# a reference to the link. We then send the client
# a list of files hosted on the server.
def client_connected(link : RNS::Link)
  path = FiletransferExample.serve_path
  FiletransferExample.latest_client_link = link

  # Check if the served directory still exists
  if path && Dir.exists?(path)
    RNS.log("Client connected, sending file list...")

    link.set_link_closed_callback(
      ->(l : RNS::Link) { client_disconnected(l) }
    )

    # We pack a list of files for sending in a packet
    files = list_files
    data = files.to_msgpack

    # Check the size of the packed data
    if data.size <= RNS::Link::MDU
      # If it fits in one packet, we will just
      # send it as a single packet over the link.
      list_packet = RNS::Packet.new(link, data)
      list_packet.send

      if receipt = list_packet.receipt
        receipt.set_timeout(APP_TIMEOUT)
        receipt.set_delivery_callback(
          ->(r : RNS::PacketReceipt) {
            RNS.log("The file list was received by the client")
          }
        )
        receipt.set_timeout_callback(
          ->(r : RNS::PacketReceipt) {
            RNS.log("Sending list to client timed out, closing this link")
            FiletransferExample.latest_client_link.try &.teardown
          }
        )
      end
    else
      RNS.log("Too many files in served directory!", RNS::LOG_ERROR)
      RNS.log("You should implement a function to split the filelist over multiple packets.", RNS::LOG_ERROR)
      RNS.log("Hint: The client already supports it :)", RNS::LOG_ERROR)
    end

    # After this, we're just going to keep the link
    # open until the client requests a file. We'll
    # configure a function that gets called when
    # the client sends a packet with a file request.
    link.set_packet_callback(
      ->(message : Bytes, packet : RNS::Packet) {
        client_request(message, packet)
      }
    )
  else
    RNS.log("Client connected, but served path no longer exists!", RNS::LOG_ERROR)
    link.teardown
  end
end

def client_disconnected(link : RNS::Link)
  RNS.log("Client disconnected")
end

def client_request(message : Bytes, packet : RNS::Packet)
  filename = String.new(message) rescue nil

  if filename && list_files.includes?(filename)
    begin
      # If we have the requested file, we'll
      # read it and pack it as a resource
      RNS.log("Client requested \"#{filename}\"")
      path = FiletransferExample.serve_path
      link = FiletransferExample.latest_client_link
      if path && link
        file_data = File.read(File.join(path, filename)).to_slice
        file_resource = RNS::Resource.new(
          file_data,
          link,
          callback: ->(r : RNS::Resource) {
            resource_sending_concluded(r, filename)
            nil
          }
        )
      end
    rescue ex
      # If something went wrong, we close the link
      RNS.log("Error while reading file \"#{filename}\"", RNS::LOG_ERROR)
      FiletransferExample.latest_client_link.try &.teardown
    end
  else
    # If we don't have it, we close the link
    RNS.log("Client requested an unknown file")
    FiletransferExample.latest_client_link.try &.teardown
  end
end

# This function is called on the server when a
# resource transfer concludes.
def resource_sending_concluded(resource : RNS::Resource, name : String)
  if resource.status == RNS::Resource::COMPLETE
    RNS.log("Done sending \"#{name}\" to client")
  elsif resource.status == RNS::Resource::FAILED
    RNS.log("Sending \"#{name}\" to client failed")
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
    ["filetransfer", "server"]
  )

  # We also want to automatically prove incoming packets
  server_destination.set_proof_strategy(RNS::Destination::PROVE_ALL)

  # And create a link
  link = RNS::Link.new(server_destination)

  # We expect any normal data packets on the link
  # to contain a list of served files, so we set
  # a callback accordingly
  link.set_packet_callback(
    ->(message : Bytes, packet : RNS::Packet) {
      filelist_received(message, packet)
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

  # And set the link to automatically begin
  # downloading advertised resources
  link.set_resource_strategy(RNS::Link::ACCEPT_ALL)
  link.set_resource_started_callback(
    ->(resource : RNS::Resource) {
      RNS.log("Download started for resource " + RNS.prettyhexrep(resource.hash))
    }
  )
  link.set_resource_concluded_callback(
    ->(resource : RNS::Resource) {
      RNS.log("Download concluded for resource " + RNS.prettyhexrep(resource.hash))
    }
  )

  menu
end

# Requests the specified file from the server
def download(filename : String)
  FiletransferExample.current_filename = filename
  FiletransferExample.download_started = 0.0
  FiletransferExample.transfer_size = 0_i64

  # We just create a packet containing the
  # requested filename, and send it down the
  # link. We also specify we don't need a
  # packet receipt.
  if link = FiletransferExample.server_link
    request_packet = RNS::Packet.new(link, filename.to_slice, create_receipt: false)
    request_packet.send
  end

  puts ""
  puts "Requested \"#{filename}\" from server, waiting for download to begin..."
  FiletransferExample.menu_mode = "download_started"
end

# This function runs a simple menu for the user
# to select which files to download, or quit
def menu
  # Wait until we have a filelist
  while FiletransferExample.server_files.empty?
    sleep(100.milliseconds)
  end
  RNS.log("Ready!")
  sleep(500.milliseconds)

  FiletransferExample.menu_mode = "main"
  should_quit = false
  while !should_quit
    print_menu

    while FiletransferExample.menu_mode != "main"
      sleep(250.milliseconds)
    end

    user_input = gets
    if user_input.nil? || user_input == "q" || user_input == "quit" || user_input == "exit"
      should_quit = true
      puts ""
    else
      if FiletransferExample.server_files.includes?(user_input)
        download(user_input)
      else
        idx = user_input.to_i? rescue nil
        if idx && idx >= 0 && idx < FiletransferExample.server_files.size
          download(FiletransferExample.server_files[idx])
        end
      end
    end
  end

  FiletransferExample.server_link.try &.teardown
end

# Prints out menus or screens for the
# various states of the client program.
def print_menu
  mode = FiletransferExample.menu_mode

  if mode == "main"
    clear_screen
    print_filelist
    puts ""
    puts "Select a file to download by entering name or number, or q to quit"
    print "> "
    STDOUT.flush
  elsif mode == "download_started"
    download_began_at = Time.utc.to_unix_f
    while FiletransferExample.menu_mode == "download_started"
      sleep(100.milliseconds)
      if Time.utc.to_unix_f > download_began_at + APP_TIMEOUT
        puts "The download timed out"
        sleep(1.second)
        FiletransferExample.server_link.try &.teardown
      end
    end
  end

  if FiletransferExample.menu_mode == "downloading"
    puts "Download started"
    puts ""
    while FiletransferExample.menu_mode == "downloading"
      if dl = FiletransferExample.current_download
        percent = (dl.get_progress * 100.0).round(1)
        print "\rProgress: #{percent} %   "
        STDOUT.flush
      end
      sleep(100.milliseconds)
    end
  end

  if FiletransferExample.menu_mode == "save_error"
    print "\rProgress: 100.0 %"
    STDOUT.flush
    puts ""
    puts "Could not write downloaded file to disk"
    FiletransferExample.menu_mode = "download_concluded"
  end

  if FiletransferExample.menu_mode == "download_concluded"
    dl = FiletransferExample.current_download
    if dl && dl.status == RNS::Resource::COMPLETE
      print "\rProgress: 100.0 %"
      STDOUT.flush

      # Print statistics
      dt = FiletransferExample.download_time
      hours = (dt / 3600).to_i
      rem = dt % 3600
      minutes = (rem / 60).to_i
      seconds = rem % 60
      timestring = "%02d:%02d:%05.2f" % [hours, minutes, seconds]

      puts ""
      puts ""
      puts "--- Statistics -----"
      puts "\tTime taken       : #{timestring}"
      puts "\tFile size        : #{size_str(FiletransferExample.file_size.to_f)}"
      puts "\tData transferred : #{size_str(FiletransferExample.transfer_size.to_f)}"
      puts "\tEffective rate   : #{size_str(FiletransferExample.file_size.to_f / dt, suffix: "b")}/s"
      puts "\tTransfer rate    : #{size_str(FiletransferExample.transfer_size.to_f / dt, suffix: "b")}/s"
      puts ""
      puts "The download completed! Press enter to return to the menu."
      puts ""
      gets
    else
      puts ""
      puts "The download failed! Press enter to return to the menu."
      gets
    end

    FiletransferExample.current_download = nil
    FiletransferExample.menu_mode = "main"
    print_menu
  end
end

# This function prints out a list of files
# on the connected server.
def print_filelist
  puts "Files on server:"
  FiletransferExample.server_files.each_with_index do |file, index|
    puts "\t(#{index})\t#{file}"
  end
end

def filelist_received(filelist_data : Bytes, packet : RNS::Packet)
  begin
    # Unpack the list and extend our
    # local list of available files
    unpacked = Array(MessagePack::Any).from_msgpack(filelist_data)
    unpacked.each do |file|
      filename = file.as_s
      unless FiletransferExample.server_files.includes?(filename)
        FiletransferExample.server_files << filename
      end
    end

    # If the menu is already visible,
    # we'll update it with what was
    # just received
    if FiletransferExample.menu_mode == "main"
      print_menu
    end
  rescue
    RNS.log("Invalid file list data received, closing link")
    FiletransferExample.server_link.try &.teardown
  end
end

# This function is called when a link
# has been established with the server
def link_established(link : RNS::Link)
  # We store a reference to the link
  # instance for later use
  FiletransferExample.server_link = link

  # Inform the user that the server is connected
  RNS.log("Link established with server")
  RNS.log("Waiting for filelist...")

  # And set up a small job to check for
  # a potential timeout in receiving the
  # file list
  spawn do
    sleep(APP_TIMEOUT.seconds)
    if FiletransferExample.server_files.empty?
      RNS.log("Timed out waiting for filelist, exiting")
      exit 0
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

  sleep(1.5.seconds)
  exit 0
end

# When RNS detects that the download has
# started, we'll update our menu state
# so the user can be shown a progress of
# the download.
def download_began(resource : RNS::Resource)
  FiletransferExample.current_download = resource

  if FiletransferExample.download_started == 0.0
    FiletransferExample.download_started = Time.utc.to_unix_f
  end

  FiletransferExample.transfer_size += resource.size
  FiletransferExample.file_size = resource.total_size

  FiletransferExample.menu_mode = "downloading"
end

# When the download concludes, successfully
# or not, we'll update our menu state and
# inform the user about how it all went.
def download_concluded(resource : RNS::Resource)
  FiletransferExample.download_finished = Time.utc.to_unix_f
  FiletransferExample.download_time = FiletransferExample.download_finished - FiletransferExample.download_started

  saved_filename = FiletransferExample.current_filename

  if resource.status == RNS::Resource::COMPLETE && saved_filename
    counter = 0
    actual_filename = saved_filename
    while File.exists?(actual_filename)
      counter += 1
      actual_filename = "#{saved_filename}.#{counter}"
    end

    begin
      if data = resource.data
        File.write(actual_filename, data)
        FiletransferExample.menu_mode = "download_concluded"
      else
        FiletransferExample.menu_mode = "save_error"
      end
    rescue
      FiletransferExample.menu_mode = "save_error"
    end
  else
    FiletransferExample.menu_mode = "download_concluded"
  end
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

# A convenience function for clearing the screen
def clear_screen
  system("clear")
end

##########################################################
#### Program Startup #####################################
##########################################################

# This part of the program gets run at startup,
# and parses input from the user, and then starts
# the desired program mode.
begin
  serve_dir : String? = nil
  configarg : String? = nil
  destination_arg : String? = nil

  i = 0
  while i < ARGV.size
    case ARGV[i]
    when "-s", "--serve"
      i += 1
      serve_dir = ARGV[i]? || abort("--serve requires a directory argument")
    when "--config"
      i += 1
      configarg = ARGV[i]? || abort("--config requires a path argument")
    when "-h", "--help"
      puts "Usage: filetransfer [-s DIR] [--config PATH] [DESTINATION]"
      puts ""
      puts "Simple file transfer server and client utility"
      puts ""
      puts "Options:"
      puts "  -s, --serve DIR   serve a directory of files to clients"
      puts "  --config PATH     path to alternative Reticulum config directory"
      puts "  -h, --help        show this help message"
      puts ""
      puts "Arguments:"
      puts "  DESTINATION       hexadecimal hash of the server destination"
      exit 0
    else
      destination_arg = ARGV[i]
    end
    i += 1
  end

  if dir = serve_dir
    if Dir.exists?(dir)
      server(configarg, dir)
    else
      RNS.log("The specified directory does not exist")
    end
  else
    if dest = destination_arg
      client(dest, configarg)
    else
      puts ""
      puts "Usage: filetransfer [-s DIR] [--config PATH] [DESTINATION]"
      puts ""
    end
  end
end
