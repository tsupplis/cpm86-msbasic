# MBASIC 5.28 style BASIC-86 for MS-DOS and CP/M-86, derived from GW-BASIC 1983
#
# Toolchain (all run under emu2 through the pcdev_* wrappers):
#   pcdev_masm   MASM 5.10
#   pcdev_link   LINK 3.65a   (LINK 5.10b, pcdev_link5, currently rejects the
#                              combined object set with L1101)
#
# emu2 needs a controlling tty.  Every tool is therefore run through a
# pseudo terminal (PTY below), which also works when make itself has no
# terminal (scripts, IDE tasks).  Override with PTY= to disable.
#
# Sources are kept LF in git.  Each target is built in its own flat 8.3
# directory (build/dos, build/cpm) holding CRLF copies, because the DOS tools
# know nothing about directories.

TARGET  ?= dos
BLD      = build/$(TARGET)

MASM    ?= pcdev_masm
LINK    ?= pcdev_link
EXE2BIN ?= pcdev_exe2bin
EXE2CMD ?= exe2cmd
UNIX2DOS?= unix2dos
AFLAGS  ?=

UNAME   := $(shell uname -s)
ifeq ($(UNAME),Darwin)
PTY     ?= script -q /dev/null
endif
PTY     ?=

# Modules linked into the interpreter.  gwmain must come first (its entry
# label has to be first in the code segment); itsa86 holds CSEND, so all code
# after it is discarded when the data segment is moved; biboot comes last: it
# is the entry point and its LSTVAR marks the end of the data segment.
MODS    = gwmain gwdata gweval gwlist gwsts gwram gwinit \
          bimisc biprtu biptrg bistrs \
          dskcom fiveo call86 next86 math1 \
          gio86 giodsk giotbl giolpt giotty oemio \
          ibmres itsa86 biboot

INCS    = oem bintrp ibmres gio86u msdosu cfg

OBJS    = $(addprefix $(BLD)/,$(addsuffix .obj,$(MODS)))
STAGED  = $(addprefix $(BLD)/,$(addsuffix .asm,$(MODS)) $(addsuffix .inc,$(INCS)))

.PHONY: all dos cpm objs exe prog run check dump refcheck compare accept test parity dist clean distclean FORCE
.SUFFIXES:
.SECONDARY:

all: dos cpm

dos:
	$(MAKE) --no-print-directory TARGET=dos exe

cpm:
	$(MAKE) --no-print-directory TARGET=cpm prog

objs: $(OBJS)

exe: $(BLD)/mbasic86.exe

# The program for the target: MBASIC86.EXE on MS-DOS, MBASIC86.CMD on CP/M-86
ifeq ($(TARGET),cpm)
PROG     = mbasic86.cmd
REFPROG  = ref/mbasic86.cmd
else
PROG     = mbasic86.exe
REFPROG  = ref/mbasic86.com
endif
REFDIR   = build/ref$(TARGET)
prog: $(BLD)/$(PROG)

$(BLD)/mbasic86.cmd: $(BLD)/mbasic86.exe tools/mkcmd.py
	python3 tools/mkcmd.py $(BLD)/mbasic86.exe $(BLD)/mbasic86.map $@

# One response line per module keeps every line below LINK's 128 character limit.
$(BLD)/mbasic86.lnk: Makefile | $(BLD)
	printf '%s\n' $(addsuffix +,$(MODS)) | sed '$$s/+$$//' > $@
	echo 'mbasic86.exe' >> $@
	echo 'mbasic86.map /M' >> $@
	echo ';' >> $@

$(BLD)/mbasic86.exe: $(OBJS) $(BLD)/mbasic86.lnk
	if ! ( cd $(BLD) && $(PTY) $(LINK) @mbasic86.lnk ) >$(BLD)/link.log 2>&1; then \
	    tr -d '\r' <$(BLD)/link.log | grep -vE '^$$|Object Modules|Run File|List File|Libraries|Copyright|Linker'; exit 1; \
	fi

$(BLD):
	mkdir -p $@

# Target selection, seen by every module through OEM.INC.  The file is only
# rewritten when its content changes, so modules rebuild only when needed.
# make DEBUG=1 enables the DEBUG code (error tracing in OEMIO).
DEBUG   ?= 0
$(BLD)/cfg.inc: FORCE | $(BLD)
	if [ "$(TARGET)" = cpm ]; then c=1; s=0; else c=0; s=1; fi; \
	 printf 'CPM86=%s\r\nSCP=%s\r\nDEBUG=%s\r\n' $$c $$s $(DEBUG) > $@.new; \
	 if cmp -s $@.new $@; then rm -f $@.new; else mv $@.new $@; fi

FORCE:

# CRLF copies for the DOS assembler
$(BLD)/%.asm: %.asm | $(BLD)
	$(UNIX2DOS) -q -n $< $@

