# Handle the higher-level logic of downloading and seeding torrent files.

module Torrent

class Client
  @torrent_file = nil

  def initialize(file) 
    require_relative "bencode"
    require_relative "metainfo"
    require_relative "peer"
    require_relative "tracker"
    
    @torrent_file = File.open(file, "r")
  end
  
  def runClient
    metainfo = Metainfo.new(@torrent_file)
    tracker = Tracker.new(metainfo)
    tracker.sendRequest("started")
    peer = Peer.new(tracker)
    peer.handshake(ARGV[1].to_i)
  end
end

unless ARGV.length == 2
  abort("Invalid number of arguments. Usage: ruby client.rb [file] [peer]")
end

client = Client.new(ARGV[0])
client.runClient

end
