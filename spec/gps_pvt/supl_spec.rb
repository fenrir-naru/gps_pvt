# frozen_string_literal: true

require 'rspec'
require 'timeout'

require 'gps_pvt'
require 'gps_pvt/supl'

RSpec::describe GPS_PVT::SUPL_Client do
  let(:receiver){
    rcv = GPS_PVT::Receiver::new
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
  before{
    # If use default URIs, comment out the following line
    skip "SUPL_URI and external ephemeris source (EX_EPH_SRC) are required by ENV" unless ['SUPL_URI', 'EX_EPH_SRC'].all?{|k| ENV[k]}
  }
  let(:supl_uri_base){
    ENV['SUPL_URI'] || 'supl://supl.google.com/'
  }
  let(:eph_src){
    ENV['EX_EPH_SRC'] || 'ntrip://test%40example.com:none@rtk2go.com:2101/RTCM3EPH'
  }
  shared_examples "per_url" do
  it "can acquire the same ephemeris as the other methods" do
    $stderr.print "Connecting #{supl_uri} ..."
    agps = URI::parse(supl_uri).open.get_assisted_data
    eph_agps = agps.ephemeris
    $stderr.puts " #{eph_agps.size} items are acquired."
    
    c_light = GPS_PVT::GPS::SpaceNode::light_speed
    
    compare_in_pvt = proc{|eph_a, eph_b, t_gps|
      t_gps ||= GPS_PVT::GPS::Time::now
      pvt_threshold = case eph_a # threshold of p(3), v(3), t(1), dt(1) in [m] or [m/s]
      when GPS_PVT::GPS::Ephemeris_GLONASS; ([20.0] * 3) + ([0.1] * 3) + [20.0, 0.1]
      else; ([5.0] * 3) + ([0.05] * 3) + [5.0, 0.05]
      end
      [eph_a, eph_b].collect{|eph|
        pos, vel, delta_t, delta_dt = eph.constellation(t_gps)
        [pos.to_a, vel.to_a, delta_t * c_light, delta_dt * c_light].flatten
      }.transpose.zip(pvt_threshold).each{|(a, b), delta|
        expect(a).to be_within(delta).of(b)
      }
    }
    
    compare = proc{|eph_a, eph_b, ignore_keys|
      ignore_keys ||= []
      proc{ # for debug
        a, b = [eph_a, eph_b].collect{|v| v.to_hash}
        ((a.keys | b.keys) - ignore_keys).each{|k|
          $stderr.puts [k, a[k], b[k]].inspect if a[k] != b[k]
        }
        $stderr.puts
      }.call if false
      if (eph_a.respond_to?(:t_oc) && (eph_a.t_oe == eph_b.t_oe)) \
          || (eph_a.respond_to?(:t_b) && (eph_a.t_b == eph_b.t_b)) then
        ignore = Hash[*(ignore_keys.collect{|k| [k, nil]}.flatten(1))]
        expect(eph_a.to_hash.merge(ignore)).to eq(eph_b.to_hash.merge(ignore))
      else
        compare_in_pvt.call(eph_a, eph_b)
      end
      true
    }

    rcv = receiver
    rcv.define_singleton_method(:hook_new_ephemeris){|sn, svid, eph_cmp|
      type, *skip_items = case sn
      when :gps_space_node; [GPS_PVT::GPS::Ephemeris, :URA, :URA_index]
      when :sbas_space_node; GPS_PVT::GPS::Ephemeris_SBAS
      when :glonass_space_node
        [GPS_PVT::GPS::Ephemeris_GLONASS, :raw, :F_T, :F_T_index,
            :t_k, :delta_tau_n, :P1, :P1_index, :freq_ch, :P4,
            :tau_GPS, :tau_c, :day_of_year, :p]
      else; NilClass
      end
      idx = eph_agps.find_index{|eph2|
        eph2.instance_of?(type) && (eph2.svid == svid)
      }
      next unless idx
      $stderr.print "Checking #{sn.to_s.split('_').first.upcase}(#{svid}) ... " 
      if compare.call(eph_agps[idx], eph_cmp, skip_items) then
        eph_agps.delete_at(idx)
        $stderr.print "passed."
      else
        $stderr.print "skipped."
      end
      if eph_agps.empty? then
        $stderr.puts " Comparison is completed."
        Thread::exit
      else
        $stderr.puts " Remaining #{eph_agps.size} items ..."
      end
    }
    
    src_cmp = eph_src
    ftype = case src_cmp
    when /\.\d{2}[nhqg](?:\.gz)?$/; :rinex_nav
    when /\.ubx$/; :ubx
    else
      if (!(uri = URI::parse(eph_src)).instance_of?(URI::Generic) rescue false) then
        src_cmp = uri
        case src_cmp
        when URI::Ntrip; uri.read_format
        when URI::Supl; :supl
        end
      else
        raise "Unsupported format"
      end
    end
    
    func = case ftype
    when :rinex_nav; :parse_rinex_nav
    when :ubx; :parse_ubx
    when :rtcm3; :parse_rtcm3
    when :supl; :parse_supl
    else; raise
    end
    Timeout::timeout(60){
      Thread::new{rcv.send(func, src_cmp, &proc{})}.join
    } rescue nil
  end
  end
  
  describe "with LPP protocol" do
    let(:supl_uri){"#{supl_uri_base}?protocol=lpp"}
    include_examples "per_url"
  end
  describe "with RRLP protocol" do
    let(:supl_uri){"#{supl_uri_base}?protocol=rrlp"}
    include_examples "per_url"
  end
end
