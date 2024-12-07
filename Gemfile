# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in gps_pvt.gemspec
gemspec

if /mingw-ucrt/ =~ RUBY_PLATFORM then
  gem "RubyInline", :git => 'https://github.com/fenrir-naru/rubyinline.git'
end
