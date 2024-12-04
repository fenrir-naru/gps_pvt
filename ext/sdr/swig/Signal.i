%module Signal

%{
#include <sstream>
#include <string>
#include <exception>

#if defined(SWIGRUBY) && defined(isfinite)
#undef isfinite
#endif

#include "param/signal.h"
%}

%include std_common.i
%include std_string.i
%include exception.i
%include std_except.i

%feature("autodoc", "1");

%import "SylphideMath.i"

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

%{
#include <iostream>
%}

%fragment(SWIG_Traits_frag(SignalUtil), "header") {
struct SignalUtil {
#if defined(SWIGRUBY)
  template <class T, int bits>
  static bool read_packed(const VALUE &src, typename Signal<T>::buf_t &dst){
    static const unsigned char mask((1 << bits) - 1);
    switch(TYPE(src)){
      case T_STRING: {
        unsigned char *buf((unsigned char *)(RSTRING_PTR(src)));
        for(int i(0), len(RSTRING_LEN(src)); i < len; ++i, ++buf){
          unsigned char c(*buf);
          for(int j(8 / bits); j > 0; --j, c >>= bits){
            dst.push_back((int)((c & mask) << 1) - (int)mask);
          }
        }
        return true;
      }
      case T_FILE: {
        rb_io_ascii8bit_binmode(src);
        while(!RTEST(rb_io_eof(src))){
          unsigned char c(NUM2CHR(rb_io_getbyte(src)));
          for(int j(8 / bits); j > 0; --j, c >>= bits){
            dst.push_back((int)((c & mask) << 1) - (int)mask);
          }
        }
        return true;
      }
      default: return false;
    }
  }
#endif
  template <class T>
  static typename Signal<T>::buf_t to_buffer(const void *src = NULL){
    typedef typename Signal<T>::size_t size_t;
    typename Signal<T>::buf_t res;
#if defined(SWIGRUBY)
    const VALUE *value(static_cast<const VALUE *>(src));
    size_t len(0), i(0);
    VALUE elm_val(Qnil);
    bool valid_input(false);
    if(value){
      if(RB_TYPE_P(*value, T_ARRAY)){
        res.reserve(len = RARRAY_LEN(*value));
        T elm;
        for(; i < len; i++){
          elm_val = RARRAY_AREF(*value, i);
          if(!SWIG_IsOK(swig::asval(elm_val, &elm))){break;}
          res.push_back(elm);
        }
        valid_input = true;
      }else if(RB_TYPE_P(*value, T_HASH)){
        static const VALUE k_src(ID2SYM(rb_intern("source"))), k_format(ID2SYM(rb_intern("format")));
        VALUE v_src(rb_hash_lookup(*value, k_src)), v_format(rb_hash_lookup(*value, k_format));
        struct {
          const VALUE name;
          bool (*func)(const VALUE &src, typename Signal<T>::buf_t &dst);
        } format_list[] = {
          {ID2SYM(rb_intern("packed_1b")), &read_packed<T, 1>},
          {ID2SYM(rb_intern("packed_2b")), &read_packed<T, 2>},
          {ID2SYM(rb_intern("packed_4b")), &read_packed<T, 4>},
          {ID2SYM(rb_intern("packed_8b")), &read_packed<T, 8>},
        };
        for(int i(0); i < sizeof(format_list) / sizeof(format_list[0]); ++i){
          if(format_list[i].name == v_format){
            valid_input = (*format_list[i].func)(v_src, res);
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
      for(; ; i++){
        elm_val = rb_protect(rb_yield, UINT2NUM(i), &state);
        if(state != 0){throw native_exception(state);}
        if(!RTEST(elm_val)){break;} // if nil returned, break loop.
        if(!SWIG_IsOK(swig::asval(elm_val, &elm))){
          len = i + 1;
          break;
        }
        res.push_back(elm);
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
    typename Signal<Complex<T> >::buf_t x1;
    x1.reserve(x.size() << 1);
#if 0 // skip reordering in (6.15) because it depends on IF configuration
    typename Signal<Complex<T> >::buf_t n_half((x.size() + 1) >> 1);
    std::copy( // (6.15)-1
        x.samples.begin() + n_half, x.samples.end(),
        std::back_inserter(x1));
    std::copy( // (6.15)-2
        x.samples.begin(), x.samples.begin() + n_half,
        std::back_inserter(x1));
#else
    std::copy(x.samples.begin(), x.samples.end(), std::back_inserter(x1));
#endif
    x1.push_back(0); // (6.16)-1
    struct op_t {
      Complex<T> operator()(const Complex<T> &v) const {return v.conjugate();}
    };
    std::transform( // (6.16)-2
        x1.rbegin() + 1, x1.rend() - 1,
        std::back_inserter(x1),
        op_t());
    return Signal<Complex<T> >(x1).ifft().real(); // (6.17)
  }
};
}

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
    %ignore Signal_Partial();
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
    %typemap(ret) Signal_Partial<T> {
#if defined(SWIGRUBY)
      rb_iv_set(vresult, "@__orig_sig__", rb_iv_get(self, "@__orig_sig__"));
#endif
    }
    Signal_Partial<T> partial(const int &start, const unsigned int &length) {
      return PartialSignalBuffer<Signal<T> >::generate_signal(*$self, start, length);
    }
    %clear Signal_Partial<T>;
  }
};

%header {
template <class T>
struct Signal_Partial
    : public Signal<T, PartialSignalBuffer<Signal<T> > > {
  typedef Signal<T, PartialSignalBuffer<Signal<T> > > super_t;
  Signal_Partial() : super_t() {}
  Signal_Partial(const super_t &sig) : super_t(sig) {}
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

  // @see SylphideMath.i
  %typemap(in, numinputs=0) SWIG_Object *self_p ""
  %typemap(argout) SWIG_Object *self_p "$result = self;"
  %typemap(out) Signal<T> & "$result = self;"

#if defined(SWIGRUBY)
  %typemap(typecheck,precedence=SWIG_TYPECHECK_VOIDPTR) const void *special_input {
    $1 = rb_block_given_p() ? 0 : 1;
  }
#endif
  %typemap(in) const void *special_input "$1 = &$input;"

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
  void replace(SWIG_Object *self_p, const void *special_input = NULL) throw(native_exception, std::invalid_argument) {
    typename Signal<T>::buf_t buf(SignalUtil::to_buffer<T>(special_input));
    $self->samples.swap(buf);
  }
  void append(SWIG_Object *self_p, const void *special_input = NULL) throw(native_exception, std::invalid_argument) {
    typename Signal<T>::buf_t buf(SignalUtil::to_buffer<T>(special_input));
    $self->samples.insert($self->samples.end(), buf.begin(), buf.end());
  }
  void shift(SWIG_Object *self_p, size_t n = 1){
    size_t current($self->samples.size());
    if(current < n){n = current;}
    $self->samples.erase($self->samples.begin(), $self->samples.begin() + n);
  }
  void pop(SWIG_Object *self_p, size_t n = 1){
    size_t current($self->samples.size());
    if(current < n){n = current;}
    $self->samples.erase($self->samples.end() - n, $self->samples.end());
  }
#ifdef SWIGRUBY
  %rename("replace!") replace;
  // %alias append "concat!"; // TODO add if need
  %rename("append!") append;
  %rename("shift!") shift;
  %rename("pop!") pop;
#endif
  %clear const void *special_input;
  Signal<T> copy() const {return Signal<T>(*$self);}

#ifdef SWIGRUBY
  %bang resize;
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
  
  %ignore max_abs_element;
  size_t max_abs_index() const {
    return std::distance(self->samples.begin(), self->max_abs_element());
  }
  %ignore min_abs_element;
  size_t min_abs_index() const {
    return std::distance(self->samples.begin(), self->min_abs_element());
  }
  
  %typemap(ret) Signal_Partial<T> {
#if defined(SWIGRUBY)
    rb_iv_set(vresult, "@__orig_sig__", self);
#endif
  }
  Signal_Partial<T> partial(const int &start, const unsigned int &length) {
    return PartialSignalBuffer<Signal<T> >::generate_signal(*$self, start, length);
  }
  %clear Signal_Partial<T>;
  
  %typemap(out) T &;
  
  %clear SWIG_Object *self_p;
  %clear Signal<T> &;
};

%define add_common_ext(target_class)
%extend target_class {
  %typemap(in,numinputs=0) SWIG_Object self_ "$1 = self;"
  %typemap(in,numinputs=0) SWIG_Object *self_p_ ""
  %typemap(argout) SWIG_Object *self_p_ "$result = self;"
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
  void each(SWIG_Object *self_p_, const void *check_block) const {
    SignalUtil::each(*$self);
  }

#if defined(SWIGRUBY)  
  SWIG_Object to_shareable(SWIG_Object self_) const {
    static const ID func(rb_intern("partial"));
    SWIG_Object res(rb_funcall(self_, func,
        2, SWIG_From(long)(0), SWIG_From(size_t)($self->size())));
    rb_obj_freeze(res);
%#if defined(HAVE_RB_EXT_RACTOR_SAFE)
    RB_FL_SET(res, RUBY_FL_SHAREABLE);
%#endif
    return res;
  }
#endif
  
  %clear const void *check_block;
  %clear SWIG_Object *self_p_;
  %clear SWIG_Object self_;
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

// vector(partial)
add_func(__mul__, operator*, Signal_Partial<v1>, Signal<v2>, Signal<v1>);
add_func(__add__, operator+, Signal_Partial<v1>, Signal<v2>, Signal<v1>);
add_func(__sub__, operator-, Signal_Partial<v1>, Signal<v2>, Signal<v1>);
add_func(dot_product, dot_product, Signal_Partial<v1>, Signal<v2>, v1);
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
}
%extend Signal<Complex<double> > {
  Signal<double> c2r() const {
    return SignalUtil::c2r(*$self);
  }
}

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

