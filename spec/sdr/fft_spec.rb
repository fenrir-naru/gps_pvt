#!/usr/bin/ruby

require 'rspec'

require 'inline'

class FFT
  inline(:C){|builder|
    builder.include('<vector>')
    builder.include('"param/complex.h"')
    builder.include('"algorithm/fft.h"')
    builder.add_compile_flags(
        '-x c++',
        "-I#{File::join(File::dirname(__FILE__), '..', '..', 'ext', 'ninja-scan-light', 'tool')}",
        "-I#{File::join(File::dirname(__FILE__), '..', '..', 'ext', 'sdr')}")
    builder.add_link_flags('-lstdc++')
    builder.prefix <<-__C_CODE__
#{<<-__CODE__ if Gem::Version::new(RUBY_VERSION) < Gem::Version::new("2.5")
/* copy from internal.h */
struct RComplex {
  struct RBasic basic;
  const VALUE real;
  const VALUE imag;
};
#define RCOMPLEX(obj) (R_CAST(RComplex)(obj))

#define rb_complex_real(obj) (RCOMPLEX(obj)->real)
#define rb_complex_imag(obj) (RCOMPLEX(obj)->imag)
__CODE__
}
typedef Complex<double> val_t;
typedef std::vector<val_t> vec_t;
static vec_t vec_ruby2c_any(int argc, VALUE *argv) {
  // read input
  vec_t res;
  if((argc == 1) && RB_TYPE_P(*argv, T_ARRAY)){
    for(int i(0); i < RARRAY_LEN(*argv); ++i){
      VALUE elm(RARRAY_AREF(*argv, i));
      if(RB_TYPE_P(elm, T_COMPLEX)){
        res.push_back(val_t(
            rb_num2dbl(rb_complex_real(elm)),
            rb_num2dbl(rb_complex_imag(elm))));
      }else{
        res.push_back(val_t(rb_num2dbl(elm)));
      }
    }
  }else{
    for(int i(0); i < argc; ++i){
      if(RB_TYPE_P(argv[i], T_COMPLEX)){
        res.push_back(val_t(
            rb_num2dbl(rb_complex_real(argv[i])),
            rb_num2dbl(rb_complex_imag(argv[i]))));
      }else{
        res.push_back(val_t(rb_num2dbl(argv[i])));
      }
    }
  }
  return res;
}
static vec_t vec_ruby2c(VALUE v) {
  return vec_ruby2c_any(1, &v);
}
static VALUE vec_c2ruby(const vec_t &vec) {
  // write output
  VALUE res(rb_ary_new_capa(vec.size()));
  for(typename vec_t::const_iterator it(vec.begin()), it_end(vec.end());
      it != it_end; ++it){
    rb_ary_push(res, rb_complex_new(
        rb_float_new(it->real()),
        rb_float_new(it->imaginary())));
  }
  return res;
}
    __C_CODE__
    builder.add_type_converter('vec_t', 'vec_ruby2c', 'vec_c2ruby')
    [:fft, :ifft].each{|func|
      builder.c_raw_singleton <<-__C_CODE__
static VALUE #{func}(int argc, VALUE *argv, VALUE self) {
  return vec_c2ruby(FFT_Generic<val_t>::#{func}(vec_ruby2c_any(argc, argv)));
}
      __C_CODE__
      [:CooleyTukey, :Bluestein].each{|alg|
        builder.c_raw_singleton <<-__C_CODE__
static VALUE #{func}_#{alg}(int argc, VALUE *argv, VALUE self) {
  vec_t input(vec_ruby2c_any(argc, argv));
  return vec_c2ruby(FFT_Generic<val_t>::#{func}(
      input.begin(), input.end(), FFT_Generic<val_t>::FFT_#{alg}));
}
        __C_CODE__
      }
    }
    [:ft, :ift].each{|func|
      builder.c_raw_singleton <<-__C_CODE__
static VALUE #{func}(int argc, VALUE *argv, VALUE self) {
  val_t v(FFT_Generic<val_t>::#{func}(vec_ruby2c_any(1, argv), rb_num2dbl(argv[1])));
  return rb_complex_new(
      rb_float_new(v.real()), rb_float_new(v.imaginary()));
}
      __C_CODE__
    }
  }
