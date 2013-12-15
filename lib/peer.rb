# Handle incoming and outgoing communication with other peers

module Torrent	

class Peer
  # use 2^14 byte block size (16kb) for compatability with other clients
  BLOCK_SIZE = 16384
  
  @peers = nil
  @local_peer_id = nil
  @info_hash = nil
  @fileio = nil
  
  @local_choking = nil
  @local_interested = nil
  
  # no data will be sent until unchoking happens
  @peer_choking = nil
  @peer_interested = nil
  
  # peer's bitfield
  @bitfield = nil
  
  def initialize(tracker, fileio)
    @peers = tracker.getPeers
    @local_peer_id = tracker.getPeerId
    @info_hash = tracker.getInfoHash
    @length = tracker.askMI.getLength
    @fileio = fileio
    @bitfield = Bitfield.new(fileio.getBitfield.get_num_of_bits)
  end
  
  def connect(peer)
    puts "Starting connection."
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
    puts "Sent handshake"

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

    if len == 0
      # keep-alive message
      puts "Got keep-alive message"
      return
    end

    id = socket.read( 1 ).unpack("c")[0]
    data = socket.read( len - 1 ) # not all messages have data to read, could be an issue?

    case id
    when 0
      puts "Got choke message"
      @peer_choking = true
    when 1
      puts "Got unchoke message"
      @peer_choking = false
    when 2
      puts "Got interested message"
      @peer_interested = true
    when 3
      puts "Got not interested message"
      @peer_interested = false
    when 4
      puts "Got have message"
      @bitfield.set_bit(data.unpack("N")[0])
      #puts @bitfield.to_binary_string
    when 5
      puts "Got bitfield message"
      # note, many clients will send incomplete bitfield, then supplement
      # remaining gaps with "have" messages (called lazy bitfield)
      @bitfield.from_binary_data(data)
      #puts @bitfield.to_binary_string
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
  
  def send_keepalive(socket)
    socket.write([0].pack("N"))
  end
  
  def send_choke(socket)
    @local_choking = true
    socket.write([1, 0].pack("Nc"))
  end
  
  def send_unchoke(socket)
    @local_choking = false
    socket.write([1, 1].pack("Nc"))
  end
  
  def send_interested(socket)
    @local_interested = true
    socket.write([1, 2].pack("Nc"))
  end
  
  def send_notinterested(socket)
    @local_interested = false
    socket.write([1, 3].pack("Nc"))
  end
  
  # piece_index is zero-based
  def send_have(piece_index)
    socket.write([5, 4, piece_index].pack("NcN"))
  end
  
  def send_bitfield(socket)
    bitfield_length = (@fileio.getBitfield.num_of_bits + 7) / 8
    bitfield_data = @fileio.getBitfield.to_binary_data
    socket.write([(1 + bitfield_length), 5].pack("Nc") + bitfield_data)
  end
  
  def send_request(socket, piece_index, begin_offset)
    socket.write([13, 6, piece_index, begin_offset, BLOCK_SIZE].pack("NcN3"))
  end
  
  def send_piece(socket, piece_index, begin_offset)
    # might be a better way to cache piece/length offsets for multiple files
    piece_offset = piece_index * @fileio.pieceLength
    file_index = nil
    filelength_offset = 0
    @fileio.files.each_with_index { |file, index|
      if filelength_offset + file[1] > piece_offset
        file_index = index
      else
        filelength_offset += file[1]
      end
    }
    
    @fileio.files[file_index][0].seek(piece_offset - filelength_offset, IO::SEEK_SET)
    block_bytes = @fileio.files[file_index][0].read(BLOCK_SIZE) # is it okay if it reads bytes from next piece?
    
    socket.write([9 + block_bytes.size, 7, piece_index, begin_offset].pack("NcN2") + block_bytes)
  end
  
  def send_cancel(socket, piece_index, begin_offset)
    socket.write([13, 8, piece_index, begin_offset, BLOCK_SIZE].pack("NcN3"))
  end
  
  # only needed with DHT
  def send_port(socket, listen_port)
    
  end
  
end

end
