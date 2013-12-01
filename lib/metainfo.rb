#handle everything dealing w/metainfo files here
#need to build some tests for this

module Torrent

class Metainfo
	@info = Hash.new
	@announce = String.new
	@announceList = Array.new
	@creationDate = 0 #= Integer.new
	@comment = String.new
	@createdBy = String.new
	@encoding = String.new

	def initialize(fh) #once we parse, @fh is at EOF, should reset it?
		# TODO should we combine this step with new()?
		infoHash = Torrent::Bencode.decode(fh)
		@info = infoHash["info"]
		@announce = infoHash["announce"]
		@announceList = infoHash["announce-list"]
		@creationDate = infoHash["creation date"]
		@comment = infoHash["comment"]
		@createdBy = infoHash["created by"]
		@encoding = infoHash["encoding"]
	end

	def getName
		@info["name"]
	end

	def getInfo
		@info
	end

	def getAnnounce
		@announce
	end

	def getAnnounceList
		@announceList
	end

end

end
