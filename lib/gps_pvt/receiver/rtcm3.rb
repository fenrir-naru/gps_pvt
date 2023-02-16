=begin
RTCM3 handler  for receiver
=end

module GPS_PVT
class Receiver
  def parse_rtcm3(src, opt = {}, &b)
    $stderr.print "Reading RTCM3 stream (%s) "%[src]
    require_relative '../rtcm3'
    src_io = Util::open(src)
    rtcm3 = GPS_PVT::RTCM3::new(src_io)
    ref_time = case (ref_time = opt[:ref_time])
    when GPS::Time; 
    when Time
      t_array = ref_time.utc.to_a[0..5].reverse
      GPS::Time::new(t_array, GPS::Time::guess_leap_seconds(t_array))
    when nil; GPS::Time::now
    else; raise "reference time (#{ref_time}) should be GPS::Time or Time"
    end
    leap_sec = ref_time.leap_seconds
    ref_pos = opt[:ref_pos] || if src_io.respond_to?(:property) then
      Coordinate::LLH::new(*(src_io.property.values_at(:latitude, :longitude).collect{|v|
        v.to_f / 180 * Math::PI
      } + [0])).xyz
    else 
      defined?(@base_station) ? @base_station : nil
    end
    after_run = b || proc{|pvt| puts pvt.to_s if pvt}
    t_meas, meas = [nil, {}]
    # meas := {msg_num => [[], ...]} due to duplicated observation such as 1074 and 1077
    run_proc = proc{
      meas_ = GPS::Measurement::new
      meas.sort.each{|k, values| # larger msg_num entries have higher priority
        values.each{|prn_k_v| meas_.add(*prn_k_v)}
      }
      pvt = nil
      after_run.call(pvt = run(meas_, t_meas), [meas_, ref_time = t_meas]) if t_meas
      ref_pos = Coordinate::XYZ::new(pvt.xyz) if pvt && pvt.position_solved? # TODO pvt.xyz returns const &
      t_meas, meas = [nil, {}]
    }
    dt_threshold = GPS::Time::Seconds_week / 2
    tow2t = proc{|tow_sec|
      dt = tow_sec - ref_time.seconds 
      GPS::Time::new(ref_time.week + if dt <= -dt_threshold then; 1
            elsif dt >= dt_threshold then; -1
            else; 0; end, tow_sec)
    }
    utc2t = proc{|utc_tod|
      if t_meas then
        delta = (t_meas.seconds - utc_tod).to_i % (60 * 60 * 24)
        leap_sec = (delta >= (60 * 60 * 12)) ? delta - (60 * 60 * 12) : delta
        t_meas
      else
        ref_dow, ref_tod = ref_time.seconds.divmod(60 * 60 * 24)
        tod = utc_tod + leap_sec
        tod_delta = ref_tod - tod
        if tod_delta > 12 * 60 * 60 then
          ref_dow -= 1
        elsif tod_delta < -12 * 60 * 60 then
          ref_dow += 1
        end
        GPS::Time::new(ref_time.week, 0) + tod + 60 * 60 * 24 * ref_dow
      end
    }
    restore_ranges = proc{
      c_1ms = 299_792.458
      threshold = c_1ms / 10 # 100 us =~ 30 km
      cache = {} # {[sys, svid] => [range, t], ...}
      get_rough = proc{|t, sys_svid_list|
        sn_list = sys_svid_list.collect{|sys, svid|
          case sys
          when :GPS, :QZSS; @solver.gps_space_node
          when :SBAS; @solver.sbas_space_node
          when :GLONASS; @solver.glonass_space_node
          end
        }
        critical{
          sn_list.uniq.compact{|sn| sn.update_all_ephemeris(t)}
          sys_svid_list.zip(sn_list).each{|(sys, svid), sn|
            next unless sn
            eph = sn.ephemeris(svid)
            cache[[sys, svid]] = [if eph.valid?(t) then
              sv_pos, clk_err = eph.constellation(t).values_at(0, 2)
              sv_pos.dist(ref_pos) - (clk_err * c_1ms * 1E3)
            end, t]
          }
        }
      }
      per_kind = proc{|t, sys_svid_list, ranges_rem|
        get_rough.call(t, sys_svid_list.uniq.reject{|sys, svid|
          next true unless sys
          range, t2 = cache[[sys, svid]]
          range && ((t2 - t).abs <= 60)
        })
        ranges_rem.zip(sys_svid_list).collect{|rem_in, (sys, svid)|
          range_ref, t2 = cache[[sys, svid]]
          next nil unless range_ref
          q, rem_ref = range_ref.divmod(c_1ms)
          delta = rem_in - rem_ref 
          res = if delta.abs <= threshold then
            q * c_1ms + rem_in
          elsif -delta + c_1ms <= threshold
            (q - 1) * c_1ms + rem_in
          elsif delta + c_1ms <= threshold
            (q + 1) * c_1ms + rem_in
          end
          #p [sys, svid, q, rem_in, rem_ref, res]
          (cache[[sys, svid]] = [res, t])[0]
        }
      }
      proc{|t, sys_svid_list, ranges|
        [
          :pseudo_range, # for MT 1001/3/9/11, MSM1/3
          :phase_range, # for MT 1003/11, MSM2/3
        ].each{|k|
          next if ranges[k]
          k_rem = "#{k}_rem".to_sym
          ranges[k] = per_kind.call(t, sys_svid_list, ranges[k_rem]) if ranges[k_rem]
        }
      }
    }.call

    while packet = rtcm3.read_packet
      msg_num = packet.message_number
      parsed = packet.parse
      t_meas2, meas2 = [nil, []] # per_packet
      add_proc = proc{
        t_meas ||= t_meas2
        meas[msg_num] = meas2 unless meas2.empty?
      }
      case msg_num
      when 1001..1004
        t_meas2 = tow2t.call(parsed[2][0]) # DF004
        ranges = parsed.ranges
        sys_svid_list = ranges[:sat].collect{|svid|
          case svid
          when 1..32; [:GPS, svid]
          when 40..58; [:SBAS, svid + 80]
          else; [nil, svid]
          end
        }
        restore_ranges.call(t_meas2, sys_svid_list, ranges)
        item_size = sys_svid_list.size
        ([sys_svid_list] + [:pseudo_range, :phase_range, :cn].collect{|k|
          ranges[k] || ([nil] * item_size)
        }).transpose.each{|(sys, svid), pr, cpr, cn|
          next unless sys
          meas2 << [svid, :L1_PSEUDORANGE, pr] if pr
          meas2 << [svid, :L1_CARRIER_PHASE, cpr / GPS::SpaceNode.L1_WaveLength] if cpr
          meas2 << [svid, :L1_SIGNAL_STRENGTH_dBHz, cn] if cn
        }
      when 1009..1012
        t_meas2 = utc2t.call(parsed[2][0] - 60 * 60 * 3) # DF034 UTC(SU)+3hr, time of day[sec]
        ranges = parsed.ranges
        sys_svid_list = ranges[:sat].collect{|svid|
          case svid
          when 1..24; [:GLONASS, svid]
          when 40..58; [:SBAS, svid + 80]
          else; [nil, svid]
          end
        }
        restore_ranges.call(t_meas2, sys_svid_list, ranges)
        item_size = sys_svid_list.size
        ([sys_svid_list] + [:freq_ch, :pseudo_range, :phase_range, :cn].collect{|k|
          ranges[k] || ([nil] * item_size)
        }).transpose.each{|(sys, svid), freq_ch, pr, cpr, cn|
          case sys
          when :GLONASS
            svid += 0x100
            freq = GPS::SpaceNode_GLONASS::L1_frequency(freq_ch)
            len = GPS::SpaceNode_GLONASS.light_speed / freq
            meas2 << [svid, :L1_FREQUENCY, freq]
            meas2 << [svid, :L1_CARRIER_PHASE, cpr / len] if cpr
          when :SBAS
            meas2 << [svid, :L1_CARRIER_PHASE, cpr / GPS::SpaceNode.L1_WaveLength] if cpr
          else; next
          end
          meas2 << [svid, :L1_PSEUDORANGE, pr] if pr
          meas2 << [svid, :L1_SIGNAL_STRENGTH_dBHz, cn] if cn
        }
      when 1013
        leap_sec = parsed[5][0]
      when 1019, 1044
        params = parsed.params
        if msg_num == 1044
          params[:svid] += 192
          params[:fit_interval] ||= 2 * 60 * 60
        end
        params[:WN] += ((ref_time.week - params[:WN]).to_f / 1024).round * 1024
        eph = GPS::Ephemeris::new
        params.each{|k, v| eph.send("#{k}=".to_sym, v)}
        critical{
          @solver.gps_space_node.register_ephemeris(eph.svid, eph)
        }
      when 1020
        params = parsed.params
        eph = GPS::Ephemeris_GLONASS::new
        params[:F_T] ||= 10 # [m]
        params.each{|k, v|
          next if [:P3, :NA, :N_4].include?(k)
          eph.send("#{k}=".to_sym, v)
        }
        proc{|date_src|
          eph.set_date(*(date_src.all? \
              ? date_src \
              : [(ref_time + 3 * 60 * 60).c_tm(leap_sec)])) # UTC -> Moscow time
        }.call([:N_4, :NA].collect{|k| params[k]})
        eph.rehash(leap_sec)
        critical{
          @solver.glonass_space_node.register_ephemeris(eph.svid, eph)
        }
      when 1043
        params = parsed.params
        eph = GPS::Ephemeris_SBAS::new
        tod_delta = params[:tod] - (ref_time.seconds % (24 * 60 * 60)) 
        if tod_delta > (12 * 60 * 60) then
          tod_delta -= (24 * 60 * 60)
        elsif tod_delta < -(12 * 60 * 60) then
          tod_delta += (24 * 60 * 60)
        end
        toe = ref_time + tod_delta
        eph.WN, eph.t_0 = [:week, :seconds].collect{|k| toe.send(k)}
        params.each{|k, v| eph.send("#{k}=".to_sym, v) unless [:iodn, :tod].include?(k)}
        critical{
          @solver.sbas_space_node.register_ephemeris(eph.svid, eph)
        }
      when 1071..1077, 1081..1087, 1101..1107, 1111..1117
        ranges = parsed.ranges
        glonass_freq = nil
        case msg_num / 10 # check time of measurement
        when 107, 110, 111 # GPS, SBAS, QZSS
          t_meas2 = tow2t.call(parsed[2][0]) # DF004
        when 108 # GLONASS
          t_meas2 = utc2t.call(parsed[3][0] - 60 * 60 * 3) # DF034 UTC(SU)+3hr, time of day[sec]
          glonass_freq = critical{
            @solver.glonass_space_node.update_all_ephemeris(t_meas2)
            Hash[*(ranges[:sat_sig].collect{|svid, sig| svid}.uniq.collect{|svid|
              eph = @solver.glonass_space_node.ephemeris(svid)
              next nil unless eph.in_range?(t_meas2)
              [svid, {:L1 => eph.frequency_L1}]
            }.compact.flatten(1))]
          }
        end
        sig_list, sys, svid_offset = case msg_num / 10
          when 107 # GPS
            [{2 => [:L1, GPS::SpaceNode.L1_WaveLength],
                15 => [:L2CM, GPS::SpaceNode.L2_WaveLength],
                16 => [:L2CL, GPS::SpaceNode.L2_WaveLength]}, :GPS, 0]
          when 108 # GLONASS
            [{2 => [:L1, nil]}, :GLONASS, 0x100]
          when 110 # SBAS
            [{2 => [:L1, GPS::SpaceNode.L1_WaveLength]}, :SBAS, 120]
          when 111 # QZSS
            [{2 => [:L1, GPS::SpaceNode.L1_WaveLength],
                15 => [:L2CM, GPS::SpaceNode.L2_WaveLength],
                16 => [:L2CL, GPS::SpaceNode.L2_WaveLength]}, :QZSS, 192]
          else; [{}, nil, 0]
        end
        sys_svid_list = ranges[:sat_sig].collect{|sat, sig| [sys, (sat + svid_offset) & 0xFF]}
        restore_ranges.call(t_meas2, sys_svid_list, ranges)
        item_size = sys_svid_list.size
        [:sat_sig, :pseudo_range, :phase_range, :phase_range_rate, :cn].collect{|k|
          ranges[k] || ([nil] * item_size)
        }.transpose.each{|(svid, sig), pr, cpr, dr, cn|
          prefix, len = sig_list[sig]
          next unless prefix
          proc{
            next unless freq = (glonass_freq[svid] || {})[prefix]
            meas2 << [svid, "#{prefix}_FREQUENCY".to_sym, freq]
            len = GPS::SpaceNode_GLONASS.light_speed / freq
          }.call if glonass_freq
          svid += svid_offset
          meas2 << [svid, "#{prefix}_PSEUDORANGE".to_sym, pr] if pr
          meas2 << [svid, "#{prefix}_RANGE_RATE".to_sym, dr] if dr
          meas2 << [svid, "#{prefix}_CARRIER_PHASE".to_sym, cpr / len] if cpr && len
          meas2 << [svid, "#{prefix}_SIGNAL_STRENGTH_dBHz".to_sym, cn] if cn
        }
      else
        #p({msg_num => parsed})
      end
      
      run_proc.call if t_meas && t_meas2 && ((t_meas - t_meas2).abs > 1E-3) # fallback for incorrect more_data flag
      add_proc.call
      run_proc.call if (1070..1229).include?(msg_num) && (!parsed.more_data?)
    end
  end
end
end
