# frozen_string_literal: true

require 'rspec'

require 'gps_pvt'

RSpec::describe GPS_PVT::Receiver do
  let(:src){{
    :SEM => URI::parse(
        "https://www.navcen.uscg.gov/sites/default/files/gps/almanac/current_sem.al3"),
    :YUMA => URI::parse(
        "https://www.navcen.uscg.gov/sites/default/files/gps/almanac/current_yuma.alm"),
    :SUPL => URI::parse(
        "supl://supl.google.com/"),
    :RTCM3 => URI::parse(
        "ntrip://test%40example.com:none@rtk2go.com:2101/RTCM3EPH"),
  }}
  let(:receiver){
    rcv = described_class.new
    rcv.define_singleton_method(:hook_new_ephemeris){|*args|}
    rcv.solver.instance_eval{
      [:gps_space_node, :sbas_space_node, :glonass_space_node].each{|k|
        k_var = "@#{k}"
        instance_variable_set(k_var, send(k))
        v = instance_variable_get(k_var)
        define_singleton_method(k){v}
        orig = v.method(:register_ephemeris)
        v.define_singleton_method(:register_ephemeris){|svid, eph|
          rcv.hook_new_ephemeris(k, svid, eph)
          orig.call(svid, eph)
        }
      }
    }
    rcv
  }
  def cmp(args_src1, args_src2)
    expect(1).to be_within(10E3).of(1)
    base_time = GPS_PVT::GPS::Time::now
    c_light = GPS_PVT::GPS::SpaceNode::light_speed
    eph_cache = {}
    rcv = receiver
    rcv.define_singleton_method(:hook_new_ephemeris){|sn, svid, eph_a|
      eph_cache[[sn, svid]] = eph_a
    }
    rcv.send(*args_src1)

    comarator = proc{|eph_a, eph_b|
      values = [eph_a, eph_b].collect{|eph|
        #eph.to_hash.each{|k, v| $stderr.puts [k, v].join(',')}
        pos, vel, delta_t, delta_dt = eph.constellation(base_time)
        [pos.to_a, delta_t * c_light, vel.to_a, delta_dt * c_light].flatten
      }.transpose
      values[0..3].each{|a, b| # check only in position
        expect(a).to be_within(10E3).of(b) # < 10 km
      }
    }

    rcv.define_singleton_method(:hook_new_ephemeris){|sn, svid, eph_b|
      next unless eph_a = eph_cache.delete([sn, svid])
      comarator.call(eph_a, eph_b)
      Thread::exit if eph_cache.empty?
    }
    Timeout::timeout(60){
      Thread::new{rcv.send(*args_src2)}.join
    } rescue $stderr.puts "Timeout with #{eph_cache.size} item comparison remained"
  end
  it "can use SEM almanac" do
    cmp([:parse_sem_almanac, src[:SEM]], [:parse_supl, src[:SUPL]])
    #cmp([:parse_sem_almanac, src[:SEM]], [:parse_rtcm3, src[:RTCM3]])
  end
  it "can use YUMA almanac" do
    cmp([:parse_yuma_almanac, src[:YUMA]], [:parse_supl, src[:SUPL]])
    #cmp([:parse_yuma_almanac, src[:YUMA]], [:parse_rtcm3, src[:RTCM3]])
  end
end
