%module Signal

%{
#include <sstream>
#include <string>
#include <exception>
#include <cmath>
// #include <ruby/ractor.h>
%}

%fragment("Signal.i", "header") %{
#include "param/signal.h"

#ifdef HAVE_RB_EXT_RACTOR_SAFE
#include <atomic>
#endif
template <class T>
struct Signal_SideLoaded<T, std::vector<T> > {
  typedef Signal_SideLoaded<T, std::vector<T> > self_t;
#ifdef HAVE_RB_EXT_RACTOR_SAFE
  typedef std::atomic<int> ref_count_t;
#else
  typedef int ref_count_t;
#endif
  ref_count_t ref_count; // keep ref_count to correspond to the same instance
  Signal_SideLoaded() : ref_count(0) {}
  Signal_SideLoaded(const self_t &another) : ref_count(0) {}
  self_t &operator=(const self_t &another){return *this;}
};
%}

%fragment("Signal.i");

%include std_common.i
%include std_string.i
%include exception.i
%include std_except.i

%feature("autodoc", "1");

%import "SylphideMath.i"
%fragment("SylphideMath.i");

%init %{
#ifdef HAVE_RB_EXT_RACTOR_SAFE
  rb_ext_ractor_safe(true);
#endif
%}

#if !defined(SWIGIMPORTED)
%exceptionclass native_exception;
%typemap(throws,noblock=1) native_exception {
  $1.regenerate();
  SWIG_fail;
}
%ignore native_exception;
%inline {
struct native_exception : public std::exception {
#if defined(SWIGRUBY)
  int state;
  native_exception(const int &state_) : std::exception(), state(state_) {}
  void regenerate() const {rb_jump_tag(state);}
#else
  void regenerate() const {}
#endif
};
}
#endif

