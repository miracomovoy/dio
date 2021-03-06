SRCDIR=src
SRCS=$(SRCDIR)\io\core.d \
	$(SRCDIR)\io\file.d \
	$(SRCDIR)\io\socket.d \
	$(SRCDIR)\io\port.d \
	$(SRCDIR)\sys\windows.d \
	$(SRCDIR)\util\typecons.d \
	$(SRCDIR)\util\meta.d \
	$(SRCDIR)\util\metastrings_expand.d

DFLAGS=-property -w -I$(SRCDIR)

DDOCDIR=html\d
DOCS=\
	$(DDOCDIR)\io_core.html \
	$(DDOCDIR)\io_file.html \
	$(DDOCDIR)\io_socket.html \
	$(DDOCDIR)\io_port.html
DDOC=io.ddoc
DDOCFLAGS=-D -Dd$(DDOCDIR) -c -o- $(DFLAGS)

IOLIB=lib\io.lib
DEBLIB=lib\io_debug.lib


# lib

lib: $(IOLIB)
$(IOLIB): $(SRCS)
	mkdir lib
	dmd -lib -of$(IOLIB) $(SRCS)
	#dmd -lib -of$@ $(DFLAGS) -O -release -noboundscheck $(SRCS)

#deblib: $(DEBLIB)
#$(DEBLIB): $(SRCS)
#	mkdir lib
#	dmd -lib -of$@ $(DFLAGS) -g $(SRCS)

clean:
	rmdir /S /Q lib  2> NUL
	del /Q test\*.obj test\*.exe  2> NUL
	del /Q html\d\*.html  2> NUL


# test

runtest: lib test\unittest.exe test\pipeinput.exe
	test\unittest.exe
	test\pipeinput.bat

test\unittest.exe: emptymain.d $(SRCS)
	dmd $(DFLAGS) -of$@ -unittest emptymain.d $(SRCS)
test\pipeinput.exe: test\pipeinput.d test\pipeinput.dat test\pipeinput.bat lib
	dmd $(DFLAGS) -of$@ test\pipeinput.d $(IOLIB)


# benchmark

runbench: lib test\default_bench.exe
	test\default_bench.exe
runbench_opt: lib test\release_bench.exe
	test\release_bench.exe

test\default_bench.exe: test\bench.d
	dmd $(DFLAGS) -of$@ test\bench.d $(IOLIB)
test\release_bench.exe: test\bench.d
	dmd $(DFLAGS) -O -release -noboundscheck -of$@ test\bench.d $(IOLIB)


# ddoc

html: makefile $(DOCS) $(SRCS)

$(DDOCDIR)\io_core.html: $(DDOC) io\core.d
	dmd $(DDOCFLAGS) -Dfio_core.html $(DDOC) io\core.d

$(DDOCDIR)\io_file.html: $(DDOC) io\file.d
	dmd $(DDOCFLAGS) -Dfio_file.html $(DDOC) io\file.d

$(DDOCDIR)\io_socket.html: $(DDOC) io\socket.d
	dmd $(DDOCFLAGS) -Dfio_socket.html $(DDOC) io\socket.d

$(DDOCDIR)\io_port.html: $(DDOC) io\port.d
	dmd $(DDOCFLAGS) -Dfio_port.html $(DDOC) io\port.d
