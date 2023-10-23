# frozen_string_literal: true

require 'rspec'
require 'timeout'

require 'gps_pvt/ubx'

RSpec::describe GPS_PVT::UBX do
  it "convert svid_legacy to/from [gnssid, svid]" do
    (1..255).each{|svid_legacy|
      gnss_svid = GPS_PVT::UBX::gnss_svid(svid_legacy)
      case svid_legacy
      when 1..32, 120..158, 211..246, 159..163, 33..64, 193..197, 65..96
        expect(svid_legacy).to be(GPS_PVT::UBX::svid(gnss_svid[1], gnss_svid[0]))
      when 255
        expect(gnss_svid).to eq([:GLONASS, nil])
      else
        expect(gnss_svid).to be_nil
      end
    }
  end
end
