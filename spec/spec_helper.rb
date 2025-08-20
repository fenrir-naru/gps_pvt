# frozen_string_literal: true

require "gps_pvt"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

module Enumerable
  def sum(init=0, &b)
    b ? each{|v| init += b.call(v)} : each{|v| init += v}
    init
  end
end if GPS_PVT::version_compare(RUBY_VERSION, "2.4.0") < 0

class Hash
  def compact; select{|k, v| v}; end
  def compact!; select!{|k, v| v}; end
end if GPS_PVT::version_compare(RUBY_VERSION, "2.4.0") < 0

class Ractor
  def take; value; end
end if GPS_PVT::version_compare(RUBY_VERSION, "3.5.0") >= 0