=begin
Additional Almanac handler for receiver
=end

module GPS_PVT
class Receiver
  def correct_week_sem_yuma_almanac(src, week_rem = 0)
    t_ref = case src.to_s
    when /www\.navcen\.uscg\.gov\/.*\/(\d{4})\//
      # ex) https://www.navcen.uscg.gov/sites/default/files/gps/almanac/20XX/(Sem|Yuma)/003.(al3|alm)
      GPS_PVT::GPS::Time::new(Time::new($1.to_i).to_a.slice(0, 6).reverse)
    when /www\.navcen\.uscg\.gov\/.*\/current_(sem|yuma)/
      GPS_PVT::GPS::Time::now
    else
      raise
    end
    q, rem = t_ref.week.divmod(1024)
    delta = rem - (week_rem % 1024)
    if delta <= -512 then
      q -= 1
    elsif delta > 512 then
      q += 1
    end
    q * 1024 + week_rem
  end
  
  def parse_sem_almanac(src)
    src_io = open(Util::get_txt(src))
    raise unless src_io.readline =~ /(\d+)\s+(\S+)/ # line 1
    num, name = [$1.to_i, $2]
    raise unless src_io.readline =~ /(\d+)\s+(\d+)/ # line 2
    week, t_oa = [$1.to_i, $2.to_i]
    week = correct_week_sem_yuma_almanac(src, week)
    src_io.readline # line 3
    
    num.times.each{
      eph = GPS::Ephemeris::new
      9.times{|i| # line R-1..9
        case i
        when 0, 1, 2, 6, 7
          # N/A items; 1 => SV reference number, 7 => configuration code
          k = {0 => :svid, 2 => :URA_index, 6 => :SV_health}[i]
          v = Integer(src_io.readline)
          eph.send("#{k}=".to_sym, v) if k
        when 3..5
          res = src_io.readline.scan(/[+-]?\d+(?:\.\d+)?(?:E[+-]\d+)?/).collect{|s| Float(s)}
          raise unless res.size == 3
          res.zip({
            3 => [:e, [:i0, GPS::GPS_SC2RAD], [:dot_Omega0, GPS::GPS_SC2RAD]],
            4 => [:sqrt_A, [:Omega0, GPS::GPS_SC2RAD], [:omega, GPS::GPS_SC2RAD]],
            5 => [[:M0, GPS::GPS_SC2RAD], :a_f0, :a_f1],
          }[i]).each{|v, (k, sf)|
            eph.send("#{k}=".to_sym, sf ? (sf * v) : v)
          }
        when 8
          src_io.readline
        end
      }
      eph.i0 = GPS::GPS_SC2RAD * 0.3 + eph.i0
      eph.WN = week
      eph.t_oc = eph.t_oe = t_oa
      [:iodc, :t_GD, :a_f2, :iode, :c_rs, :delta_n,
          :c_uc, :c_us, :c_ic, :c_is, :c_rc, :dot_i0, :iode_subframe3].each{|k|
        eph.send("#{k}=", 0)
      }
      critical{@solver.gps_space_node.register_ephemeris(eph.svid, eph)}
    }
    
    $stderr.puts "Read SEM Almanac file (%s): %d items."%[src, num]
  end
  
  YUMA_ITEMS = [
    [proc{|s| s.to_i}, {
      :ID => :svid,
      :Health => :SV_health,
      :week => :WN,
    }],
    [proc{|s| Float(s)}, {
      :Eccentricity => :e,
      "Time of Applicability" => [:t_oc, :t_oe],
      "Orbital Inclination" => :i0,
      "Rate of Right Ascen" => :dot_Omega0,
      'SQRT\(A\)' => :sqrt_A,
      "Right Ascen at Week" => :Omega0,
      "Argument of Perigee" => :omega,
      "Mean Anom" => :M0,
      "Af0" => :a_f0,
      "Af1" => :a_f1,
    }],
  ].collect{|cnv, key_list|
    key_list.collect{|k1, k2_list|
      [/#{k1}[^:]*:/, cnv,
          *([k2_list].flatten(1).collect{|k2|
            "#{k2}=".to_sym
          })]
    }
  }.flatten(1)
  
  def parse_yuma_almanac(src)
    src_io = open(Util::get_txt(src))
    num = 0
    
    idx_line = -1
    eph, items = nil
    while !src_io.eof?
      line = src_io.readline.chomp
      if idx_line < 0 then
        if line =~ /^\*{8}/ then
          eph = GPS::Ephemeris::new
          items = YUMA_ITEMS.clone
          idx_line = 0
        end
        next
      end
      raise unless i = items.index{|re, cnv, *k_list|
        next false unless re =~ line
        v = cnv.call($')
        k_list.each{|k| eph.send(k, v)}
        true
      }
      items.delete_at(i)
      next unless items.empty?

      [:iodc, :t_GD, :a_f2, :iode, :c_rs, :delta_n,
          :c_uc, :c_us, :c_ic, :c_is, :c_rc, :dot_i0, :iode_subframe3].each{|k|
        eph.send("#{k}=", 0)
      }
      eph.WN = correct_week_sem_yuma_almanac(src, eph.WN)
      critical{@solver.gps_space_node.register_ephemeris(eph.svid, eph)}
      num += 1
      idx_line = -1
    end
    
    $stderr.puts "Read YUMA Almanac file (%s): %d items."%[src, num]
  end
end
end
