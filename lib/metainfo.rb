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
  @single = nil

	def initialize(fh) #once we parse, @fh is at EOF, should reset it?
		infoHash = Torrent::Bencode.decode(fh)
		@info = infoHash["info"]
		@announce = infoHash["announce"]
		@announceList = infoHash["announce-list"]
		@creationDate = infoHash["creation date"]
		@comment = infoHash["comment"]
		@createdBy = infoHash["created by"]
		@encoding = infoHash["encoding"]

    if @info["files"].nil?
      @single = true
    else
      @single = false
    end

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

  def getLength
    if @single
      @info["length"]
    else
      numBytes = 0
      @info["files"].each { |file|
        numBytes += file["length"] 
      }
      numBytes
    end
  end

  def isSingle?
    @single
  end

end

end
