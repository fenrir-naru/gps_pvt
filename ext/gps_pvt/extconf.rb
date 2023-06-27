require "mkmf"
proc{|ninja_tool_dir|
  dir_config('ninja_tool', ninja_tool_dir, ninja_tool_dir)
}.call(File::absolute_path(File::join(
    File::dirname(__FILE__), '..', 'ninja-scan-light', 'tool')))
cflags = " -Wall"
$CFLAGS += cflags
$CPPFLAGS += cflags
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

Dir::glob(File::join(File::dirname(__FILE__), "*/")).each{|dir|
  mod_name = File::basename(dir)
  
  dst = File::join(Dir.getwd, mod_name)
  FileUtils::mkdir_p(dst) if dir != dst
  
  $stderr.puts "For #{mod_name} ..."

  # @see https://stackoverflow.com/a/35842162/15992898
  $srcs = Dir::glob(File::join(dir, '*.cxx')).collect{|path|
    File::join(mod_name, File::basename(path))
  }
  $objs = $srcs.collect{|path|
    path.sub(/\.[^\.]+$/, '.o')
  }

  IO_TARGETS.mod{
    # rename Makefile to Makefile.#{mod_name}
    define_method(:open){|*args, &b|
      args[0] += ".#{mod_name}" if (args[0] && (args[0] == "Makefile"))
      open_orig(*args, &b)
    }
  }
  create_makefile("gps_pvt/#{mod_name}")
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
