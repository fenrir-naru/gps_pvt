#ifndef __FFT_H__
#define __FFT_H__

#include <vector>
#include <iterator>
#include <algorithm>
#include <numeric>

#ifdef _MSC_VER
  #define _USE_MATH_DEFINES
#endif

#include <cmath>

#include "param/complex.h"
#include "util/bit_counter.h"

template <class T>
class FFT_Generic {
  public:
    template <class T2>
    struct val_t {
      typedef T2 r_t;
      typedef Complex<T2> c_t;
      typedef std::vector<c_t> cvec_t;
      static const bool is_complex = false;
    };
    template <class T2>
    struct val_t<Complex<T2> > {
      typedef T2 r_t;
      typedef Complex<T2> c_t;
      typedef std::vector<c_t> cvec_t;
      static const bool is_complex = true;
    };

    typedef typename val_t<T>::r_t real_t;
    typedef typename val_t<T>::c_t complex_t;
    typedef typename val_t<T>::cvec_t cvec_t;
    static const bool is_complex = val_t<T>::is_complex;
    struct op_conjugate_t {
      complex_t operator()(const complex_t &v){return v.conjugate();}
    };

    template <class T2>
    friend class FFT_Generic;

  protected:
    struct cvec_sorted_t {
      cvec_t vec;
      typename cvec_t::size_type border;
    };

    template <class IteratorT>
    static cvec_sorted_t prepare_CooleyTukey_pow2(
        IteratorT it_head, IteratorT it_tail, const bool &is_forward = true){

      int n_pi(is_forward ? -2 : 2);

      cvec_sorted_t sorted = {cvec_t(it_head, it_tail), sorted.vec.size()};

      // Calculate log2
      int power2(BitCounter<typename cvec_t::size_type>::ntz(sorted.border));

      // Sort before FT/IFT
      if(power2 > 0){
        cvec_sorted_t sorted_next = {cvec_t(sorted.vec.size()), sorted.border};
        for(int n(0); n < power2; n++){
          int i(0), i2(sorted_next.vec.size() / 2);
          sorted_next.border >>= 1;
          for(typename cvec_t::const_iterator elm(sorted.vec.begin()), elm_end(sorted.vec.end());
              elm < elm_end;
              elm += sorted.border){
            for(typename cvec_t::size_type j(0), j2(sorted_next.border); j < sorted_next.border; j++, j2++){
              sorted_next.vec[i++] = elm[j] + elm[j2];
              sorted_next.vec[i2++] = (elm[j] - elm[j2]) * complex_t::exp(M_PI * n_pi * j / sorted.border);
            }
          }
          sorted.vec.swap(sorted_next.vec);
          sorted.border = sorted_next.border;
        }
      }
      return sorted;
    }

