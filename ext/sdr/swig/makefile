CURRENT_MAKEFILE := $(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
MAKEFILE_DIR_REL := $(dir $(CURRENT_MAKEFILE))
MAKEFILE_DIR := $(shell cd $(MAKEFILE_DIR_REL) && pwd)

SWIG = swig
SWIGFLAGS = -c++ -ruby $(shell if [ -n "$$MSYSTEM" ]; then echo -D__MINGW__; fi)
INCLUDES = \
  -I$(MAKEFILE_DIR)/.. \
  -I$(MAKEFILE_DIR)/../../ninja-scan-light/tool \
  -I$(MAKEFILE_DIR)/../../ninja-scan-light/tool/swig
BUILD_DIR = build_SWIG

RUBY = ruby
RUBY_CONF = extconf.rb

SRCS = $(shell ls *.i)
	
PACKAGES = $(SRCS:.i=.so)

all : $(BUILD_DIR) depend $(PACKAGES)

depend : INCLUDES+=-I$(shell echo $${MSYSTEM_PREFIX:-/usr})/include/

# ヘッダーファイルの依存関係
depend : $(SRCS)
	if [ -f $(BUILD_DIR)/depend.inc ]; then rm -f $(BUILD_DIR)/depend.inc; fi
	for i in $^; do\
		$(SWIG) $(SWIGFLAGS) $(INCLUDES) -MM -MP $$i  | sed -e 's/[^\.]*\.cxx/$$\(BUILD_DIR\)\/&/g' >> $(BUILD_DIR)/depend.inc;\
	done

-include $(BUILD_DIR)/depend.inc

$(PACKAGES) : $(patsubst %,$(BUILD_DIR)/%,$(PACKAGES))

$(BUILD_DIR)/%_wrap.cxx : %.i
	$(SWIG) $(SWIGFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/%.so : PACKAGE = $(shell echo $@ | sed -e 's/^$(BUILD_DIR)\/\([^\.]*\)\.so/\1/g')
$(BUILD_DIR)/%.so : $(BUILD_DIR)/%_wrap.cxx $(RUBY_CONF)
	echo "building $(PACKAGE) ..."
	if ! [ -d $(BUILD_DIR)/$(PACKAGE) ]; then mkdir $(BUILD_DIR)/$(PACKAGE); fi
	cp $(RUBY_CONF) $(BUILD_DIR)/$(PACKAGE)/
	cp $(BUILD_DIR)/$(PACKAGE)_wrap.cxx $(BUILD_DIR)/$(PACKAGE)/
	cd $(BUILD_DIR)/$(PACKAGE); \
	echo 'create_makefile("$(PACKAGE)")' >> $(RUBY_CONF); \
	$(RUBY) $(RUBY_CONF); \
	make V=1; \
	cp *.so ../

$(BUILD_DIR) :
	mkdir -p $@

clean :
	rm -rf $(BUILD_DIR)/*

run : all

.PHONY : clean all depend
