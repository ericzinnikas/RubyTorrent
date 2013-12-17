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
    @tracker = tracker
    @pending_requests = Array.new
    @bitfield = Bitfield.new(fileio.getBitfield.get_num_of_bits)
    srand
  end
  
  def connect(peer)
    # for clean exit if no peers exist (needs to be before @peers[peer][..])
    if @peers.nil? || @peers.empty? || @peers[peer].nil?
      if $verb
        puts "Aborting connection, no available peers"
      end
      return
    end
    
    if $verb
      puts "\nStarting connection with #{@peers[peer][0]}:#{@peers[peer][1]}"
    end
    
    begin #Begin error handling.
          #Only really need to worry about initial protocol setup, after
          #that we shouldn't be seeing errors.

      begin
        socket = TCPSocket.new(@peers[peer][0], @peers[peer][1])
      rescue Interrupt
        if $verb
          puts "Connection to peer cancelled."
        end
        @tracker.sendRequest("stopped")
        return false
      end
    
      sendHandshake( socket )
      response = getHandshake(socket)

    rescue Errno::ECONNREFUSED
      if $verb
        puts "Connection to #{@peers[peer][0]} refused."
      end
      return false
    rescue Errno::ECONNRESET
      if $verb
        puts "Connection to #{@peers[peer][0]} reset."
      end
      return false
    rescue Errno::EHOSTUNREACH
      if $verb
        puts "Connection to #{@peers[peer][0]} unreachable."
      end
      return false
    rescue Errno::ENETUNREACH
      if $verb
        puts "Connection to #{@peers[peer][0]} unreachable."
      end
      return false
    rescue Errno::ETIMEDOUT
      if $verb
        puts "Connection to #{@peers[peer][0]} timed out."
      end
      return false
    end #End error handling.
    
    # ensure client is serving received info hash
    if verifyHandshake(response)
      # send bitfield if we have any pieces (not required if we have none)
      if @fileio.getBitfield.has_set_bits?
        send_bitfield(socket)
      end
      
      begin
      loop {
        if socket.closed? || socket.eof? # peer has sent FIN, no more to read from socket
          if $verb
            puts "Connection closed by peer"
          end
          break
        end
      
        parseMessages( socket )
      }
      rescue Errno::ECONNRESET
        if $verb
          puts "Connection reset by peer"
        end
        return false
      end
    else
      if $verb
        puts "Invalid infohash received in handshake"
      end
    end
    
    #socket.close 
  end

  def seed( socket ) #doesn't necessarily mean we're a seeder...
    if $verb
      puts "Starting seeding."
    end

    sendHandshake( socket )

    send_bitfield( socket )

    begin
      loop {
        if socket.eof?
          if $verb
            puts "Connection closed by peer"
          end
          break
        end

        parseMessages( socket )

      }
    rescue Errno::ECONNRESET
      if $verb
        puts "Connection reset (maybe we're done?)"
      end
      return false
    end
  end
  
  def self.getHandshake( socket ) #define as class/instance method too
    sel = IO.select([socket], [], [], 15);

    if sel.nil?
      if $verb
        puts "Timed out waiting to read."
      end
      return ""
    end

    begin
      pstrlen = socket.read(1).unpack("c")[0]
    rescue NoMethodError
      if $verb
        puts "Received null byte in handshake. Exiting."
      end
      return ""
    end
    
    response = socket.read( 48 + pstrlen )
    if $verb
      puts "Got handshake"
    end
    
    response
  end
  def getHandshake( socket )
    sel = IO.select([socket], [], [], 15);

    if sel.nil?
      if $verb
        puts "Timed out waiting to read."
      end
      return ""
    end

    begin
      pstrlen = socket.read(1).unpack("c")[0]
    rescue NoMethodError
      if $verb
        puts "Received null byte in handshake. Exiting."
      end
      return ""
    end
    
    response = socket.read( 48 + pstrlen )
    if $verb
      puts "Got handshake"
    end
    
    response
  end
  
  def sendHandshake(socket)
    raw_data = [19, "BitTorrent protocol"] + Array.new(8, 0) << @info_hash << @local_peer_id

    sel = IO.select([], [socket], [], 15);

    if sel.nil?
      if $verb
        puts "Timed out waiting to write."
      end
      exit
    end
    
    socket.write(raw_data.pack("cA19c8A20A20"))
    if $verb
      puts "Sent handshake"
    end
    true
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
      if $verb
        puts "Got keep-alive message"
      end
      return
    end

    id = socket.read( 1 ).unpack("c")[0]

    case id
    when 0
      if $verb
        puts "Got choke message"
      end
      @peer_choking = true
      @pending_requests = [] # choke discards all unanswered requests
    when 1
      # only send data messages when unchoked
      if $verb
        puts "Got unchoke message"
      end

      if ! @fileio.isComplete?
        send_request( socket, @work_piece, @work_offset )
        (1..(( @fileio.getPieceLength / BLOCK_SIZE ) - 1)).each { |n| # fill the pipeline
          send_request( socket, @work_piece, @work_offset + n*BLOCK_SIZE )
        }
      end

      @peer_choking = false
    when 2
      # only send data when peer is interested
      if $verb
        puts "Got interested message"
      end

      send_unchoke( socket )

      @peer_interested = true
    when 3
      if $verb
        puts "Got not interested message"
      end

      send_choke( socket )

      @peer_interested = false
    when 4
      if $verb
        puts "Got have message"
      end
      # build logic to ask peers for pieces
      # maybe trigger a request msg once we learn
      # they have a piece we need? or maybe trigger it
      # after loading a bitfield....
      data = socket.read( len - 1 )
      @bitfield.set_bit(data.unpack("N")[0])
      #puts @bitfield.to_binary_string
      if @work_piece.nil? && ! @peer_choking && ! @fileio.isComplete?
        needed_bits = @fileio.getBitfield.bits_to_get( @bitfield )
        unless needed_bits.empty?
          @work_piece = needed_bits.sample( random: Random.new( Random.new_seed ) )
          @work_offset = 0

          if $verb
            puts "Starting work on piece #{@work_piece}"
          end

          # send request for first block
          send_request( socket, @work_piece, @work_offset )
        end
      end
    when 5
      if $verb
        puts "Got bitfield message"
      end
      # note, many clients will send incomplete bitfield, then supplement
      # remaining gaps with "have" messages (called lazy bitfield)
      data = socket.read( len - 1 )
      @bitfield.from_binary_data(data)
      

      #select random piece to work on
      if @work_piece.nil? && ! @fileio.isComplete?
        needed_bits = @fileio.getBitfield.bits_to_get( @bitfield )
        unless needed_bits.empty?
          @work_piece = needed_bits.sample( random: Random.new( Random.new_seed ) )
          @work_offset = 0

          if $verb
            puts "Starting work on piece #{@work_piece}"
          end

          send_unchoke( socket );
          send_interested( socket );

          # send request for first block
          # wait until unchoked to request
          #send_request( socket, @work_piece, @work_offset )
        end
      end

    when 6
      if $verb
        puts "Got request message"
      end
      reqData = socket.read(12).unpack("N3")
      @pending_requests << reqData
      ## we  should just send pieces now? or use a queue

      if ! @peer_choking && @peer_interested
        send_piece( socket, reqData[0], reqData[1], reqData[2] )
      end
    when 7
      if $verb
        puts "Got piece message"
      end
      # Also, I don't think we need to synchronize access
      # to this with a mutex. Because peers will probably
      # be writing at separate times, right?
      if @fileio.isComplete?
        return
      end
      
      piece_index, begin_offset = socket.read(8).unpack("N2")
      block_bytes = socket.read( len - 9 )

      #@lock.synchronize {
      #for some reason there's a MethodNotFound exception here

      if @fileio.getBitfield.check_bit( piece_index )
        # TODO choose a new piece to work on
        needed_bits = @fileio.getBitfield.bits_to_get( @bitfield )
        unless needed_bits.empty?
          @work_piece = needed_bits.sample( random: Random.new( Random.new_seed ) )
          @work_offset = 0
        end
        return
      end
      
      @fileio.set_piece_bytes(piece_index, begin_offset, block_bytes)
      
      #} # end synchronize

      # after writing to file, we need to recheck this piece to see if it is now complete
      actualHash = @fileio.getInfoDict["pieces"].byteslice(piece_index * 20, 20)
      pieceHash = @fileio.get_piece_hash(piece_index)
      
      if pieceHash == actualHash
        @fileio.getBitfield.set_bit(piece_index)
        @fileio.setComplete(1)
        if $verb
          puts "Bit #{piece_index} set"
        end

        send_have( socket, piece_index ) #also need to send this to all other peers

        # need to choose a new piece to work on
        needed_bits = @fileio.getBitfield.bits_to_get( @bitfield )
        unless needed_bits.empty?
          @work_piece = needed_bits.sample( random: Random.new( Random.new_seed ) )
          @work_offset = 0
        end
      else
        # piece not complete, request other blocks
        #@work_offset += BLOCK_SIZE
      end

      if ! @peer_choking
        send_request( socket, @work_piece, @work_offset )
        (1..(( @fileio.getPieceLength / BLOCK_SIZE ) - 1)).each { |n| # fill the pipeline
          send_request( socket, @work_piece, @work_offset + n*BLOCK_SIZE )
        }
      end
      
      perc = (@fileio.getComplete.to_f / @fileio.getTotal.to_f) * 100
      perc = perc.to_s.slice(0, 4)
      if perc == "100."
        if @fileio.recheckComplete() == "100."
          socket.close

          if $verb
            puts "File download complete! (#{@fileio.getInfoDict["name"]})"
          end
          # now exit
          # and trigger all other threads to exit
          @tracker.sendRequest("completed")
          Thread.current["nowSeed"] == true
          Thread.current["completed"] = 1
          return true
          #exit #Don't necessarily need to stop now. Unless connection is closed.
        else
          if $verb
            puts "Recheck failed."
          end
        end
      else
        if $verb
          puts "File #{perc}% complete (#{@fileio.getComplete}/#{@fileio.getTotal})."
        end
        Thread.current["completed"] = perc.to_f / 100
      end
    when 8
      if $verb
        puts "Got cancel message"
      end
      @pending_requests.delete(socket.read(12).unpack("N3"))
    when 9
      # only needed with DHT
      if $verb
        puts "Got port message"
      end
      data = socket.read( len - 1 )
    else
      if $verb
        puts "Unsupported Protocol Message #{id}"
      end
    end

  end
  
  def send_keepalive(socket)
    if $verb
      puts "Sent keep-alive message"
    end
    socket.write([0].pack("N"))
  end
  
  def send_choke(socket)
    if $verb
      puts "Sent choke message"
    end
    @local_choking = true
    socket.write([1, 0].pack("Nc"))
  end
  
  def send_unchoke(socket)
    if $verb
      puts "Sent unchoke message"
    end
    @local_choking = false
    socket.write([1, 1].pack("Nc"))
  end
  
  def send_interested(socket)
    if $verb
      puts "Sent interested message"
    end
    @local_interested = true
    socket.write([1, 2].pack("Nc"))
  end
  
  def send_notinterested(socket)
    if $verb
      puts "Sent not interested message"
    end
    @local_interested = false
    socket.write([1, 3].pack("Nc"))
  end
  
  # piece_index is zero-based
  def send_have( socket, piece_index)
    if $verb
      puts "Sent have message"
    end
    socket.write([5, 4, piece_index].pack("NcN"))
  end
  
  # might want to implement lazy bitfield to ensure our bitfield messages
  # aren't getting filtered by ISPs
  def send_bitfield(socket)
    if $verb
      puts "Sent bitfield message"
    end
    bitfield_length = (@fileio.getBitfield.get_num_of_bits + 7) / 8
    bitfield_data = @fileio.getBitfield.to_binary_data
    socket.write([(1 + bitfield_length), 5].pack("Nc") + bitfield_data)
  end
  
  def send_request(socket, piece_index, begin_offset)
    if $verb
      puts "Sent request message for piece #{piece_index} (#{begin_offset})"
    end
    
    # account for last block in last piece which may be truncated
    req_len = nil
    if piece_index == @fileio.getTotal - 1 && begin_offset == (@fileio.getLastPieceLen / BLOCK_SIZE) * BLOCK_SIZE
      req_len = @fileio.getLastPieceLen - begin_offset
    else
      req_len = BLOCK_SIZE
    end
    
    socket.write([13, 6, piece_index, begin_offset, req_len].pack("NcN3"))
  end
  
  def send_piece(socket, piece_index, begin_offset, block_length )
    if $verb
      puts "Sent piece message"
    end
    # lets use block size specified by peer..?
    block_bytes = @fileio.get_piece_bytes(piece_index).byteslice(begin_offset, block_length )

    # don't use BLOCK_SIZE for <len> part of message, truncated blocks/pieces may be sent
    socket.write([9 + block_bytes.bytesize, 7, piece_index, begin_offset].pack("NcN2") + block_bytes)
  end
  
  def send_cancel(socket, piece_index, begin_offset)
    if $verb
      puts "Sent cancel message"
    end
    
    # account for last block in last piece which may be truncated
    req_len = nil
    if piece_index == @fileio.getTotal - 1 && begin_offset == (@fileio.getLastPieceLen / BLOCK_SIZE) * BLOCK_SIZE
      req_len = @fileio.getLastPieceLen - begin_offset
    else
      req_len = BLOCK_SIZE
    end
    
    socket.write([13, 8, piece_index, begin_offset, req_len].pack("NcN3"))
  end
  
  # only needed with DHT
  def send_port(socket, listen_port)
    if $verb
      puts "Sent port message"
    end
    socket.write([3, 9, listen_port].pack("Ncn"))
  end
  
end

end