%fragment(SWIG_Traits_frag(SignalUtil), "header") {
struct SignalUtil {
#if defined(SWIGRUBY)
  template <class T, int bits, class IteratorT>
  static bool read_packed(const VALUE &src, IteratorT &dst_it){
    static const unsigned char mask((1 << bits) - 1);
    switch(TYPE(src)){
      case T_STRING: {
        unsigned char *buf((unsigned char *)(RSTRING_PTR(src)));
        int len_src(RSTRING_LEN(src));
        for(int i(0); i < len_src; ++i, ++buf){
          unsigned char c(*buf);
          for(int j(8 / bits); j > 0; --j, c >>= bits, ++dst_it){
            *dst_it = ((int)((c & mask) << 1) - (int)mask);
          }
        }
        return true;
      }
      case T_FILE: {
        rb_io_ascii8bit_binmode(src);
        while(true){
          VALUE v(rb_io_getbyte(src));
          if(!RTEST(v)){break;} // eof?
          unsigned char c(NUM2CHR(v));
          for(int j(8 / bits); j > 0; --j, c >>= bits, ++dst_it){
            *dst_it = ((int)((c & mask) << 1) - (int)mask);
          }
        }
        return true;
      }
      default: return false;
    }
  }
#endif
  template <class T, class IteratorT = typename Signal<T>::buf_t::iterator>
  static void fill_buffer(IteratorT &it, const void *src = NULL){
    typedef typename Signal<T>::size_t size_t;
#if defined(SWIGRUBY)
    const VALUE *value(static_cast<const VALUE *>(src));
    size_t len(0), i(0);
    VALUE elm_val(Qnil);
    bool valid_input(false);
    if(value){
      if(RB_TYPE_P(*value, T_ARRAY)){
        len = RARRAY_LEN(*value);
        T elm;
        for(; i < len; i++, ++it){
          elm_val = RARRAY_AREF(*value, i);
          if(!SWIG_IsOK(swig::asval(elm_val, &elm))){break;}
          *it = elm;
        }
        valid_input = true;
      }else if(RB_TYPE_P(*value, T_HASH)){
        static const VALUE k_src(ID2SYM(rb_intern("source"))), k_format(ID2SYM(rb_intern("format")));
        VALUE v_src(rb_hash_lookup(*value, k_src)), v_format(rb_hash_lookup(*value, k_format));
        static const struct {
          const VALUE name;
          bool (*func)(const VALUE &src, IteratorT &dst_it);
        } format_list[] = {
          {ID2SYM(rb_intern("packed_1b")), &read_packed<T, 1, IteratorT>},
          {ID2SYM(rb_intern("packed_2b")), &read_packed<T, 2, IteratorT>},
          {ID2SYM(rb_intern("packed_4b")), &read_packed<T, 4, IteratorT>},
          {ID2SYM(rb_intern("packed_8b")), &read_packed<T, 8, IteratorT>},
        };
        for(int i(0); i < sizeof(format_list) / sizeof(format_list[0]); ++i){
          if(format_list[i].name == v_format){
            valid_input = (*format_list[i].func)(v_src, it);
            break;
          }
        }
      }else{
        valid_input = false;
      }
    }else if(rb_block_given_p()){
      valid_input = true;
      int state;
      T elm;
      for(; ; i++, ++it){
        elm_val = rb_protect(rb_yield, UINT2NUM(i), &state);
        if(state != 0){throw native_exception(state);}
        if(!RTEST(elm_val)){break;} // if nil returned, break loop.
        if(!SWIG_IsOK(swig::asval(elm_val, &elm))){
          len = i + 1;
          break;
        }
        *it = elm;
      }
    }
    if(!valid_input){
      std::string str("Unexpected input");
      if(value){
        VALUE v_str(rb_inspect(*value));
        str.append(": ").append(RSTRING_PTR(v_str), RSTRING_LEN(v_str));
      }
      throw std::invalid_argument(str);
    }
    if(i < len){
      std::stringstream s;
      s << "Unexpected input [" << i << "]: ";
      VALUE v_str(rb_inspect(elm_val));
      throw std::invalid_argument(s.str().append(RSTRING_PTR(v_str), RSTRING_LEN(v_str)));
    }
#endif
  }
  static int buffer_size_required(const void *src) {
    if(!src){return -1;}
#if defined(SWIGRUBY)
    const VALUE *value(static_cast<const VALUE *>(src));
    switch(TYPE(*value)){
      case T_ARRAY: return RARRAY_LEN(*value);
      case T_HASH: {
        static const VALUE k_src(ID2SYM(rb_intern("source"))), k_format(ID2SYM(rb_intern("format")));
        VALUE v_src(rb_hash_lookup(*value, k_src)), v_format(rb_hash_lookup(*value, k_format));
        static const struct {
          const VALUE name;
          int per_byte;
        } format_list[] = {
          {ID2SYM(rb_intern("packed_1b")), 8},
          {ID2SYM(rb_intern("packed_2b")), 4},
          {ID2SYM(rb_intern("packed_4b")), 2},
          {ID2SYM(rb_intern("packed_8b")), 1},
        };
        for(int i(0); i < sizeof(format_list) / sizeof(format_list[0]); ++i){
          if(format_list[i].name == v_format){
            switch(TYPE(v_src)){
              case T_STRING: return (format_list[i].per_byte * RSTRING_LEN(v_src));
              case T_FILE: break; // TODO
            }
            break;
          }
        }
      }
    }
#endif
    return -1;
  }
  template <class T>
  static typename Signal<T>::buf_t to_buffer(const void *src = NULL){
    typename Signal<T>::buf_t res;
    int dst_size(buffer_size_required(src));
    if(dst_size >= 0){
      res.resize(dst_size);
      typename Signal<T>::buf_t::iterator it(res.begin());
      fill_buffer<T>(it, src);
    }else{
      std::back_insert_iterator<typename Signal<T>::buf_t> it(std::back_inserter(res));
      fill_buffer<T>(it, src);
    }
    return res;
  }
  template <class SignalT>
  static void each(const SignalT &sig) {
    for(typename SignalT::buf_t::const_iterator
        it(sig.samples.begin()), it_end(sig.samples.end());
        it != it_end; ++it){
#if defined(SWIGRUBY)
      int state;
      rb_protect(rb_yield, swig::from(*it), &state);
      if(state != 0){throw native_exception(state);}
#endif
    }
  }
  template <class T, class T2 = T>
  static Signal<Complex<T2> > r2c(const Signal<T> &sig){
    ///< @see Tsui 6.13 Hilbert transform (6.8), (6.12)-(6.13)
    Signal<Complex<T2> > x(FFT_Generic<T2>::fft(sig.samples));
    return x.circular(0, (x.size() + 1) >> 1).ifft(); // X -(1/2)-> X1 -(ifft)-> x1; TODO when odd case
  }
  template <class T>
  static Signal<T> c2r(const Signal<Complex<T> > &sig){
    ///< @see Tsui 6.14 Hilbert transform (6.14)-(6.17)
    Signal<Complex<T> > x(sig.fft()); // (6.14)
    typename Signal<Complex<T> >::buf_t x1(x.size() << 1);
    typename Signal<Complex<T> >::buf_t::iterator x1_it(x1.begin());
#if 0 // skip reordering in (6.15) because it depends on IF configuration
    typename Signal<Complex<T> >::buf_t::size_type n_half((x.size() + 1) >> 1);
    std::copy( // (6.15)-1
        x.samples.begin() + n_half, x.samples.end(),
        x1_it);
    x1_it += x.samples.size() - n_half;
    std::copy( // (6.15)-2
        x.samples.begin(), x.samples.begin() + n_half,
        x1_it);
    x1_it += n_half;
#else
    std::copy(x.samples.begin(), x.samples.end(), x1_it);
    x1_it += x.samples.size();
#endif
    *(x1_it++) = 0; // (6.16)-1
    struct op_t {
      Complex<T> operator()(const Complex<T> &v) const {return v.conjugate();}
    };
    std::transform( // (6.16)-2
        x1.rend() - x.samples.size(), x1.rend() - 1,
        x1_it,
        op_t());
    return Signal<Complex<T> >(x1).ifft().real(); // (6.17)
  }
%#if defined(SWIGRUBY)
  template <class T>
  static void free(void *ptr){
    Signal<T> *sig = (Signal<T> *)ptr;
    if((--(sig->side_loaded.ref_count)) < 0){
      delete sig;
    }
  }
%#endif
};
}

