#Inspired by William Morgan's bencoding.rb 
#Here: https://github.com/reddavis/rubytorrent/blob/master/rubytorrent/bencoding.rb


#Need to handle Strings, Integers, Lists (Arrays), Dictionaries (Hashes)
#so we will just extend these Ruby Classes with our own methods

module Torrent

class Bencode
	def self.decode(fh)
		if String.is_bencoded?(fh)
			String.parse_bencode(fh)
		elsif Integer.is_bencoded?(fh)
			Integer.parse_bencode(fh)
		elsif Array.is_bencoded?(fh)
			Array.parse_bencode(fh)
		elsif Hash.is_bencoded?(fh)
			Hash.parse_bencode(fh)
		else
			errCh = fh.getc
			fh.ungetc errCh
			"Error at char: #{errCh}"
		end
	end
end

end

class String
	def self.is_bencoded?(fh) # are we looking at a string, etc. ?
		ch = fh.getc #just need first char of input
		fh.ungetc ch #put it back
		("0" .. "9").include? ch
	end

	def to_bencode
		self.length.to_s + ":" + self.to_s
	end

	def self.parse_bencode(fh)
		len = fh.getc
		while( (x = fh.getc) != ":")
			len += x	
		end

		fh.read( len.to_i )
	end
end

class Integer
	def self.is_bencoded?(fh)
		ch = fh.getc
		fh.ungetc ch
		ch == 'i'
	end

	def to_bencode
		"i" + self.to_s + "e"
	end

	def self.parse_bencode(fh)
		ch = fh.getc # should be 'i', do some error checking?
		if ch != 'i'
			# TODO
		end
		int = String.new # make sure we don't add ints or something?

		while( (x = fh.getc) != "e")
			int += x	
		end

		int.to_i
	end
end

class Array
	def self.is_bencoded?(fh)
		ch = fh.getc
		fh.ungetc ch
		ch == 'l'
	end

	def to_bencode
		"l" + self.map { |elm|
			elm.to_bencode
		}.join + "e"
	end

	def self.parse_bencode(fh)
		ch = fh.getc
		if ch != "l"
			# TODO
		end

		out = Array.new

		while( (x = fh.getc) != "e")
			fh.ungetc x
			out << Torrent::Bencode.decode(fh)
		end
		return out
	end
end

class Hash
	def self.is_bencoded?(fh)
		ch = fh.getc
		fh.ungetc ch
		ch == 'd'
	end

	def to_bencode
		# keys need to be "compared using a binary comparison, as strings.."
		"d" + self.keys.sort { |x, y|
			x.to_s <=> y.to_s #ensure string comparison
		}.map { |k|
			k.to_bencode + self[k].to_bencode
		}.join + "e"
	end

	def self.parse_bencode(fh)
		ch = fh.getc
		if ch != "d"
			# TODO
		end

		out = Hash.new

		while( (x = fh.getc) != "e")
			fh.ungetc x
			key = String.parse_bencode(fh) # keys must be bencoded strings
			out[key] = Torrent::Bencode.decode(fh)
		end
		return out
	end
end
