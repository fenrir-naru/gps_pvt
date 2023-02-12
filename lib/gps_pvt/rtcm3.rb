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
      # 24 is offset of header in transport layer
      Util::BitOp::extract(self, bits_list, offset || 24)
    end
    def message_number
      decode([12]).first
    end
    DataFrame = proc{
      unum_gen = proc{|n, sf|
        next [n, proc{|v| v}] unless sf
        [n, sf.kind_of?(Rational) ? proc{|v| (sf * v).to_f} : proc{|v| sf * v}]
      }
      num_gen = proc{|n, sf|
        lim = 1 << (n - 1)
        lim2 = lim << 1
        next [n, proc{|v| v >= lim ? v - lim2 : v}] unless sf
        [n, sf.kind_of?(Rational) ?
            proc{|v| v -= lim2 if v >= lim; (sf * v).to_f} :
            proc{|v| v -= lim2 if v >= lim; sf * v}]
      }
      num_sign_gen = proc{|n, sf|
        lim = 1 << (n - 1)
        next [n, proc{|v| v >= lim ? lim - v : v}] unless sf
        [n, sf.kind_of?(Rational) ?
            proc{|v| v = lim - v if v >= lim; (sf * v).to_f} :
            proc{|v| v = lim - v if v >= lim; sf * v}]
      }
      invalidate = proc{|orig, err|
        [orig[0], proc{|v| v == err ? nil : orig[1].call(v)}]
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
        4 => unum_gen.call(30, Rational(1, 1000)), # [sec]
        5 => 1,
        6 => 5,
        7 => 1,
        8 => 3,
        9 => 6,
        10 => 1,
        11 => invalidate.call(unum_gen.call(24, Rational(2, 100)), 0x800000), # [m]
        12 => invalidate.call(num_gen.call(20, Rational(5, 10000)), 0x80000), # [m]
        13 => 7,
        14 => unum_gen.call(8, 299_792.458), # [m]
        15 => invalidate.call(unum_gen.call(8, Rational(1, 4)), 0), # [db-Hz],
        16 => 2,
        17 => invalidate.call(num_gen.call(14, Rational(2, 100)), 0x2000), # [m]
        18 => num_gen.call(20, Rational(5, 10000)), # [m]
        19 => 7,
        20 => invalidate.call(unum_gen.call(8, Rational(1, 4)), 0), # [db-Hz]
        21 => 6,
        22 => 1,
        23 => 1,
        24 => 1,
        25 => num_gen.call(38, Rational(1, 10000)), # [m]
        34 => unum_gen.call(27, Rational(1, 1000)), # [sec]
        35 => 5,
        36 => 1,
        37 => 3,
        38 => 6,
        39 => 1,
        40 => [5, proc{|v| v - 7}],
        41 => invalidate.call(unum_gen.call(25, Rational(2, 100)), 0x1000000), # [m]
        42 => invalidate.call(num_gen.call(20, Rational(5, 10000)), 0x80000), # [m]
        43 => 7,
        44 => unum_gen.call(7, 599_584.916), # [m]
        45 => invalidate.call(unum_gen.call(8, Rational(1, 4)), 0), # [db-Hz],
        46 => 2,
        47 => invalidate.call(num_gen.call(14, Rational(2, 100)), 0x2000), # [m]
        48 => invalidate.call(num_gen.call(20, Rational(5, 10000)), 0x80000), # [m]
        49 => 7,
        50 => invalidate.call(unum_gen.call(8, Rational(1, 4)), 0), # [db-Hz]
        71 => 8,
        76 => 10,
        77 => proc{
          idx2meter = [
              2.40, 3.40, 4.85, 6.85, 9.65, 13.65, 24.00, 48.00,
              96.00, 192.00, 384.00, 768.00, 1536.00, 3072.00, 6144.00]
          [4, proc{|v| (v >= idx2meter.size) ? (idx2meter[-1] * 2) : idx2meter[v]}]
        }.call, # [m]
        78 => 2,
        79 => num_gen.call(14, Rational(sc2rad, 1 << 43)), # [rad/s]
        81 => unum_gen.call(16, 1 << 4), # [sec]
        82 => num_gen.call(8, Rational(1, 1 << 55)), # [s/s^2]
        83 => num_gen.call(16, Rational(1, 1 << 43)), # [s/s]
        84 => num_gen.call(22, Rational(1, 1 << 31)), # [sec]
        85 => 10,
        86 => num_gen.call(16, Rational(1, 1 << 5)), # [m]
        87 => num_gen.call(16, Rational(sc2rad, 1 << 43)), # [rad/s]
        88 => num_gen.call(32, Rational(sc2rad, 1 << 31)), # [rad/s]
        89 => num_gen.call(16, Rational(1, 1 << 29)), # [rad]
        90 => unum_gen.call(32, Rational(1, 1 << 33)),
        91 => num_gen.call(16, Rational(1, 1 << 29)), # [rad]
        92 => unum_gen.call(32, Rational(1, 1 << 19)), # [m^1/2]
        93 => unum_gen.call(16, 1 << 4), # [sec]
        94 => num_gen.call(16, Rational(1, 1 << 29)), # [rad]
        95 => num_gen.call(32, Rational(sc2rad, 1 << 31)), # [rad/s]
        96 => num_gen.call(16, Rational(1, 1 << 29)), # [rad]
        97 => num_gen.call(32, Rational(sc2rad, 1 << 31)), # [rad/s]
        98 => num_gen.call(16, Rational(1, 1 << 5)), # [m]
        99 => num_gen.call(32, Rational(sc2rad, 1 << 31)), # [rad]
        100 => num_gen.call(24, Rational(sc2rad, 1 << 43)), # [rad/s]
        101 => num_gen.call(8, Rational(1, 1 << 31)), # [sec]
        102 => 6,
        103 => 1,
        104 => 1,
        105 => 1,
        106 => [2, proc{|v| [0, 30, 45, 60][v] * 60}], # [s]
        107 => [12, proc{|v|
          hh, mm, ss = [v >> 7, (v & 0x7E) >> 1, (v & 0x1) > 0 ? 30 : 0]
          hh * 3600 + mm * 60 + ss # [sec]
        }],
        108 => 1,
        109 => 1,
        110 => unum_gen.call(7, 15 * 60), # [sec]
        111 => num_sign_gen.call(24, Rational(1000, 1 << 20)), # [m/s]
        112 => num_sign_gen.call(27, Rational(1000, 1 << 11)), # [m]
        113 => num_sign_gen.call(5, Rational(1000, 1 << 30)), # [m/s^2]
        120 => 1,
        121 => num_sign_gen.call(11, Rational(1, 1 << 40)),
        122 => 2, # (M)
        123 => 1, # (M)
        124 => num_sign_gen.call(22, Rational(1, 1 << 30)), # [sec]
        125 => num_sign_gen.call(5, Rational(1, 1 << 30)), # [sec], (M)
        126 => 5, # [day]
        127 => 1, # (M)
        128 => [4, proc{|v|
          [1, 2, 2.5, 4, 5, 7, 10, 12, 14, 16, 32, 64, 128, 256, 512, 1024][v]
        }], # [m] (M)
        129 => 11, # [day]
        130 => 2, # 1 => GLONASS-M, (M) fields are active 
        131 => 1,
        132 => 11, # [day]
        133 => num_sign_gen.call(32, Rational(1, 1 << 31)), # [sec]
        134 => 5, # [4year], (M)
        135 => num_sign_gen.call(22, Rational(1, 1 << 30)), # [sec], (M)
        136 => 1, # (M)
        137 => 1,
        141 => 1,
        142 => 1,
        248 => 30,
        364 => 2,
        393 => 1,
        394 => idx_list_gen.call(64, 1),
        395 => idx_list_gen.call(32, 1),
        396 => proc{|df394, df395|
          x_list = df394.product(df395)
          idx_list = idx_list_gen.call(x_list.size)[1]
          [x_list.size, proc{|v| x_list.values_at(*idx_list.call(v))}]
        },
        397 => invalidate.call(unum_gen.call(8, Rational(1, 1000)), 0xFF), # [sec]
        398 => unum_gen.call(10, Rational(1, 1000 << 10)), # [sec]
        399 => invalidate.call(num_gen.call(14), 0x2000), # [m/s]
        400 => invalidate.call(num_gen.call(15, Rational(1, 1000 << 24)), 0x4000), # [sec],
        401 => invalidate.call(num_gen.call(22, Rational(1, 1000 << 29)), 0x200000), # [sec],
        402 => 4,
        403 => invalidate.call(unum_gen.call(6), 0), # [dB-Hz],
        404 => invalidate.call(num_gen.call(15, Rational(1, 10000)), 0x4000), # [m/s]
        405 => invalidate.call(num_gen.call(20, Rational(1, 1000 << 29)), 0x80000), # [sec]
        406 => invalidate.call(num_gen.call(24, Rational(1, 1000 << 31)), 0x800000), # [sec]
        407 => 10,
        408 => invalidate.call(unum_gen.call(10, Rational(1, 1 << 4)), 0), # [dB-Hz]
        409 => 3,
        411 => 2,
        412 => 2,
        416 => 3,
        417 => 1,
        418 => 3,
        420 => 1,
        429 => 4,
        :uint => proc{|n| n},
      }
      df[27] = df[26] = df[25]
      df[117] = df[114] = df[111]
      df[118] = df[115] = df[112]
      df[119] = df[116] = df[113]
      {430..433 => 81..84, 434 => 71, 435..449 => 86..100, 450 => 79, 451 => 78,
          452 => 76, 453 => 77, 454 => 102, 455 => 101, 456 => 85, 457 => 137}.each{|dst, src|
        # QZSS ephemeris => GPS
        src = (src.to_a rescue [src]).flatten
        (dst.to_a rescue ([dst] * src.size)).flatten.zip(src).each{|i, j| df[i] = df[j]}
      }
      df.merge!({
        :SBAS_prn => [6, proc{|v| v + 120}],
        :SBAS_iodn => 8,
        :SBAS_tod => num_gen.call(13, 1 << 4),
        :SBAS_ura => df[77],
        :SBAS_xy => num_gen.call(30, Rational(8, 100)),
        :SBAS_z => num_gen.call(25, Rational(4, 10)),
        :SBAS_dxy => num_gen.call(17, Rational(1, 1600)),
        :SBAS_dz => num_gen.call(18, Rational(1, 250)),
        :SBAS_ddxy => num_gen.call(10, Rational(1, 80000)),
        :SBAS_ddz => num_gen.call(10, Rational(1, 16000)),
        :SBAS_agf0 => num_gen.call(12, Rational(1, 1 << 31)),
        :SBAS_agf1 => num_gen.call(8, Rational(1, 1 << 40)),
      })
      df.define_singleton_method(:generate_prop){|idx_list|
        hash = Hash[*([:bits, :op].collect.with_index{|k, i|
          [k, idx_list.collect{|idx, *args|
            case prop = self[idx]
            when Proc; prop = prop.call(*args)
            end
            [prop].flatten(1)[i]
          }]
        }.flatten(1))].merge({:df => idx_list})
        hash[:bits_total] = hash[:bits].inject{|a, b| a + b} || 0
        hash
      }
      df
    }.call
    MessageType = Hash[*({
      1001..1004 => (2..8).to_a,
      1005 => [2, 3, 21, 22, 23, 24, 141, 25, 142, [1, 1], 26, 364, 27],
      1009..1012 => [2, 3, 34, 5, 35, 36, 37],
      1019 => [2, 9, (76..79).to_a, 71, (81..103).to_a, 137].flatten, # 488 bits @see Table 3.5-21
      1020 => [2, 38, 40, (104..136).to_a].flatten, # 360 bits @see Table 3.5-21
      1043 => [2] + [:prn, :iodn, :tod, :ura, 
          [:xy] * 2, :z, [:dxy] * 2, :dz, [:ddxy] * 2, :ddz,
          :agf0, :agf1].flatten.collect{|k| "SBAS_#{k}".to_sym}, # @see BNC Ntrip client RTCM3Decorder.cpp
      1044 => [2, (429..457).to_a].flatten, # 485 bits
      1071..1077 => [2, 3, 4, 393, 409, [1, 7], 411, 412, 417, 418, 394, 395], # 169 bits @see Table 3.5-78
      1081..1087 => [2, 3, 416, 34, 393, 409, [1, 7], 411, 412, 417, 418, 394, 395], # 169 bits @see Table 3.5-93
      1091..1097 => [2, 3, 248, 393, 409, [1, 7], 411, 412, 417, 418, 394, 395], # 169 bits @see Table 3.5-98
      1101..1107 => [2, 3, 4, 393, 409, [1, 7], 411, 412, 417, 418, 394, 395], # 169 bits
      1111..1117 => [2, 3, 4, 393, 409, [1, 7], 411, 412, 417, 418, 394, 395], # 169 bits
      1121..1127 => [2, 3, 4, 393, 409, [1, 7], 411, 412, 417, 418, 394, 395], # 169 bits
    }.collect{|mt_list, df_list|
      (mt_list.to_a rescue [mt_list]).collect{|mt|
        [mt, DataFrame.generate_prop(df_list)]
      }
    }.flatten(2))]
    module GPS_Observation
      def ranges
        res = {
          :sat => select{|v, df| df == 9}.transpose[0],
          :pseudo_range_rem => select{|v, df| df == 11}.transpose[0],
        }
        add_proc = proc{|k, df, base|
          values = select{|v, df_| df_ == df}
          next if values.empty?
          res[k] = values.transpose[0]
          res[k] = res[k].zip(res[base]).collect{|a, b| (a + b) rescue nil} if base
        }
        add_proc.call(:pseudo_range, 14, :pseudo_range_rem)
        suffix = res[:pseudo_range] ? "" : "_rem"
        base = "pseudo_range#{suffix}".to_sym
        add_proc.call("phase_range#{suffix}".to_sym, 12, base)
        add_proc.call(:cn, 15)
        add_proc.call("pseudo_range_L2#{suffix}".to_sym, 17, base)
        add_proc.call("phase_range_L2#{suffix}".to_sym, 18, base)
        add_proc.call(:cn_L2, 20)
        res
      end
    end
    module GLONASS_Observation
      def ranges
        res = {
          :sat => select{|v, df| df == 38}.transpose[0],
          :freq_ch => select{|v, df| df == 40}.transpose[0],
          :pseudo_range_rem => select{|v, df| df == 41}.transpose[0],
        }
        add_proc = proc{|k, df, base|
          values = select{|v, df_| df_ == df}
          next if values.empty?
          res[k] = values.transpose[0]
          res[k] = res[k].zip(res[base]).collect{|a, b| (a + b) rescue nil} if base
        }
        add_proc.call(:pseudo_range, 44, :pseudo_range_rem)
        suffix = res[:pseudo_range] ? "" : "_rem"
        base = "pseudo_range#{suffix}".to_sym
        add_proc.call("phase_range#{suffix}".to_sym, 42, base)
        add_proc.call(:cn, 45)
        add_proc.call("pseudo_range_L2#{suffix}".to_sym, 47, base)
        add_proc.call("phase_range_L2#{suffix}".to_sym, 48, base)
        add_proc.call(:cn_L2, 50)
        res
      end
    end
    module GPS_Ephemeris
      KEY2IDX = {:svid => 1, :WN => 2, :URA => 3, :dot_i0 => 5, :iode => 6, :t_oc => 7,
          :a_f2 => 8, :a_f1 => 9, :a_f0 => 10, :iodc => 11, :c_rs => 12, :delta_n => 13,
          :M0 => 14, :c_uc => 15, :e => 16, :c_us => 17, :sqrt_A => 18, :t_oe => 19, :c_ic => 20,
          :Omega0 => 21, :c_is => 22, :i0 => 23, :c_rc => 24, :omega => 25, :dot_Omega0 => 26,
          :t_GD => 27, :SV_health => 28}
      def params
        # TODO WN is truncated to 0-1023
        res = Hash[*(KEY2IDX.collect{|k, i| [k, self[i][0]]}.flatten(1))]
        res[:fit_interval] = ((self[29] == 0) ? 4 : case res[:iodc] 
          when 240..247; 8
          when 248..255, 496; 14
          when 497..503; 26
          when 504..510; 50
          when 511, 752..756; 74
          when 757..763; 98
          when 764..767, 1088..1010; 122
          when 1011..1020; 146
          else; 6
        end) * 60 * 60
        res
      end
    end
    module SBAS_Ephemeris
      KEY2IDX = {:svid => 1, :iodn => 2, :tod => 3, :URA => 4,
          :x => 5, :y => 6, :z => 7,
          :dx => 8, :dy => 9, :dz => 10,
          :ddx => 11, :ddy => 12, :ddz => 13,
          :a_Gf0 => 14, :a_Gf1 => 15}
      def params
        # TODO WN is required to provide
        Hash[*(KEY2IDX.collect{|k, i| [k, self[i][0]]}.flatten(1))]
      end
    end
    module GLONASS_Ephemeris
      def params
        # TODO insufficient: :n => ?(String4); extra: :P3
        # TODO generate time with t_b, N_T, NA, N_4
        # TODO GPS.i is required to modify to generate EPhemeris_with_GPS_Time
        k_i =  {:svid => 1, :freq_ch => 2, :P1 => 5, :t_k => 6, :B_n => 7, :P2 => 8, :t_b => 9,
            :xn_dot => 10, :xn => 11, :xn_ddot => 12,
            :yn_dot => 13, :yn => 14, :yn_ddot => 15,
            :zn_dot => 16, :zn => 17, :zn_ddot => 18,
            :P3 => 19, :gamma_n => 20, :p => 21, :tau_n => 23, :delta_tau_n => 24, :E_n => 25,
            :P4 => 26, :F_T => 27, :N_T => 28, :M => 29}
        k_i.merge!({:NA => 31, :tau_c => 32, :N_4 => 33, :tau_GPS => 34}) if self[30][0] == 1 # check DF131
        res = Hash[*(k_i.collect{|k, i| [k, self[i][0]]}.flatten(1))]
        res.reject!{|k, v|
          case k
          when :N_T; v == 0
          when :p, :delta_tau_n, :P4, :F_T, :N_4, :tau_GPS; true # TODO sometimes delta_tau_n is valid?
          else; false
          end
        } if (res[:M] != 1) # check DF130
        res
      end
    end
    module QZSS_Ephemeris
      KEY2IDX = {:svid => 1, :t_oc => 2, :a_f2 => 3, :a_f1 => 4, :a_f0 => 5,
          :iode => 6, :c_rs => 7, :delta_n => 8, :M0 => 9, :c_uc => 10, :e => 11,
          :c_us => 12, :sqrt_A => 13, :t_oe => 14, :c_ic => 15, :Omega0 => 16,
          :c_is => 17, :i0 => 18, :c_rc => 19, :omega => 20, :dot_Omega0 => 21,
          :dot_i0 => 22, :WN => 24, :URA => 25, :SV_health => 26,
          :t_GD => 27, :iodc => 28}
      def params
        # TODO PRN = svid + 192, WN is truncated to 0-1023
        res = Hash[*(KEY2IDX.collect{|k, i| [k, self[i][0]]}.flatten(1))]
        res[:fit_interval] = (self[29] == 0) ? 2 * 60 * 60 : nil # TODO how to treat fit_interval > 2 hrs
        res
      end
    end
    module MSM_Header
      def more_data?
        self.find{|v| v[1] == 393}[0] == 1
      end
      def property
        idx_sat = self.find_index{|v| v[1] == 394}
        {
          :sats => self[idx_sat][0],
          :cells => self[idx_sat + 2][0], # DF396
          :header_items => idx_sat + 3,
        }
      end
    end
    module MSM
      include MSM_Header
      def ranges
        {:sat_sig => property[:cells]} # expect to be overriden
      end
      SPEED_OF_LIGHT = 299_792_458
    end
    module MSM4
      include MSM
      def ranges
        sats, cells, offset = property.values_at(:sats, :cells, :header_items)
        nsat, ncell = [sats.size, cells.size]
        range_rough = self[offset, nsat] # DF397
        range_rough2 = self[offset + (nsat * 1), nsat] # DF398
        range_fine = self[offset + (nsat * 2), ncell] # DF400
        phase_fine = self[offset + (nsat * 2) + (ncell * 1), ncell] # DF401
        cn = self[offset + (nsat * 2) + (ncell * 4), ncell] # DF403
        Hash[*([:sat_sig, :pseudo_range, :phase_range, :cn].zip(
            [cells] + cells.collect.with_index{|(sat, sig), i|
              i2 = sats.find_index(sat)
              rough_ms = (range_rough2[i2][0] + range_rough[i2][0]) rescue nil
              [(((range_fine[i][0] + rough_ms) * SPEED_OF_LIGHT) rescue nil),
                  (((phase_fine[i][0] + rough_ms) * SPEED_OF_LIGHT) rescue nil),
                  cn[i][0]]
            }.transpose).flatten(1))]
      end
    end
    module MSM7
      include MSM
      def ranges
        sats, cells, offset = property.values_at(:sats, :cells, :header_items)
        nsat, ncell = [sats.size, cells.size]
        range_rough = self[offset, nsat] # DF397
        range_rough2 = self[offset + (nsat * 2), nsat] # DF398
        delta_rough = self[offset + (nsat * 3), nsat] # DF399
        range_fine = self[offset + (nsat * 4), ncell] # DF405
        phase_fine = self[offset + (nsat * 4) + (ncell * 1), ncell] # DF406
        cn = self[offset + (nsat * 4) + (ncell * 4), ncell] # DF403
        delta_fine = self[offset + (nsat * 4) + (ncell * 5), ncell] # DF404
        Hash[*([:sat_sig, :pseudo_range, :phase_range, :phase_range_rate, :cn].zip(
            [cells] + cells.collect.with_index{|(sat, sig), i|
              i2 = sats.find_index(sat)
              rough_ms = (range_rough2[i2][0] + range_rough[i2][0]) rescue nil
              [(((range_fine[i][0] + rough_ms) * SPEED_OF_LIGHT) rescue nil),
                  (((phase_fine[i][0] + rough_ms) * SPEED_OF_LIGHT) rescue nil),
                  ((delta_fine[i][0] + delta_rough[i2][0]) rescue nil),
                  cn[i][0]]
            }.transpose).flatten(1))]
      end
    end
    def parse
      msg_num = message_number
      return nil unless (mt = MessageType[msg_num])
      # return [[value, df], ...]
      values, df_list, attributes = [[], [], []]
      add_proc = proc{|target, offset|
        values += decode(target[:bits], offset).zip(target[:op]).collect{|v, op|
          op ? op.call(v) : v
        }
        df_list += target[:df]
      }
      add_proc.call(mt)
      case msg_num
      when 1001..1004
        nsat = values[4]
        offset = 24 + mt[:bits_total]
        add_proc.call(DataFrame.generate_prop(([{
              1001 => (9..13).to_a,
              1002 => (9..15).to_a,
              1003 => (9..13).to_a + (16..19).to_a,
              1004 => (9..20).to_a,
            }[msg_num]] * nsat).flatten), offset)
        attributes << GPS_Observation
      when 1009..1012
        nsat = values[4]
        offset = 24 + mt[:bits_total]
        add_proc.call(DataFrame.generate_prop(([{
              1009 => (38..43).to_a,
              1010 => (38..45).to_a,
              1011 => (38..43).to_a + (46..49).to_a,
              1012 => (38..50).to_a,
            }[msg_num]] * nsat).flatten), offset)
        attributes << GLONASS_Observation
      when 1019
        attributes << GPS_Ephemeris
      when 1020
        attributes << GLONASS_Ephemeris
      when 1043
        attributes << SBAS_Ephemeris
      when 1044
        attributes << QZSS_Ephemeris
      when 1071..1077, 1081..1087, 1091..1097, 1101..1107, 1111..1117, 1121..1127
        # 107X(GPS), 108X(GLONASS), 109X(GALILEO), 110X(SBAS), 111X(QZSS), 112X(Beidou)
        nsat, nsig = [-2, -1].collect{|i| values[i].size}
        offset = 24 + mt[:bits_total]
        df396 = DataFrame.generate_prop([[396, values[-2], values[-1]]])
        add_proc.call(df396, offset)
        ncell = values[-1].size
        offset += df396[:bits_total]
        case msg_num % 10
        when 4
          attributes << MSM4
          msm4_sat = DataFrame.generate_prop(([[397, 398]] * nsat).transpose.flatten(1))
          add_proc.call(msm4_sat, offset)
          offset += msm4_sat[:bits_total]
          msm4_sig = DataFrame.generate_prop(
              ([[400, 401, 402, 420, 403]] * ncell).transpose.flatten(1))
          add_proc.call(msm4_sig, offset)
        when 7
          attributes << MSM7
          msm7_sat = DataFrame.generate_prop(
              ([[397, [:uint, 4], 398, 399]] * nsat).transpose.flatten(1))
          add_proc.call(msm7_sat, offset)
          offset += msm7_sat[:bits_total]
          msm7_sig = DataFrame.generate_prop(
              ([[405, 406, 407, 420, 408, 404]] * ncell).transpose.flatten(1))
          add_proc.call(msm7_sig, offset)
        else
          attributes << MSM # for #range
        end
      end
      attributes << MSM_Header if (1070..1229).include?(msg_num)
      res = values.zip(df_list)
      attributes.empty? ? res : res.extend(*attributes)
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