    template <class IteratorT, std::size_t N>
    static cvec_sorted_t prepare_CooleyTukey(
        const int (&prime_numbers)[N],
        IteratorT it_head, IteratorT it_tail, const bool &is_forward = true){

      int n_pi(is_forward ? -2 : 2);

      cvec_sorted_t sorted = {cvec_t(it_head, it_tail), sorted.vec.size()};
      cvec_sorted_t sorted_next = {cvec_t(sorted.vec.size()), sorted.border};

      for(int prime_idx(0); prime_idx < N;){
        const int div(prime_numbers[prime_idx]);
        std::div_t qr(std::div(sorted.border, div));
        if((sorted_next.border = qr.quot) == 0){break;}
        if(qr.rem != 0){
          ++prime_idx;
          continue;
        }
        typename cvec_t::iterator dst(sorted_next.vec.begin());
        typename cvec_t::size_type chunks(sorted.vec.size() / sorted.border);
        /* example: 2 * 3 * ..., chunks: 2 => 6
         * src = [(chunk)0:(final_idx=)0, 2, 4, 6, ...] |[1:1, 3, 5, 7, ...]
         * dst = [0:0, 6, ...][1:1, 7, ...][2:2, ...]   |[3:3, 9, ...][4:4, 10, ...][5:5, ...]
         * dst[0] = src[00] + src[01] + src[02] // k = 0
         * dst[1] = src[10] + src[11] + src[12]
         * dst[2] = (src[00] + src[01](-2pi/3) + src[02](-4pi/3))*[0,-2pi/3) // k = 1, phi = -2pi/3
         * dst[3] = (src[10] + src[11](-2pi/3) + src[12](-4pi/3))*[0,-2pi/3)
         * dst[4] = (src[00] + src[01](-4pi/3) + src[02](-8pi/3))*[0,-4pi/3) // k = 2, phi = -4pi/3
         * dst[5] = (src[10] + src[11](-4pi/3) + src[12](-8pi/3))*[0,-4pi/3)
         */
        { // k = 0
          typename cvec_t::const_iterator src(sorted.vec.begin());
          for(typename cvec_t::size_type chunk(0); chunk < chunks; ++chunk, dst += sorted_next.border){
            std::copy(src, src + sorted_next.border, dst);
            src += sorted_next.border;
            for(int j(1); j < div; ++j){
              for(int i(0); i < sorted_next.border; ++i, ++src){
                dst[i] += *src;
              }
            }
          }
        }
        for(int k(1); k < div; ++k){ // k = [1, div)
          typename cvec_t::const_iterator src(sorted.vec.begin());
          const real_t phi(M_PI * n_pi * k / div), phi2(phi / sorted_next.border);
          for(typename cvec_t::size_type chunk(0); chunk < chunks; ++chunk, dst += sorted_next.border){
            std::copy(src, src + sorted_next.border, dst);
            src += sorted_next.border;
            for(int j(1); j < div; ++j){
              const complex_t offset(complex_t::exp(phi * j));
              for(int i(0); i < sorted_next.border; ++i, ++src){
                dst[i] += *src * offset;
              }
            }
            for(int i(1); i < sorted_next.border; ++i){
              dst[i] *= complex_t::exp(phi2 * i);
            }
          }
        }
        sorted.vec.swap(sorted_next.vec);
        sorted.border = sorted_next.border;
      }

      return sorted;
    }

    static const int builtin_prime_numbers[];
    template <class IteratorT>
    static cvec_sorted_t prepare_CooleyTukey(
        IteratorT it_head, IteratorT it_tail, const bool &is_forward = true){
      return prepare_CooleyTukey(builtin_prime_numbers, it_head, it_tail, is_forward);
    }

    static cvec_t coefficients(
        const int &len, const real_t &step, const bool &is_forward = true){
      cvec_t res; // e^(-i * 2pi * step * j / N)
      res.reserve(len);
      int n_pi(is_forward ? -2 : 2);
      real_t delta(M_PI * n_pi * step / len);
      for(int j(0); j < len; ++j){
        res.push_back(complex_t::exp(delta * j));
      }
      return res;
    }
    template <class IteratorT>
    static complex_t accumulate(const cvec_t &coef, IteratorT it_head){
      return std::inner_product(coef.begin(), coef.end(), it_head, complex_t(0));
    }

