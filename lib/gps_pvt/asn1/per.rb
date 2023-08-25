#!/usr/bin/ruby

# @see ISO/IEC 8825-2:2003(E)
# @see http://www5d.biglobe.ne.jp/~stssk/asn1/per.html
module PER
module Basic_Unaligned
module Encoder
class <<self
  def non_negative_binary_integer2(v, bits) # 10.3
    "%0#{bits}b" % v
  end
  def non_negative_binary_integer(v, align = 1) # 10.3
    non_negative_binary_integer2(
        v, (Math::log2(v + 1) / align).ceil * align)
  end
  def twos_complement_binary_integer(v) # 10.4
    if v >= 0 then
      bits = ((Math::log2(v + 1) + 1) / 8).ceil * 8
      "%0#{bits}b" % v
    else
      bits = ((Math::log2(-v) + 1) / 8).ceil * 8 - 1
      "1%0#{bits}b" % (v + (1 << bits))
    end
  end
  def constrainted_whole_number2(v, v_min, v_max) # 10.5.6
    non_negative_binary_integer2(
        v - v_min,
        Math::log2(v_max - v_min + 1).ceil)
  end
  def constrainted_whole_number(v, v_range) # 10.5.6
    constrainted_whole_number2(v, *v_range.minmax)
  end
  def normally_small_non_negative_whole_number(
      v, len_enc = [:length_normally_small_length]) # 10.6
    if v <= 63 then
      "0%06b" % v # 10.6.1
    else
      "1#{semi_constrained_whole_number(v, 0, len_enc)}" # 10.6.2
    end
  end
  def semi_constrained_whole_number(
        v, v_min, len_enc = [:length_normally_small_length]) # 10.7
    bf = non_negative_binary_integer(v - v_min, 8)
    "#{send(len_enc[0], bf.length / 8, *len_enc[1..-1])}#{bf}"
  end
  def unconstrained_whole_number(
        v, len_enc = [:length_normally_small_length]) # 10.8
    bf = twos_complement_binary_integer(v)
    "#{send(len_enc[0], bf.length / 8, *len_enc[1..-1])}#{bf}"
  end
  def length_constrained_whole_number(len, len_range)
    if len_range.max < 65536 then # 10.9.4.1
      (len_range.min == len_range.max) ?
          "" : 
          constrainted_whole_number(len, len_range)
    else
      length_otherwise(len)
    end
  end
  def length_normally_small_length(len) # 10.9.4.2 -> 10.9.3.4
    if len <= 64 then
      normally_small_non_negative_whole_number(len - 1)
    else
      "1#{length_otherwise(len)}"
    end
  end
  def length_otherwise(len) # 10.9.4.2 -> 10.9.3.5-8
    if len <= 127 then # 10.9.3.6
      non_negative_binary_integer2(len, 8)
    elsif len < 16384 then # 10.9.3.7
      "10#{non_negative_binary_integer2(len, 14)}"
    else # 10.9.3.8
      raise # TODO
    end
  end
end
end
module Decoder
class <<self
  def non_negative_binary_integer(str, bits) # 10.3
    str.slice!(0, bits).to_i(2)
  end
  def twos_complement_binary_integer(str, bits) # 10.4
    bits -= 1
    case str.slice!(0)
    when '0'; 0 
    when '1'; -(1 << bits) 
    end + non_negative_binary_integer(str, bits)
  end
  def constrainted_whole_number2(str, v_min, v_max) # 10.5.6
    non_negative_binary_integer(
        str,
        Math::log2(v_max - v_min + 1).ceil) + v_min
  end
  def constrainted_whole_number(str, v_range) # 10.5.6
    constrainted_whole_number2(str, *v_range.minmax)
  end
  def normally_small_non_negative_whole_number(
      str, len_enc = [:length_normally_small_length]) # 10.6
    case str.slice!(0)
    when '0'; str.slice!(0, 6).to_i(2) # 10.6.1
    when '1'; semi_constrained_whole_number(str, 0, len_enc) # 10.6.2
    end
  end
  def semi_constrained_whole_number(
        str, v_min, len_enc = [:length_normally_small_length]) # 10.7
    oct = send(len_enc[0], str, *len_enc[1..-1])
    non_negative_binary_integer(str, oct * 8) + v_min
  end
  def unconstrained_whole_number(
        str, len_enc = [:length_normally_small_length]) # 10.8
    oct = send(len_enc[0], str, *len_enc[1..-1])
    twos_complement_binary_integer(str, oct * 8)
  end
  def length_constrained_whole_number(str, len_range)
    if len_range.max < 65536 then # 10.9.4.1
      (len_range.min == len_range.max) ?
          len_range.min :
          constrainted_whole_number(str, len_range)
    else
      length_otherwise(str)
    end
  end
  def length_normally_small_length(str) # 10.9.4.2 -> 10.9.3.4
    case str.slice!(0)
    when '0'; str.slice!(0, 6).to_i(2) + 1
    when '1'; length_otherwise(str)
    end
  end
  def length_otherwise(str) # 10.9.4.2 -> 10.9.3.5-8
    case str.slice!(0)
    when '0'; non_negative_binary_integer(str, 7) # 10.9.3.6
    when '1';
      case str.slice!(0)
      when '0'; non_negative_binary_integer(str, 14) # 10.9.3.7
      when '1'; raise # TODO 10.9.3.8
    end
  end
end
end
end
end
end

if __FILE__ == $0 then
  enc, dec = [:Encoder, :Decoder].collect{|k| PER::Basic_Unaligned.const_get(k)}
  
  checker = proc{|func, src, *opts|
    str = enc.send(func, src, *opts)
    #p [func, src, opts, str.reverse.scan(/.{1,8}/).join('_').reverse]
    dst = dec.send(func, str, *opts)
    raise unless src == dst
  }
    
  [0..255, -128..127].each{|range|
    range.each{|i|
      checker.call(:constrainted_whole_number, i, range)
    }
  }
  [
    [:length_normally_small_length],
    [:length_constrained_whole_number, 0..4],
    [:length_otherwise],
  ].each{|len_enc|
    (0..255).each{|i|
      checker.call(:normally_small_non_negative_whole_number, i, len_enc)
    }
    [0, -128, 127].each{|v_min|
      (0..255).each{|i|
        checker.call(:semi_constrained_whole_number, i + v_min, v_min, len_enc)
      }
    }
    (0..(1 << 16)).each{|i|
      checker.call(:unconstrained_whole_number, i, len_enc)
    }
  }
end