// @see SylphideMath.i
%typemap(in, numinputs=0) SWIG_Object *_self "$1 = &self;"

template <class T>
struct Signal_Partial {
  std::size_t size() const;
  typename Signal<T>::sig_t operator-() const;
  typename Signal<T>::sig_t slice(const int &start, const unsigned int &length) const;
  typename Signal<T>::sig_r_t real() const;
  typename Signal<T>::sig_r_t imaginary() const;
  typename Signal<T>::sig_t conjugate() const;
  typename Signal<T>::sig_r_t abs() const;
  T sum() const;
  typename Signal<T>::complex_t ft(const typename Signal<T>::real_t &k) const;
  typename Signal<T>::complex_t ift(const typename Signal<T>::real_t &n) const;
  typename Signal<T>::sig_c_t fft() const; 
  typename Signal<T>::sig_c_t ifft() const;
  %extend {
    %fragment(SWIG_Traits_frag(Signal<T>));
    %ignore side_loaded;
    %ignore Signal_Partial();
    %ignore free(void *);
    Signal<T> copy() const {return Signal<T>(*$self);}
    T __getitem__(const unsigned int &i) const {
      return ($self)->operator[](i);
    }
    Signal<T> __getitem__(const int &start, const unsigned int &length) const {
      return ($self)->slice(start, length);
    }
    size_t max_abs_index() const {
      return std::distance(self->samples.begin(), self->max_abs_element());
    }
    size_t min_abs_index() const {
      return std::distance(self->samples.begin(), self->min_abs_element());
    }
    SWIG_Object partial(
        SWIG_Object *_self,
        const int &start, const unsigned int &length) const throw(std::runtime_error) {
      Signal_Partial<T> *sig(const_cast<Signal_Partial<T> *>($self));
      if(((sig->samples.orig->side_loaded.ref_count)++) < 0){
        throw std::runtime_error("Original signal was destructed.");
      }
      SWIG_Object res(swig::from_ptr(new Signal_Partial<T>(
          Signal_PartialBuffer<Signal<T> >::generate_signal(
            *sig, start, length)), 1));
      return res;
    }
#if defined(SWIGRUBY)
  SWIG_Object to_shareable(SWIG_Object *_self) const throw(std::runtime_error) {
%#if defined(HAVE_RB_EXT_RACTOR_SAFE)
    if(RB_FL_TEST(*_self, RUBY_FL_SHAREABLE)){
      return *_self;
    }
%#else
    if(rb_obj_frozen_p(*_self)){
      return *_self;
    }
%#endif
    Signal_Partial<T> *sig(const_cast<Signal_Partial<T> *>($self));
    if(((sig->samples.orig->side_loaded.ref_count)++) < 0){
      throw std::runtime_error("Original signal was destructed.");
    }
    SWIG_Object res(swig::from_ptr(new Signal_Partial<T>(*sig), 1));
%#if defined(HAVE_RB_EXT_RACTOR_SAFE)
    RB_FL_SET(res, RUBY_FL_SHAREABLE);
%#endif
    rb_obj_freeze(res);
    return /*rb_ractor_make_shareable(res);*/ res;
  }
#endif
  }
};

