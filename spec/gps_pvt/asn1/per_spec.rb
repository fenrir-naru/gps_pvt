# frozen_string_literal: true

require 'rspec'

require 'gps_pvt/asn1/per'
require 'gps_pvt/asn1/asn1'

require 'stringio'

RSpec::describe GPS_PVT::PER do
  describe 'Basic_Unaligned' do
    describe 'Encoder and Decoder' do
      let(:enc){GPS_PVT::PER::Basic_Unaligned::Encoder}
      let(:dec){GPS_PVT::PER::Basic_Unaligned::Decoder}
      let(:check){
        proc{|func, src, *opts|
          str = enc.send(func, src, *opts)
          #p [func, src, opts, str.reverse.scan(/.{1,8}/).join('_').reverse]
          dst = dec.send(func, str.dup, *opts)
          expect(dst).to eq(src)
          str2 = enc.send(func, dst, *opts)
          expect(str2).to eq(str)
        }
      }
      it 'support constrainted_whole_number' do
        [0..255, -128..127].each{|range|
          range.each{|i|
            check.call(:constrainted_whole_number, i, range)
          }
        }
      end
      it 'support normally_small_non_negative_whole_number' do
        [
          :length_normally_small_length,
          [:length_constrained_whole_number, 0..4],
          :length_otherwise,
        ].each{|len_enc|
          (0..255).each{|i|
            check.call(:normally_small_non_negative_whole_number, i, *len_enc)
          }
        }
      end
      it 'support semi_constrained_whole_number' do
        [
          :length_normally_small_length,
          [:length_constrained_whole_number, 0..4],
          :length_otherwise,
        ].each{|len_enc|
          [0, -128, 127].each{|v_min|
            (0..255).each{|i|
              check.call(:semi_constrained_whole_number, i + v_min, v_min, *len_enc)
            }
          }
        }
      end
      it 'support unconstrained_whole_number' do
        [
          :length_normally_small_length,
          [:length_constrained_whole_number, 0..4],
          :length_otherwise,
        ].each{|len_enc|
          (0..(1 << 16)).each{|i|
            check.call(:unconstrained_whole_number, i, *len_enc)
          }
        }
      end
    end
    
    describe 'with ASN1' do
      let(:asn1){GPS_PVT::ASN1}
      let(:examples){
        [<<-'__JSON__',
{"X691_A1": {
"PersonnelRecord": {
  "type": [
    "SEQUENCE",
    {"root": [
      {"name": "name", "typeref": "Name"},
      {"name": "number", "typeref": "EmployeeNumber"},
      {"name": "title", "type": "VisibleString"},
      {"name": "dateOfHire", "typeref": "Date"},
      {"name": "nameOfSpouse", "typeref": "Name"},
      {"name": "children",
        "type": [
          "SEQUENCE_OF",
          {"typeref": "ChildInformation"}
        ],
        "default": []
      }
    ] }
  ]
},
"ChildInformation": {
  "type": [
    "SEQUENCE",
    {"root": [
      {"name": "name", "typeref": "Name"},
      {"name": "dateOfBirth", "typeref": "Date"}
    ] }
  ]
},
"Name": {
  "type": [
    "SEQUENCE",
    {"root": [
      {"name": "givenName", "type": "VisibleString"},
      {"name": "initial", "type": "VisibleString"},
      {"name": "familyName", "type": "VisibleString"}
    ] }
  ]
},
"EmployeeNumber": {"type": "INTEGER"},
"Date": {"type": "VisibleString"}
} }
          __JSON__
          #<<-'__JSON__',
          #__JSON__
          #<<-'__JSON__',
          #__JSON__
        ].inject({}){|res, json_str|
          res.merge!(asn1.read_json(StringIO::new(json_str)))
        }
      }
      it 'passes tests of X691 A.1 example' do
        data = {:PersonnelRecord => {
          :name => {:givenName => "John", :initial => "P", :familyName => "Smith"},
          :title => "Director",
          :number => 51,
          :dateOfHire => "19710917",
          :nameOfSpouse => {:givenName => "Mary", :initial => "T", :familyName => "Smith"},
          :children => [{
            :name => {:givenName => "Ralph", :initial => "T", :familyName => "Smith"},
            :dateOfBirth => "19571111"
          }, {
            :name => {:givenName => "Susan", :initial => "B", :familyName => "Jones"},
            :dateOfBirth => "19590717"
          }]
        }}
        fmt = examples[:X691_A1][:PersonnelRecord]
        #asn1.debug = true
        encoded = asn1.encode_per(fmt, data[:PersonnelRecord])
        encoded_true = (<<-__HEX_STRING__).gsub(/\s+/, '').scan(/.{2}/).collect{|str| "%08b"%[Integer(str, 16)]}.join[0..-2]
824ADFA3 700D005A 7B74F4D0 02661113 4F2CB8FA 6FE410C5 CB762C1C B16E0937
0F2F2035 0169EDD3 D340102D 2C3B3868 01A80B4F 6E9E9A02 18B96ADD 8B162C41
69F5E787 700C2059 5BF765E6 10C5CB57 2C1BB16E
        __HEX_STRING__
        expect(encoded).to eq(encoded_true)

        decoded = asn1.decode_per(fmt, encoded_true.dup)
        encoded2 = asn1.encode_per(fmt, decoded)
        expect(encoded2).to eq(encoded_true)
      end
    end
  end
end
