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
    pstrlen = "19"
    pstr = "BitTorrent protocol"
    reserved = "00000000"
    
    socket = TCPSocket.new(@peers[peer][0], @peers[peer][1])
    socket.write(pstrlen + pstr + reserved + @info_hash + @local_peer_id)
    while line = socket.gets
      puts line
    end
    socket.close
  end
end

end
