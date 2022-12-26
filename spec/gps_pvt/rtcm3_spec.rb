# frozen_string_literal: true

require 'rspec'

require 'gps_pvt/rtcm3'

RSpec::describe GPS_PVT::RTCM3 do
  let(:test_data){
    [
      "D3 00 13 3E D7 D3 02 02 98 0E DE EF 34 B4 BD 62 AC 09 41 98 6F 33 36 0B 98", # RTCM 10403.2 4.2 Eample
    ].collect{|item|
      case item
      when String
        item.split(/\s+/).collect{|str| str.to_i(16)}
      else; item
      end
    }
  }
  it "can parse data" do
    checksum = GPS_PVT::RTCM3::checksum(test_data[0])
    $stderr.puts "Parity: #{(["%02X"] * 3 + ["%06X"]).join(', ')}"%(test_data[0][-3..-1] + [checksum])
    [(checksum >> 16), (checksum >> 8) & 0xFF, (checksum & 0xFF)].zip(test_data[0][-3..-1]).each{|a, b|
      expect(a).to eq(b)
    }
  end
end
