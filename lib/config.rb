# Handle storing/reading YAML config files for torrents

require 'yaml'

module Torrent

class SessionConfig
  @torrents = nil
  @file_descriptor = nil

  # file_path is path with filename of YAML config file
  def initialize(file_path)
    # create if default doesn't exist?
    @file_descriptor = File.open(file_path, File::RDWR | File::CREAT)
    @file_descriptor.seek(0, IO::SEEK_SET)
    torrent_string = @file_descriptor.readlines.join
    @torrents = YAML.load(torrent_string)
  end
  
  def getTorrents
    @torrents
  end
  
  # info: [torrent-file, file-dir, download-dir]
  def add_torrent(info)
    hash = { "torrent-file"=>info[0], "file-dir"=>info[1], "download-dir"=>info[2] }
    @torrents["torrent#{@torrents.length}"] = hash
    @file_descriptor.seek(0, IO::SEEK_SET)
    @file_descriptor.write(@torrents.to_yaml)
  end
end

end
