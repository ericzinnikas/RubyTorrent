# Handle the file IO logic for writing and reading files, as well as starting from partial files.

module Torrent

class FileIO
  @info_dictionary = nil
  @files = nil # [[File descriptor, length], ...] (may be only a single file)
  @bitfield = nil
  @pieceLength = nil
  
  # accepts the info hash from metainfo
  def initialize(info) 
    @info_dictionary = info
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
        
        build_dir = info["name"] + File::SEPARATOR # for making directory trees
        file["path"].rotate(-1).drop(1).each { |dir| # don't use filename (last element)
          build_dir += (dir + File::SEPARATOR) # use constant separator for portability
          unless Dir.exists?(build_dir)
            Dir.mkdir(build_dir)
          end
        }
        
        @files << [File.open(build_dir + filename, File::RDWR | File::CREAT), file["length"]]
        if @files.last[0].size < @files.last[1]
          @files.last[0].seek(@files.last[0].size, IO::SEEK_SET)
          @files.last[0].write("\0" * (@files.last[1] - @files.last[0].size))
        end
      }
    else
      # single file mode
      numBytes = info["length"] 
      @files << [File.open(info["name"], File::RDWR | File::CREAT), info["length"]]
      if @files.last[0].size < @files.last[1]
        @files.last[0].seek(@files.last[0].size, IO::SEEK_SET)
        @files.last[0].write("\0" * (@files.last[1] - @files.last[0].size))
      end
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
      # Maybe read all the files into a string...? Would this kill
      # Ruby if the files were large though?
      #
      # This would probably work, but per @177 on Piazza we would lose points
      
      # NEEDS TESTING
      countLoaded = 0
      lastIndex = @files.length - 1
      currentSeek = 0
      pieceOffset = 0
      @files.each_with_index { |file, index|
        pieces = file[1] / @pieceLength
        partialPieces = (file[1] % @pieceLength) != 0
        
        # iterate over all complete pieces in file
        pieces.times { |pieceIndex|
          # in case partial piece in beginning & end but file[1] % @pieceLength = 0
          if (currentSeek + @pieceLength > file[1])
            partialPieces = true
            break
          end
          
          file[0].seek( currentSeek, IO::SEEK_SET )
          bytes = file[0].read( @pieceLength )
          
          pieceHash = Digest::SHA1.digest( bytes )
          compHash = info["pieces"].byteslice( (pieceIndex + pieceOffset) * 20, 20 )
          
          if pieceHash == compHash
            @bitfield.set_bit( pieceIndex + pieceOffset )
            countLoaded += 1
            puts "Bit #{pieceIndex + pieceOffset} set"
          end
          
          currentSeek += @pieceLength
        }
        
        # handle partial piece at end of file
        if partialPieces
          # read to end of first file
          file[0].seek( currentSeek, IO::SEEK_SET )
          bytes = file[0].read( @pieceLength ) # okay to read more bytes than exist? will there be empty bytes? test this
          partialByteLength = @pieceLength - bytes.length
          
          if (index != @files.length - 1) # last partial piece CAN have truncated length
            # reading beginning of next file
            @files[index + 1][0].seek( 0, IO::SEEK_SET )
            bytes += @files[index + 1][0].read( partialByteLength )
          end
          
          pieceHash = Digest::SHA1.digest( bytes )
          compHash = info["pieces"].byteslice( (pieces + pieceOffset) * 20, 20 )
          
          if pieceHash == compHash
            @bitfield.set_bit( pieces + pieceOffset )
            countLoaded += 1
          end
          
          # start currentSeek to exclude the preceding partial bytes in the next file
          currentSeek = partialByteLength
        else
          # if no partial file, start currentSeek at the beginning for the next file
          currentSeek = 0
        end
        
        # maintain offset of pieces from previous file for next file
        pieceOffset += pieces
      }

      puts "Loaded #{(countLoaded*100 / ( numBytes / @pieceLength )*100) / 100}% complete file."
      puts @bitfield.to_binary_string
    end
  end

  def getBitfield
    @bitfield
  end
  
end

end
