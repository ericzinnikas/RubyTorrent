# Handle the higher-level logic of downloading and seeding torrent files.

require 'thread'
require_relative 'config'

module Torrent

class Client
  @config = nil

  def initialize(config) 
    require_relative "bencode"
    require_relative "bitfield"
    require_relative "fileio"
    require_relative "metainfo"
    require_relative "peer"
    require_relative "tracker"
    
    @config = config
  end
  
  def runClient
    tList = Array.new
    @config.getTorrents.each { |i, torrent_data|
      dir_path = torrent_data["file-dir"]
      if dir_path.nil?
        dir_path = Dir.pwd
      end
      Dir.chdir(dir_path) {
        t_name = torrent_data["torrent-file"]
        tList << Thread.new {
          puts "Loading #{t_name}"
          fh = File.new(dir_path + t_name, "r")
          metainfo = Metainfo.new(fh)
          
          fileio = FileIO.new(metainfo.getInfo)

          tracker = Tracker.new(metainfo)
          leftBytes = (fileio.getTotal - fileio.getComplete) * fileio.getPieceLength
          if (fileio.getBitfield.check_bit(fileio.getTotal - 1) == 0)
            leftBytes -= fileio.getPieceLength
            leftBytes += fileio.getLastPieceLen
          end
          tracker.setLeft(leftBytes)

          # check here if we're done with the file
          if fileio.recheckComplete == "100."
            puts "Starting as Seed. (#{t_name})" 
            tracker.setLeft( 0 )
            tracker.sendRequest("started")
            peer = Peer.new(tracker, fileio)
            seedCon = TCPServer.new( 6889 ) #arbitrary port
            begin
              loop do
                client = seedCon.accept
                peer.seed( client )
              end
            rescue Interrupt
              tracker.sendRequest("stopped")
            end
          else
            puts "Starting as Peer. (#{t_name})"
            tracker.sendRequest("started")
            peer = Peer.new(tracker, fileio)
            peer.connect(ARGV[0].to_i)
          end
        }
      }
    }

    tList.each { |t|
      t.join
    }
    
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

unless ARGV.length == 1
  abort("Invalid number of arguments. Usage: ruby client.rb [peer]")
end

# use default config so that states are stored across sessions? or let user
# specify? (default for now)
config = SessionConfig.new("config/config.yaml") 

client = Client.new(config)
client.runClient

end
