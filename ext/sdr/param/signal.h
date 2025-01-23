/**
 * Basic class for GNSS signal processing
 *
 * coded by fenrir.
 */
#include <cstdlib>
#include <vector>
#include <algorithm>
#include <numeric>

#if defined(isfinite)
#define isfinite_
#undef isfinite
#endif

#include "navigation/GPS.h"
#include "param/complex.h"
#include "algorithm/fft.h"

#if defined(isfinite_)
#undef isfinite_
#define isfinite(x) finite(x)
#endif

template <class T, class BufferT = std::vector<T> >
class Signal;

template <class T_Generator, class T_Signal, class T_Tick = double>
struct SignalGenerator {
  typedef T_Tick tick_t;
  tick_t phase_cycle;
  SignalGenerator(const tick_t &offset_cycle = 0)
      : phase_cycle(offset_cycle){}
  ~SignalGenerator(){}
  T_Signal current() const;
  void advance(const tick_t &shift_cycle){
    phase_cycle += shift_cycle;
  }
  Signal<T_Signal> generate(
      const tick_t &t, const tick_t &dt, const tick_t &freq);
};

template <class T_Generator, class T_Signal, class T_Tick = double>
struct TimeBasedSignalGenerator : public SignalGenerator<T_Generator, T_Signal, T_Tick> {
  typedef SignalGenerator<T_Generator, T_Signal, T_Tick> super_t;
  typename super_t::tick_t frequency;
  TimeBasedSignalGenerator(
      const typename super_t::tick_t &init_freq,
      const typename super_t::tick_t &offset_time = 0)
      : super_t(offset_time * init_freq), frequency(init_freq) {}
  void advance_time(const typename super_t::tick_t &shift_time){
    static_cast<T_Generator *>(this)->advance(frequency * shift_time);
  }
  using super_t::generate;
  Signal<T_Signal> generate(
      const typename super_t::tick_t &t, const typename super_t::tick_t &dt);
};

template <class T_Signal>
struct CosineWave
    : public TimeBasedSignalGenerator<CosineWave<T_Signal>, T_Signal> {
  typedef TimeBasedSignalGenerator<CosineWave<T_Signal>, T_Signal> super_t;
  CosineWave(const typename super_t::tick_t &init_freq)
      : super_t(init_freq) {}
  T_Signal current() const {
    return std::cos(M_PI * 2 * super_t::phase_cycle);
  }
};
template <class T_Signal>
struct CosineWave<Complex<T_Signal> >
    : public TimeBasedSignalGenerator<CosineWave<Complex<T_Signal> >, Complex<T_Signal> > {
  typedef TimeBasedSignalGenerator<CosineWave<Complex<T_Signal> >, Complex<T_Signal> > super_t;
  CosineWave(const typename super_t::tick_t &init_freq)
      : super_t(init_freq) {}
  Complex<T_Signal> current() const {
    return Complex<T_Signal>::exp(M_PI * 2 * super_t::phase_cycle);
  }
};

template <class T, class BufferT>
struct SignalTypeResolver;

template <class T, class T2>
struct SignalTypeResolver<T, std::vector<T2> > {
  typedef Signal<T, std::vector<T> > assignable_t;
};

template <class SignalT>
struct PartialSignalBuffer;

template <class T, class BufferT>
class Signal {
public:
  typedef Signal<T, BufferT> self_t;
  template <class T2>
  struct val_t {
    typedef T2 r_t;
    typedef Complex<T2> c_t;
    static const bool is_complex = false;
  };
  template <class T2>
  struct val_t<Complex<T2> > {
    typedef T2 r_t;
    typedef Complex<T2> c_t;
    static const bool is_complex = true;
  };

  typedef T value_t;
  typedef typename val_t<value_t>::r_t real_t;
  typedef typename val_t<value_t>::c_t complex_t;
  static const bool is_complex = val_t<value_t>::is_complex;

  template <class T2, class BufferT2>
  friend class Signal;

  typedef BufferT buf_t;
  typedef typename buf_t::size_type size_t;

