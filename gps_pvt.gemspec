# frozen_string_literal: true

require_relative "lib/gps_pvt/version"

Gem::Specification.new do |spec|
  spec.name = "gps_pvt"
  spec.version = GPS_PVT::VERSION
  spec.authors = ["fenrir(M.Naruoka)"]
  spec.email = ["fenrir.naru@gmail.com"]

  spec.summary = "GPS position, velocity, and time (PVT) solver"
  spec.description = "This module calculate PVT by using raw observation obtained from a GPS receiver"
  spec.homepage = "https://github.com/fenrir-naru/gps_pvt"
  spec.required_ruby_version = ">= 2.6.0"

  #spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  #spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."
    
  spec.extensions = ["ext/gps_pvt/extconf.rb"]

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  
  spec.files += proc{
    base_dir = File::absolute_path(File.dirname(__FILE__))
    require 'pathname'
    # get an array of submodule dirs by executing 'pwd' inside each submodule
    `git submodule --quiet foreach pwd`.split($/).collect{|dir|
      # issue git ls-files in submodule's directory
      `git -C #{dir} ls-files -v`.split($/).collect{|f|
        next nil unless f =~ /^H */ # consider git sparse checkout
        # get relative path
        f = Pathname::new(File::join(dir, $'))
        (f.relative? ? f : f.relative_path_from(base_dir)).to_s
      }.compact
    }.flatten
  }.call

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rake-compiler"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
