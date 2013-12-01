#Program Usage

###Example 1
Reading in a torrent file, parsing it, sending an initial request to the tracker and parsing the response.


```ruby
require './lib/bencode.rb'
require './lib/metainfo.rb'
require './lib/tracker.rb'

fh = File.new("torrents/linuxmint.torrent", "r")
mi = Torrent::Metainfo.new( fh ) # load/parse the metainfo (torrent) file
tr = Torrent::Tracker.new( mi ) # setup our tracker connection & data
tr.sendRequest("stopped") # send a sample "stopped" request
```


And we'll recieve this hash back: **{"interval"=>1800, "min interval"=>300,"peers"=>""}**

