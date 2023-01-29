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
    after_run = b || proc{|pvt| puts pvt.to_s if pvt}
    t_meas, meas = [nil, {}]
    # meas := {msg_num => [[], ...]} due to duplicated observation such as 1074 and 1077
    dt_threshold = GPS::Time::Seconds_week / 2

    while packet = rtcm3.read_packet
      msg_num = packet.message_number
      parsed = packet.parse
      case msg_num
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
      when 1071..1077, 1081..1087, 1091..1097, 1111..1117
        ranges = parsed.ranges
        glonass = nil
        sig_list, svid_offset = case msg_num / 10
          when 107 # GPS
            t_meas ||= proc{ # update time of measurement
              t_meas_sec = parsed[2][0] # DF004
              dt = t_meas_sec - ref_time.seconds 
              GPS::Time::new(ref_time.week + if dt <= -dt_threshold then; 1
                  elsif dt >= dt_threshold then; -1
                  else; 0; end, t_meas_sec)
            }.call
            [{2 => [:L1, GPS::SpaceNode.L1_WaveLength],
                15 => [:L2CM, GPS::SpaceNode.L2_WaveLength],
                16 => [:L2CL, GPS::SpaceNode.L2_WaveLength]}, 0]
          when 108 # GLONASS
            proc{
              utc = parsed[3][0] - 60 * 60 * 3 # DF034 UTC(SU)+3hr
              delta = (t_meas.seconds - utc).to_i % (60 * 60 * 24)
              leap_sec = (delta >= (60 * 60 * 12)) ? delta - (60 * 60 * 12) : delta
              (glonass = @solver.glonass_space_node).update_all_ephemeris(t_meas)
            }.call if t_meas
            [{2 => [:L1, nil]}, 0x100]
          when 111 # QZSS
            [{2 => [:L1, GPS::SpaceNode.L1_WaveLength],
                15 => [:L2CM, GPS::SpaceNode.L2_WaveLength],
                16 => [:L2CL, GPS::SpaceNode.L2_WaveLength]}, 192]
          else; [{}, 0]
        end
        meas[msg_num] = meas_ = []
        item_size = ranges[:sat_sig].size
        [:sat_sig, :pseudo_range, :phase_range, :phase_range_rate, :cn].collect{|k|
          ranges[k] || ([nil] * item_size)
        }.transpose.each{|(svid, sig), pr, cpr, dr, cn|
          prefix, len = sig_list[sig]
          next unless prefix
          proc{|eph|
            next unless eph.in_range?(t_meas)
            freq = eph.send("frequency_#{prefix}".to_sym)
            meas_ << [svid, "#{prefix}_FREQUENCY".to_sym, freq]
            len = GPS::SpaceNode_GLONASS.light_speed / freq
          }.call(glonass.ephemeris(svid)) if glonass
          svid += svid_offset
          meas_ << [svid, "#{prefix}_PSEUDORANGE".to_sym, pr] if pr
          meas_ << [svid, "#{prefix}_RANGE_RATE".to_sym, dr] if dr
          meas_ << [svid, "#{prefix}_CARRIER_PHASE".to_sym, cpr / len] if cpr && len
          meas_ << [svid, "#{prefix}_SIGNAL_STRENGTH_dBHz".to_sym, cn] if cn
        }
      else
        #p({msg_num => parsed})
      end
      if (1070..1229).include?(msg_num) && 
          (!parsed.more_data? rescue (packet.decode([1], 24 + 54)[0] == 0)) then
        if t_meas then
          meas_ = GPS::Measurement::new
          meas.sort.each{|k, values| # larger msg_num entries have higher priority
            values.each{|prn_k_v| meas_.add(*prn_k_v)}
          } 
          after_run.call(run(meas_, t_meas), [meas_, ref_time = t_meas])
        end 
        t_meas, meas = [nil, {}]
      end
    end
  end
end
end
