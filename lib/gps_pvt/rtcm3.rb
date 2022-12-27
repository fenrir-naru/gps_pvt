# RTCM3 parser

require_relative 'util'

module GPS_PVT
class RTCM3
  def initialize(io)
    @io = io
    @buf = []
  end
  def RTCM3.checksum(packet, range = 0..-4)
    GPS_PVT::Util::CRC24Q::checksum(packet[range])
  end
  module Packet
    def message_number
      Util::BitOp::extract(self, [12], 24).first
    end
    DataFrame = proc{
      unum = proc{|n, sf|
        [n, proc{|v| sf.kind_of?(Rational) ? (v * sf).to_f : (v * sf)}]
      }
      num = proc{|n, sf|
        [n, proc{|v| 
          v -= (1 << n) if v >= (1 << (n - 1))
          v *= sf if sf
          v = v.to_f if sf.kind_of?(Rational)
          v
        }]
      }
      df = {
        1 => [1],
        2 => [12],
        3 => [12],
        21 => [6],
        22 => [1],
        23 => [1],
        24 => [1],
        25 => num.call(38, Rational(1, 10000)),
        141 => [1],
        142 => [1],
        364 => [2],
      }
      df[27] = df[26] = df[25]
      df
    }.call
    MessageType = Hash[*({
      1005 => [2, 3, 21, 22, 23, 24, 141, 25, 142, 1, 26, 364, 27],
    }.collect{|mt, df_list|
      [mt, Hash[*([:bits, :op].collect.with_index{|k, i|
        [k, df_list.collect{|df| DataFrame[df][i]}]
      }.flatten(1))].merge({:df => df_list})]
    }.flatten(1))]
    def parse
      return nil unless (mt = MessageType[message_number])
      # return [[value, df], ...]
      Util::BitOp.extract(self, mt[:bits], 24).zip(mt[:op]).collect{|v, op|
        op ? op.call(v) : v
      }.zip(mt[:df])
    end
  end
  def read_packet
    while !@io.eof?
      if @buf.size < 6 then
        @buf += @io.read(6 - @buf.size).unpack('C*')
        return nil if @buf.size < 6
      end
      
      if @buf[0] != 0xD3 then
        @buf.shift
        next
      elsif (@buf[1] & 0xFC) != 0x0 then
        @buf = @buf[2..-1]
        next
      end
      
      len = ((@buf[1] & 0x3) << 8) + @buf[2]
      if @buf.size < len + 6 then
        @buf += @io.read(len + 6 - @buf.size).unpack('C*')
        return nil if @buf.size < len + 6
      end
      
      #p (((["%02X"] * 3) + ["%06X"]).join(', '))%[*(@buf[(len + 3)..(len + 5)]) + [RTCM3::checksum(@buf)]]
      if "\0#{@buf[(len + 3)..(len + 5)].pack('C3')}".unpack('N')[0] != RTCM3::checksum(@buf) then
        @buf = @buf[2..-1]
        next
      end
      
      packet = @buf[0..(len + 5)]
      @buf = @buf[(len + 6)..-1]
      
      return packet.extend(Packet)
    end
    return nil
  end
end
end