  public:
    template <class IteratorT>
    static complex_t ft(IteratorT it_head, IteratorT it_tail, const real_t &k){
      return accumulate(coefficients(std::distance(it_head, it_tail), k), it_head);
    }
    template <class T2>
    static complex_t ft(const std::vector<T2> &v, const real_t &k){
      return ft(v.begin(), v.end(), k);
    }
  protected:
    template <class IteratorT>
    static cvec_t fft_CooleyTukey_pow2(IteratorT it_head, int n, const bool &is_forward = true){
      // expect n = 2^x
      cvec_sorted_t sorted(prepare_CooleyTukey_pow2(it_head, it_head + n, is_forward));
      if(!is_forward){
        for(typename cvec_t::iterator it(sorted.vec.begin()), it_end(sorted.vec.end());
            it != it_end; ++it){
          *it /= n;
        }
      }
      return sorted.vec;
    }
    template <class IteratorT>
    static cvec_t fft_CooleyTukey(IteratorT it_head, int n, const bool &is_forward = true){
      // expect n >= 1

      cvec_sorted_t sorted(prepare_CooleyTukey(it_head, it_head + n, is_forward));

      cvec_t result;
      // FT
      if(sorted.border == 1){
        result.swap(sorted.vec);
      }else{
        result.resize(n);
        typename cvec_t::iterator it(result.begin());
        for(typename cvec_t::size_type j(0), j_end(sorted.border); j < j_end; j++){
          cvec_t coef(coefficients(sorted.border, j, is_forward));
          for(typename cvec_t::const_iterator elm(sorted.vec.begin()), elm_end(sorted.vec.end());
              elm < elm_end;
              elm += sorted.border, ++it){
            *it = FFT_Generic<complex_t>::accumulate(coef, elm);
          }
        }
      }
      if(!is_forward){
        for(typename cvec_t::iterator it(result.begin()), it_end(result.end()); it != it_end; ++it){
          *it /= n;
        }
      }

      return result;
    }
  public:
    template <class IteratorT>
    static cvec_t fft_CooleyTukey(IteratorT it_head, IteratorT it_tail, const bool &is_forward = true){
      int n(std::distance(it_head, it_tail));
      return (n <= 0) ? cvec_t() : fft_CooleyTukey(it_head, n, is_forward);
    }
    template <class T2>
    static cvec_t fft_CooleyTukey(const std::vector<T2> &v, const bool &is_forward = true){
      return fft_CooleyTukey(v.begin(), v.end(), is_forward);
    }
    template <class IteratorT>
    static complex_t ift_no_divide(IteratorT it_head, IteratorT it_tail, const real_t &n){
      return accumulate(coefficients(std::distance(it_head, it_tail), n, false), it_head);
    }
    template <class T2>
    static complex_t ift_no_divide(const std::vector<T2> &v, const real_t &n){
      return accumulate(v.begin(), v.end(), n);
    }
    template <class IteratorT>
    static complex_t ift(IteratorT it_head, IteratorT it_tail, const real_t &n){
      typename IteratorT::difference_type len(std::distance(it_head, it_tail));
      if(len < 1){len = 1;}
      return ift_no_divide(it_head, it_tail, n) / len;
    }
    template <class T2>
    static complex_t ift(const std::vector<T2> &v, const real_t &n){
      return ift(v.begin(), v.end(), n);
    }