  template <class T2, class BufferT2>
  struct type_resolver_t {
    typedef Signal<T2> assignable_t;
  };
  typedef typename SignalTypeResolver<T, BufferT>::assignable_t sig_t;
  typedef typename SignalTypeResolver<real_t, BufferT>::assignable_t sig_r_t;
  typedef typename SignalTypeResolver<complex_t, BufferT>::assignable_t sig_c_t;

  buf_t samples;

  Signal() : samples() {}
  Signal(const buf_t &buf) : samples(buf) {}
protected:
  Signal(const size_t &capacity) : samples() {
    samples.reserve(capacity);
  }
public:
  template <class T2, class BufferT2>
  Signal(const Signal<T2, BufferT2> &sig)
      : samples(sig.samples.begin(), sig.samples.end()) {}
  template <class T_Generator, class T_Signal, class T_Tick>
  Signal(
      SignalGenerator<T_Generator, T_Signal, T_Tick> &gen,
      const T_Tick &t, const T_Tick &dt, const T_Tick &freq)
      : samples(std::round(t / dt)) {
    for(typename buf_t::iterator it(samples.begin()), it_end(samples.end());
        it != it_end; ++it){
      *it = static_cast<T_Generator &>(gen).current();
      static_cast<T_Generator &>(gen).advance(freq * dt);
    }
  }
  template <class T_Generator, class T_Signal, class T_Tick>
  Signal(
      TimeBasedSignalGenerator<T_Generator, T_Signal, T_Tick> &gen,
      const T_Tick &t, const T_Tick &dt)
      : samples(std::round(t / dt)) {
    for(typename buf_t::iterator it(samples.begin()), it_end(samples.end());
        it != it_end; ++it){
      *it = static_cast<T_Generator &>(gen).current();
      static_cast<T_Generator &>(gen).advance_time(dt);
    }
  }

  static sig_t cw(const real_t &t, const real_t &dt, const real_t &freq) {
    CosineWave<value_t> gen(freq);
    return Signal(gen, t, dt);
  }

  size_t size() const {return samples.size();}
  value_t &operator[](const size_t &i) {return samples[i];}
  const value_t &operator[](const size_t &i) const {return samples[i];}

  // Scalar operation
  template <class T2>
  self_t &operator*=(const T2 &k){
    struct op_t {
      T2 k;
      value_t operator()(const value_t &v) const {return v * k;}
    };
    op_t op = {k};
    std::transform(samples.begin(), samples.end(), samples.begin(), op);
    return *this;
  }
  template <class T2>
  sig_t operator*(const T2 &k) const {return (sig_t(*this) *= k);}
  sig_t operator-() const {return *this * -1;}
  template <class T2>
  self_t &operator+=(const T2 &v){
    struct op_t {
      T2 v2;
      value_t operator()(const value_t &v1) const {return v1 + v2;}
    };
    op_t op = {v};
    std::transform(samples.begin(), samples.end(), samples.begin(), op);
    return *this;
  }
  template <class T2>
  sig_t operator+(const T2 &v) const {return (sig_t(*this) += v);}
  template <class T2>
  self_t &operator-=(const T2 &v){return (*this) += (-v);}
  template <class T2>
  sig_t operator-(const T2 &v) const {return (sig_t(*this) -= v);}

  // Vector operation
  template <class T2, class BufferT2>
  self_t &operator*=(const Signal<T2, BufferT2> &sig){
    struct op_t {
      value_t operator()(const value_t &v1, const T2 &v2) const {return v1 * v2;}
    };
    std::transform(
        samples.begin(), samples.end(), sig.samples.begin(),
        samples.begin(),
        op_t());
    return *this;
  }
  template <class T2, class BufferT2>
  sig_t operator*(const Signal<T2, BufferT2> &sig) const {
    return (sig_t(*this) *= sig);
  }
  template <class T2, class BufferT2>
  self_t &operator+=(const Signal<T2, BufferT2> &sig){
    struct op_t {
      value_t operator()(const value_t &v1, const T2 &v2) const {return v1 + v2;}
    };
    std::transform(
        samples.begin(), samples.end(), sig.samples.begin(),
        samples.begin(),
        op_t());
    return *this;
  }
  template <class T2, class BufferT2>
  sig_t operator+(const Signal<T2, BufferT2> &sig) const {
    return (sig_t(*this) += sig);
  }
  template <class T2, class BufferT2>
  self_t &operator-=(const Signal<T2, BufferT2> &sig){
    struct op_t {
      value_t operator()(const value_t &v1, const T2 &v2) const {return v1 - v2;}
    };
    std::transform(
        samples.begin(), samples.end(), sig.samples.begin(),
        samples.begin(),
        op_t());
    return *this;
  }
  template <class T2, class BufferT2>
  sig_t operator-(const Signal<T2, BufferT2> &sig) const {
    return (sig_t(*this) -= sig);
  }

