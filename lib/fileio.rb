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
  @lastPieceLength = nil # length of last piece, which can be irregular

  @completePieces = 0
  @totalPieces = nil
  
  # accepts the info hash from metainfo. prefix_dir is the directory  
  # (i.e. download directory, etc.) for torrent files and their directories.
  def initialize(info, prefix_dir) 
    @info_dictionary = info
    @files = Array.new
    @piece_files = Array.new
    @pieceLength = info["piece length"]
    @numBytes = 0
    @totalPieces = info["pieces"].bytesize / 20
    
    build_dir_path(prefix_dir)
    
    unless prefix_dir.chars.last == File::SEPARATOR 
      prefix_dir += File::SEPARATOR 
    end
    
    no_files_existed = true
    if info["files"] != nil
      # multiple file mode
      
      unless Dir.exists?(prefix_dir + info["name"])
        Dir.mkdir(prefix_dir + info["name"])
      end
      
      info["files"].each { |file|
        @numBytes += file["length"]
        filename = file["path"].last
        
        build_dir = prefix_dir + info["name"] + File::SEPARATOR # for making directory trees
        file["path"].rotate(-1).drop(1).each { |dir| # don't use filename (last element)
          build_dir += (dir + File::SEPARATOR) # use constant separator for portability
          unless Dir.exists?(build_dir)
            Dir.mkdir(build_dir)
          end
        }
        
        if File.exists?(build_dir + filename)
          no_files_existed = false
        end
        @files << [File.open(build_dir + filename, File::RDWR | File::CREAT), file["length"]]
        if @files.last[0].size < @files.last[1]
          @files.last[0].seek(@files.last[0].size, IO::SEEK_SET)
          @files.last[0].write("\0" * (@files.last[1] - @files.last[0].size))
        end
      }
    else
      # single file mode
      @numBytes = info["length"] 
      if File.exists?(prefix_dir + info["name"])
        no_files_existed = false
      end
      @files << [File.open(prefix_dir + info["name"], File::RDWR | File::CREAT), info["length"]]
      if @files.last[0].size < @files.last[1] # still needs to be checked even if file exists
        @files.last[0].seek(@files.last[0].size, IO::SEEK_SET)
        (0..((@files.last[1] - @files.last[0].size)/1024)).each {
          @files.last[0].write("\0" * 1024)
        }
      end
    end
    unless no_files_existed
      recheckComplete()
    else
      gen_initial_states()
    end
    
    #puts @bitfield.to_binary_string
  end
  
  def gen_initial_states
    info = @info_dictionary
    @piece_files = Array.new
    fieldSize = info["pieces"].length / 20
    @bitfield = Bitfield.new( fieldSize )
    @completePieces = 0
    
    bytes = nil
    @totalPieces.times { |piece_index|     
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
      
      if @files[file_index][1] - (piece_offset - filelength_offset) > @pieceLength
        bytes = @pieceLength
      else
        bytes = @files[file_index][1] - (piece_offset - filelength_offset)
      end
      
      while bytes != @pieceLength && file_index + 1 < @files.length
        file_index += 1
        @piece_files[piece_index][2] += 1
          
        if @files[file_index][1] > @pieceLength - bytes
          bytes += @pieceLength - bytes
        else
          bytes += @files[file_index][1] 
        end
      end
    }
    @lastPieceLength = bytes
  end
  
  def recheckComplete
    info = @info_dictionary
    @piece_files = Array.new #don't wanna overwrite old array, so start new
    # check which pieces are valid per the included hashes, set bits in bitfield
    # populate @piece_files array
    fieldSize = info["pieces"].length / 20
    @bitfield = Bitfield.new( fieldSize )
    countLoaded = 0
    
    bytes = nil   
    @totalPieces.times { |piece_index|     
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
      
      while bytes.bytesize != @pieceLength && file_index + 1 < @files.length
        file_index += 1
        @piece_files[piece_index][2] += 1
        @files[file_index][0].seek(0, IO::SEEK_SET)
        bytes += @files[file_index][0].read(@pieceLength - bytes.bytesize)
      end
      
      pieceHash = Digest::SHA1.digest( bytes )
      compHash = info["pieces"].byteslice(piece_index * 20, 20)
      
      if pieceHash == compHash
        @bitfield.set_bit(piece_index)
        countLoaded += 1
        #puts "Bit #{piece_index} set"
      end
    }
    @lastPieceLength = bytes.bytesize
    
    @completePieces = countLoaded
    perc = (@completePieces.to_f / @totalPieces.to_f) * 100
    perc = perc.to_s.slice(0, 4)
    if $verb
      puts "Checked: #{perc}% complete file (#{@completePieces}/#{@totalPieces})."
    end
    perc
  end
  
  # untested
  def set_piece_bytes(piece_index, begin_offset, bytes)
    file_index, first_file_offset, num_files = @piece_files[piece_index]
    upper_filelength_offset = @files[file_index][1] - first_file_offset
    while upper_filelength_offset < begin_offset
      file_index += 1
      upper_filelength_offset += @files[file_index][1]
    end
    
    seek_pos = @files[file_index][1] - (upper_filelength_offset - begin_offset)
    @files[file_index][0].seek(seek_pos, IO::SEEK_SET)

    chunk = bytes.byteslice(0, @files[file_index][1] - seek_pos)
    num_bytes_written = chunk.bytesize
    @files[file_index][0].write(chunk)
    
    byte_size = bytes.bytesize
    while num_bytes_written != byte_size
      file_index += 1
      @files[file_index][0].seek(0, IO::SEEK_SET)     
      chunk = bytes.byteslice(num_bytes_written, @files[file_index][1])
      num_bytes_written += chunk.bytesize
      @files[file_index][0].write(chunk)
    end
  end
  
  # untested
  def get_piece_bytes(piece_index)
    file_index, first_file_offset, num_files = @piece_files[piece_index]
    @files[file_index][0].seek(first_file_offset, IO::SEEK_SET)
    bytes = @files[file_index][0].read(@pieceLength)

    while num_files - 1 > 0
      num_files -= 1
      file_index += 1
      @files[file_index][0].seek(0, IO::SEEK_SET)
      bytes += @files[file_index][0].read(@pieceLength - bytes.bytesize)
    end
    bytes
  end
  
  # will build the provided directory path, or do nothing if it exists already
  def build_dir_path(dir_path)
    dir_builder = ""
    dir_path.split("/").each { |dir|
      unless Dir.exists?(dir_builder + dir)
        Dir.mkdir(dir_builder + dir)
      end
      dir_builder += dir + "/"
    }
  end
  
  def get_piece_hash(piece_index)   
    Digest::SHA1.digest(get_piece_bytes(piece_index))
  end

  def getBitfield
    @bitfield
  end

  def getComplete
    @completePieces
  end

  def getTotal
    @totalPieces
  end

  def getPieceLength
    @pieceLength
  end

  def getInfoDict
    @info_dictionary
  end
  
  def getLastPieceLen
    @lastPieceLength
  end

  def setComplete( n )
    @completePieces += n
  end

  def isComplete?
    @completePieces == @totalPieces
  end
  
end

end
