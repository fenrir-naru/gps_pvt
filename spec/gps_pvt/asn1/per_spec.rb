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
          <<-'__JSON__',
{"X691_A2": {
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
      {"name": "givenName", "typeref": "NameString"},
      {"name": "initial", "typeref": "NameString", "type": [null, {"size": 1}]},
      {"name": "familyName", "typeref": "NameString"}
    ] }
  ]
},
"EmployeeNumber": {"type": "INTEGER"},
"Date": {"type": [
  "VisibleString",
  {"from": {"and": [[">=", "0"], ["<=", "9"]]}, "size": 8}
]},
"NameString": {"type": [
  "VisibleString", {
    "from": [{"and": [[">=", "a"], ["<=", "z"]]}, {"and": [[">=", "A"], ["<=", "Z"]]}, "-."],
    "size": {"and": [[">=", 1], ["<=", 64]]}
  }
]}
} }
          __JSON__
          <<-'__JSON__',
{"X691_A3": {
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
          {"typeref": "ChildInformation", "size": {"root": 2}}
        ],
        "optional": true
      }
    ], "extension": [] }
  ]
},
"ChildInformation": {
  "type": [
    "SEQUENCE",
    {"root": [
      {"name": "name", "typeref": "Name"},
      {"name": "dateOfBirth", "typeref": "Date"}
    ], "extension": [
      {"name": "sex", "type": [
          "ENUMERATED",
          {"root": {"male": 1, "female": 2, "unknown": 3}}],
        "optional": true
      }
    ] }
  ]
},
"Name": {
  "type": [
    "SEQUENCE",
    {"root": [
      {"name": "givenName", "typeref": "NameString"},
      {"name": "initial", "typeref": "NameString", "type": [null, {"size": 1}]},
      {"name": "familyName", "typeref": "NameString"}
    ], "extension": [] }
  ]
},
"EmployeeNumber": {"type": [
  "INTEGER",
  {"value": {"root": {"and": [[">=", 0], ["<=", 9999]]}}}
] },
"Date": {"type": [
  "VisibleString",
  {"from": {"and": [[">=", "0"], ["<=", "9"]]}, "size": {
    "root": 8,
    "additional": {"and": [[">=", 9], ["<=", 20]]}
  }}
]},
"NameString": {"type": [
  "VisibleString", {
    "from": [{"and": [[">=", "a"], ["<=", "z"]]}, {"and": [[">=", "A"], ["<=", "Z"]]}, "-."],
    "size": {"root": {"and": [[">=", 1], ["<=", 64]]}}
  }
]}
} }
          __JSON__
          <<-'__JSON__',
{"X691_A4": {
"Ax": {
  "type": [
    "SEQUENCE",
    {
      "root": [
        {
          "name": "a",
          "type": ["INTEGER", {"value": {"and": [[">=", 250], ["<=", 253]]}}]
        },
        {"name": "b", "type": "BOOLEAN"},
        {
          "name": "c",
          "type": ["CHOICE",
              {"root": [{"name": "d", "type": "INTEGER"}],
                "extension": [{"group": [
                  {"name": "e", "type": "BOOLEAN"},
                  {"name": "f", "type": "IA5String"}]}]}]
        },
        {"name": "i", "type": "IA5String", "optional": true},
        {"name": "j", "type": "PrintableString", "optional": true}
      ],
      "extension": [{"group": [
          {"name": "g", "type": ["NumericString", {"size": 3}]},
          {"name": "h", "type": "BOOLEAN", "optional": true}]}]
    }]
}
} }
          __JSON__
        ].inject({}){|res, json_str|
          res.merge!(asn1.read_json(StringIO::new(json_str)))
        }
      }
      it 'passes tests of X.691 A.1 example' do
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
      it 'passes tests of X.691 A.2 example' do
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
        fmt = examples[:X691_A2][:PersonnelRecord]
        #asn1.debug = true
        encoded = asn1.encode_per(fmt, data[:PersonnelRecord])
        encoded_true = (<<-__HEX_STRING__).gsub(/\s+/, '').scan(/.{2}/).collect{|str| "%08b"%[Integer(str, 16)]}.join[0..-4]
865D51D2 888A5125 F1809984 44D3CB2E 3E9BF90C B8848B86 7396E8A8 8A5125F1
81089B93 D71AA229 4497C632 AE222222 985CE521 885D54C1 70CAC838 B8
        __HEX_STRING__
        expect(encoded).to eq(encoded_true)

        decoded = asn1.decode_per(fmt, encoded_true.dup)
        encoded2 = asn1.encode_per(fmt, decoded)
        expect(encoded2).to eq(encoded_true)
      end
      it 'passes tests of X.691 A.3 example' do
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
            :dateOfBirth => "19590717", :sex => :female
          }]
        }}
        fmt = examples[:X691_A3][:PersonnelRecord]
        #asn1.debug = true
        encoded = asn1.encode_per(fmt, data[:PersonnelRecord])
        encoded_true = (<<-__HEX_STRING__).gsub(/\s+/, '').scan(/.{2}/).collect{|str| "%08b"%[Integer(str, 16)]}.join[0..-2]
40CBAA3A 5108A512 5F180330 889A7965 C7D37F20 CB8848B8 19CE5BA2 A114A24B
E3011372 7AE35422 94497C61 95711118 22985CE5 21842EAA 60B832B2 0E2E0202
80
        __HEX_STRING__
        expect(encoded).to eq(encoded_true)

        decoded = asn1.decode_per(fmt, encoded_true.dup)
        encoded2 = asn1.encode_per(fmt, decoded)
        expect(encoded2).to eq(encoded_true)
      end
      it 'passes tests of X.691 A.4 example' do
        data = {:Ax => {:a => 253, :b => true, :c => {:e => true}, :g => "123", :h => true}}
        fmt = examples[:X691_A4][:Ax]
        #asn1.debug = true
        encoded = asn1.encode_per(fmt, data[:Ax])
        encoded_true = (<<-__HEX_STRING__).gsub(/\s+/, '').scan(/.{2}/).collect{|str| "%08b"%[Integer(str, 16)]}.join[0..-3]
9E000600 040A4690
        __HEX_STRING__
        expect(encoded).to eq(encoded_true)

        decoded = asn1.decode_per(fmt, encoded_true.dup)
        encoded2 = asn1.encode_per(fmt, decoded)
        expect(encoded2).to eq(encoded_true)
      end
    end
  end
end
