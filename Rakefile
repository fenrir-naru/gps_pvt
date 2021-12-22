# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rake/extensiontask"

Rake::ExtensionTask.new("gps_pvt") do |ext|
  ext.lib_dir = "lib/gps_pvt"
end

namespace :git do
  namespace :submodules do
    desc "Initialize git submodules"
    task :init do
      sh "git submodule init"
      # for sparse-checkout; @see https://stackoverflow.com/a/59521050/15992898
      `git config --file .gitmodules --name-only --get-regexp path`.lines.each{|str|
        # list submodule; @see https://stackoverflow.com/a/23490756/15992898
        next unless str =~ /submodule\.(.+)\.path/
        repo_dir = $1
        sh "git clone -n #{`git config submodule.#{repo_dir}.url`.chomp} #{repo_dir}"
      }
      {
        'ext/ninja-scan-light' => [
          "sparse-checkout init", # same as "git -C #{repo} config core.sparseCheckout true"
          # same as #{repo}/.git/info/sparse-checkout
          "sparse-checkout set" + (<<-__SPARSE_PATTERNS__).lines.collect{|str| str.chomp.gsub(/^ */, ' ')}.join,
            /tool/param/
            /tool/navigation/GPS*
            /tool/navigation/coordinate.h
            /tool/navigation/EGM.h
            /tool/navigation/MagneticField.h
            /tool/navigation/NTCM.h
            /tool/navigation/RINEX.h
            /tool/navigation/WGS84.h
            /tool/swig/SylphideMath.i
            /tool/swig/GPS.i
            /tool/swig/Coordinate.i
            /tool/swig/makefile
            /tool/swig/extconf.rb
            /tool/swig/spec/GPS_spec.rb
            /tool/swig/spec/SylphideMath_spec.rb
          __SPARSE_PATTERNS__
        ]
      }.each{|repo, commands|
        commands.each{|str| sh "git -C #{repo} #{str}"}
      }
      sh "git submodule absorbgitdirs" # Move #{repo}/.git to .git/modules/#{repo}/.git
      sh "git submodule update"
      # if already checked out, then git -C #{repo} read-tree -mu HEAD
    end
  end
end


desc "Generate SWIG wrapper codes"
task :swig do
  swig_dir = File::join(File::dirname(__FILE__), 'ext', 'ninja-scan-light', 'tool', 'swig')
  out_base_dir = File::join(File::dirname(__FILE__), 'ext', 'gps_pvt')
  Dir::chdir(swig_dir){
    Dir::glob("*.i"){|src|
      mod_name = File::basename(src, '.*')
      out_dir = File::join(out_base_dir, mod_name)
      sh "mkdir -p #{out_dir}"
      wrapper = File::join(out_dir, "#{mod_name}_wrap.cxx")
      sh [:make, :clean, wrapper,
          "BUILD_DIR=#{out_dir}",
          "SWIGFLAGS='-c++ -ruby -prefix \"GPS_PVT::\"#{" -D__MINGW__" if ENV["MSYSTEM"]}'"].join(' ')
      open(wrapper, 'r+'){|io|
        lines = io.read.lines.collect{|line|
          line.sub(/rb_require\(\"([^\"]+)\"\)/){ # from camel to underscore downcase style
            "rb_require(\"#{$1.sub('GPS_PVT', 'gps_pvt')}\")"
          }
        }
        io.rewind
        io.write(lines.join)
      }
    }
  }
end

file "ext/ninja-scan-light/tool" do |t|
  Rake::Task["git:submodules:init"].invoke
end

task :default => ["ext/ninja-scan-light/tool", :compile, :spec]