module Torrent	

class Bitfield

  @bit_array = nil

  # length is number of bits (i.e. pieces)
  def initialize(length)
    @bit_array = Array.new(length / 8, 0)
  end

  # 0-based index
  def set_bit(index)
    offset = index / 8
    shift_num = 7 - (index % 8)
    @bit_array[index] |= (1 << shift_num)
  end
  
  # 0-based index. returns true if set, otherwise false.
  def check_bit(index)
    offset = index / 8
    shift_num = 7 - (index % 8)
    (@bit_array[index] & (1 << shift_num)) != 0
  end
  
  # 0-based index
  def clear_bit(index)
    offset = index / 8
    shift_num = 7 - (index % 8)
    if (@bit_array[index] & (1 << shift_num)) != 0
      @bit_array[index] ^= (1 << shift_num)
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
    out = String.new
    @bit_array.each { |byte|
      suffix_bits = byte.to_s(2)
      prefix_bits = "0" * (8 - suffix_bits.length) # ensure each byte is 8 chars
      out << (prefix_bits + suffix_bits)
    }
    out
  end
  
end
  
end