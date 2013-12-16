# Handle incoming and outgoing communication with other peers
 require 'thread'

module Torrent	

class Peer
  # use 2^14 byte block size (16kb) for compatability with other clients
  BLOCK_SIZE = 16384
  
  @peers = nil
  @local_peer_id = nil
  @info_hash = nil
  @fileio = nil
  
  @local_choking = true
  @local_interested = false
  
  # no data will be sent until unchoking happens
  @peer_choking = true
  @peer_interested = false

  # [[piece_index, begin_offset, req_length], ...] - see spec for more info on these 3 vars
  @pending_requests = nil
  
  # peer's bitfield
  @bitfield = nil
  
  # seems we only need to watch access
  # to the FileIO class (as that stores file state info)
  @lock = Mutex.new
  
  # which piece are we trying to complete?
  @work_piece = nil
  # which block within this piece are we working on?
  @work_offset = 0

  
  def initialize(tracker, fileio)
    @peers = tracker.getPeers # I think we should move this logic out to
                              # client. Then client can handle distributing
                              # workers to specific peers.
    @local_peer_id = tracker.getPeerId
    @info_hash = tracker.getInfoHash
    @length = tracker.askMI.getLength
    @fileio = fileio
    @pending_requests = Array.new
    @bitfield = Bitfield.new(fileio.getBitfield.get_num_of_bits)
  end
  
  def connect(peer)
    puts "Starting connection with #{@peers[peer][0]}:#{@peers[peer][1]}"
    
    # for clean exit if no peers exist
    if @peers.empty?
      puts "Aborting connection, no available peers"
      return
    end
    
    begin #Begin error handling.
          #Only really need to worry about initial protocol setup, after
          #that we shouldn't be seeing errors.

      socket = TCPSocket.new(@peers[peer][0], @peers[peer][1])
    
      response = handshake(socket)

    rescue Errno::ECONNREFUSED
      puts "Connection to #{@peers[peer][0]} refused."
      return false
    rescue Errno::ECONNRESET
      puts "Connection to #{@peers[peer][0]} reset."
      return false
    rescue Errno::EHOSTUNREACH
      puts "Connection to #{@peers[peer][0]} unreachable."
      return false
    rescue Errno::ENETUNREACH
      puts "Connection to #{@peers[peer][0]} unreachable."
      return false
    rescue Errno::ETIMEDOUT
      puts "Connection to #{@peers[peer][0]} timed out."
      return false
    end #End error handling.
    
    # ensure client is serving received info hash
    if verifyHandshake(response)
      # send bitfield if we have any pieces (not required if we have none)
      if @fileio.getBitfield.has_set_bits?
        send_bitfield(socket)
      end
      
      loop {
        if socket.eof? # peer has sent FIN, no more to read from socket
          puts "Connection closed by peer"
          break
        end
      
        parseMessages( socket )
      }
    else
      puts "Invalid infohash received in handshake"
    end
    
    socket.close 
  end
  
  # 'peer' argument is the index of the peer in the peers array.
  def handshake(socket)
    raw_data = [19, "BitTorrent protocol"] + Array.new(8, 0) << @info_hash << @local_peer_id

    sel = IO.select([], [socket], [], 15);

    if sel.nil?
      puts "Timed out waiting to write."
      exit
    end
    
    socket.write(raw_data.pack("cA19c8A20A20"))
    puts "Sent handshake"

    sel = IO.select([socket], [], [], 15);

    if sel.nil?
      puts "Timed out waiting to read."
      exit
    end

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

    case id
    when 0
      puts "Got choke message"
      @peer_choking = true
      @pending_requests = [] # choke discards all unanswered requests
    when 1
      puts "Got unchoke message"
      send_request( socket, @work_piece, @work_offset )
      @peer_choking = false
    when 2
      puts "Got interested message"
      @peer_interested = true
    when 3
      puts "Got not interested message"
      @peer_interested = false
    when 4
      puts "Got have message"
      # build logic to ask peers for pieces
      # maybe trigger a request msg once we learn
      # they have a piece we need? or maybe trigger it
      # after loading a bitfield....
      data = socket.read( len - 1 )
      @bitfield.set_bit(data.unpack("N")[0])
      #puts @bitfield.to_binary_string
      if @work_piece.nil? && ! @peer_choking
        @work_piece = @fileio.getBitfield.bits_to_get( @bitfield ).sample
        @work_offset = 0

        puts "Starting work on piece #{@work_piece}"

        # send request for first block
        send_request( socket, @work_piece, @work_offset )
      end
    when 5
      puts "Got bitfield message"
      # note, many clients will send incomplete bitfield, then supplement
      # remaining gaps with "have" messages (called lazy bitfield)
      data = socket.read( len - 1 )
      @bitfield.from_binary_data(data)
      

      #select random piece to work on
      if @work_piece.nil?
        @work_piece = @fileio.getBitfield.bits_to_get( @bitfield ).sample
        @work_offset = 0

        puts "Starting work on piece #{@work_piece}"

        send_unchoke( socket );
        send_interested( socket );

        # send request for first block
        # wait until unchoked to request
        #send_request( socket, @work_piece, @work_offset )
      end

    when 6
      puts "Got request message"
      @pending_requests << socket.read(12).unpack("N3")
    when 7
      puts "Got piece message"
      # check to see if we already have this piece?
      # technically, we should only get pieces we
      # request, but it can't hurt
      #
      # Also, I don't think we need to synchronize access
      # to this with a mutex. Because peers will probably
      # be writing at separate times, right?

      # Better safe than sorry for now.
      
      piece_index, begin_offset = socket.read(8).unpack("N2")
      block_bytes = socket.read( len - 9 )

      #@lock.synchronize {

      if @fileio.getBitfield.check_bit( piece_index )
        return
      end
      
      @fileio.set_piece_bytes(piece_index, begin_offset, block_bytes)
      
      #} # end synchronize

      # after writing to file, we need to recheck this piece to see if it is now complete
      actualHash = info["pieces"].byteslice(piece_index * 20, 20)
      pieceHash = @fileio.get_piece_hash(piece_index)
      
      if pieceHash == actualHash
        @fileio.getBitfield.set_bit(piece_index)
        @fileio.setComplete(1)
        puts "Bit #{piece_index} set"

        # need to choose a new piece to work on
        @work_piece = @fileio.getBitfield.bits_to_get( @bitfield ).sample
        @work_offset = 0
      else
        # piece not complete, request other blocks
        @work_offset += BLOCK_SIZE
      end

      if ! @peer_choking
        send_request( socket, @work_piece, @work_offset )
      end

      perc = (@fileio.getComplete * 100) / (@fileio.getTotal * 100) / 100
      if perc == 100
        if @fileio.recheckComplete() == 100

          puts "File download complete!"
          # now exit
          # and trigger all other threads to exit
          exit
        else
          puts "Recheck failed."
        end
      else
        puts "File #{perc}% complete."
      end
    when 8
      puts "Got cancel message"
      @pending_requests.delete(socket.read(12).unpack("N3"))
    when 9
      # only needed with DHT
      puts "Got port message"
      data = socket.read( len - 1 )
    else
      puts "Unsupported Protocol Message #{id}"
    end

  end
  
  def send_keepalive(socket)
    puts "Sent keep-alive message"
    socket.write([0].pack("N"))
  end
  
  def send_choke(socket)
    puts "Sent choke message"
    @local_choking = true
    socket.write([1, 0].pack("Nc"))
  end
  
  def send_unchoke(socket)
    puts "Sent unchoke message"
    @local_choking = false
    socket.write([1, 1].pack("Nc"))
  end
  
  def send_interested(socket)
    puts "Sent interested message"
    @local_interested = true
    socket.write([1, 2].pack("Nc"))
  end
  
  def send_notinterested(socket)
    puts "Sent not interested message"
    @local_interested = false
    socket.write([1, 3].pack("Nc"))
  end
  
  # piece_index is zero-based
  def send_have(piece_index)
    puts "Sent have message"
    socket.write([5, 4, piece_index].pack("NcN"))
  end
  
  # might want to implement lazy bitfield to ensure our bitfield messages
  # aren't getting filtered by ISPs
  def send_bitfield(socket)
    puts "Sent bitfield message"
    bitfield_length = (@fileio.getBitfield.get_num_of_bits + 7) / 8
    bitfield_data = @fileio.getBitfield.to_binary_data
    socket.write([(1 + bitfield_length), 5].pack("Nc") + bitfield_data)
  end
  
  def send_request(socket, piece_index, begin_offset)
    puts "Sent request message for piece #{piece_index} (#{begin_offset})"
    socket.write([13, 6, piece_index, begin_offset, BLOCK_SIZE].pack("NcN3"))
  end
  
  def send_piece(socket, piece_index, begin_offset)
    puts "Sent piece message"
    block_bytes = @fileio.get_piece_bytes(piece_index).byteslice(begin_offset, BLOCK_SIZE)

    # don't use BLOCK_SIZE for <len> part of message, truncated blocks/pieces may be sent
    socket.write([9 + block_bytes.bytesize, 7, piece_index, begin_offset].pack("NcN2") + block_bytes)
  end
  
  def send_cancel(socket, piece_index, begin_offset)
    puts "Sent cancel message"
    socket.write([13, 8, piece_index, begin_offset, BLOCK_SIZE].pack("NcN3"))
  end
  
  # only needed with DHT
  def send_port(socket, listen_port)
    puts "Sent port message"
    socket.write([3, 9, listen_port].pack("Ncn"))
  end
  
end

end
