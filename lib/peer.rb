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
  
  def connect(peer)
    socket = TCPSocket.new(@peers[peer][0], @peers[peer][1])
    
    response = handshake(socket)
    
    # ensure client is serving received info hash
    if verifyHandshake(response)
      loop {
        parseMessages( socket )
        #for debugging this won't exit..
      }
    else
      puts "Invalid infohash received in handshake"
    end
    
    socket.close 
  end
  
  # 'peer' argument is the index of the peer in the peers array.
  def handshake(socket)
    raw_data = [19, "BitTorrent protocol"] + Array.new(8, 0) << @info_hash << @local_peer_id
    
    socket.write(raw_data.pack("cA19c8A20A20"))

    pstrlen = socket.read(1).unpack("c")[0]
    response = socket.read( 48 + pstrlen )
    puts "Got handshake"
    
    response
  end
  
  def verifyHandshake(handshake)
    # to unpack complete response with pstrlen prefix use "cA19c8A20A20" and index [10]
    (handshake.unpack("A19c8A20A20")[9] == @info_hash)
  end

  # pass socket, after handshake is complete
  # this will handle message parsing and hand off as needed
  def parseMessages( socket )
    len = socket.read( 4 ).unpack("N")[0]
    puts ">#{len}<"

    if len == 0
    #keep alive message....do nothing?
      puts "got keep-alive message (wrong)"
      parseMessages( socket )
      return
    end

    id = socket.read( 1 ).unpack("c")[0]
    data = socket.read( len - 1 ) # not all messages have data to read, could be an issue?

    case id
    when 0
      puts "Got choke message"
    when 1
      puts "Got unchoke message"
    when 2
      puts "Got interested message"
    when 3
      puts "Got not interested message"
    when 4
      puts "Got have message"
      # we know that data describes zero-based index of piece that was just downloaded & verified
    when 5
      puts "Got bitfield message"
      # read wiki entry on bitfield
      bitfield = Bitfield.new((len - 1) * 8)
      bitfield.from_binary_data(data)
      puts bitfield.to_binary_string
    when 6
      puts "Got request message"
    when 7
      puts "Got piece message"
    when 8
      puts "Got cancel message"
    when 9
      puts "Got port message"
      # only needed with DHT
    else
      puts "Unsupported Protocol Message #{id}"
    end

  end
  
end

end