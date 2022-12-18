# frozen_string_literal: true

require 'rspec'
require 'timeout'

require 'gps_pvt/ntrip'

RSpec::describe GPS_PVT::Ntrip do
  before{skip "Ntrip caster is not specified by ENV['NTRIP_CASTER']" unless ENV['NTRIP_CASTER']}
  let(:caster){ENV['NTRIP_CASTER'].split(':')} # 'rtk2go.com:2101'
  let(:auth){(ENV['NTRIP_AUTH'] || '').split(':')} # 'test@example.com:none'
  let(:header_options){
    {'Ntrip-Version' => [nil, 'Ntrip/1.0', 'Ntrip/2.0']}
  }
  it "can acquire data" do
    opt = header_options.merge({
      :basic_auth => [auth.empty? ? nil : auth],
    }).collect{|k, v|
      v.kind_of?(Array) ? v.collect{|v2| [k, v2]} : [[k, v]]
    }
    opt[0].product(*opt[1..-1]).each{|header|
      header = Hash[*header.flatten(1)].compact
      GPS_PVT::Ntrip.start(*caster){|ntrip|
        # source table
        tbl = ntrip.get_source_table(header)
        expect(header.size).to be >= 0
        mnt_pt = tbl.mount_points.keys[0]
        
        # stream
        $stderr.puts "Connecting #{mnt_pt} of #{caster.join(':')} with #{header} ..."
        Timeout::timeout(10){
          expect{ntrip.get_data(tbl.mount_points.keys[0], header){|data|
            expect(data).to be_a(String)
            break unless data.empty?
          }}.not_to raise_error
        }
      }
    }
  end
  describe 'can be used via OpenURI' do
    let(:options){
      res = {
        :version => header_options['Ntrip-Version'].collect{|str|
          /\d+\.\d+$/ =~ str ? $&.to_f : str
        }
      }.collect{|k, v|
        v.kind_of?(Array) ? v.collect{|v2| [k, v2]} : [[k, v]]
      }
      res[0].product(*res[1..-1]).collect{|params|
        Hash[*params.flatten(1)].compact
      }
    }
    it "to acquire data" do
      host, port = caster
      uname, pass = auth
      mnt_pt = GPS_PVT::Ntrip.start(*caster){|ntrip|
        pt_list = ntrip.get_source_table.mount_points
        ubx_pt = pt_list.select{|k, v|
          v[:format] =~ /ubx|u-?blox/i
        }
        next ubx_pt.keys.first unless ubx_pt.empty?
        pt_list.keys.first
      }
      next unless mnt_pt
      
      top_level = "#{host}#{":#{port}" if port}"
      uri_str = "ntrip://#{top_level}/#{mnt_pt}"
      uri = URI::parse(uri_str)
      auth_str = "#{URI::encode_www_form_component(uname)}:#{pass}@" if uname
      uri_str_with_auth = "ntrip://#{auth_str}#{top_level}/#{mnt_pt}"
      uri_with_auth = URI::parse(uri_str)
      auth_hash = uname ? {:basic_auth => auth} : {}
      
      expect(uri).to be_a(URI::Ntrip)
      expect(uri_with_auth).to be_a(URI::Ntrip)
      
      b = proc{|io|
        expect(io.property).to be_a(Hash)
        expect(io.property[:mountpoint]).to eq(mnt_pt)
        expect{io.read(128)}.not_to raise_error
      }
      
      params_list = [
        [uri, :open, auth_hash],
        [uri_with_auth, :open],
        [:open, uri, auth_hash],
        [:open, uri_with_auth],
        [:open, uri_str, auth_hash],
        [:open, uri_str_with_auth],
      ].collect{|params|
        options.collect{|opt|
          params2 = params.clone
          params2 << opt.merge((params2[-1].kind_of?(Hash) ? params2.pop : {}))
          params2
        }
      }.flatten(1).uniq
      
      #params_list = params_list.shuffle.values_at(0) # Just one case to reduce the access
      
      params_list.each{|params|
        $stderr.puts "Connecting #{params} ..."
        params[0].kind_of?(Symbol) ?
            (GPS_PVT::version_compare(RUBY_VERSION, "2.5.0") >= 0 ? URI : Kernel)::send(*params, &b) :
            params[0].send(*params[1..-1], &b)
      }
    end
  end
end
