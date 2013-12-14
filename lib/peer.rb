# Handle incoming and outgoing communication with other peers

module Torrent	

class Peer
  @peers = nil
  
  @local_peer_id = nil
  @info_hash = nil
  
  # Formatted messages for the protocol
  @keep_alive = Array.new(4, 0).pack("c4")
  @choke = [0, 0, 0, 1, 0].pack("c5")
  @unchoke = [0, 0, 0, 1, 1].pack("c5")
  @interested = [0, 0, 0, 1, 2].pack("c5")
  @not_interested = [0, 0, 0, 1, 3].pack("c5")
  
  def initialize(tracker)
    @peers = tracker.getPeers
    @local_peer_id = tracker.getPeerId
    @info_hash = tracker.getInfoHash
  end
  
  # 'peer' argument is the index of the peer in the peers array.
  def handshake(peer)
    raw_data = [19, "BitTorrent protocol"] + Array.new(8, 0) << @info_hash << @local_peer_id
    
    socket = TCPSocket.new(@peers[peer][0], @peers[peer][1])
    socket.write(raw_data.pack("cA19c8A20A20"))
    puts socket.read
    socket.close
  end
  
end

end
