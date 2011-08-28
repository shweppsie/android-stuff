
# -*- sh -*-

PREFIX=/usr
EXEC_PREFIX=$(PREFIX)
SBINDIR=$(EXEC_PREFIX)/sbin
MANDIR=$(PREFIX)/share/man
INCLUDEDIR=$(PREFIX)/include

CROSS=arm-linux-gnueabi-
CC := $(CROSS)gcc
CFLAGS ?= -O2 -g -static
CFLAGS += -Wall
CPPFLAGS += -I. -I$(INCLUDEDIR) $(ZLIBCPPFLAGS) $(LZOCPPFLAGS) 
LDFLAGS += -static

ifeq ($(origin CROSS),undefined)
  BUILDDIR := .
else
# Remove the trailing slash to make the directory name
  BUILDDIR := $(CROSS:-=)
endif

ifeq ($(WITHOUT_XATTR), 1)
  CPPFLAGS += -DWITHOUT_XATTR
endif

RAWTARGETS = flash_image dump_image

TARGETS = $(foreach target,$(RAWTARGETS),$(BUILDDIR)/$(target))

SYMLINKS =

%: %.o
	$(CC) $(CFLAGS) $(LDFLAGS) -g -o $@ $^

$(BUILDDIR)/%.o: %.c
	mkdir -p $(BUILDDIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $< -g -Wp,-MD,$(BUILDDIR)/.$(<F).dep

.SUFFIXES:

all: $(TARGETS)

IGNORE=${wildcard $(BUILDDIR)/.*.c.dep}
-include ${IGNORE}

clean:
	rm -f $(BUILDDIR)/*.o $(TARGETS) $(BUILDDIR)/.*.c.dep $(SYMLINKS)
	if [ "$(BUILDDIR)x" != ".x" ]; then rm -rf $(BUILDDIR); fi

$(BUILDDIR)/flash_image: $(BUILDDIR)/mtdutils.o \
			$(BUILDDIR)/mounts.o  \
			$(BUILDDIR)/strlcat.o \
			$(BUILDDIR)/flash_image.o 
	$(CC) $(LDFLAGS) -o $@ $^ 

$(BUILDDIR)/dump_image: $(BUILDDIR)/mtdutils.o \
			$(BUILDDIR)/mounts.o  \
			$(BUILDDIR)/strlcat.o \
			$(BUILDDIR)/dump_image.o 
	$(CC) $(LDFLAGS) -o $@ $^ 

