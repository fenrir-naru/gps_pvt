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
    #$stderr.puts "Parity: #{(["%02X"] * 3 + ["%06X"]).join(', ')}"%(test_data[0][-3..-1] + [checksum])
    [(checksum >> 16), (checksum >> 8) & 0xFF, (checksum & 0xFF)].zip(test_data[0][-3..-1]).each{|a, b|
      expect(a).to eq(b)
    }
    df_list = GPS_PVT::Util::BitOp.extract(
        test_data[0], [12, 12, 6, 1, 1, 1, 1, 38, 1, 1, 38, 2, 38], 24)
    {0 => 1005, 1 => 2003,
        7 => 11141045999,
        10 => -48507297108 + (137438953472*2),
        12 => 39755214643}.each{|i, v|
      expect(df_list[i]).to eq(v)
    }
    packet = GPS_PVT::RTCM3::new(StringIO::new(test_data[0].pack('C*'))).read_packet
    expect(packet).to be_a(GPS_PVT::RTCM3::Packet)
    expect(packet.message_number).to eq(1005)
    proc{|parsed|
      #$stderr.puts parsed.inspect
      {25 => 1114104.5999, 26 => -4850729.7108, 27 => 3975521.4643}.each{|df1, v1|
        expect(parsed.find{|v2, df2| df1 == df2}[0]).to eq(v1)
      }
    }.call(packet.parse)
  end
  it "knows sufficient structure of messages" do
    GPS_PVT::RTCM3::Packet::MessageType.each{|mt, prop|
      expect(prop[:bits].all?).to eq(true)
      expect(prop[:bits_total]).to eq({
        1005 => 152,
        1019 => 488,
        1020 => 360 - 7,
        1044 => 485,
        1071..1077 => 169,
        1081..1087 => 169,
        1091..1097 => 169,
        1111..1117 => 169,
      }.select{|k, v| k === mt}.values[0])
    }
  end
end
