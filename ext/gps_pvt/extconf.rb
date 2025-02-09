require "mkmf"

extconf_dir = File::dirname(__FILE__)

{
  'ninja_tool' => [extconf_dir, '..', 'ninja-scan-light', 'tool'],
  'sdr' => [extconf_dir, '..', 'sdr'],
}.each{|target, path|
  path = File::join(path) if path.kind_of?(Array)
  path = File::absolute_path(path)
  dir_config(target, path, path)
}
cflags = " -Wall -I../../.. -O3" # -march=native
RE_optflags = /(?<=^|\s)-O(?:[0-3sgz]|fast)?/
if RE_optflags =~ cflags then
  $CFLAGS.gsub!(RE_optflags, '')
  $CXXFLAGS.gsub!(RE_optflags, '')
end
$CFLAGS << cflags
$CXXFLAGS << cflags
$LOCAL_LIBS += " -lstdc++ "

IO_TARGETS = [
  [Kernel, :instance_eval],
  [(class << File; self; end), :class_eval], # https://github.com/ruby/ruby/commit/19beb028
]
def IO_TARGETS.mod(&b)
  self.each{|class_, func| class_.send(func, &b)}
end

IO_TARGETS.mod{
  alias_method(:open_orig, :open)
}

require 'pathname'

Pathname::glob(File::join(extconf_dir, "**/")){|dir|
  mod_path = dir.relative_path_from(Pathname(extconf_dir))
  mod_name = mod_path.basename

  # @see https://stackoverflow.com/a/35842162/15992898
  $srcs = Pathname::glob(dir.join('*.cxx')).collect{|cxx_path|
    mod_path.join(cxx_path.basename).to_s
  }
  next if $srcs.empty?
  $objs = $srcs.collect{|path|
    path.sub(/\.[^\.]+$/, '.o')
  }
  
  $stderr.puts "For #{mod_path} ..."
  
  cfg_recovery = case mod_path.to_s
  when /^sdr\//
    Hash[*([:CFLAGS, :CXXFLAGS].collect{|k|
      orig = eval("$#{k}").clone
      eval("$#{k}").gsub!(/(?<=^|\s)-O(?:[0-3sgz]|fast)?/, '')
      eval("$#{k}") << " -O3 -march=native"
      [k, orig]
    }.flatten(1))]
  end || {}
  
  dst = Pathname::getwd.join(mod_path)
  FileUtils::mkdir_p(dst) if dir != dst

  IO_TARGETS.mod{
    # rename Makefile to Makefile.#{mod_name}
    define_method(:open){|*args, &b|
      args[0] += ".#{mod_path.to_s.gsub('/', '.')}" if (args[0] && (args[0] == "Makefile"))
      open_orig(*args, &b)
    }
  }
  create_makefile(mod_path.to_s){|conf|
    conf.collect!{|lines|
      lines.sub(/^target_prefix = /){"target_prefix ?= /gps_pvt\noverride target_prefix := $(target_prefix)"}
    }
  }

  cfg_recovery.each{|k, v| eval("$#{k}").replace(v)}
}

IO_TARGETS.mod{
  alias_method(:open, :open_orig)
}

# manual generation of top-level Makefile
# @see https://yorickpeterse.com/articles/hacking-extconf-rb/
open("Makefile", 'w'){|io|
  # @see https://stackoverflow.com/a/17845120/15992898
  io.write(<<-__TOPLEVEL_MAKEFILE__)
TOPTARGETS := all clean distclean realclean install site-install

SUBMFS := $(wildcard Makefile.*)

$(TOPTARGETS): $(SUBMFS)
$(SUBMFS):
#{"\t"}$(MAKE) -f $@ $(MAKECMDGOALS)

.PHONY: $(TOPTARGETS) $(SUBMFS)
  __TOPLEVEL_MAKEFILE__
}

require 'fileutils'
FileUtils::touch("gps_pvt.so") # dummy
