=begin
AGPS handler for receiver
=end

module GPS_PVT
class Receiver
  def parse_supl(src, opt = {}, &b)
    $stderr.print "A-GPS (%s) "%[src]
    opt = {
      :interval => 60 * 10, # 10 min.
    }.merge(opt)
    require_relative '../supl'
    src_io = Util::open(src)
    while data = src_io.get_assisted_data
      data.ephemeris.each{|eph|
        target = case eph
        when GPS::Ephemeris; @solver.gps_space_node
        when GPS::Ephemeris_GLONASS; @solver.glonass_space_node
        when GPS::Ephemeris_SBAS; @solver.sbas_space_node
        else nil
        end
        critical{target.register_ephemeris(eph.svid, eph)} if target
      } if data.respond_to?(:ephemeris)
      critical{
        @solver.gps_space_node.update_iono_utc(data.iono_utc)
      } if data.respond_to?(:iono_utc)
      sleep(opt[:interval])
    end
  end
end
end