  self_t &resize(const size_t &new_size){
    samples.resize(new_size);
    return *this;
  }

  self_t &rotate(int offset){
    offset = std::div(offset, samples.size()).rem;
    if(offset < 0){offset += samples.size();}
    buf_t buf(samples.size());
    std::copy(samples.begin() + offset, samples.end(), buf.begin());
    std::copy(samples.begin(), samples.begin() + offset, buf.end() - offset);
    samples.swap(buf);
    return *this;
  }
  sig_t circular(int offset, size_t length) const {
    offset = std::div(offset, samples.size()).rem;
    if(offset < 0){offset += samples.size();}
    typename sig_t::buf_t buf(length);
    typename sig_t::buf_t::iterator it(buf.begin());
    typename buf_t::const_iterator it_first(samples.begin() + offset);
    size_t length_latter(samples.size() - offset);
    if(length >= length_latter){
      std::copy(it_first, samples.end(), it);
      it += length_latter;
      for(length -= length_latter; length > samples.size(); length -= samples.size(), it += samples.size()){
        std::copy(samples.begin(), samples.end(), it);
      }
      std::copy(samples.begin(), samples.begin() + length, it);
    }else{
      std::copy(it_first, it_first + length, it);
    }
    return sig_t(buf);
  }
  sig_t circular(const int &offset) const {
    return circular(offset, size());
  }
  int get_slice_end(int &start, const size_t &length) const {
    if(start < 0){start += size();}
    if(start < 0){return start;}
    int end(start + length);
    if(end > size()){end = size();}
    return end;
  }
  sig_t slice(int start, const size_t &length) const {
    int end(get_slice_end(start, length));
    if(end < 0){return sig_t();}
    return circular(start, end - start);
  }

protected:
  sig_r_t pick(const bool &is_real) const {
    typename sig_r_t::buf_t buf(samples.size());
    if(is_real){
      struct op_t {
        real_t operator()(const real_t &v) const {return v;}
        real_t operator()(const complex_t &v) const {return v.real();}
      };
      std::transform(
          samples.begin(), samples.end(),
          buf.begin(), op_t());
    }else{
      struct op_t {
        real_t operator()(const real_t &v) const {return real_t(0);}
        real_t operator()(const complex_t &v) const {return v.imaginary();}
      };
      std::transform(
          samples.begin(), samples.end(),
          buf.begin(), op_t());
    }
    return sig_r_t(buf);
  }
public:
  sig_r_t real() const {return pick(true);}
  sig_r_t imaginary() const {return pick(false);}
  sig_t conjugate() const {
    struct op_t {
      real_t operator()(const real_t &v) const {return v;}
      complex_t operator()(const complex_t &v) const {return v.conjugate();}
    };
    typename sig_t::buf_t buf(samples.size());
    std::transform(
        samples.begin(), samples.end(),
        buf.begin(),
        op_t());
    return sig_t(buf);
  }
  sig_r_t abs() const {
    struct op_t {
      real_t operator()(const real_t &v) const {return std::abs(v);}
      real_t operator()(const complex_t &v) const {return v.abs();}
    };
    typename sig_r_t::buf_t buf(samples.size());
    std::transform(
        samples.begin(), samples.end(),
        buf.begin(),
        op_t());
    return sig_r_t(buf);
  }
  value_t sum() const {
    return std::accumulate(samples.begin(), samples.end(), value_t(0));
  }
  template <class T2, class BufferT2>
  value_t dot_product(const Signal<T2, BufferT2> &sig) const {
    return std::inner_product(
        samples.begin(), samples.end(), sig.samples.begin(), value_t(0));
  }
protected:
  struct cmp_abs_t {
    bool operator()(const real_t &v1, const real_t &v2) const {return v1 < v2;}
    bool operator()(const complex_t &v1, const complex_t &v2) const {
      return v1.abs() < v2.abs();
    }
  };
public:
  typename buf_t::const_iterator max_abs_element() const {
    return std::max_element(samples.begin(), samples.end(), cmp_abs_t());
  }
  typename buf_t::const_iterator min_abs_element() const {
    return std::min_element(samples.begin(), samples.end(), cmp_abs_t());
  }

