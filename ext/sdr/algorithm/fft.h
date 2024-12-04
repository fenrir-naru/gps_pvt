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

    template <class T2>
    friend class FFT_Generic;

  protected:
    struct cvec_sorted_t {
      cvec_t vec;
      typename cvec_t::size_type border;
    };

    template <class IteratorT>
    static cvec_sorted_t prepare_CooleyTukey(
        IteratorT it_head, IteratorT it_tail, const bool &is_forward = true){

      int n_pi(is_forward ? -2 : 2);

      typedef cvec_t V1;
      typedef cvec_sorted_t V2;

      V2 sorted;
      if(is_complex){
        std::copy(it_head, it_tail, std::back_inserter(sorted.vec));
      }else{ // cast explicitly
        for(; it_head != it_tail; ++it_head){
          sorted.vec.push_back(complex_t(*it_head));
        }
      }
      sorted.border = sorted.vec.size();

      // Calculate log2
      int power2(BitCounter<typename V1::size_type>::ntz(sorted.border));

      // Sort before FT/IFT
      if(power2 > 0){
        V2 sorted_next = {V1(sorted.vec.size()), sorted.border};
        for(int n(0); n < power2; n++){
          int i(0), i2(sorted_next.vec.size() / 2);
          sorted_next.border >>= 1;
          for(typename V1::const_iterator elm(sorted.vec.begin()), elm_end(sorted.vec.end());
              elm < elm_end;
              elm += sorted.border){
            for(typename V1::size_type j(0), j2(sorted_next.border); j < sorted_next.border; j++, j2++){
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

    static cvec_t coefficients(
        const int &len, const real_t &i, const bool &is_forward = true){
      cvec_t res;
      res.reserve(len);
      int n_pi(is_forward ? -2 : 2);
      for(int j(0); j < len; ++j){
        res.push_back(complex_t::exp(M_PI * n_pi * i * j / len));
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
    template <class IteratorT>
    static cvec_t fft_CooleyTukey(IteratorT it_head, IteratorT it_tail, const bool &is_forward = true){

      typedef cvec_t V1;
      typedef cvec_sorted_t V2;

      int n(std::distance(it_head, it_tail));
      V1 result(n);
      if(n == 0){return result;}

      V2 sorted(prepare_CooleyTukey(it_head, it_tail, is_forward));

      // FT
      int chunks(n / sorted.border), chunks2(chunks * chunks);
      int base(0);
      for(typename V1::size_type j(0), j_end(sorted.border); j < j_end; j++){
        typename V1::iterator it(result.begin() + base);
        V1 coef(coefficients(sorted.border, j * chunks, is_forward));
        for(typename V1::const_iterator elm(sorted.vec.begin()), elm_end(sorted.vec.end());
            elm < elm_end;
            elm += sorted.border, ++it){
          *it = FFT_Generic<complex_t>::accumulate(coef, elm);
        }
        base += chunks2;
        base %= n;
      }
      if(!is_forward){
        for(typename V1::iterator it(result.begin()), it_end(result.end()); it != it_end; ++it){
          *it /= n;
        }
      }
      
      return result;
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
    
    template <class IteatorT>
    static cvec_t fft(IteatorT it_head, IteatorT it_tail){
      return fft_CooleyTukey(it_head, it_tail);
    }
    template <class T2>
    static cvec_t fft(const std::vector<T2> &v){
      return fft(v.begin(), v.end());
    }
    template <class IteatorT>
    static cvec_t ifft(IteatorT it_head, IteatorT it_tail){
      return fft_CooleyTukey(it_head, it_tail, false);
    }
    template <class T2>
    static cvec_t ifft(const std::vector<T2> &v){
      return ifft(v.begin(), v.end());
    }
};

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
