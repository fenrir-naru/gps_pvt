src_dir = File::absolute_path(File::join(
    File::dirname(__FILE__), '..', 'ninja-scan-light', 'tool'))

Dir::glob('*/').each{|dir|
  dir.gsub!(/\/$/, '')
  Dir::chdir(dir){
    Process.waitpid(fork{
      require "mkmf"
      cflags = " -Wall -I#{src_dir}"
      $CFLAGS += cflags
      $CPPFLAGS += cflags if RUBY_VERSION >= "2.0.0"
      $LOCAL_LIBS += " -lstdc++ "
      create_makefile(dir)
    })
  }
}

# manual generation of top-level Makefile
# @see https://yorickpeterse.com/articles/hacking-extconf-rb/
open("Makefile", 'w'){|io|
  # @see https://stackoverflow.com/a/17845120/15992898
  io.write(<<-__TOPLEVEL_MAKEFILE__)
TOPTARGETS := all clean

SUBDIRS := $(wildcard */.)

$(TOPTARGETS): $(SUBDIRS)
$(SUBDIRS):
#{"\t"}$(MAKE) -C $@ $(MAKECMDGOALS)

.PHONY: $(TOPTARGETS) $(SUBDIRS)
  __TOPLEVEL_MAKEFILE__
} unless File.exist?("Makefile")
