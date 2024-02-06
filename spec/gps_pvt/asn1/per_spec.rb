# frozen_string_literal: true

require 'rspec'

require 'gps_pvt/asn1/per'

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
  end
end
