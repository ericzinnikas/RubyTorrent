#Handle communication w/tracker (i.e. HTTP(S) GET requests)
#Need to implement proper urlencoding (See: https://wiki.theory.org/BitTorrentSpecification#Tracker_HTTP.2FHTTPS_Protocol )

#ask Bobby / Lex if we can use these libs
#move these includes to the client file?
require 'digest/sha1'
require 'net/http'
require 'ipaddr'

module Torrent

class Tracker
	@mi = nil
	@interval = nil
	@minInterval = nil
	@trackerId = String.new
	@complete = nil
	@incomplete = nil
	@peers = String.new

	# worry about UTF-8 vs BINARY (ASCII-8BIT) encodings?
	def self.urlencode(string)
		# need to force encoding to binary...default is UTF-8 or something?
		string.force_encoding("BINARY").gsub(/[^a-zA-Z0-9_\.\-\~]/) {
			sprintf( "%%%02X", $&.unpack("C")[0] )
		}
	end

	def self.urldecode(string)
		match = /((?:%[0-9a-fA-F]{2})+)/
		string.force_encoding("BINARY").gsub(match) {
			[$1.delete('%')].pack("H*")
		}.force_encoding("BINARY")
	end

	def initialize(metainfo)
		@mi = metainfo
		#save the metainfo object in here, so we don't need to provide it again
		@announce = @mi.getAnnounce
		@uploaded = 0
		@downloaded = 0
		@trackerid =  ""
		@left = @mi.getInfo["length"]
		#we need to first determine if this is "single file" or
		#"multiple file" mode, because there are differences
	end

  def askMI
    @mi #give access to the metainfo object
  end

	def sendRequest(type)
		# ask Lex/Bobby if we can use 3rd party sha1 lib (also url get request)
		@info_hash = Tracker.urlencode( Digest::SHA1.digest( @mi.getInfo.to_bencode ) ) #sha1 hash

		@peer_id = "-RR0001-"
		# we need 12 random digits
		12.times { @peer_id += rand(10).to_s }

		port = 6889 #arbitrary decision
		uploaded = @uploaded
		downloaded = @downloaded
		left = @left
		compact = 1
		event = type # started, stopped, completed
		numwant = 50 #arbitrary
		trackerid = @trackerid #if we get a trackerid, put it here, otherwise nil or don't send

		get = "?info_hash=#{@info_hash}&peer_id=#{@peer_id}&port=#{port.to_s}&uploaded=#{uploaded}&downloaded=#{downloaded}&left=#{left}&compact=#{compact}&event=#{event}&numwant=#{numwant}&trackerid=#{trackerid}"

		uri = URI( @announce + get )
		req = Net::HTTP::Get.new(uri)
		res = Net::HTTP.start(uri.hostname, uri.port) { |http|
			http.request(req)
		}

		#since we need to pass a file handle...just create a temp file
		fh = File.new("temp", "w+")
		fh.write( res.body )
		fh.pos = 0
		#fh.flush #unsure if needed
		response = Torrent::Bencode.decode(fh) #return tracker response as hash
    fh.close
    File.delete("temp")
    
		@interval = response["interval"]
		@minInterval = response["min interval"]
		@trackerId = response["tracker id"]
		@complete = response["complete"]
		@incomplete = response["incomplete"]
		@peers = response["peers"]

		#parse peers into something usable
		@peerSize = @peers.bytesize / 6
		@peersNew = Array.new
		@peerSize.times { |n|
			ipOff = n*6
			portOff = n*6 + 4
			port = @peers.byteslice( portOff, 2 ).bytes
			intPort = (port[0] << 8) | port[1]
			@peersNew << [ IPAddr.new(@peers.byteslice( ipOff, 4 ).reverse.unpack("!L")[0], Socket::AF_INET).to_s, intPort ]
		}

		@peers = @peersNew

		return true
	end

	def getPeers
		@peers
	end

	def getInfoHash
		Tracker.urldecode( @info_hash )
	end

	def getPeerId
		@peer_id
	end
end

end
