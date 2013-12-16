# Handle the file IO logic for writing and reading files, as well as starting from partial files.

module Torrent

class FileIO
  @info_dictionary = nil
  
  @files = nil # [[File descriptor, length], ...] (may be only a single file)
  @piece_files = nil # [[file_index, first_file_offset, num_files], ...]
  # we know that after first file, offset in later files will always be 0 bytes, 
  # so we only need to know the number of files a piece is stored across
  
  @bitfield = nil
  @pieceLength = nil
  
  # accepts the info hash from metainfo
  def initialize(info) 
    @info_dictionary = info
    @files = Array.new
    @piece_files = Array.new
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
    
    # check which pieces are valid per the included hashes, set bits in bitfield
    # populate @piece_files array
    fieldSize = info["pieces"].length / 20
    @bitfield = Bitfield.new( fieldSize )

    #this will only work for single files right now
    if info["files"].nil?
      countLoaded = 0
      (0..numBytes).step( @pieceLength ) { |n|
      # NEEDS TESTING
        @piece_files << [0, n, 1]
        
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
      
      (info["pieces"].bytesize / 20).times { |piece_index|     
        piece_offset = piece_index * @pieceLength
        file_index = nil
        filelength_offset = 0
        @files.each_with_index { |file, index|
          if filelength_offset + file[1] > piece_offset
            file_index = index
            break
          else
            filelength_offset += file[1]
          end
        }
        
        @piece_files << [file_index, piece_offset - filelength_offset, 1]
        
        @files[file_index][0].seek(@piece_files[piece_index][1], IO::SEEK_SET)
        bytes = @files[file_index][0].read(@pieceLength)
        
        while bytes.bytesize != @pieceLength && @files.length < ++file_index
          @piece_files[piece_index][2] += 1
          @files[file_index][0].seek(0, IO::SEEK_SET)
          bytes += @fileio.files[file_index][0].read(@pieceLength - bytes.bytesize)
        end
        
        pieceHash = Digest::SHA1.digest( bytes )
        compHash = info["pieces"].byteslice(piece_index * 20, 20)
        
        if pieceHash == compHash
          @bitfield.set_bit(piece_index)
          countLoaded += 1
          puts "Bit #{piece_index} set"
        end
      }
    end
    
    puts "Loaded #{(countLoaded*100 / ( numBytes / @pieceLength )*100) / 100}% complete file."
    puts @bitfield.to_binary_string
  end
  
  def get_piece_bytes(piece_index)
    file_index, first_file_offset, num_files = @piece_files[piece_index]
    @files[file_index][0].seek(first_file_offset, IO::SEEK_SET)
    bytes = @files[file_index][0].read(@pieceLength)
    
    while --num_files > 0
      file_index++
      @files[file_index][0].seek(0, IO::SEEK_SET)
      bytes += @files[file_index][0].read(@pieceLength - bytes.bytesize)
    end
  end
  
  def get_piece_hash(piece_index)   
    Digest::SHA1.digest(get_piece_bytes(piece_index))
  end

  def getBitfield
    @bitfield
  end
  
end

end
