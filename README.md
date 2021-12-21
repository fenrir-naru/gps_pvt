# GPS_PVT

GPS_PVT is a Ruby GPS (Global positioning system) PVT (position, velocity and time) solver. It accepts RINEX NAV and OBS files in addition to u-blox ubx format. Its significant features are easy to use with highly flexibility to customize internal solver behavior such as weight for each available satellite.

The PVT solution is obtained with a stand alone positioning (i.e. neither differential nor kinematic) with least square. Its main internal codes are derived from ones of [ninja-scan-light](https://github.com/fenrir-naru/ninja-scan-light) having capability to calculate tightly-coupled GNSS/INS integrated solution. These codes are written by C++, and wrapped by [SWIG](http://www.swig.org/).

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

For developer, this library will be used in the following:

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
  meas # => measurement, array of [prn, key, value]; key is represented by GPS_PVT::GPS::Measurement::L1_PSEUDORANGE
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
    pvt.G # design matrix in Earth-centered-Earth-fixed (ECEF); .to_a returns double array converted from matrix. its row corresponds to one of used_satellite_list
    pvt.G_enu # design matrix in East-North-Up (ENU)
    pvt.W # weight for each satellite
    pvt.delta_r # residual of pseudo range
    pvt.S # (delta position) = S * (residual) in last iteration in ECEF
  }
}

# Customize solution
receiver.solver.options.exclude(prn) # Exclude satellite; the default is to use every satellite if visible
receiver.solver.options.include(prn) # Discard previous setting of exclusion
receiver.solver.hooks[:relative_property] = proc{|prn, rel_prop, rcv_e, t_arv, usr_pos, usr_vel|
  # control weight per satellite per iteration
  weight, range_c, range_r, rate_rel_neg, *los_neg = rel_prop # relative property
  weight = 1 # default; same weight
  # or weight based on elevation
  # elv = GPS_PVT::Coordinate::ENU::relative_rel(GPS_PVT::Coordinate::XYZ::new(*los_neg), usr_pos).elevation
  # weight = (Math::sin(elv)/0.8)**2
  [weight, range_c, range_r, rate_rel_neg] + los_neg
}
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake` to build library and run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/fenrir-naru/gps_pvt. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/fenrir-naru/gps_pvt/blob/master/CODE_OF_CONDUCT.md).

## Code of Conduct

Everyone interacting in the GPS_PVT project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/fenrir-naru/gps_pvt/blob/master/CODE_OF_CONDUCT.md).
