# GPS_PVT

GPS_PVT is a Ruby GPS (Global positioning system) PVT (position, velocity and time) solver. It accepts RINEX NAV and OBS files in addition to u-blox ubx format. Its significant features are easy to use with highly flexibility to customize internal solver behavior such as weight for each available satellite.

The PVT solution is obtained with a stand alone positioning (i.e. neither differential nor kinematic) with application of least square to each snapshot. Its main internal codes are derived from ones of [ninja-scan-light](https://github.com/fenrir-naru/ninja-scan-light) having capability to calculate tightly-coupled GNSS/INS integrated solution. These codes are written by C++, and wrapped by [SWIG](http://www.swig.org/).

[![Gem Version](https://badge.fury.io/rb/gps_pvt.svg)](https://badge.fury.io/rb/gps_pvt)
[![Ruby](https://github.com/fenrir-naru/gps_pvt/actions/workflows/main.yml/badge.svg)](https://github.com/fenrir-naru/gps_pvt/actions/workflows/main.yml)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'gps_pvt'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install gps_pvt

For Windows users, this gem requires Devkit because of native compilation.

## Usage

For user who just generate PVT solution, an attached executable is useful. After installation, type

    $ gps_pvt RINEX_or_UBX_file(s)

The format of RINEX_or_UBX_file is automatically determined with its extention, such as .ubx will be treated as UBX format. If you want to specify the file format, instead of RINEX_or_UBX_file(s), use the following arguments:

    --rinex_nav=filename
    --rinex_obs=filename
    --ubx=filename

From version 0.2.0, SBAS and QZSS are supported in addition to GPS. QZSS ranging is activated in default, however, SBAS is just utilized for ionospheric correction. If you want to activate SBAS ranging, "--with=(SBAS PRN number, ex. 137)" option is used with gps_pvt executable like

    $ gps_pvt --with=137 RINEX_or_UBX_file(s)

For developer, this library will be used like:

```ruby
require 'gps_pvt'

receiver = GPS_PVT::Receiver::new
receiver.parse_rinex_nav(rinex_nav_file) # This is required before parsing RINEX obs file (For ubx, skippable)

# For generate solution in CSV format
puts GPS_PVT::Receiver::header
receiver.parse_rinex_obs(rinex_obs_file)
# receiver.parse_ubx(ubx_file) # same as above for ubx file including RXM-RAW(X) and RXM-SFRB(X)

# Or precise control of outputs
receiver.parse_rinex_obs(rinex_obs_file){|pvt, meas| # per epoch
  meas.to_a # => measurement, array of [prn, key, value]; key is represented by GPS_PVT::GPS::Measurement::L1_PSEUDORANGE; instead of .to_a, .to_hash returns {prn => {key => value, ...}, ...}
  
  pvt # => PVT solution, all properties are shown by pvt.methods
  # for example
  if(pvt.position_solved?){
    pvt.receiver_time # receiver time; .to_a => [GPS week, seconds], .c_tm => [year, month, day, hour, min, sec] without leap second consideration
    [:lat, :lng, :alt].collect{|f| pvt.llh.send(f)} # latitude[rad], longitude[rad], WGS-84 altitude[m]
    pvt.receiver_error # receiver clock error in meter
    [:g, :p, :h, :v, :t].collect{|k| pvt.send("#{k}dop".to_sym)} # various DOP, dilution of precision
    if(pvt.velocity_solved?){
      [:north, east, :down].collect{|dir| pvt.velocity.send(dir)} # speed in north/east/down [m/s]
      pvt.receiver_error_rate # clock error rate in m/s
    }
    pvt.used_satellite_list # array of used, i.e., visible and weight>0, satellite
    pvt.azimuth # azimuth angle [rad] to used satellites in Hash {prn => value, ...}
    pvt.elevation # elevation angle [rad]

    pvt.G # design matrix in Earth-centered-Earth-fixed (ECEF); .to_a returns double array converted from matrix. its row corresponds to one of used_satellite_list
    pvt.G_enu # design matrix in East-North-Up (ENU)
    pvt.W # weight for each satellite
    pvt.delta_r # residual of pseudo range
    pvt.S # (delta position) = S * (residual) in last iteration in ECEF
  }
}

## Further customization
# General options
receiver.solver.gps_options.exclude(prn) # Exclude satellite; the default is to use every satellite if visible
receiver.solver.gps_options.include(prn) # Discard previous setting of exclusion
receiver.solver.gps_options.elevation_mask = Math::PI / 180 * 10 # example 10 [deg] elevation mask
# receiver.solver.sbas_options is for SBAS.

# Precise control of properties for each satellite and for each iteration
receiver.solver.hooks[:relative_property] = proc{|prn, rel_prop, meas, rcv_e, t_arv, usr_pos, usr_vel|
  weight, range_c, range_r, rate_rel_neg, *los_neg = rel_prop # relative property
  # meas is measurement represented by pseudo range of the selected satellite.
  # rcv_e, t_arv, usr_pos, usr_vel are temporary solution of 
  # receiver clock error [m], time of arrival [s], user position and velocity in ECEF, respectively.
  
  weight = 1 # same as default; identical weight for each visible satellite
  # or weight based on elevation, for example:
  # elv = GPS_PVT::Coordinate::ENU::relative_rel(GPS_PVT::Coordinate::XYZ::new(*los_neg), usr_pos).elevation
  # weight = (Math::sin(elv)/0.8)**2
  
  [weight, range_c, range_r, rate_rel_neg] + los_neg # must return relative property
}

# Range correction (since v0.3.0)
receiver.solver.correction = { # provide by using a Hash
  # ionospheric and transpheric models are changeable, and current configuration
  # can be obtained by receiver.solver.correction without assigner.
  :gps_ionospheric => proc{|t, usr_pos_xyz, sat_pos_enu|
    # t, usr_pos_xyz, sat_pos_enu are temporary solution of 
    # time of arrival [s], user position in ECEF, 
    # and satellite position in ENU respectively.
    0 # must return correction value, delaying is negative.
  },
  # combination of (gps or sbas) and (ionospheric or tropospheric) are available
}

# Dynamic customization of weight for each epoch
(class << receiver; self; end).instance_eval{ # do before parse_XXX
  alias_method(:run_orig, :run)
  define_method(:run){|meas, t_meas, &b|
    meas # observation, same as the 2nd argument of parse_XXX
    receiver.solver.hooks[:relative_property] = proc{|prn, rel_prop, meas, rcv_e, t_arv, usr_pos, usr_vel|
      # Do something based on meas, t_meas.
      rel_prop
    }
    run_orig(meas, t_meas, &b)
  }
}
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake` to build library and run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/fenrir-naru/gps_pvt. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/fenrir-naru/gps_pvt/blob/master/CODE_OF_CONDUCT.md).

## Code of Conduct

Everyone interacting in the GPS_PVT project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/fenrir-naru/gps_pvt/blob/master/CODE_OF_CONDUCT.md).