%header {
template <class T>
struct Signal_Partial
    : public Signal<T, Signal_PartialBuffer<Signal<T> > > {
  typedef Signal<T, Signal_PartialBuffer<Signal<T> > > super_t;
  //Signal_Partial() : super_t() {} // delete ctor()
  Signal_Partial(const super_t &sig) : super_t(sig) {}
  Signal_Partial(Signal<T> *orig, const int &idx_begin, const int &idx_end)
      : super_t() {
    super_t::samples.orig = orig;
    super_t::samples.idx_begin = idx_begin;
    super_t::samples.idx_end = idx_end;
  }
%#if defined(SWIGRUBY)
  static void free(void *ptr){
    Signal_Partial<T> *sig = (Signal_Partial<T> *)ptr;
    if(sig->samples.orig){
      if((--(sig->samples.orig->side_loaded.ref_count)) < 0){
        delete sig->samples.orig;
      }
    }
    delete sig;
  }
%#endif
};
}


%extend Signal {
#if 0
  std::string __str__() const {
    std::stringstream s;
    s << (*self);
    return s.str();
  }
#endif
  %fragment(SWIG_Traits_frag(T));
  %typemap(out) T & "$result = swig::from(*$1);"
  
  %fragment(SWIG_Traits_frag(SignalUtil));
  
  %fragment(SWIG_Traits_frag(Signal<T>), "header",
      fragment=SWIG_Traits_frag(T)){
    namespace swig {
      template <>
      inline swig_type_info *type_info<Signal_Partial<T> >() {
        return $descriptor(Signal_Partial<T> *);
      }
      template <>
      inline swig_type_info *type_info<Signal_Partial<T> *>() {
        return $descriptor(Signal_Partial<T> *);
      }
    }
  }
  %fragment(SWIG_Traits_frag(Signal<T>));

  %typemap(out) Signal<T> & "$result = self;"

#if defined(SWIGRUBY)
  %typemap(typecheck,precedence=SWIG_TYPECHECK_VOIDPTR) const void *special_input {
    $1 = rb_block_given_p() ? 0 : 1;
  }
#endif
  %typemap(in) const void *special_input "$1 = &$input;"

  %ignore side_loaded;
#ifdef SWIGRUBY
  Signal() throw(native_exception, std::invalid_argument) {
    if(rb_block_given_p()){return new Signal<T>(SignalUtil::to_buffer<T>());}
    return new Signal<T>();
  }
#endif
  %ignore Signal(const buf_t &);
  %ignore Signal(const size_t &);
  Signal(const Signal &orig){ // work around of %copyctor Signal;
    return new Signal<T>(orig);
  }
  Signal(const void *special_input) throw(native_exception, std::invalid_argument) {
    return new Signal<T>(SignalUtil::to_buffer<T>(special_input));
  }
  SWIG_Object replace(SWIG_Object *_self, const void *special_input = NULL) throw(native_exception, std::invalid_argument) {
    typename Signal<T>::buf_t buf(SignalUtil::to_buffer<T>(special_input));
    $self->samples.swap(buf);
    return *_self;
  }
  SWIG_Object fill(
      SWIG_Object *_self,
      int idx_start, const size_t &length,
      const void *special_input = NULL) throw(native_exception, std::invalid_argument) {
    int idx_last($self->get_slice_end(idx_start, length));
    int n(idx_last - idx_start);
    if((idx_start < 0) || (n < 0) || (n != length)){
      SWIG_exception(SWIG_ValueError, "Invalid index or length.");
    }
    do{
      if(special_input){
        const SWIG_Object *obj_p(static_cast<const SWIG_Object *>(special_input));
        T v;
        if(SWIG_IsOK(swig::asval(*obj_p, &v))){
          std::fill($self->samples.begin() + idx_start, $self->samples.begin() + idx_last, v);
          break;
        }
      }
      if(SignalUtil::buffer_size_required(special_input) == length){
        typename Signal<T>::buf_t::iterator it($self->samples.begin() + idx_start);
        SignalUtil::fill_buffer<T>(it, special_input);
        break;
      }
      typename Signal<T>::buf_t buf(SignalUtil::to_buffer<T>(special_input));
      if(buf.size() > length){SWIG_exception(SWIG_ValueError, "Invalid input length.");}
      std::copy(buf.begin(), buf.begin() + length, $self->samples.begin() + idx_start);
    }while(false);
    return *_self;
  }
  SWIG_Object append(SWIG_Object *_self, const void *special_input = NULL) throw(native_exception, std::invalid_argument) {
    typename Signal<T>::buf_t buf(SignalUtil::to_buffer<T>(special_input));
    $self->samples.insert($self->samples.end(), buf.begin(), buf.end());
    return *_self;
  }
  SWIG_Object shift(SWIG_Object *_self, size_t n = 1){
    size_t current($self->samples.size());
    if(current < n){n = current;}
    $self->samples.erase($self->samples.begin(), $self->samples.begin() + n);
    return *_self;
  }
  SWIG_Object pop(SWIG_Object *_self, size_t n = 1){
    size_t current($self->samples.size());
    if(current < n){n = current;}
    $self->samples.erase($self->samples.end() - n, $self->samples.end());
    return *_self;
  }
#ifdef SWIGRUBY
  %rename("replace!") replace;
  %rename("fill!") fill;
  // %alias append "concat!"; // TODO add if need
  %rename("append!") append;
  %rename("shift!") shift;
  %rename("pop!") pop;
#endif
  %clear const void *special_input;
  Signal<T> copy() const {return Signal<T>(*$self);}

#ifdef SWIGRUBY
  %bang resize;
  %bang slide;
  %bang rotate;
#endif
  %ignore get_slice_end;
  
  %ignore is_complex;
  %ignore val_t;
  %ignore buf_t;
  %ignore samples;
  T __getitem__(const unsigned int &i) const {
    return ($self)->operator[](i);
  }
  Signal<T> __getitem__(const int &start, const unsigned int &length) const {
    // '%alias slice "[]";' does not work because of overloading.
    return ($self)->slice(start, length);
  }
  T &__setitem__(const unsigned int &i, const T &v){
    return (($self)->operator[](i) = v);
  }
#ifdef SWIGRUBY
  SWIG_Object __setitem__(SWIG_Object *_self, SWIG_Object range, SWIG_Object v){
    do{
      if(rb_obj_is_kind_of(range, rb_cRange)){
        long beg, len;
        // @see rb_ary_aset implementation
        if(rb_range_beg_len(range, &beg, &len, $self->size(), 1)){
          // The last argument(1) means to raise rb_eRangeError in case len is out of range.
          static const ID id_fill(rb_intern("fill!"));
          rb_funcall(*_self, id_fill, 3,
              SWIG_From_long(beg), SWIG_From_long(len), v);
          break;
        }
      }
      SWIG_exception(SWIG_ValueError, "Invalid range.");
    }while(false);
    return v;
  }
#endif
  
  %ignore max_abs_element;
  size_t max_abs_index() const {
    return std::distance(self->samples.begin(), self->max_abs_element());
  }
  %ignore min_abs_element;
  size_t min_abs_index() const {
    return std::distance(self->samples.begin(), self->min_abs_element());
  }
  
  SWIG_Object partial(
      SWIG_Object *_self,
      const int &start, const unsigned int &length) const {
    Signal<T> *sig(const_cast<Signal<T> *>($self));
    ++(sig->side_loaded.ref_count);
    SWIG_Object res(swig::from_ptr(new Signal_Partial<T>(
        Signal_PartialBuffer<Signal<T> >::generate_signal(
          *sig, start, length)), 1));
    return res;
  }
#if defined(SWIGRUBY)
  SWIG_Object to_shareable(SWIG_Object *_self) const {
    Signal<T> *sig(const_cast<Signal<T> *>($self));
    ++(sig->side_loaded.ref_count);
    SWIG_Object res(swig::from_ptr(new Signal_Partial<T>(sig, 0, -1), 1));
%#if defined(HAVE_RB_EXT_RACTOR_SAFE)
    RB_FL_SET(res, RUBY_FL_SHAREABLE);
%#endif
    rb_obj_freeze(res);
    return res;
  }
#endif
  
  %typemap(out) T &;
  %clear Signal<T> &;
};

