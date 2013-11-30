#Need to handle Strings, Integers, Lists (Arrays), Dictionaries (Hashes)
#so we will just extend these Ruby Classes with our own methods

class String
	def self.is_bencoded?(fh) # are we looking at a string, etc. ?
		ch = fh.getc #just need first char of input
		fh.ungetc ch #put it back
		(1 .. 9).include? ch
	end

	def to_bencode
		# TODO
	end

	def self.parse_bencode()
		# TODO
	end
end

class Integer
	def self.is_bencoded?(fh)
		ch = fh.getc
		fh.ungetc ch
		ch == 'i'
	end

	def to_bencode
		# TODO
	end

	def self.parse_bencode()
		# TODO
	end
end

class Array
	def self.is_bencoded?(fh)
		ch = fh.getc
		fh.ungetc ch
		ch == 'l'
	end

	def to_bencode
		# TODO
	end

	def self.parse_bencode()
		# TODO
	end
end

class Hash
	def self.is_bencoded?(fh)
		ch = fh.getc
		fh.ungetc ch
		ch == 'd'
	end

	def to_bencode
		# TODO
	end

	def self.parse_bencode()
		# TODO
	end
end
