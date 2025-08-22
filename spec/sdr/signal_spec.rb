#!/usr/bin/ruby

require 'rspec'
require 'tempfile'

require 'gps_pvt/sdr/Signal.so'

(GPS_PVT::SDR::Signal.constants - [:GC_VALUE]).each{|k|
  GPS_PVT::SDR::Signal.const_get(k).instance_eval{
    case k.to_s
    when /^Complex/
      define_method(:==){|another|
        (self.to_a == another.to_a) || self.to_a.zip(another.to_a).all?{|a, b|
          (a - b).abs <= 1E-8
        }
      }
    else
      define_method(:==){|another| self.to_a == another.to_a}
    end
  }
}

RSpec::shared_examples GPS_PVT::SDR::Signal do
  it "has constructor without any argument" do
    expect{ sig_type::new() }.not_to raise_error
    expect(sig_type::new().size).to eq(0)
  end
  it "has constructor with an Array argument" do
    expect{ sig_type::new(src_array) }.not_to raise_error
    expect(sig_type::new(src_array)).to eq(src_array)
    expect{ sig_type::new(src_array){|i|} }.to raise_error(ArgumentError)
  end
  let(:src_array_01){(1<<10).times.collect{rand(2)}}
  let(:src_str_01){
    Hash[*([1, 2, 4, 8].collect{|bits|
      base = (1 << (bits - 1)) - 1
      [bits, src_array_01.each_slice(8 / bits).collect{|list|
        list.reverse.inject(0){|res, v| (res << bits) + (v + base)}
      }.pack("C*")]
    }.flatten(1))]
  }
  it "has constructor with a Hash argument" do
    src_str_01.each{|bits, str|
      fmt = "packed_#{bits}b".to_sym
      expect(sig_type::new({:format => fmt, :source => str})\
          .collect{|v| (v + 1).abs.to_i >> 1}).to eq(src_array_01)
      Tempfile::create{|fp|
        fp.binmode
        fp.write(str)
        fp.rewind
        expect(sig_type::new({:format => fmt, :source => fp})\
            .collect{|v| (v + 1).abs.to_i >> 1}).to eq(src_array_01)
      }
    }
  end
  it "has constructor with block" do
    expect{ sig_type::new{|i| src_array[i]} }.not_to raise_error
    expect(sig_type::new{|i| src_array[i]}).to eq(src_array)
  end
  it "has copy constructor" do
    expect{ sig_type::new(sig_type::new) }.not_to raise_error
    a = sig_type::new((1 << 10).times.to_a) + 1
    b = sig_type::new(a) * 2
    expect(a.zip(b.to_a).any?{|v1, v2| v1 == v2}).to eq(false)
  end
  it "has copy()" do
    expect{sig_type::new.copy}.not_to raise_error
    a = sig_type::new((1 << 10).times.to_a) + 1
    b = a.copy * 2
    expect(a.zip(b.to_a).any?{|v1, v2| v1 == v2}).to eq(false)
  end
  let(:src_sig){sig_type::new(src_array)}
  let(:src_array_n01){src_array.collect{|v| [0, 1].include?(v) ? 2 : v}}
  let(:src_sig_n01){sig_type::new(src_array_n01)}
  it "is a kind of Enumerable" do
    expect(src_sig).to be_a_kind_of(Enumerable)
  end
  it "has each" do
    expect(src_sig.each{}).to be(src_sig)
    expect(src_sig.each).to be_a_kind_of(Enumerator)
  end
  it "is a kind of Enumerable" do
    expect(src_sig).to be_a_kind_of(Enumerable)
  end
  it "has size" do
    expect(src_sig.size).to eq(src_array.size)
  end
  it "can get value via []" do
    src_array.each.with_index{|v, i|
      expect(src_sig[i]).to eq(v)
    }
  end
  it "can set value via []=" do
    src_array.each.with_index{|v, i|
      expect{src_sig[i] = v * 2}.not_to raise_error
      expect(src_sig[i]).to eq(src_array[i] * 2)
    }
    expect{src_sig[0..-1] = src_array}.not_to raise_error
    expect(src_sig).to eq(src_array)
  end
  it "has binary functions */+/-" do
    [:*, :+, :-].each{|func|
      src_sig2 = src_sig_n01.send(func, src_sig_n01)
      expect(src_sig2.zip(src_sig_n01.to_a).all?{|a, b| a != b}).to be(true)
      src_array2 = src_array_n01.collect{|v| v.send(func, v)}
      expect(src_sig2).to eq(src_array2)
    }
  end
  it "has unary function -@" do
    src_sig2 = -src_sig_n01
    expect(src_sig2.zip(src_sig_n01.to_a).all?{|a, b| a != b}).to be(true)
    src_array2 = src_array_n01.collect{|v| -v}
    expect(src_sig2).to eq(src_array2)
  end
  it "has resize!(new_size)" do
    len_orig = src_sig.size()
    [len_orig * 2, len_orig / 2].each{|len|
      sig_clone = sig_type::new(src_sig)
      sig = sig_clone.resize!(len)
      expect(sig).to be(sig_clone)
      expect(sig.size).to eq(len)
      if len > len_orig then
        expect(sig.to_a.slice(len_orig..-1).all?{|v| v == 0}).to eq(true)
      end
      len2 = [len, len_orig].min
      expect(sig.to_a.slice(0, len2)).to eq(src_array.slice(0, len2))
    }
  end
  it "has slide!(offset)" do
    len = src_sig.size
    sig_clone = sig_type::new(src_sig)
    [0, 1, -1, len/2, -len/2].each{|offset|
      sig = sig_clone.slide!(offset)
      expect(sig).to be(sig_clone)
      expect(sig.size).to eq(len)
      if offset > 0 then
        src_array[0...-offset] = src_array[offset..-1]
      elsif offset < 0 then
        src_array[-offset..-1] = src_array[0...offset]
      end
      expect(sig.to_a).to eq(src_array)
    }
  end
  it "has rotate!(offset)" do
    len = src_sig.size
    [0, 1, -1, len, -len].each{|offset|
      sig_clone = sig_type::new(src_sig)
      sig = sig_clone.rotate!(offset)
      expect(sig).to be(sig_clone)
      expect(sig.size).to eq(len)
      expect(sig).to eq(src_array.rotate(offset))
    }
  end
  it "has circular(shift, length)" do
    len_orig = src_sig.size
    [0, 1, -1, len_orig, -len_orig]\
        .product([len_orig, len_orig * 2, len_orig / 2])\
        .each{|offset, len|
      sig = src_sig.circular(offset, len)
      expect(sig).to eq(
          (src_array * (len.to_f / len_orig).ceil).flatten.rotate(offset).slice(0, len))
    }
  end
  it "has circular(shift)" do
    [0, 1, -1, src_sig.size, -src_sig.size].each{|offset|
      expect(src_sig.circular(offset)).to eq(src_array.rotate(offset))
    }
  end
  it "has slice(start, length) and its alias [start, length]" do
    len_orig = src_sig.size
    [:slice, :[]].each{|func|
      [0, 1, -1, len_orig, -len_orig, len_orig-1, -len_orig+1]\
          .product([len_orig, len_orig * 2, len_orig / 2, 1])\
          .each{|offset, len|
        expect(src_sig.send(func, offset, len)).to eq(src_array.send(func, offset, len))
      }
    }
  end
  it "has replace!" do
    sig_orig = src_sig
    ary = nil
    [ary, proc{|i| ary[i]}].each{|arg|
      ary = (src_sig + 1).to_a
      expect(arg.kind_of?(Proc) ? src_sig.replace!(&arg) : src_sig.replace!(ary)).to be(sig_orig)
      expect(src_sig.zip(ary).all?{|a, b| a == b}).to be(true)
    }
  end
  it "has fill!" do
    len = src_sig.size
    sig_orig = src_sig
    ary = nil
    [ary, proc{|i| ary[i]}].each{|arg|
      ary = (src_sig + 1).to_a
      expect(arg.kind_of?(Proc) ? src_sig.fill!(0, len, &arg) : src_sig.fill!(0, len, ary)).to be(sig_orig)
      expect(src_sig.zip(ary).all?{|a, b| a == b}).to be(true)
    }
    expect(src_sig.fill!(0, len, ary[0])).to be(sig_orig)
    expect(src_sig.zip([ary[0]] * ary.size).all?{|a, b| a == b}).to be(true)
  end
  it "has append!" do
    sig_orig = src_sig
    ary = nil
    [ary, proc{|i| ary[i]}].each{|arg|
      ary_orig = src_sig.to_a
      ary = (src_sig + 1).to_a
      len_orig = src_sig.size
      expect(arg.kind_of?(Proc) ? src_sig.append!(&arg) : src_sig.append!(ary)).to be(sig_orig)
      expect(sig_orig.size).to be(len_orig * 2)
      expect(src_sig.to_a[0, len_orig]).to eq(ary_orig)
      expect(src_sig.to_a[len_orig, len_orig]).to eq(ary)
    }
  end
  it "has shift! and pop!" do
    [:shift, :pop].each{|func|
      sig = src_sig.copy
      ary = sig.to_a
      n = 1
      while !ary.empty?
        expect(sig.send("#{func}!".to_sym, n)).to be(sig)
        ary.send(func, n)
        expect(sig).to eq(ary)
        n += 1
      end
    }
  end
  # TODO real, imaginary, conjugate
  it "has abs" do
    expect(src_sig.abs.zip(src_array.collect{|v| v.abs}).all?{|a, b| (a - b).abs < 1E-8}).to be(true)
  end
  it "has sum" do
    expect(src_sig.sum).to eq(src_array.inject{|res, v| res + v})
  end
  it "has dot_product" do
    expect(src_sig_n01.dot_product(src_sig_n01)).to be_within(1E-8).of((src_sig_n01 * src_sig_n01).sum)
  end
  it "has circular_dot_product" do
    (-2..2).each{|offset|
      expect(src_sig_n01.circular_dot_product(offset, src_sig_n01)) \
          .to be_within(1E-8).of(src_sig_n01.circular(offset).dot_product(src_sig_n01))
    }
  end
  it "has max/min_abs_index" do
    [:max, :min].each{|k|
      func = "#{k}_abs_index".to_sym
      expect(src_sig[src_sig.send(func)]).to eq(src_array.send(k))
    }
  end
  it "has partial(start, length) and its resultant has subset of functions" do
    len_orig = src_sig_n01.size
    [0, 1, -1, len_orig, -len_orig, len_orig-1, -len_orig+1]\
        .product([len_orig, len_orig * 2, len_orig / 2, 1])\
        .each{|offset, len|
      sig_slice = src_sig_n01.slice(offset, len)
      sig_partial = src_sig_n01.partial(offset, len)
      [:size, :-@, :abs, :sum, :copy, :max_abs_index, :min_abs_index, :fft, :ifft].each{|func|
        expect(sig_partial.send(func)).to eq(sig_slice.send(func))
      }
      expect(sig_partial.partial(0, sig_partial.size)).to eq(sig_slice.partial(0, sig_slice.size))
      [:*, :+, :-, :dot_product].each{|func|
        expect(sig_partial.send(func, sig_slice)).to eq(sig_slice.send(func, sig_slice))
      }
    }
  end
  # TODO ft, ift
  it "has fft/ifft" do
    expect((src_sig.fft.ifft - src_sig).abs.all?{|v| v < 1E-8}).to be(true)
  end
  it "works correctly with Ractor" do
    expect{
      src_sig_shareable = src_sig.to_shareable
      expect(src_sig_shareable.to_shareable).to be(src_sig_shareable) # return self at multiple calls
      rac = Ractor::new{receive.size}
      rac.send(src_sig_shareable)
      expect(RUBY_VERSION =~ /^3\.5/ ? rac.value : rac.take).to eq(src_sig.size)
    }.not_to raise_error
  end if defined?(Ractor)