%define add_common_ext(target_class)
%extend target_class {
#if defined(SWIGRUBY)
  %typemap(in,numinputs=0) const void *check_block {
    if(!rb_block_given_p()){
      return rb_enumeratorize(self, ID2SYM(rb_frame_callee()), argc, argv);
    }
  }
#else
  %typemap(in,numinputs=0) const void *check_block ""
#endif

  %catches(native_exception) each;
  SWIG_Object each(SWIG_Object *_self, const void *check_block) const {
    SignalUtil::each(*$self);
    return *_self;
  }
  
  %clear const void *check_block;
};
#if defined(SWIGRUBY)
%mixin target_class "Enumerable";
#endif
%enddef

add_common_ext(Signal);
add_common_ext(Signal_Partial);

#undef add_common_ext

%define type_resolver(type, with_complex)
struct Signal<type> {
  typedef Signal<type> self_t;
  typedef type value_t;
  typedef Signal<type> sig_t;
  typedef type real_t;
  typedef Signal<type> sig_r_t;
  typedef Complex<type> complex_t;
  typedef Signal<Complex<type> > sig_c_t;
  typedef std::size_t size_t;
};
#if with_complex
struct Signal<Complex<type> > {
  typedef Signal<Complex<type> > self_t;
  typedef Complex<type> value_t;
  typedef Signal<Complex<type> > sig_t;
  typedef type real_t;
  typedef Signal<type> sig_r_t;
  typedef Complex<type> complex_t;
  typedef Signal<Complex<type> > sig_c_t;
  typedef std::size_t size_t;
};
#endif
%enddef

