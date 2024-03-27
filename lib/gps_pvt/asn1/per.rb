#!/usr/bin/ruby

module GPS_PVT

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
  def normally_small_non_negative_whole_number(v, *len_enc) # 10.6
    if v <= 63 then
      "0%06b" % v # 10.6.1
    else
      "1#{semi_constrained_whole_number(v, 0, *len_enc)}" # 10.6.2
    end
  end
  def semi_constrained_whole_number(v, v_min, *len_enc) # 10.7
    len_enc = :length_otherwise if len_enc.empty?
    bf = non_negative_binary_integer(v - v_min, 8).scan(/.{8}/)
    with_length(bf.size, *len_enc).collect{|len_str, range|
      len_str + bf[range].join
    }.join
  end
  def unconstrained_whole_number(v, *len_enc) # 10.8
    len_enc = :length_otherwise if len_enc.empty?
    bf = twos_complement_binary_integer(v).scan(/.{8}/)
    with_length(bf.size, *len_enc).collect{|len_str, range|
      len_str + bf[range].join
    }.join
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
      len_enc, len_remain = length_otherwise(len)
      len_enc = "1#{len_enc}"
      len_remain ? [len_enc, len_remain] : len_enc
    end
  end
  def length_otherwise(len) # 10.9.4.2 -> 10.9.3.5-8
    if len <= 127 then # 10.9.3.6
      non_negative_binary_integer2(len, 8)
    elsif len < 16384 then # 10.9.3.7
      "10#{non_negative_binary_integer2(len, 14)}"
    else # 10.9.3.8
      q, r = len.divmod(16384)
      q2 = [q, 4].min
      res = "11#{non_negative_binary_integer2(q2, 6)}"
      ((r == 0) && (q <= 4)) ? res : [res, len - (q2 * 16384)]
    end
  end
  def with_length(len, *len_enc)
    Enumerator::new{|y|
      len_str, len_remain = len_enc[0].kind_of?(Symbol) ? send(len_enc[0], len, *len_enc[1..-1]) : len_enc
      loop{
        if len_remain then
          y << [len_str, -len..-(len_remain+1)]
        else
          y << [len_str, -len..-1]
          break
        end
        len_str, len_remain = length_otherwise(len = len_remain) # fragmentation
      }
    }
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
  def normally_small_non_negative_whole_number(str, *len_dec) # 10.6
    case str.slice!(0)
    when '0'; str.slice!(0, 6).to_i(2) # 10.6.1
    when '1'; semi_constrained_whole_number(str, 0, *len_dec) # 10.6.2
    end
  end
  def semi_constrained_whole_number(str, v_min, *len_dec) # 10.7
    len_dec = :length_otherwise if len_dec.empty?
    v_str = with_length(str, *len_dec).collect{|len_oct|
      str.slice!(0, len_oct * 8)
    }.join
    non_negative_binary_integer(v_str, v_str.size) + v_min
  end
  def unconstrained_whole_number(str, *len_dec) # 10.8
    len_dec = :length_otherwise if len_dec.empty?
    v_str = with_length(str, *len_dec).collect{|len_oct|
      str.slice!(0, len_oct * 8)
    }.join
    twos_complement_binary_integer(v_str, v_str.size)
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
      when '1'; [non_negative_binary_integer(str, 6) * (1 << 14), true] # 10.9.3.8
      end
    end
  end
  def with_length(str, *len_dec)
    Enumerator::new{|y|
      len, cnt = len_dec[0].kind_of?(Symbol) ? send(len_dec[0], str, *len_dec[1..-1]) : len_dec
      loop{
        y << len
        break unless cnt
        len, cnt = length_otherwise(str) # fragmentation
      }
    }
  end
end
end
end
end

end