$(BLD)/%.inc: %.inc | $(BLD)
	$(UNIX2DOS) -q -n $< $@

# MASM returns non-zero on any error; show the diagnostics when it does.
$(BLD)/%.obj: $(BLD)/%.asm $(addprefix $(BLD)/,$(addsuffix .inc,$(INCS)))
	if ! ( cd $(BLD) && $(PTY) $(MASM) $(AFLAGS) '$*,$*,$*;' ) >$(BLD)/$*.log 2>&1; then \
	    tr -d '\r' <$(BLD)/$*.log | grep -iE 'error' | grep -v emu2; \
	    rm -f $@; exit 1; \
	fi

# Type tests/smoke.txt (or TESTS=file) into the interpreter and show the
# session.  EMU2_RAMDUMP, when set, receives the guest memory image at exit.
TESTS   ?= tests/smoke.txt
check: prog
	python3 tools/runbas.py $(BLD) $(PROG) $(TESTS)

# The same session on the reference MBASIC 5.28 (ref/mbasic86.com)
refcheck:
	mkdir -p $(REFDIR) && cp $(REFPROG) $(REFDIR)/
	python3 tools/runbas.py $(REFDIR) $(notdir $(REFPROG)) $(TESTS)

# Diff our session against the reference (MBASIC 5.28 for dos, 5.22 for cpm),
# ignoring the sign-on banner, free memory and the clock.  Differences that
# were reviewed (5.50 doing more than the reference) are recorded in
# tests/accept/<target>/<test>.diff and accepted.
compare: prog
	mkdir -p $(REFDIR) && cp $(REFPROG) $(REFDIR)/
	python3 tools/runbas.py $(REFDIR) $(notdir $(REFPROG)) $(TESTS) | tools/normout.sh > build/ref.out
	python3 tools/runbas.py $(BLD) $(PROG) $(TESTS) | tools/normout.sh > build/ours.out
	diff build/ref.out build/ours.out > build/diff.out; \
	 acc=tests/accept/$(TARGET)/$(notdir $(TESTS:.txt=.diff)); \
	 if [ ! -s build/diff.out ]; then echo "compare: identical ($(TESTS))"; \
	 elif [ -f $$acc ] && cmp -s build/diff.out $$acc; then echo "compare: reviewed differences ($(TESTS))"; \
	 else cat build/diff.out; exit 1; fi

# Same behaviour on both targets: run every test on our MS-DOS and our CP/M-86
# build and diff the two transcripts (banner, free memory and clock masked).
parity:
	$(MAKE) --no-print-directory TARGET=dos prog
	$(MAKE) --no-print-directory TARGET=cpm prog
	rc=0; for t in tests/*.txt; do \
	  python3 tools/runbas.py build/dos mbasic86.exe $$t | tools/normout.sh > build/par-dos.out; \
	  python3 tools/runbas.py build/cpm mbasic86.cmd $$t | tools/normout.sh > build/par-cpm.out; \
	  acc=tests/accept/parity/$$(basename $$t .txt).diff; \
	  if diff build/par-dos.out build/par-cpm.out > build/par.diff; then echo "parity: same      $$t"; \
	  elif [ -f $$acc ] && cmp -s build/par.diff $$acc; then echo "parity: reviewed  $$t"; \
	  else echo "parity: DIFFERENT $$t"; cat build/par.diff; rc=1; fi; \
	done; exit $$rc

# Record the current differences of TESTS as reviewed (after checking them!)
accept: prog
	mkdir -p tests/accept/$(TARGET)
	$(MAKE) --no-print-directory compare TESTS=$(TESTS) >/dev/null 2>&1; \
	 cp build/diff.out tests/accept/$(TARGET)/$(notdir $(TESTS:.txt=.diff)); \
	 echo "accepted: $(TESTS) ($(TARGET))"

# Run every tests/*.txt script against the reference and diff the results
test: prog
	for t in tests/*.txt; do $(MAKE) --no-print-directory compare TESTS=$$t || exit 1; done

# Same session, keeping the guest memory image in $(BLD)/ram.bin
dump: prog
	EMU2_RAMDUMP=ram.bin python3 tools/runbas.py $(BLD) $(PROG) $(TESTS)

# Start the DOS interpreter under emu2 (interactive)
run: prog
	cd $(BLD) && emu2 $(PROG)

# Flat archive (no directories): our two builds, the 5.28 / 5.22 reference
# binaries under 8.3 names, the license and the README
dist: all
	rm -rf build/dist build/mbasic.zip
	mkdir -p build/dist
	cp build/dos/mbasic86.exe build/cpm/mbasic86.cmd LICENSE.md README.md build/dist/
	cp ref/mbasic86.com build/dist/mbas528.com
	cp ref/mbasic86.cmd build/dist/mbas522.cmd
	cd build/dist && zip -q ../mbasic.zip *
	unzip -l build/mbasic.zip

clean:
	rm -rf build

distclean: clean
