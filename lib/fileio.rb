# Handle the file IO logic for writing and reading files, as well as starting from partial files.

module Torrent

class FileIO
  @info_dictionary = nil
  @files = nil # [[File descriptor, length], ...] (may be only a single file)
  @bitfield = nil
  @pieceLength = nil
  
  # accepts the info hash from metainfo
  def initialize(info) @info_dictionary = info
    @files = Array.new
    @pieceLength = info["piece length"]

    numBytes = 0
    
    if info["files"] != nil
      # multiple file mode
      
      unless Dir.exists?(info["name"])
        Dir.mkdir(info["name"])
      end
      
      info["files"].each { |file|
        numBytes += file["length"]
        filename = file["path"].last
        
        build_dir = String.new # for making directory trees
        file["path"].rotate(-1).drop(1).each { |dir| # don't use filename (last element)
          build_dir += (dir + "/")
          unless Dir.exists?(build_dir)
            Dir.mkdir(build_dir)
          end
        }
        
        @files << [File.open(build_dir + filename, File::RDWR | File::CREAT), file["length"]]
      }
    else
      # single file mode
      numBytes = info["length"] 
      @files << [File.open(info["name"], File::RDWR | File::CREAT), info["length"]]
    end
    
    # TO DO: Check which pieces are valid per the included hashes, set bits in bitfield
    fieldSize = info["pieces"].length / 20
    @bitfield = Bitfield.new( fieldSize )

    #this will only work for single files right now
    if info["files"].nil?
      countLoaded = 0
      (0..numBytes).step( @pieceLength ) { |n|
      # NEEDS TESTING

        @files[0][0].seek( n, IO::SEEK_SET )
        bytes = @files[0][0].read( @pieceLength )
        if bytes.nil?
          @files[0][0].seek( 0, IO::SEEK_SET ) #reset fh
          next
        end
        pieceHash = Digest::SHA1.digest( bytes )
        compHash = info["pieces"].byteslice( (n / @pieceLength) * 20, 20 )

        if pieceHash == compHash
          @bitfield.set_bit( n / @pieceLength )
          countLoaded += 1
        end

        @files[0][0].seek( 0, IO::SEEK_SET ) #reset fh
      }
    else
      # Still working on this part
      # TODO: we need to read each file consecutively
      # is there a way we can chain file handles/opens
      # in ruby or something?
      #
      # Maybe read all the files into a string...? Would this kill
      # Ruby if the files were large though?
      lastPiece = nil
      currentSeek = 0
      @files.each { |file, length|
        while (currentSeek + @pieceLength) <= length
          file.seek( currentSeek, IO::SEEK_GET )
          bytes = file.read( @pieceLength )
          if bytes.length != @pieceLength
            lastPiece = bytes
          else
            lastPiece = nil
          end

          #pieceHash = Digest::SHA1.digest( bytes )
          #compHash = info["pieces"].byteslice( ( 

          currentSeek += @pieceLength
        end 
      }
    end

    puts "Loaded #{(countLoaded*100 / ( numBytes / @pieceLength )*100) / 100}% complete file."
    puts @bitfield.to_binary_string

  end

  def getBitfield
    @bitfield
  end
  
    
end

end
