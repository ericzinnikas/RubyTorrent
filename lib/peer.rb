module Torrent	
	class Peer
		@local_peer_id = nil
		@recipient_peer_id = nil
		@info_hash = nil
		
		def initialize(tracker)
			@local_peer_id = tracker.getPeerId
			@info_hash = tracker.getInfoHash
		end
		
		def handshake(ip, port)
			pstrlen = "19"
			pstr = "BitTorrent protocol"
			reserved = "00000000"
			
			socket = TCPSocket.new(ip, port)
			socket.write(pstrlen + pstr + reserved + info_hash + local_peer_id)
			while line = socket.gets
			  puts line
			end
			socket.close
		end
	end
end