  protected:
    static cvec_t coefficients2(
        const int &len, const real_t &step, const bool &is_forward = true){
      cvec_t res; // e^(-i * pi * step * j^2 / N)
      res.reserve(len);
      int n_pi(is_forward ? -1 : 1), len2(len * 2);
      real_t delta(M_PI * n_pi * step / len);
      for(int j(0), j2(0); j < len; (j2 += (j * 2 + 1)) %= len2, ++j){
        res.push_back(complex_t::exp(delta * j2));
      }
      return res;
    }
    template <class IteratorT>
    static cvec_t fft_Bluestein(
        IteratorT it_head, const cvec_t &w, const cvec_t &b_dash_f, const bool &is_forward = true){

      int n(w.size()), n_dash(b_dash_f.size()); // expect n >= 1, n_dash = 2^x (>2n-1)

      /*
       * w = e^(-i * pi * n^2 / N)
       * a = x .* w; a_dash = [a_0, a_1, ..., a_(N-1), 0, ..., 0]
       * b = w.conj; b_dash = [b_0, ..., b_(N-1), 0, ..., 0, b_(N-1), ..., b_1]
       */
      cvec_t a_dash(n_dash);
      std::transform(it_head, it_head + n, w.begin(), a_dash.begin(), std::multiplies<complex_t>());

      // F^(-1)(F(a) .* F(b))
      cvec_t f1(fft_CooleyTukey_pow2(a_dash.begin(), n_dash, is_forward));
      std::transform(f1.begin(), f1.end(), b_dash_f.begin(), f1.begin(), std::multiplies<complex_t>());
      cvec_t result(fft_CooleyTukey_pow2(f1.begin(), n_dash, !is_forward));

      result.resize(n);
      std::transform(w.begin(), w.end(), result.begin(), result.begin(), std::multiplies<complex_t>());

      if(!is_forward){
        for(typename cvec_t::iterator it(result.begin()), it_end(result.end()); it != it_end; ++it){
          *it = *it * n_dash / n;
        }
      }

      return result;
    }
    static cvec_t get_b_dash_f_Bluestein(const cvec_t &w, const int &n_dash, const bool &is_forward = true){
      int n(w.size()); // expect n >= 1, n_dash = 2^x (>2n-1)
      cvec_t b_dash(n_dash);
      std::transform(w.begin(), w.end(), b_dash.begin(), op_conjugate_t());
      std::copy(b_dash.begin() + 1, b_dash.begin() + n, b_dash.rbegin());
      return fft_CooleyTukey_pow2(b_dash.begin(), n_dash, is_forward);
    }
  public:
    template <class IteratorT>
    static cvec_t fft_Bluestein(IteratorT it_head, IteratorT it_tail, const bool &is_forward = true){

      int n(std::distance(it_head, it_tail));
      if(n <= 0){return cvec_t();}

      // Calculate power of two
      int n_dash(BitCounter<int>::set_lower_bits(n) + 1);
      if((n << 1) == n_dash){ // If the original size is just power of two, then use CooleyTukey.
        return fft_CooleyTukey_pow2(it_head, n, is_forward);
      }else{
        cvec_t
            w(coefficients2(n, 1, is_forward)),
            b_dash_f(get_b_dash_f_Bluestein(w, n_dash << 1, is_forward));
        return fft_Bluestein(it_head, w, b_dash_f, is_forward);
      }
    }

  public:
    enum FFT_Algorithm {
      FFT_CooleyTukey,
      FFT_Bluestein,
      FFT_Default,
    };

    template <class IteatorT>
    static cvec_t fft(IteatorT it_head, IteatorT it_tail, const FFT_Algorithm &alg = FFT_Default){
      switch(alg){
        case FFT_CooleyTukey: break;
        case FFT_Bluestein: return fft_Bluestein(it_head, it_tail);
      }
      return fft_CooleyTukey(it_head, it_tail);
    }
    template <class T2>
    static cvec_t fft(const std::vector<T2> &v){
      return fft(v.begin(), v.end());
    }
    template <class IteatorT>
    static cvec_t ifft(IteatorT it_head, IteatorT it_tail, const FFT_Algorithm &alg = FFT_Default){
      switch(alg){
        case FFT_CooleyTukey: break;
        case FFT_Bluestein: return fft_Bluestein(it_head, it_tail, false);
      }
      return fft_CooleyTukey(it_head, it_tail, false);
    }
    template <class T2>
    static cvec_t ifft(const std::vector<T2> &v){
      return ifft(v.begin(), v.end());
    }
};

template <class T>
const int FFT_Generic<T>::builtin_prime_numbers[] = {2, 3, 5, 7, 11, 13, 17, 19};

namespace FFT {
  template <class T>
  static typename FFT_Generic<T>::complex_t ft(const std::vector<T> &v, const typename FFT_Generic<T>::real_t &k){
    return FFT_Generic<T>::ft(v, k);
  }
  template <class T>
  static typename FFT_Generic<T>::complex_t ift(const std::vector<T> &v, const typename FFT_Generic<T>::real_t &n){
    return FFT_Generic<T>::ift(v, n);
  }
  template <class T>
  static typename FFT_Generic<T>::cvec_t fft(const std::vector<T> &v){
    return FFT_Generic<T>::fft(v);
  }
  template <class T>
  static typename FFT_Generic<T>::cvec_t ifft(const std::vector<T> &v){
    return FFT_Generic<T>::ifft(v);
  }
};

#endif /* __FFT_H__ */
