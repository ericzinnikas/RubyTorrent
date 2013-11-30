module Torrent

class Metainfo
	def initialize(fh)
		@fh = fh
	end

	@info = Hash.new
	@announce = String.new
	@announceList = Array.new
	@creationDate = Integer.new
	@comment = String.new
	@createdBy = String.new
	@encoding = String.new

	def parse
		infoHash = Torrent::Bencode.decode(fh)
		puts infoHash["info"]
	end
end

end
