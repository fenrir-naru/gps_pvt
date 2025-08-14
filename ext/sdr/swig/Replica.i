%module Replica

%{
#include <cmath>

#if defined(SWIGRUBY) && defined(isfinite)
#undef isfinite
#endif

#include "navigation/GPS.h"
%}

%include std_common.i
%include std_string.i

%feature("autodoc", "1");

%import "SylphideMath.i"
%fragment("SylphideMath.i");

%import "Signal.i"
%fragment("Signal.i");

%init %{
#ifdef HAVE_RB_EXT_RACTOR_SAFE
  rb_ext_ractor_safe(true);
#endif
%}

%inline {
typedef double tick_t;
}

%fragment(SWIG_Traits_frag(Complex<double>));

struct Carrier {
  Carrier(const tick_t &init_freq);
  Complex<double> current() const;
  Signal<Complex<double> > generate(const tick_t &t, const tick_t &dt, const tick_t &freq);
  Signal<Complex<double> > generate(const tick_t &t, const tick_t &dt);
  
  tick_t phase_cycle, frequency;
  void advance(const tick_t &shift_cycle);
  void advance_time(const tick_t &shift_time);
};

%{
struct Carrier : public CosineWave<Complex<double> > {
  Carrier(const tick_t &init_freq) : CosineWave<Complex<double> >(init_freq) {}
};
%}

struct GPS_CA_Code {
  GPS_CA_Code(const int &sid, const tick_t &offset_cycle = 0);
  int current() const;
  Signal<int> generate(const tick_t &t, const tick_t &dt);
  
  tick_t phase_cycle, frequency;
  void advance(const tick_t &shift_cycle);
  void advance_time(const tick_t &shift_time);
};

%{
struct GPS_CA_Code : public TimeBasedSignalGenerator<GPS_CA_Code, int, tick_t> {
  typedef TimeBasedSignalGenerator<GPS_CA_Code, int, tick_t> super_t;
  typedef typename GPS_Signal<tick_t>::CA_Code code_t;
  code_t code;
  int phase_cycle_int;
  void advance(const tick_t &shift_cycle){
    int phase_next(std::floor(super_t::phase_cycle += shift_cycle));
    for(; phase_cycle_int < phase_next; ++phase_cycle_int){
      code.next();
    }
    for(; phase_cycle_int > phase_next; --phase_cycle_int){
      code.previous();
    }
  }
  GPS_CA_Code(const int &sid, const tick_t &offset_cycle = 0)
      : super_t(code_t::FREQUENCY), code(sid), phase_cycle_int(0) {
    advance(offset_cycle);
  }
  int current() const {
    return code.get_multi();
  }
};
%}
