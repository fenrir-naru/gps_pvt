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
    def decode(bits_list, offset = nil)
      Util::BitOp::extract(self, bits_list, offset || 24)
    end
    def message_number
      decode([12]).first
    end
    DataFrame = proc{
      unum_gen = proc{|n, sf|
        sf ||= 1
        [n, sf.kind_of?(Rational) ? proc{|v| (sf * v).to_f} : proc{|v| sf * v}]
      }
      num_gen = proc{|n, sf|
        lim = 1 << (n - 1)
        lim2 = lim << 1
        sf ||= 1
        [n, sf.kind_of?(Rational) ?
            proc{|v| v -= lim2 if v >= lim; (sf * v).to_f} :
            proc{|v| v -= lim2 if v >= lim; sf * v}]
      }
      num_sign_gen = proc{|n, sf|
        lim = 1 << (n - 1)
        sf ||= 1
        [n, sf.kind_of?(Rational) ?
            proc{|v| v = lim - v if v >= lim; (sf * v).to_f} :
            proc{|v| v = lim - v if v >= lim; sf * v}]
      }
      idx_list_gen = proc{|n, start|
        start ||= 0
        idx_list = (start...(start+n)).to_a.reverse
        [n, proc{|v| idx_list.inject([]){|res, idx|
          res.unshift(idx) if (v & 0x1) > 0
          break res unless (v >>= 1) > 0
          res
        } }]
      }
      sc2rad = 3.1415926535898
      df = { # {df_num => [bits, post_process] or generator_proc, ...}
        1 => proc{|n| n},
        2 => 12,
        3 => 12,
        4 => 30,
        9 => 6,
        21 => 6,
        22 => 1,
        23 => 1,
        24 => 1,
        25 => num_gen.call(38, Rational(1, 10000)),
        34 => 27,
        38 => 6,
        40 => 5,
        71 => 8,
        76 => 10,
        77 => 4,
        78 => 2,
        79 => num_gen.call(14, Rational(sc2rad, 1 << 43)),
        81 => unum_gen.call(16, 1 << 4),
        82 => num_gen.call(8, Rational(1, 1 << 55)),
        83 => num_gen.call(16, Rational(1, 1 << 43)),
        84 => num_gen.call(22, Rational(1, 1 << 31)),
        85 => 10,
        86 => num_gen.call(16, Rational(1, 1 << 5)),
        87 => num_gen.call(16, Rational(sc2rad, 1 << 43)),
        88 => num_gen.call(32, Rational(sc2rad, 1 << 31)),
        89 => num_gen.call(16, Rational(1, 1 << 29)),
        90 => unum_gen.call(32, Rational(1, 1 << 33)),
        91 => num_gen.call(16, Rational(1, 1 << 29)),
        92 => unum_gen.call(32, Rational(1, 1 << 19)),
        93 => unum_gen.call(16, 1 << 4),
        94 => num_gen.call(16, Rational(1, 1 << 29)),
        95 => num_gen.call(32, Rational(sc2rad, 1 << 31)),
        96 => num_gen.call(16, Rational(1, 1 << 29)),
        97 => num_gen.call(32, Rational(sc2rad, 1 << 31)),
        98 => num_gen.call(16, Rational(1, 1 << 5)),
        99 => num_gen.call(32, Rational(sc2rad, 1 << 31)),
        100 => num_gen.call(24, Rational(sc2rad, 1 << 43)),
        101 => num_gen.call(8, Rational(1, 1 << 31)),
        102 => 6,
        103 => 1,
        104 => 1,
        105 => 1,
        106 => 2,
        107 => [12, proc{|v| [v >> 7, (v & 0x7E) >> 1, (v & 0x1) > 0 ? 30 : 0]}],
        108 => 1,
        109 => 1,
        110 => unum_gen.call(7, 15 * 60),
        111 => num_sign_gen.call(24, Rational(1000, 1 << 20)),
        112 => num_sign_gen.call(27, Rational(1000, 1 << 11)),
        113 => num_sign_gen.call(5, Rational(1000, 1 << 30)),
        120 => 1,
        121 => num_sign_gen.call(11, Rational(1, 1 << 40)),
        122 => 2,
        123 => 1,
        124 => num_sign_gen.call(22, Rational(1, 1 << 30)),
        125 => num_sign_gen.call(5, Rational(1, 1 << 30)),
        126 => 5,
        127 => 1,
        128 => 4,
        129 => 11,
        130 => 2,
        131 => 1,
        132 => 11,
        133 => num_sign_gen.call(32, Rational(1, 1 << 31)),
        134 => 5,
        135 => num_sign_gen.call(22, Rational(1, 1 << 30)),
        136 => 1,
        137 => 1,
        141 => 1,
        142 => 1,
        248 => 30,
        364 => 2,
        393 => 1,
        394 => idx_list_gen.call(64, 1),
        395 => idx_list_gen.call(32, 1),
        396 => proc{|df394, df395|
          x_list = df395.product(df394).collect{|sig_prn| sig_prn.reverse}
          idx_list = idx_list_gen.call(x_list.size)[1]
          [x_list.size, proc{|v| x_list.values_at(*idx_list.call(v))}]
        },
        397 => 8,
        398 => unum_gen.call(10, Rational(1, 1 << 10)),
        399 => num_gen.call(14),
        404 => num_gen.call(15, Rational(1, 10000)),
        405 => num_gen.call(20, Rational(1, 1 << 29)),
        406 => num_gen.call(24, Rational(1, 1 << 31)),
        407 => 10,
        408 => unum_gen.call(10, Rational(1, 1 << 4)),
        409 => 3,
        411 => 2,
        412 => 2,
        416 => 3,
        417 => 1,
        418 => 3,
        420 => 1,
        :uint => proc{|n| n},
      }
      df[27] = df[26] = df[25]
      df[117] = df[114] = df[111]
      df[118] = df[115] = df[112]
      df[119] = df[116] = df[113]
      df.define_singleton_method(:generate_prop){|idx_list|
        hash = Hash[*([:bits, :op].collect.with_index{|k, i|
          [k, idx_list.collect{|idx, *args|
            case prop = self[idx]
            when Proc; prop = prop.call(*args)
            end
            [prop].flatten(1)[i]
          }]
        }.flatten(1))].merge({:df => idx_list})
        hash[:bits_total] = hash[:bits].inject{|a, b| a + b}
        hash
      }
      df
    }.call
    MessageType = Hash[*({
      1005 => [2, 3, 21, 22, 23, 24, 141, 25, 142, [1, 1], 26, 364, 27],
      1019 => [2, 9, (76..79).to_a, 71, (81..103).to_a, 137].flatten, # 488 bits @see Table 3.5-21
      1020 => [2, 38, 40, (104..136).to_a].flatten, # 360 bits @see Table 3.5-21
      1077 => [2, 3, 4, 393, 409, [1, 7], 411, 412, 417, 418, 394, 395], # 169 bits @see Table 3.5-78
      1087 => [2, 3, 416, 34, 393, 409, [1, 7], 411, 412, 417, 418, 394, 395], # 169 bits @see Table 3.5-93
      1097 => [2, 3, 248, 393, 409, [1, 7], 411, 412, 417, 418, 394, 395], # 169 bits @see Table 3.5-98
    }.collect{|mt, df_list| [mt, DataFrame.generate_prop(df_list)]}.flatten(1))]
    def parse
      msg_num = message_number
      return nil unless (mt = MessageType[msg_num])
      # return [[value, df], ...]
      values, df_list = [[], []]
      add_proc = proc{|target, offset|
        values += decode(target[:bits], offset).zip(target[:op]).collect{|v, op|
          op ? op.call(v) : v
        }
        df_list += target[:df]
      }
      add_proc.call(mt)
      case msg_num
      when 1077, 1087, 1097
        # 1077(GPS), 1087(GLONASS), 1097(GALILEO)
        nsat, nsig = [-2, -1].collect{|i| values[i].size}
        offset = 24 + mt[:bits_total]
        df396 = DataFrame.generate_prop([[396, values[-2], values[-1]]])
        add_proc.call(df396, offset)
        ncell = values[-1].size
        offset += df396[:bits_total]
        msm7_sat = DataFrame.generate_prop(
            ([[397, [:uint, 4], 398, 399]] * nsat).transpose.flatten(1))
        add_proc.call(msm7_sat, offset)
        offset += msm7_sat[:bits_total]
        msm7_sig = DataFrame.generate_prop(
            ([[405, 406, 407, 420, 408, 404]] * ncell).transpose.flatten(1))
        add_proc.call(msm7_sig, offset)
      end
      values.zip(df_list)
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
