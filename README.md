# GPS_PVT

GPS_PVT is a Ruby GPS (Global positioning system) PVT (position, velocity and time) solver. It accepts RINEX NAV and OBS files in addition to u-blox ubx format. Its significant features are easy to use with highly flexibility to customize internal solver behavior such as weight for each available satellite.

The PVT solution is obtained with a stand alone positioning (i.e. neither differential nor kinematic) with application of least square to each snapshot. Its main internal codes are derived from ones of [ninja-scan-light](https://github.com/fenrir-naru/ninja-scan-light) having capability to calculate tightly-coupled GNSS/INS integrated solution. These codes are written in C++, and wrapped by [SWIG](http://www.swig.org/).

[![Gem Version](https://badge.fury.io/rb/gps_pvt.svg)](https://badge.fury.io/rb/gps_pvt)
[![Ruby](https://github.com/fenrir-naru/gps_pvt/actions/workflows/main.yml/badge.svg)](https://github.com/fenrir-naru/gps_pvt/actions/workflows/main.yml)

## Installation

Install it yourself as:

    $ gem install gps_pvt

Or add this line to your Ruby application's Gemfile:

```ruby
gem 'gps_pvt'
```

And then execute:

    $ bundle install

For Windows users, this gem requires Devkit because of compilation of native shared library.

## Usage

### For user who just wants to generate PVT solution
An attached executable is useful. After installation, type

    $ gps_pvt file_or_URI(s)

The format of file is automatically determined with its extension, such as .ubx will be treated as UBX format. A compressed file of .gz or .Z can be specified directly (decompression is internally performed). URI such as http(s)://... and ftp://, and serial port (COMn for Windows and /dev/tty* for *NIX, version >= 0.8.0) are also acceptable. Moreover, Ntrip URI of ntrip://(username):(password)@(caster_host):(port)/(mount_point), for exmaple, ```ntrip://test%40example.com:none@rtk2go.com:2101/NAIST-UBX``` (%40 is recognized as '@') is supported (version >= 0.8.4), and its content format can be automatically determined (version >= 0.9.0). A-GPS to get ephemeris quickly is supported via special URI like ```supl://supl.google.com/``` (version >= 0.10.0). If you want to specify the file format, instead of file_or_URI(s), use the following arguments:

| specification | recoginized as |
----|----
| <a name=opt_rinex_nav>--rinex_nav=file_or_URI</a> | [RINEX](https://www.igs.org/wg/rinex/#documents-formats) navigation file |
| <a name=opt_rinex_obs>--rinex_obs=file_or_URI</a> | [RINEX](https://www.igs.org/wg/rinex/#documents-formats) observation file |
| <a name=opt_ubx>--ubx=file_or_URI</a> | [U-blox](https://www.u-blox.com/) dedicated format |
| --sp3=file_or_URI | [Standard Product 3 Orbit Format](https://files.igs.org/pub/data/format/sp3c.txt) (supported gps_pvt version >= 0.6.0) |
| --antex=file_or_URI | [Antenna Exchange Format](https://igs.org/wg/antenna#files) (supported gps_pvt version >= 0.6.0) |
| --rinex_clk=file_or_URI | [RINEX clock](https://files.igs.org/pub/data/format/rinex_clock304.txt) file (supported gps_pvt version >= 0.7.0) |
| <a name=opt_rtcm3>--rtcm3=file_or_URI</a> | [RTCM 10403.x](https://rtcm.myshopify.com/collections/differential-global-navigation-satellite-dgnss-standards). (supported gps_pvt version >= 0.9.0) The latest version uses message type Observation(GPS: 1001..1004; GLONASS: 1009..1012), Epehemris(GPS: 1019; GLOANSS: 1020; SBAS: 1043; QZSS: 1044), MSM(GPS: 1071..1077; GLONASS: 1081..1087; SBAS: 1101..1107; QZSS: 1111..1117) |
| <a name=opt_supl>--supl=URI</a> | [SUPL, secure user plane location](https://www.openmobilealliance.org/release/SUPL/). (supported gps_pvt version >= 0.10.0) Both [LPP](https://portal.3gpp.org/desktopmodules/Specifications/SpecificationDetails.aspx?specificationId=3710)(default) and [RRLP](https://portal.3gpp.org/desktopmodules/Specifications/SpecificationDetails.aspx?specificationId=2688) are internally used, which can be manually selected by adding ```?protocol=lpp_or_rrlp``` URI query string. |

Since version 0.2.0, SBAS and QZSS are supported in addition to GPS. Since version 0.4.0, GLONASS is also available. QZSS ranging is activated in default, however, SBAS is just utilized for ionospheric correction. GLONASS is also turned off by default. If you want to activate SBAS or GLONASS ranging, "--with=(system or PRN)" options are used with gps_pvt executable like

    $ gps_pvt --with=137 --with=GLONASS file_or_URI(s)

Additionally, the following command options *--key=value* are available.

| key | value | comment | since |
----|----|----|----
| base_station | 3 \* (numeric+coordinate) | base position used for relative ENU position calculation. XYZ, NEU formats are acceptable. *ex1) --base_station=0X,0Y,0Z*, *ex2) --base_station=12.34N,56.789E,0U* | v0.1.7 |
| elevation_mask_deg | numeric | satellite elevation mask specified in degrees. *ex) --elevation_mask_deg=10* | v0.3.0 |
| start_time | time string | start time to perform solution. GPS, UTC and other formats are supported. *ex1) --start_time=1234:5678* represents 5678 seconds in 1234 GPS week, *ex2) --start_time="2000-01-01 00:00:00 UTC"* is in UTC format. | v0.3.3 |
| end_time | time string | end time to perform solution. Its format is the same as start_time. | v0.3.3 |
| <a name=opt_online_ephemeris>online_ephemeris</a> | URL string | based on observation, ephemeris which is previously broadcasted from satellite and currently published online will automatically be loaded. If value is not given, the default source "ftp://gssc.esa.int/gnss/data/daily/%Y/brdc/BRDC00IGS_R_%Y%j0000_01D_MN.rnx.gz" is used. The value string is converted with [strftime](https://docs.ruby-lang.org/en/master/strftime_formatting_rdoc.html) before actual use. | v0.8.1 |

### For advanced user

This library will be used like:

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
  weight_range, range_c, range_r, weight_rate, rate_rel_neg, *los_neg = rel_prop # relative property
  # meas is measurement represented by pseudo range of the selected satellite.
  # rcv_e, t_arv, usr_pos, usr_vel are temporary solution of 
  # receiver clock error [m], time of arrival [s], user position and velocity in ECEF, respectively.
  # Note: weight_rate is added since v0.10.1
  
  weight_range = 1 # quick example: identical weight for each visible satellite
  # or weight based on elevation, for example:
  # elv = GPS_PVT::Coordinate::ENU::relative_rel(GPS_PVT::Coordinate::XYZ::new(*los_neg), usr_pos).elevation
  # weight_range = (Math::sin(elv)/0.8)**2
  
  [weight_range, range_c, range_r, weight_rate, rate_rel_neg] + los_neg # must return relative property
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
  run_orig = instance_method(:run)
  define_method(:run){|meas, t_meas, &b|
    meas # observation, same as the 2nd argument of parse_XXX
    receiver.solver.hooks[:relative_property] = proc{|prn, rel_prop, meas, rcv_e, t_arv, usr_pos, usr_vel|
      # Do something based on meas, t_meas.
      rel_prop
    }
    run_orig.bind(self).call(meas, t_meas, &b)
  }
}
```

## Additional utilities

### [gps2ubx](exe/gps2ubx) <sub>(formerly [to_ubx](../../tree/v0.8.4/exe/to_ubx))</sub>

Utility to convert observation into u-blox ubx format and dump standard input. After installation of gps_pvt, to type

    $ gps2ubx file_or_URI(s) (options) > out.ubx

saves resultant into out.ubx by using redirection. The shared options with gps_pvt executable are [rinex_obs](#opt_rinex_obs), [rinex_nav](#opt_rinex_nav), [ubx](#opt_ubx), [rtcm3](#opt_rtcm3), [supl](#opt_supl) and [online_ephemeris](#opt_online_ephemeris). In addition, the following options are available.

| key | value | comment | since |
----|----|----|----
| ubx_rawx |  | Change output packet types to UBX-RAWX from its default UBX-RAW. | v0.8.1 |
| broadcast_data |  | In addition to observation, ephemeris is inserted by using UBX-SFRB packets. If ubx_rawx option is specified, UBX-SFRBX is used instead of UBX-SFRB. | v0.8.1 |

### [gps_get](exe/gps_get)

Utility to get and dump GPS files. After installation of gps_pvt, to type

    $ gps_get file_or_URI(s) (options) > output_file

saves data into output_file by using redirection. http(s), ftp, ntrip, and supl can be used as scheme of URI. Serial port is also supported. Note that compressed data is automatically decompressed before output. The following options are available.

| key | value | comment | since |
----|----|----|----
| out | file | Change output target from the standard output. In addition to file, serial port is supported. | v0.8.5 |

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake` to build library and run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/fenrir-naru/gps_pvt. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/fenrir-naru/gps_pvt/blob/master/CODE_OF_CONDUCT.md).

## Code of Conduct

Everyone interacting in the GPS_PVT project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/fenrir-naru/gps_pvt/blob/master/CODE_OF_CONDUCT.md).
