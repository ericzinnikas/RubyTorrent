#Program Usage

###Libraries

Our implementation is split into eight different classes/files:

1. `bencode.rb` --> Our bencoding library.
2. `bitfield.rb` --> Handles manipulation of piece/block states.
3. `fileio.rb` --> Everything related to saving blocks/hashing/etc.
4. `metainfo.rb` --> Parsing of .torrent files.
5. `peer.rb` --> Peer protocol messages and logic.
6. `tracker.rb` --> Tracker communication logic.
7. `client.rb` --> User interface for the implementation.
8. `config.rb` --> Client configuration loading logic.

####Bencode

Our Bencode class provides `.is_bencoded?`, `.to_bencode`, and `.parse_bencode` methods for each of `String`, `Integer`, `Array`, and `Hash` data types.

####Bitfield

The Bitfield class can be used as follows:
```ruby
bf = Torrent::Bitfield.new( size )   #Initialize bitfield with length size

bf.set_bit( index )     #Set specified index
bf.check_bit( index )   #Check if index is set
bf.clear_bit( index )   #Clear index

bf.bits_to_get( bitfield )    #Returns array of bit indicies (i.e. pieces) that are available
                              #to get from a given bitfield (e.g. what pieces does this peer
                              #have that we don't?)

bf.to_binary_data( data )     #Export bitfield
bf.from_binary_data( data )   #Import bitfield

bf.to_binary_string   #Human readible output
```

####FileIO

FileIO manages reading and writing of specific pieces, and hash verification of torrents.

```ruby
fio = Torrent::FileIO.new( info_hash, prefix_dir )    #Initialize with an info hash (from a
                                                      #metainfo file) and prefix directory
                                                      #where torrents will be downloaded to

fio.gen_initial_states    #Calculate current file completion (if any, and initialize file
                          #space on disk)

fio.recheckComplete   #Return percentage completion (and run hash verification)

fio.set_piece_bytes( piece_index, begin_offset, bytes )   #Set piece
fio.get_piece_bytes( piece_index )    #Get piece
fio.get_piece_hash( piece_index )     #Get piece hash
```

####Metainfo

This class handles parsing of torrent files.  All computation is done upon initialization, various getter methods are provided to access the parsed data.

```ruby
fh = File.new("file.torrent", "r")

mi = Torrent::Metainfo.new( fh )    #Load metainfo (torrent) file
```

####Peer

The Peer class implements the BitTorrent peer protocol and provides methods to validate protocol handshakes, and fire events on specific messages.

```ruby
pr = Torrent::Peer.new( tracker, fileio )   #Initialize a new peer, with related
                                            #Tracker and FileIO

pr.connect( socket )    #Connect to a new peer (for downloading)
pr.seed( socket )       #Connect to a new peer (as a seed)
```

####Tracker

This class manages interaction with a tracker.

```ruby
tr = Torrent::Tracker.new( metainfo )   #Initialize a new tracker, with a
                                        #related Metainfo file

tr.urlencode( string )    #Encode and Decode methods are provided for
                          #data transformation
tr.urldecode( string )

tr.sendRequest( event )   #Fires "started", "stopped", "completed" events

tr.getPeers   #Returns a list of peers for the torrent
```

####Client

The Client class is a higher-level class which contains the user interface and handles the higher-level logic of using our BitTorrent implementation. This class is run from the console to use our BitTorrent client.

````
ruby ./lib/client.rb
````

####Config

This class loads YAML config files of the torrents that the client will download or seed.

````
cfg = Torrent::Config.new( filepath )  #Load the config from the
                                       #specified YAML file.
                                      
cfg.getTorrents   #Returns a hash containing the data about
                  #the torrents from the config file.
                  
cfg.add_torrent( torrent_info )   #Adds the specified torrent to the loaded
                                  #hash and saves it to the file.
````

###Sample Code
A functional client implementation can be seen in `client.rb`.  A basic interface is provided to download and seed files.  Specific configuration can be made in the `./config/config.yaml` file.
