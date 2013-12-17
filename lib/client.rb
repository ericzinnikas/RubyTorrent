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

  def updateDelay( sec )
    last = Time.now
    loop do
      sleep 0.1
      if Time.new - last >= sec
        yield
        last = Time.now
      end
    end
  end
  
  def runClient

    hashAssoc = Hash.new

    @config.getTorrents.each { |i, torrent_data|
      dir_path = torrent_data["file-dir"]
      if dir_path.nil?
        dir_path = ""
      end
      unless Dir.exists?(dir_path)
        puts "Invalid file path provided, exiting"
        exit
      end
      file_path = Dir.pwd + "/" + dir_path + "/" + torrent_data["torrent-file"]
      dl_path = torrent_data["download-dir"]
      fh = File.new(file_path, "r")
      mi = Metainfo.new(fh)
      tr = Tracker.new( mi )
      tr.sendRequest("started") #need to announce our presence
      hashAssoc[mi.getInfoHash] = [file_path, dl_path, torrent_data["download-dir"]]
      puts "Seeding #{torrent_data["torrent-file"]}"
    }

    sList = Array.new
    seedThread = Thread.new {
      seedCon = TCPServer.new( 6889 )
      tracker = nil
      begin
        loop do
          sList << Thread.start( seedCon.accept ) { |client|
            client_con = Socket.unpack_sockaddr_in(client.getpeername)
            res = Peer.getHandshake( client )
            recv_hash = res.unpack("A19c8A20A20")[9]
            recv_path = hashAssoc[recv_hash][0]
            if recv_path.nil?
              puts "Bad path."
              exit
            end
            #if $verb
              puts "\nSeeding to client #{client_con[1]}:#{client_con[0]}"
            #end
            fh = File.new( recv_path, "r")
            
            metainfo = Metainfo.new(fh)
            fileio = FileIO.new( metainfo.getInfo, hashAssoc[recv_hash][2] )
            tracker = Tracker.new( metainfo )  

            leftBytes = (fileio.getTotal - fileio.getComplete) * fileio.getPieceLength
            if (fileio.getBitfield.check_bit(fileio.getTotal - 1) == 0)
              leftBytes -= fileio.getPieceLength
              leftBytes += fileio.getLastPieceLen
            end

            tracker.setLeft(leftBytes)
            tracker.sendRequest("started") 

            Thread.current["seed"] = true
            peer = Peer.new( tracker, fileio )
            if $verb
              puts "Seeding!"
            end
            peer.seed( client )
            Thread.current["seed"] = false
            #if $verb
              puts "\nClient #{client_con[1]}:#{client_con[0]} disconnected."
            #end
          }
        end
      rescue Interrupt
        puts "\nStopping seed."
        tracker.sendRequest("stopped")
      end 
    }
    
    tList = Array.new
    @config.getTorrents.each { |i, torrent_data|
      dir_path = torrent_data["file-dir"]
      if dir_path.nil?
        dir_path = ""
      end
      t_name = torrent_data["torrent-file"]
      fh = File.new(Dir.pwd + "/" + dir_path + File::SEPARATOR + t_name, "r")
      metainfo = Metainfo.new(fh)
      
      fileio = FileIO.new(metainfo.getInfo, torrent_data["download-dir"])
      tracker = Tracker.new(metainfo)
      leftBytes = (fileio.getTotal - fileio.getComplete) * fileio.getPieceLength
      if (fileio.getBitfield.check_bit(fileio.getTotal - 1) == 0)
        leftBytes -= fileio.getPieceLength
        leftBytes += fileio.getLastPieceLen
      end
      tracker.setLeft(leftBytes)


      if leftBytes != 0
        tracker.sendRequest("started")
        numSpawn = 5
        if tracker.getPeers.length < 5
          numSpawn = tracker.getPeers.length
        end
        begin
          (0..numSpawn - 1).each { |n|
            tList << Thread.new {
              Thread.current["peer"] = true
              peer = Peer.new(tracker, fileio)
              peer.connect(n)
              Thread.current["peer"] = false
            }
          }
        rescue Interrupt
          puts "\nStopping peer."
          tracker.sendRequest("stopped")
        end
      end
    }

    begin
      updateDelay( 1 ) {
        peers = 0
        seeds = 0

        tList.each { |t|
          if t["peer"] == true
            if t["nowSeed"] == true
              seeds += 1
            else
              peers += 1
            end
          end
        }

        sList.each { |t|
          if t["seed"] == true
            seeds += 1
          end
        }

        # account for any changes to terminal window size
        t_cols = `/usr/bin/env tput cols`.to_i
        t_rows = `/usr/bin/env tput lines`.to_i
        
        STDOUT.write "Seeds: #{seeds} || Peers: #{peers}             \r"  
      }
    rescue Interrupt
      puts "\n\nCaught Interrupt. Exiting."
      sList.each { |t|
        #t.join
      }
      tList.each { |t|
        #t.join
      }
      #seedThread.join
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

if ARGV.length == 1 && ARGV[0] == "verbose"
  $verb = true
else
  $verb = false
end

# use default config so that states are stored across sessions? or let user
# specify? (default for now)
config = SessionConfig.new("config/config.yaml") 

client = Client.new(config)
client.runClient

end