%include param/signal.h

%define add_ctor(type_this, type_arg)
%extend type_this {
  type_this(const type_arg &arg){return new type_this(arg);}
};
%enddef
add_ctor(Signal<double>, Signal<int>);
add_ctor(Signal<Complex<double> >, Signal<double>);
add_ctor(Signal<Complex<double> >, Signal<int>);
#undef add_ctor

%extend Signal {
  // scalar
  %template(__mul__) operator*<T>;
  %template(__add__) operator+<T>;
  %template(__sub__) operator-<T>;
  // vector
  %template(__mul__) operator*<T, BufferT>;
  %template(__add__) operator+<T, BufferT>;
  %template(__sub__) operator-<T, BufferT>;
  
  // %template(dot_product) dot_product<T, BufferT>; // does not work?
  T dot_product(const Signal<T> &sig) const {return $self->dot_product(sig);}
  T circular_dot_product(const int &offset, const Signal<T> &sig) const {
    return $self->circular_dot_product(offset, sig);
  }
};

%define add_func(func_to, func_from, type_this, type_arg, type_res)
%extend type_this {
  type_res func_to(const type_arg &arg) const {
    return $self->func_from(arg);
  }
};
%enddef

%define add_func2(v)
// vector
add_func(__mul__, operator*, Signal_Partial<v>, Signal<v>, Signal<v>);
add_func(__add__, operator+, Signal_Partial<v>, Signal<v>, Signal<v>);
add_func(__sub__, operator-, Signal_Partial<v>, Signal<v>, Signal<v>);
add_func(dot_product, dot_product, Signal_Partial<v>, Signal<v>, v);
%extend Signal_Partial<v> {
  v circular_dot_product(const int &offset, const Signal<v> &arg) const {
    return $self->circular_dot_product(offset, arg);
  }
};
%enddef

add_func2(int);
add_func2(double);
add_func2(Complex<double>);

#undef add_func2

%define add_func2(v1, v2)
// scalar
add_func(__mul__, operator*, Signal<v1>, v2, Signal<v1>);
add_func(__add__, operator+, Signal<v1>, v2, Signal<v1>);
add_func(__sub__, operator-, Signal<v1>, v2, Signal<v1>);

// vector
add_func(__mul__, operator*, Signal<v1>, Signal<v2>, Signal<v1>);
add_func(__add__, operator+, Signal<v1>, Signal<v2>, Signal<v1>);
add_func(__sub__, operator-, Signal<v1>, Signal<v2>, Signal<v1>);
add_func(dot_product, dot_product, Signal<v1>, Signal<v2>, v1);
%extend Signal<v1> {
  v1 circular_dot_product(const int &offset, const Signal<v2> &arg) const {
    return $self->circular_dot_product(offset, arg);
  }
};

