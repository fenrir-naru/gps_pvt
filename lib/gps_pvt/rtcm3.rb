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
