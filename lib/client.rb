# Handle the higher-level logic of downloading and seeding torrent files.

require 'thread'

module Torrent

class Client
  @torrent_file = nil

  def initialize(file) 
    require_relative "bencode"
    require_relative "bitfield"
    require_relative "fileio"
    require_relative "metainfo"
    require_relative "peer"
    require_relative "tracker"
    
    @torrent_file = File.open(file, "r")
  end
  
  def runClient
    metainfo = Metainfo.new(@torrent_file)
    
    fileio = FileIO.new(metainfo.getInfo)

    tracker = Tracker.new(metainfo)
    tracker.sendRequest("started")
    # we should also be opening a socket to listen
    # on some port

    # check here if we're done with the file
    if fileio.recheckComplete == "100."
      puts "Starting as Seed." 
      seedCon = TCPServer.new( 6889 ) #arbitrary port
      loop do
        client = seedCon.accept
        peer.seed( client )
      end
    else
      peer = Peer.new(tracker, fileio)
      peer.connect(ARGV[1].to_i)
    end
    
    # TODO: eventually for off here to other peers
    # TODO: Detect timeouts in each peer connection
    # and reattribute threads
    # Thread.new {
    #   peer.connect(1)
    # }
  end
end

class Workers

  @size = nil
  @work = nil
  
  def initialize(number)
    @size = number
    @work = Queue.new

    @pool = Array.new( @size ) { |n|
      Thread.new {
        Thread.current[:id] = i #thread local var
        catch( :exit ) { #can call a shutdown
          loop {
            job, argvs = @work.pop
            job.call( *argvs )
          }
        }
      }
    }
  end

  def addWork( *argvs, &code )
    @work << [code, argvs]
  end

  def quit
    @size.times {
      schedule { throw :exit }
    }

    @pool.map( &:join ) #wait for all to finish
  end
  
end

unless ARGV.length == 2
  abort("Invalid number of arguments. Usage: ruby client.rb [file] [peer]")
end

client = Client.new(ARGV[0])
client.runClient

end