  complex_t ft(const real_t &k) const {
    return FFT_Generic<value_t>::ft(samples.begin(), samples.end(), k);
  }
  sig_c_t fft() const {
    return sig_c_t(FFT_Generic<value_t>::fft(samples.begin(), samples.end()));
  }
  complex_t ift(const real_t &n) const {
    return FFT_Generic<value_t>::ft(samples.begin(), samples.end(), n);
  }
  sig_c_t ifft() const {
    return sig_c_t(FFT_Generic<value_t>::ifft(samples.begin(), samples.end()));
  }
};

template <class T_Generator, class T_Signal, class T_Tick>
Signal<T_Signal> SignalGenerator<T_Generator, T_Signal, T_Tick>::generate(
    const tick_t &t, const tick_t &dt, const tick_t &freq) {
  return Signal<T_Signal>(static_cast<T_Generator &>(*this), t, dt, freq);
}

template <class T_Generator, class T_Signal, class T_Tick>
Signal<T_Signal> TimeBasedSignalGenerator<T_Generator, T_Signal, T_Tick>::generate(
    const typename super_t::tick_t &t, const typename super_t::tick_t &dt) {
  return Signal<T_Signal>(static_cast<T_Generator &>(*this), t, dt);
}

template <class SignalT>
struct PartialSignalBuffer {
  typedef SignalT sig_raw_t;
  typedef typename sig_raw_t::value_t value_t;
  typedef Signal<value_t, PartialSignalBuffer<SignalT> > sig_partial_t;

  sig_raw_t *orig;
  typedef typename sig_raw_t::size_t size_type;
  size_type idx_head, length;
  size_type size() const {return length;}
  value_t &operator[](const size_type &i) {return orig->samples[idx_head + i];}
  const value_t &operator[](const size_type &i) const {return orig->samples[idx_head + i];}
  typedef typename sig_raw_t::buf_t::iterator iterator;
  iterator begin() {
    return orig->samples.begin() + idx_head;
  }
  iterator end() {
    return begin() + length;
  }
  typedef typename sig_raw_t::buf_t::const_iterator const_iterator;
  const_iterator begin() const {
    return orig->samples.begin() + idx_head;
  }
  const_iterator end() const {
    return begin() + length;
  }

  static sig_partial_t generate_signal(
      sig_raw_t &orig, int start, const size_type &length){
    int end(orig.get_slice_end(start, length));
    if(end < 0){start = end = 0;}
    typename sig_partial_t::buf_t buf = {
        &orig, size_type(start), size_type(end - start)};
    return sig_partial_t(buf);
  }
  static sig_partial_t generate_signal(
      sig_partial_t &orig, int start, const size_type &length){
    int end(orig.get_slice_end(start, length));
    if(end < 0){start = end = 0;}
    typename sig_partial_t::buf_t buf = {
        orig.samples.orig, orig.samples.idx_head + size_type(start), size_type(end - start)};
    return sig_partial_t(buf);
  }
};

template <class T, class SignalT>
struct SignalTypeResolver<T, PartialSignalBuffer<SignalT> >
    : public SignalTypeResolver<T, typename SignalT::buf_t> {};
