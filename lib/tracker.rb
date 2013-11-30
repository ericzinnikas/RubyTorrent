#Handle communication w/tracker (i.e. HTTP(S) GET requests)
#Need to implement proper urlencoding (See: https://wiki.theory.org/BitTorrentSpecification#Tracker_HTTP.2FHTTPS_Protocol )

require 'digest/sha1'

module Torrent

class Tracker
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
		@announce = metainfo.getAnnounce
		@uploaded = 0
		@downloaded = 0
		@trackerid =  ""
		@left = metainfo.getInfo["length"]
		#we need to first determine if this is "single file" or
		#"multiple file" mode, because there are differences
	end

	def sendRequest(type, metainfo)
		# ask Lex/Bobby if we can use 3rd party sha1 lib (also url get request)
		info_hash = Digest::SHA1.digest( Tracker.urlencode( metainfo.getInfo.to_bencode ) ) #sha1 hash

		peer_id = "-RR0001-"
		# we need 12 random digits
		12.times { peer_id += rand(10).to_s }

		port = 6889 #arbitrary decision
		uploaded = @uploaded
		downloaded = @downloaded
		left = @left
		compact = 1
		event = type # started, stopped, completed
		numwant = 50 #arbitrary
		trackerid = @trackerid #if we get a trackerid, put it here, otherwise nil or don't send

		get = "?info_hash=#{info_hash}&peer_id=#{peer_id}&port=#{port.to_s}&uploaded=#{uploaded}&downloaded=#{downloaded}&left=#{left}&compact=#{compact}&event=#{event}&numwant=#{numwant}&trackerid=#{trackerid}"
	end
end

end