end

RSpec::describe GPS_PVT::SDR::Signal::Int do
  let(:sig_type){described_class}
  let(:src_array){(1<<10).times.collect{rand(1<<10)}}
  include_examples GPS_PVT::SDR::Signal
end

RSpec::shared_examples :cw do
  let(:duration){1E0}
  let(:dt){1E-3}
  let(:freq){1.023E6}
  let(:omega){Math::PI * 2 * freq}
  it "has cw" do
    sig = sig_type::cw(duration, dt, freq)
    conv = sig[0].kind_of?(Complex) \
        ? proc{|t| Complex(Math::cos(t), Math::sin(t))} \
        : proc{|t| Math::cos(t)}
    ary = (duration / dt).round.times.collect{|i|
      omega * (dt * i)
    }.collect{|t|
      conv.call(t)
    }
    expect(sig.zip(ary).all?{|a, b| (a - b).abs < 1E-8}).to be(true)
  end
end

RSpec::describe GPS_PVT::SDR::Signal::Real do
  let(:sig_type){described_class}
  let(:src_array){(1<<10).times.collect{rand}}
  include_examples GPS_PVT::SDR::Signal
  include_examples :cw
  it "has type converter" do
    [:Int].each{|arg_type|
      arg_type = GPS_PVT::SDR::Signal.const_get(arg_type)
      expect{ sig_type::new(arg_type::new) }.not_to raise_error
      [:*, :+, :-].each{|func|
        expect(sig_type::new.send(func, arg_type::new).class).to be(sig_type)
      }
    }
  end
  it "has r2c (Hilbert transform), whose inverted operation is c2r in complex version." do
    sig = sig_type::cw(1E-3, 2E-7, freq) # sampling freq. = 5MHz
    sig_c = sig.r2c
    expect(sig_c).to be_a_kind_of(GPS_PVT::SDR::Signal::Complex)
    expect(sig_c.size).to eq(((sig.size + 1) / 2).floor)
    sig2 = sig_c.c2r
    expect(sig2).to be_a_kind_of(GPS_PVT::SDR::Signal::Real)
    expect(sig.zip(sig2.to_a).all?{|a, b| (a - b).abs < 1E-6}).to be(true)
  end
  it "has r2i" do
    sig = sig_type::cw(1E-3, 2E-7, freq) # sampling freq. = 5MHz
    sf = (1 << 8)
    sig_i = sig.r2i(sf)
    expect(sig_i).to be_a_kind_of(GPS_PVT::SDR::Signal::Int)
    expect(sig.zip(sig_i.to_a).all?{|a, b| (a * sf).truncate == b}).to be(true)
  end
