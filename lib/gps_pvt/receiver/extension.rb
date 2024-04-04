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

[
  :Ionospheric_UTC_Parameters,
  :Ephemeris, :Ephemeris_SBAS, :Ephemeris_GLONASS,
].each{|cls|
  GPS.const_get(cls).class_eval{
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
