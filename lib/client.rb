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
  
  def runClient( whichTorrent )

    hashAssoc = Hash.new

    if whichTorrent.nil?
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
        if $verb
          puts "Seeding #{torrent_data["torrent-file"]}"
        end
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
              if $verb
                puts "\nSeeding to client #{client_con[1]}:#{client_con[0]}"
              end
              
              Thread.current["torrent-file"] = hashAssoc[recv_hash][0].split("/").last
              
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
              if $verb
                puts "\nClient #{client_con[1]}:#{client_con[0]} disconnected."
              end
            }
          end
        rescue Interrupt
          puts "\nStopping seed."
          tracker.sendRequest("stopped")
        end 
      }
    end
    
    tList = Array.new
    @config.getTorrents.each { |i, torrent_data|
      t_name = torrent_data["torrent-file"]
      if ! whichTorrent.nil? && t_name != whichTorrent
        #only start the one we want
        next
      end
      dir_path = torrent_data["file-dir"]
      if dir_path.nil?
        dir_path = ""
      end
      fh = File.new(Dir.pwd + "/" + dir_path + File::SEPARATOR + t_name, "r")
      metainfo = Metainfo.new(fh)
      
      fileio = FileIO.new(metainfo.getInfo, torrent_data["download-dir"])
      $perc[t_name] = fileio.getComplete / fileio.getTotal
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
              Thread.current["torrent-file"] = t_name
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

    torrent_cols = Array.new
    begin
      updateDelay( 1 ) {
        # torrents = ["torrent name" => [seed_num, peer_num], ...]
        torrents = Hash.new
        @config.getTorrents.each { |i, torrent_data|
          completed = $perc[torrent_data["torrent-file"]]
          if completed.nil?
            completed = 0
          end
          torrents[torrent_data["torrent-file"]] = [0, 0, completed]
        }

        tList.each { |t|
          if t["peer"] == true
            if t["nowSeed"] == true
              torrents[t["torrent-file"]][0] += 1
            else
              torrents[t["torrent-file"]][1] += 1
            end
          end
        }

        sList.each { |t|
          if t["seed"] == true
            torrents[t["torrent-file"]][0] += 1
          end
        }

        # account for any changes to terminal window size
        cols_width = `/usr/bin/env tput cols`.to_i
        rows_height = `/usr/bin/env tput lines`.to_i
        
        row_splitter = ("=" * cols_width) + "\n"
        
        # cols = [["Column name", col_width], ...]
        label_cols = Array.new
        label_cols << ["Torrent Name", 0.5]
        label_cols << ["Seeds", 0.0875]
        label_cols << ["Peers", 0.0875]
        label_cols << ["Progress", 0.325]
        
        torrent_cols = Array.new
        torrents.each_with_index { |object, i|
          torrent = object[0]
          data = object[1]
         
          # generate perentage bar
          num_spacers = label_cols.length + 1
          percentage_width = label_cols[3][1] * (cols_width - num_spacers)
          percentage_bar = get_percentage_bar(data[2], percentage_width)
          
          # populate torrent info row
          curr_col = Array.new
          curr_col << [i.to_s + ": " + torrent, label_cols[0][1]]
          curr_col << [data[0].to_s, label_cols[1][1]]
          curr_col << [data[1].to_s, label_cols[2][1]]
          curr_col << [percentage_bar, label_cols[3][1]]
          torrent_cols << curr_col
        }
        
        # build string prior to outputting to prevent the screen from flashing
        out_string = String.new
        out_string += row_splitter
        out_string += get_columns_string(label_cols, cols_width)
        out_string +=  row_splitter
        torrent_cols.each { |torrent_col|
          out_string += get_columns_string(torrent_col, cols_width)
        }
        out_string +=  row_splitter # add footer
        
        STDOUT.write "\e[2J\e[f" + out_string # 1st part clears screen, portable?
      }
    rescue Interrupt
      #this is where we'll actually take user input
      #possible actions would be removing(?) a torrent
      #maybe ask them to enter a number of the torrent to stop
      #seeding.
      #or pause/unpause a torrent, etc.
      #then throw them back into the loop
      

      STDOUT.write "\nChoose from the following actions:\n\t(s)top | s(t)art | (r)ehash | (q)uit \nChoice: "
      choice = STDIN.gets

      case choice
      when "s\n"
        STDOUT.write "Select torrent: "
        choice = STDIN.gets
        STDOUT.write "Stopping #{torrent_cols[choice.to_i][0][0]}"
        sList.each { |t|
          if "#{choice.to_i}: " + t["torrent-file"] == "#{choice.to_i}: " + torrent_cols[choice.to_i][0][0]
            t["stopNow"] = true
          end
        }
        tList.each { |t|
          if "#{choice.to_i}: " + t["torrent-file"] == torrent_cols[choice.to_i][0][0]
            t["stopNow"] = true
          end
        }
        retry
      when "t\n"
        STDOUT.write "Select torrent: "
        choice = STDIN.gets
        STDOUT.write "Starting #{torrent_cols[choice.to_i][0][0]}"
        sList.each { |t|
          if "#{choice.to_i}: " + t["torrent-file"] == "#{choice.to_i}: " + torrent_cols[choice.to_i][0][0]
            t["stopNow"] = false
          end
        }
        tList.each { |t|
          if "#{choice.to_i}: " + t["torrent-file"] == torrent_cols[choice.to_i][0][0]
            t["stopNow"] = false
          end
        }
        Thread.new {
          self.runClient( torrent_cols[choice.to_i][0][0].slice(3, torrent_cols[choice.to_i][0][0].length).to_s )
        }
        retry
      when "r\n"
        STDOUT.write "Select torrent: "
        choice = STDIN.gets
        STDOUT.write "Rehashing #{choice}"
        retry
      when "q\n"
        exit  
      end

        
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
  
  # cols = [["Column name", col_width], ...]
  def get_columns_string(cols, width)
    line = String.new
    line += "|"
    content_width = width - (cols.length + 1) # accounts for vertical spacers
    cols.each { |col|
      col_width = (content_width * col[1]).to_i
      col_label = col[0].slice(0, col_width)
      space_width = 0
      if col_width > col[0].length
        space_width = col_width - col[0].length
      end
      line += " " * (space_width / 2)
      line += col_label
      line += " " * (space_width - (space_width / 2)) # accounts for odd space widths
      line += "|"
    }
    # accounts for truncation variations to ensure consistent row length
    if line.length <= width 
      line[line.length - 1] = " "
      line += " " * (width - line.length)
      line[line.length - 1] = "|"
    end
    line.slice(0, width) + "\n"
  end
  
  # percent is in the range [0, 1]
  # bar_width is the total number of characters the bar occupies (must be >= 2)
  def get_percentage_bar(percent, bar_width)
    inner_width = bar_width - 2
    complete_num = (inner_width * percent).to_i
    incomplete_num = inner_width - complete_num # accounts for any truncation
    "[" + ("#" * complete_num) + ("-" * incomplete_num) + "]"
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

$perc = Hash.new

# use default config so that states are stored across sessions? or let user
# specify? (default for now)
config = SessionConfig.new("config/config.yaml") 

client = Client.new(config)
client.runClient(nil)

end
