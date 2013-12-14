# Handle incoming and outgoing communication with other peers

module Torrent	

class Peer
  @peers = nil
  
  @local_peer_id = nil
  @info_hash = nil
  
  def initialize(tracker)
    @peers = tracker.getPeers
    @local_peer_id = tracker.getPeerId
    @info_hash = tracker.getInfoHash
  end
  
  # 'peer' argument is the index of the peer in the peers array.
  def handshake(peer)
    raw_data = [19, "BitTorrent protocol"] + Array.new(8, 0) << @info_hash << @local_peer_id
    formatted_data = raw_data.pack("CA19L8A20A20")
    
    socket = TCPSocket.new(@peers[peer][0], @peers[peer][1])
    socket.write(formatted_data)
    
    sleep(3) # sleep prior to read
    puts socket.read(5) # testing to see if 'gets' isn't receiving because it's waiting for newline character
    
    #while line = socket.gets
    #  puts line
    #end
    socket.close
  end
end

end
