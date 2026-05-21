# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in gps_pvt.gemspec
gemspec

if /(?:mingw32|mingw-ucrt)$/ =~ RUBY_PLATFORM then
  gem "RubyInline", :git => 'https://github.com/fenrir-naru/rubyinline.git'
end

group :test do
  gem "ruby-fftw3"
  gem "numo-fftw", :git => 'https://github.com/fenrir-naru/numo-fftw.git'
end
