=begin
Receiver extension
=end

module GPS_PVT
class Receiver
  
  # shortcut to access ephemeris registered in receiver 
  def ephemeris(t, sys, prn)
    eph = case sys
    when :GPS, :QZSS
      critical{
        @solver.gps_space_node.update_all_ephemeris(t)
        @solver.gps_space_node.ephemeris(prn)
      }
    when :SBAS
      critical{
        @solver.sbas_space_node.update_all_ephemeris(t)
        @solver.sbas_space_node.ephemeris(prn)
      }
    when :GLONASS
      critical{
        @solver.glonass_space_node.update_all_ephemeris(t)
        @solver.glonass_space_node.ephemeris(prn)
      }
    else
      return nil
    end
    return (eph.valid?(t) ? eph : nil)
  end

  def attach_online_ephemeris(uri_template = [nil])
    uri_template = uri_template.collect{|v|
      if (!v) || (v =~ /^\s*$/) then
        "ftp://gssc.esa.int/gnss/data/daily/%Y/brdc/BRDC00IGS_R_%Y%j0000_01D_MN.rnx.gz"
      else
        v
      end
    }.uniq
    loader = proc{|t_meas|
      utc = Time::utc(*t_meas.c_tm)
      uri_template.each{|v|
        uri = URI::parse(utc.strftime(v))
        begin
          self.parse_rinex_nav(uri)
        rescue Net::FTPError, Net::HTTPExceptions => e
          $stderr.puts "Skip to read due to %s (%s)"%[e.inspect.gsub(/[\r\n]/, ' '), uri]
        end
      }
    }
    run_orig = self.method(:run)
    eph_list = {}
    self.define_singleton_method(:run){|meas, t_meas, *args|
      w_d = [t_meas.week, (t_meas.seconds.to_i / 86400)]
      eph_list[w_d] ||= loader.call(t_meas)
      run_orig.call(meas, t_meas, *args)
    }
  end
end

module GPS

# These ephemeris helper functions will be removed
# when native functions are available in GPS.i
class Ephemeris
  URA_TABLE = [
      2.40, 3.40, 4.85, 6.85, 9.65, 13.65, 24.00, 48.00,
      96.00, 192.00, 384.00, 768.00, 1536.00, 3072.00, 6144.00]
  def URA_index=(idx)
    send(:URA=, (idx >= URA_TABLE.size) ? (URA_TABLE[-1] * 2) : (idx < 0 ? -1 : URA_TABLE[idx]))
  end
  def URA_index
    ura = send(:URA)
    (ura < 0) ? -1 : URA_TABLE.find_index{|v| ura <= v}
  end
  proc{
    orig = instance_method(:fit_interval=)
    define_method(:fit_interval=){|args|
      args = case args
      when Array
        flag, iodc, sys = args
        hr = case (sys ||= :GPS)
        when :GPS, :gps
          (flag == 0) ? 4 : case iodc 
          when 240..247; 8
          when 248..255, 496; 14
          when 497..503; 26
          when 504..510; 50
          when 511, 752..756; 74
          when 757..763; 98
          when 764..767, 1088..1010; 122
          when 1011..1020; 146
          else; 6
          end
        when :QZSS, :qzss
          raise unless flag == 0 # TODO how to treat fit_interval > 2 hrs
          2
        else; raise
        end
        hr * 60 * 60
      else
        args
      end
      orig.bind(self).call(args)
    }
  }.call
end
class Ephemeris_SBAS
  URA_TABLE = [ # Table 2-3 in DO-229E
      2.0, 2.8, 4.0, 5.7, 8.0, 11.3, 16.0, 32.0,
      64.0, 128.0, 256.0, 512.0, 1024.0, 2048.0, 4096.0]
  def URA_index=(idx)
    send(:URA=, (idx >= URA_TABLE.size) ? (URA_TABLE[-1] * 2) : (idx < 0 ? -1 : URA_TABLE[idx]))
  end
  def URA_index
    ura = send(:URA)
    (ura < 0) ? -1 : URA_TABLE.find_index{|v| ura <= v}
  end
end

[
  Ionospheric_UTC_Parameters,
  Ephemeris, Ephemeris_SBAS, Ephemeris_GLONASS,
].each{|cls|
  cls.class_eval{
    proc{|func_list|
      func_list.select!{|func|
        (/=$/ !~ func.to_s) && func_list.include?("#{func}=".to_sym)
      }
      define_method(:to_hash){
        Hash[*(func_list.collect{|func|
          [func, send(func)]
        }.flatten(1))]
      }
    }.call(instance_methods(false))
  }
}
end
end
