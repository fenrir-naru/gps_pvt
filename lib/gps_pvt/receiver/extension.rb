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

  def attach_online_ephemeris(uri_template = nil)
    if (!uri_template) || (uri_template =~ /^\s*$/) then
      uri_template = "ftp://gssc.esa.int/gnss/data/daily/%Y/brdc/BRDC00IGS_R_%Y%j0000_01D_MN.rnx.gz"
    end
    loader = proc{|t_meas|
      utc = Time::utc(*t_meas.c_tm)
      uri = URI::parse(utc.strftime(uri_template))
      self.parse_rinex_nav(uri)
      uri
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
end
