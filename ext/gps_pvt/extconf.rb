extconf_abs_path = File::expand_path(__FILE__)
ninja_tool_dir = File::join(
    File::dirname(extconf_abs_path), '..', 'ninja-scan-light', 'tool')

if idx = ARGV.find_index{|arg| arg =~ /^--src_dir=(.+)$/} then
  ARGV.delete_at(idx)
  src_dir = $1
  
  require "mkmf"
  cflags = " -Wall -I#{ninja_tool_dir}"
  $CFLAGS += cflags
  $CPPFLAGS += cflags if RUBY_VERSION >= "2.0.0"
  $LOCAL_LIBS += " -lstdc++ "
  
  # @see https://stackoverflow.com/a/35842162/15992898
  $srcs = Dir::glob(File::join(src_dir, '*.cxx'))

  create_makefile(File::basename(src_dir), src_dir)
  exit
end

require 'fileutils'
require 'rbconfig'

Dir::glob(File::join(File::dirname(__FILE__), "*/")).each{|dir|
  mod_name = File::basename(dir)
  src, dst = [
      dir,
      File::join(Dir.getwd, mod_name)].collect{|path|
    File::absolute_path(path)
  }
  if src != dst then
    FileUtils::mkdir_p(dst)
    #FileUtils::cp_r(src, File::join(dst, '..')) # no need, 2nd arg of create_makefile resolves it
  end
  Dir::chdir(dst){
    cmd = [RbConfig.ruby, ARGV, extconf_abs_path, "--src_dir=#{src}"].flatten.collect{|str|
      str =~ /\s+/ ? "'#{str}'" : str
    }.join(' ')
    $stderr.puts "#{cmd} ..."
    system(cmd)
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