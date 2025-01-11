require 'rspec'

require 'gps_pvt/sdr/Replica'

begin; require 'inline'; rescue LoadError; end

class NativeGenerator
  inline(:C){|builder|
    builder.include('<vector>')
    builder.include('"navigation/GPS.h"')
      
    builder.add_compile_flags(
        '-x c++',
        '-DHAVE_ISFINITE', # for ruby/missing.h
        "-I#{File::join([File::absolute_path(File::dirname(__FILE__)),
          ['..'] * 2, 'ext', 'ninja-scan-light', 'tool'].flatten)}")
    builder.add_link_flags('-lstdc++')
    builder.prefix <<-__C_CODE__
VALUE v2val(const double &v){return rb_float_new(v);}
VALUE v2val(const int &v){return INT2NUM(v);}
template <class T>
static VALUE vec_c2ruby(const std::vector<T> &vec) {
  // write output
  VALUE res(rb_ary_new_capa(vec.size()));
  for(typename std::vector<T>::const_iterator it(vec.begin()), it_end(vec.end());
      it != it_end; ++it){
    rb_ary_push(res, v2val(*it));
  }
  return res;
}
    __C_CODE__
    builder.c_singleton <<-__C_CODE__
static VALUE gps_ca_code(int prn, double dt, int len) {
  typedef double real_t;
  typedef typename GPS_Signal<real_t>::CA_Code gen_t;
  
  std::vector<int> res;
  gen_t gen(prn);
  int code_idx(0);
  for(real_t time(0); res.size() < len; time += dt){
    int shift(std::floor(time / gen_t::length_1chip()) - code_idx);
    for(int i(0); i < shift; ++i){
      gen.next();
    }
    code_idx += shift;
    res.push_back(gen.get_multi());
  }
  return vec_c2ruby(res);
}
    __C_CODE__
  }
end if defined?(Module::inline)

RSpec::describe GPS_PVT::SDR::Replica::GPS_CA_Code do
  let(:gen_type){described_class}
  let(:prn_range){1..32}
  let(:duration){1E-2}
  let(:dt){1E-6}
  it "generates GPS C/A code replica" do
    prn_range.each{|prn|
      a = gen_type::new(prn).generate(duration, dt).to_a
      b = NativeGenerator::gps_ca_code(prn, dt, (duration / dt).round)
      idx_diff = a.zip(b).collect{|v_a, v_b| v_a == v_b}.find_index(false)
      msg_fail = "PRN(#{prn}) difference at idx(#{idx_diff}) as #{[a, b].zip([:ext, :native]).collect{|ary, label|
        idx_pre, idx_post = [-3, 3].collect{|v| idx_diff + v}
        (idx_pre < 0) ? (idx_pre = 0) : (msg_pre = '...') 
        (idx_post > ary.size) ? (idx_post = -1) : (msg_post = '...')
        "#{label}:[%s]" % [msg_pre, ary[idx_pre..idx_post], msg_post].flatten.compact.join(', ')
      }.join(', ')}" if idx_diff
      expect(idx_diff).to be_nil, msg_fail
    }
  end if defined?(NativeGenerator)
  it "has functionality to retreat replica" do
    prn_range.each{|prn|
      gen_f, gen_b = 2.times.collect{gen_type::new(prn)}
      forward = gen_f.generate(duration, dt).to_a[10..-1] # patched
      gen_b.advance(gen_f.phase_cycle)
      forward.reverse.each.with_index{|v, i|
        gen_b.advance_time(-dt)
        expect(v).to eq(gen_b.current)
      }
    }
  end
end
