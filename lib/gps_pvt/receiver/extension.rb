=begin
Receiver extension
=end

module GPS_PVT
class Receiver
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