// vector(partial)
add_func(__mul__, operator*, Signal_Partial<v1>, Signal<v2>, Signal<v1>);
add_func(__add__, operator+, Signal_Partial<v1>, Signal<v2>, Signal<v1>);
add_func(__sub__, operator-, Signal_Partial<v1>, Signal<v2>, Signal<v1>);
add_func(dot_product, dot_product, Signal_Partial<v1>, Signal<v2>, v1);
%extend Signal_Partial<v1> {
  v1 circular_dot_product(const int &offset, const Signal<v2> &arg) const {
    return $self->circular_dot_product(offset, arg);
  }
};
%enddef

add_func2(double, int);
add_func2(Complex<double>, int);
add_func2(Complex<double>, double);

#undef add_func2
#undef add_func

%extend Signal<double> {
  Signal<Complex<double> > r2c() const {
    return SignalUtil::r2c(*$self);
  }
  Signal<int> r2i(const double &sf = 1) const {
    typename Signal<int>::buf_t buf($self->size());
    struct op_t {
      const double &sf;
      int operator()(const double &v) const {
%#if __cplusplus >= 201103L
        return (int)std::trunc(v * sf);
%#else
        return (int)std::floor(std::abs(v * sf)) * (v > 0 ? 1 : -1);
%#endif
      }
    } op = {sf};
    std::transform(
        $self->samples.begin(), $self->samples.end(),
        buf.begin(), op);
    return Signal<int>(buf);
  }
}
%extend Signal<Complex<double> > {
  Signal<double> c2r() const {
    return SignalUtil::c2r(*$self);
  }
}

#if defined(SWIGRUBY)
%freefunc Signal<double> "SignalUtil::free<double>";
%freefunc Signal<Complex<double> > "SignalUtil::free<Complex<double> >";
%freefunc Signal<int> "SignalUtil::free<int>";
#endif

%template(Real) Signal<double>;
%template(Complex) Signal<Complex<double> >;
type_resolver(double, 1);

%extend Signal<int> {
  %ignore cw;
  %ignore real;
  %ignore imaginary;
  %ignore conjugate;
  %ignore ft(const real_t &k) const;
  Complex<double> ft(const double &k) const {
    return FFT_Generic<double>::ft($self->samples, k);
  }
  Signal<Complex<double> > fft() const {
    return Signal<Complex<double> >(FFT_Generic<double>::fft($self->samples));
  }
  %ignore ift(const real_t &) const;
  Complex<double> ift(const double &n) const {
    return FFT_Generic<double>::ft($self->samples, n);
  }
  Signal<Complex<double> > ifft() const {
    return Signal<Complex<double> >(FFT_Generic<double>::ifft($self->samples));
  }
  Signal<Complex<double> > r2c() const {
    return SignalUtil::r2c<int, double>(*$self);
  }
};
%template(Int) Signal<int>;
type_resolver(int, 0);

#undef type_resolver

#if defined(SWIGRUBY)
%freefunc Signal_Partial<double> "Signal_Partial<double>::free";
%freefunc Signal_Partial<Complex<double> > "Signal_Partial<Complex<double> >::free";
%freefunc Signal_Partial<int> "Signal_Partial<int>::free";
#endif

%template(Real_Partial) Signal_Partial<double>;
%template(Complex_Partial) Signal_Partial<Complex<double> >;

%extend Signal_Partial<int> {
  %ignore real;
  %ignore imaginary;
  %ignore conjugate;
  %ignore ft(const typename Signal<int>::real_t &k) const;
  Complex<double> ft(const double &k) const {
    return FFT_Generic<double>::ft($self->samples.begin(), $self->samples.end(), k);
  }
  Signal<Complex<double> > fft() const {
    return Signal<Complex<double> >(FFT_Generic<double>::fft($self->samples.begin(), $self->samples.end()));
  }
  %ignore ift(const typename Signal<int>::real_t &n) const;
  Complex<double> ift(const double &n) const {
    return FFT_Generic<double>::ft($self->samples.begin(), $self->samples.end(), n);
  }
  Signal<Complex<double> > ifft() const {
    return Signal<Complex<double> >(FFT_Generic<double>::ifft($self->samples.begin(), $self->samples.end()));
  }
};
%template(Int_Partial) Signal_Partial<int>;

%clear SWIG_Object *_self;
