module Torrent

class Metainfo
	def initialize(fh)
		@fh = fh
	end

	@info = Hash.new
	@announce = String.new
	@announceList = Array.new
	@creationDate = 0 #= Integer.new
	@comment = String.new
	@createdBy = String.new
	@encoding = String.new

	def parse #once we parse, @fh is at EOF, should reset it?
		infoHash = Torrent::Bencode.decode(@fh)
		@info = infoHash["info"]
		@announce = infoHash["announce"]
		@announceList = infoHash["announce-list"]
		@creationDate = infoHash["creation date"]
		@comment = infoHash["comment"]
		@createdBy = infoHash["created by"]
		@encoding = infoHash["encoding"]
		return true
	end

	# need some getter methods, etc.?
end

end
