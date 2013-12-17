module Torrent	

class Bitfield
  @bit_array = nil
  @num_of_bits = nil # needed because bit_array is in multiples of 8
  
  # length is number of bits (i.e. pieces)
  def initialize(length)
    if $verb
      puts "Creating bitfield of #{length} pieces (stored as #{(length + 7)/8} bytes)"
    end
    @bit_array = Array.new((length + 7) / 8, 0) # + 7 to round up
    @num_of_bits = length
  end

  # 0-based index
  def set_bit(index)
    offset = index / 8
    shift_num = 7 - (index % 8)
    @bit_array[offset] |= (1 << shift_num)
  end

  # 0-based index. returns true if set, otherwise false.
  def check_bit(index)
    offset = index / 8
    shift_num = 7 - (index % 8)
    (@bit_array[offset] & (1 << shift_num)) != 0
  end
  
  # 0-based index
  def clear_bit(index)
    offset = index / 8
    shift_num = 7 - (index % 8)
    if (@bit_array[offset] & (1 << shift_num)) != 0
      @bit_array[offset] ^= (1 << shift_num)
    end
  end
  
  # returns an array of bit indices (i.e. piece indices) that are available to
  # get from a given bitfield.
  #
  # usage: local_bitfield.bits_to_get(peer_bitfield) returns indices that peer
  # has and local needs.
  def bits_to_get(bitfield)
    bytes_to_get = Array.new
    bitfield.get_byte_array.each_with_index { |byte, index|
      bytes_to_get.push(byte & (byte ^ @bit_array[index]))
    }
    bit_arr = to_binary_string_from_array(bytes_to_get).chars.to_a
    bit_arr = bit_arr.zip((0...bit_arr.size).to_a)
    bit_arr.delete_if { |a| a[0] == "0" }
    indices = bit_arr.transpose[1]
    unless indices.nil?
      indices
    else
      Array.new
    end
  end

  # used for sending messages with bitmask
  def to_binary_data
    @bit_array.pack("C#{@bit_array.length}")
  end
  
  # used for loading into object from received bitmasks
  def from_binary_data(data)
    @bit_array = data.unpack("C#{@bit_array.length}")
  end
  
  # e.g. "010101"
  def to_binary_string
    to_binary_string_from_array(@bit_array)
  end
  
  def to_binary_string_from_array(array)
    out = String.new
    array.each { |byte|
      suffix_bits = byte.to_s(2)
      prefix_bits = "0" * (8 - suffix_bits.length) # ensure each byte is 8 chars
      out << (prefix_bits + suffix_bits)
    }
    out.byteslice(0, @num_of_bits)
  end
  
  def has_set_bits?
    @bit_array.each { |byte|
      if byte != 0
        return true
      end
    }
    false
  end
  
  def get_num_of_bits
    @num_of_bits
  end
  
  # the *byte* representation of the bitfield
  def get_byte_array
    @bit_array
  end
  
  private :to_binary_string_from_array
end
  
end