end

RSpec::describe GPS_PVT::SDR::Signal::Complex do
  let(:sig_type){described_class}
  let(:src_array){
    klass = Class::new(Complex){
      define_method(:<=>){|another|
        abs2 <=> another.abs2
      }
    }
    (1<<10).times.collect{klass::rect(rand, rand)}
  }
  include_examples GPS_PVT::SDR::Signal
  include_examples :cw
  it "has type converter" do
    [:Int, :Real].each{|arg_type|
      arg_type = GPS_PVT::SDR::Signal.const_get(arg_type)
      expect{ sig_type::new(arg_type::new) }.not_to raise_error
      [:*, :+, :-].each{|func|
        expect(sig_type::new.send(func, arg_type::new).class).to be(sig_type)
      }
    }
  end
end

RSpec::shared_examples :Signal_Partial do
  let(:orig_sig_type){eval(described_class.to_s.sub(/_Partial$/, ''))}
  it "cannot generate an instance via new()" do
    expect{described_class::new}.to raise_error(TypeError)
  end
  it "works correctly after the original instance is dereferenced" do
    sig = orig_sig_type::new((1<<10).times.collect{rand(1<<10)})
    sig_partial = sig.partial(0, sig.size)
    sig = nil
    GC::start
    expect{sig_partial.to_a}.not_to raise_error
    sig_partial2 = sig_partial.partial(0, sig_partial.size)
    sig_partial = nil
    GC::start
    expect{sig_partial2.to_a}.not_to raise_error
  end
end

RSpec::describe GPS_PVT::SDR::Signal::Int_Partial do
  include_examples :Signal_Partial
end

RSpec::describe GPS_PVT::SDR::Signal::Real_Partial do
  include_examples :Signal_Partial
end

RSpec::describe GPS_PVT::SDR::Signal::Complex_Partial do
  include_examples :Signal_Partial
end