end

RSpec::describe FFT do
  let(:target){described_class}
  let(:src){
    srand(0)
    values = (1 << 16).times.collect{
      Complex(rand, rand)
    }
    [1 << 5, 3 ** 6, 1000, 1 << 10, 3833, 1 << 12, 5456, 8117, 1 << 14, 1 << 16].collect{|len|
      values.slice(0, len)
    }
  }
  shared_examples :comparison do
    [:fft, :ifft].each{|func|
      it "generates the same #{func} results" do
        src.each{|values|
          target.send(func, values).zip(another_lib.send(func, values)).each{|v1, v2|
            expect(v1.real).to be_within(1E-8).of(v2.real)
            expect(v1.imag).to be_within(1E-8).of(v2.imag)
          }
        }
      end
    }
  end

  [:CooleyTukey, :Bluestein].combination(2).each{|alg1, alg2|
    [:fft, :ifft].each{|func|
      it "generates the same #{func} results with different algorithm (#{alg1}, #{alg2})" do
        src.each{|values|
          target.send("#{func}_#{alg1}".to_sym, values)
              .zip(target.send("#{func}_#{alg2}".to_sym, values)).each.with_index{|(v1, v2), i|
            #p [values.size, i, v1 / v2, v1, v2]
            expect(v1.real).to be_within(1E-8).of(v2.real)
            expect(v1.imag).to be_within(1E-8).of(v2.imag)
          }
        }
      end
    }
  }

  begin
    require 'narray'
    require 'numru/fftw3'
  rescue LoadError
  end
  
  context 'in comparison with NumRu::FFTW3' do
    let(:another_lib){Class::new{class << self
      def fft(values)
        NumRu::FFTW3::fft(NArray[*values], NumRu::FFTW3::FORWARD).to_a
      end
      def ifft(values)
        # FFTW computes an unnormalized transform: computing a forward followed
        # by a backward transform (or vice versa) will result in the original data
        # multiplied by the size of the transform (the product of the dimensions)
        (NumRu::FFTW3::fft(NArray[*values], NumRu::FFTW3::BACKWARD) / values.size).to_a
      end
    end}}
    include_examples :comparison
  end if defined?(NumRu::FFTW3)
  
  begin
    require 'numo/narray'
    require 'numo/fftw'
  rescue LoadError
  end
  
  context 'in comparison with Numo::FFTW' do
    let(:another_lib){Class::new{class << self
      def fft(values)
        Numo::FFTW::dft(Numo::NArray[*values], -1).to_a
      end
      def ifft(values)
        (Numo::FFTW::dft(Numo::NArray[*values], 1) / values.size).to_a
      end
    end}}
    include_examples :comparison
  end if defined?(Numo::FFTW)

  it "has the same results by using DFT and FFT in forward and backward transformations" do
    src[0..1].each{|values|
      target::fft(values).zip(values.size.times.collect{|i| target::ft(values, i)}).each{|v1, v2|
        expect(v1.real).to be_within(1E-8).of(v2.real)
        expect(v1.imag).to be_within(1E-8).of(v2.imag)
      }
      target::ifft(values).zip(values.size.times.collect{|i| target::ift(values, i)}).each{|v1, v2|
        expect(v1.real).to be_within(1E-8).of(v2.real)
        expect(v1.imag).to be_within(1E-8).of(v2.imag)
      }
    }
  end
  it "reproduces the input with forward, then backward transformations" do
    src.each{|values|
      target::ifft(target::fft(values)).zip(values).each{|v1, v2|
        expect(v1.real).to be_within(1E-8).of(v2.real)
        expect(v1.imag).to be_within(1E-8).of(v2.imag)
      }
    }
  end
end
