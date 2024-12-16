require 'gps_pvt/GPS'
require 'gps_pvt/Coordinate'

module GPS_PVT
class GPS::PVT_minimal
  def initialize
    # GLOBAL POSITIONING SYSTEM STANDARD POSITIONING SERVICE
    # PERFORMANCE STANDARD 5th edition (Apr. 2020) 3.8
    @hsigma = 8.0 # 95%
    @vsigma = 13.0 # 95%
    @pdop = 6.0 # 98% global
    @vel_sigma = 0.2 # 85%
    @used_satellites = 0 # unknown
  end
  def position_solved?; @xyz || @llh; end
  def velocity_solved?; @velocity; end
  def xyz; @xyz || @llh.xyz; end
  def llh; @xyz ? @xyz.llh : @llh; end
  def xyz=(args); @xyz = Coordinate::XYZ::new(*args); end
  def llh=(args); @llh = Coordinate::LLH::new(*args); end
  def velocity=(args); @velocity = Coordinate::ENU::new(*args); end
  attr_reader :velocity
  attr_accessor :hsigma, :vsigma, :pdop, :vel_sigma, :used_satellites
  class <<self
    def parse_csv(csv_fname, &b)
      require_relative 'util'
      $stderr.puts "Reading CSV file (%s) "%[csv_fname]
      io = open(Util::get_txt(csv_fname), 'r')
      
      header = io.readline.chomp.split(/ *, */)
      idx_table = [
        :week, [:tow, /^i?t(?:ime_)?o(?:f_)?w(?:eek)?/],
        :year, :month, :mday, :hour, :min, [:sec, /^sec/],
        [:lng, /^(?:long(?:itude)?|lng)/], [:lat, /^lat(?:itude)/],
              [:alt, /^(?:alt(?:itude)?|h(?:$|eight|_))/], # assumption: [deg], [deg], [m]
        :x, :y, :z, # ECEF xyz
        :hsigma, :vsigma, :pdop,
        [:vn, /^v(?:el)?_?n(?:orth)?/], [:ve, /^v(?:el)?_?e(?:ast)?/],
            [:vd, /^v(?:el)?_?d(?:own)?/], [:vu, /^v(?:el)?_?u(?:p)?/],
        :vx, :vy, :vz, # ECEF xyz
        [:vel_sigma, /^v(?:el)?_sigma/],
        [:used_satellites, /^(?:used_)?sat(?:ellite)?s/],
      ].collect{|k, re|
        re ||= k.to_s
        idx = header.find_index{|str| re === str}
        idx && [k, idx]
      }.compact
      opt_keys = [:pdop, :hsigma, :vsigma, :vel_sigma, :used_satellites].select{|k|
        idx_table.any?{|k2, idx| k == k2}
      }
      enum = Enumerator::new{|y|
        io.each_line{|line|
          values = line.chomp.split(/ *, */)
          items = Hash[*(idx_table.collect{|k, idx|
            v = values[idx]
            (v == '') ? nil : [k, (Integer(v) rescue Float(v))]
          }.compact.flatten(1))]
          if items[:week] then
            t = GPS::Time::new(items[:week], items[:tow])
          else
            # UTC assumption, thus leap seconds must be added.
            t = GPS::Time::new([:year, :month, :mday, :hour, :min, :sec].collect{|k| items[k]})
            t += GPS::Time::guess_leap_seconds(t)
          end
          pvt = GPS::PVT_minimal::new
          if items[:lat] then
            pvt.llh = ([:lat, :lng].collect{|k| Math::PI / 180 * items[k]} + [items[:alt]])
          elsif items[:x] then
            pvt.xyz = [:x, :y, :z].collect{|k| items[k]}
          end
          if items[:vn] then
            pvt.velocity = ([:vn, :ve].collect{|k| items[k]} + [items[:vu] || -items[:vd]])
          elsif items[:vx] then
            pvt.velocity = Coordinate::ENU::relative_rel(
                Coordinate::XYZ::new(*([:vx, :vy, :vz].collect{|k| items[k]})),
                pvt.llh)
          end
          opt_keys.each{|k| pvt.send("#{k}=", items[k]) if items[k]}
          y.yield(t, pvt)
        }
      }
      b ? enum.each{|*res| b.call(*res)} : enum
    end
  end
end
end
