src_dir = File::absolute_path(File::join(
    File::dirname(__FILE__), '..', 'ninja-scan-light', 'tool'))
    
require 'fileutils'

Dir::glob(File::join(File::dirname(__FILE__), "*/")).each{|dir|
  mod_name = File::basename(dir)
  src, dst = [
      dir,
      File::join(Dir.getwd, mod_name)].collect{|path|
    File::absolute_path(path)
  }
  if src != dst then
    FileUtils::mkdir_p(dst)
    FileUtils::cp_r(src, File::join(dst, '..')) # really need?
  end
  Dir::chdir(dst){
    Process.waitpid(fork{
      require "mkmf"
      cflags = " -Wall -I#{src_dir}"
      $CFLAGS += cflags
      $CPPFLAGS += cflags if RUBY_VERSION >= "2.0.0"
      $LOCAL_LIBS += " -lstdc++ "
      dir_config("gps_pvt")
      
      # @see https://stackoverflow.com/a/35842162/15992898
      $srcs = Dir::glob(File::join(dst, '*.cxx'))
      $VPATH << "$(srcdir)" # really need?

      create_makefile(mod_name)
    })
  }
}

# manual generation of top-level Makefile
# @see https://yorickpeterse.com/articles/hacking-extconf-rb/
open("Makefile", 'w'){|io|
  # @see https://stackoverflow.com/a/17845120/15992898
  io.write(<<-__TOPLEVEL_MAKEFILE__)
TOPTARGETS := all clean install

SUBDIRS := $(wildcard */.)

$(TOPTARGETS): $(SUBDIRS)
$(SUBDIRS):
#{"\t"}$(MAKE) -C $@ $(MAKECMDGOALS)

.PHONY: $(TOPTARGETS) $(SUBDIRS)
  __TOPLEVEL_MAKEFILE__
} unless File.exist?("Makefile")

FileUtils::touch("gps_pvt.so") # dummy