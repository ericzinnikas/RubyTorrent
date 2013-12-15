# Handle the file IO logic for writing and reading files, as well as starting from partial files.

module Torrent

class FileIO
  @info_dictionary = nil
  @files = nil # [[File descriptor, length], ...] (may be only a single file)
  @bitfield = nil
  
  # accepts the info hash from metainfo
  def initialize(info)
    @info_dictionary = info
    @files = Array.new
    
    if info["files"] != nil
      # multiple file mode
      
      unless Dir.exists?(info["name"])
        Dir.mkdir(info["name"])
      end
      
      info["files"].each { |file|
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
      
      @files << [File.open(info["name"], File::RDWR | File::CREAT), info["length"]]
    end
    
    @bitfield = Bitfield.new((info["pieces"].length / 20))
    # TO DO: Check which pieces are valid per the included hashes, set bits in bitfield
  end
  
    
end

end
