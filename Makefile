YOSYS           := yosys
NEXTPNR         := nextpnr-ecp5
PACKER          := ecppack
FPGALOADER      := openFPGALoader
CWD             := $(shell pwd)

CONSTRAINTDIR   := $(CWD)/constraints
CONSTRAINTFILE  := $(CONSTRAINTDIR)/colorlighti5.lpf
RTLSOURCEDIR    := $(CWD)/srcs/rtl
RTLINCLUDEDIR   := $(CWD)/srcs/rtl/include
TESTDIR         := $(CWD)/srcs/tests
ICRTESTDIR		:= $(TESTDIR)/icarus
VRLTTESTDIR		:= $(TESTDIR)/verilator
VRLTINCLDIR     := $(VRLTTESTDIR)/include

BUILDDIR        := $(CWD)/build
TESTBUILDDIR    := $(CWD)/build_test
VRLTTESTBUILDDIR:= $(TESTBUILDDIR)/verilator
ICRTESTBUILDDIR := $(TESTBUILDDIR)/icarus

TOPMODULE       := Top
TARGET          := $(BUILDDIR)/$(TOPMODULE)
TARGETROM       := $(BUILDDIR)/rom.txt

RTLSRCFILES     := $(shell find $(RTLSOURCEDIR) -type f -name '*.v' -o -type f -name '*.sv')
ICRTESTFILES    := $(shell find $(ICRTESTDIR) -type f -name '*.v' -o -type f -name '*.sv')
VRLTINCLSRCFILES:= $(shell find $(VRLTINCLDIR) -type f -name '*.c' -o -type f -name '*.cpp')
VRLTTESTFILES   := $(shell find $(VRLTTESTDIR) -type d \( -path $(VRLTINCLDIR) \) -prune \
							-o -type f \( -name '*.c' -o -name '*.cpp' \) -print )

default: bit

all: bit test

# make rom ROM=</dir/to/rom.c>
# Copy to $(BUILDDIR) since yosys couldn't handle DPI to get env
# 	=> need to hard code rom location, to "./build/"
$(TARGETROM):
	mkdir -p $(BUILDDIR)
ifndef ROM
	$(error ROM not set, add ROM=</dir/to/rom.c> to make command)
endif
	$(CWD)/rom.sh $(ROM) $(BUILDDIR)

rom: $(TARGETROM)

$(TARGET).ys: $(RTLSRCFILES)
	mkdir -p $(BUILDDIR)
	echo "verilog_defaults -add -I $(RTLINCLUDEDIR)" > $@
	for SRCFILES in $^ ; do \
		echo "read_verilog -sv $${SRCFILES}" >> $@; \
	done
	echo "hierarchy -top $(TOPMODULE)" >> $@
	echo "synth_ecp5 -json $(TARGET).json" >> $@

$(TARGET).json: $(TARGETROM) $(TARGET).ys
	export ROMFILE=$(TARGETROM)
	$(YOSYS) -s $(TARGET).ys
# \ $(RTLSRCFILES)

$(TARGET)_out.config: $(TARGET).json
	$(NEXTPNR) --25k --package CABGA381 --speed 6 --json $< --textcfg $@ --lpf $(CONSTRAINTFILE) --freq 65

$(TARGET).bit: $(TARGET)_out.config
	$(PACKER) $< --bit $@

${TARGET}.svf: $(TARGET)_out.config
	$(PACKER) $< --svf $@

bit: ${TARGET}.bit

svf: ${TARGET}.svf

prog: bit
	$(FPGALOADER) -b colorlight-i5 $(TARGET).bit

# vvp console -> trace on
icr_test: $(ICRTESTFILES)
	mkdir -p $(TESTBUILDDIR)
	for TESTFILE in $^ ; do \
		DUMPFILENAME="$${TESTFILE##*/}"; \
		DUMPFILENAME="$${DUMPFILENAME%.*}"; \
		DUMPFILENAMEARG="DUMPFILENAME=\"$(TESTBUILDDIR)/$${DUMPFILENAME}.vcd\""; \
		iverilog -v -pfileline=1 -g2012 -D $${DUMPFILENAMEARG} -o "$(TESTBUILDDIR)/$${DUMPFILENAME}.vvp" $${TESTFILE} $(RTLSRCFILES); \
		vvp $(TESTBUILDDIR)/$${DUMPFILENAME}.vvp; \
	done

# Rule: verilatortestfilename = <top_module_of_choice>.c
# Verilator options:
#   -sv               : enable systemverilog support
#   --trace           : enable tracing
#   --trace-underscore: tracing signal started with underscore "_", normally not traced
#   -Wno-lint         : ignore verilator linting
#	--build           : verilator run make to create verilator header and obj automatically
#	--prefix          : verilator header and obj name (--prefix $${TOP})
#   -I                : include directory
#	--Mdir            : verilator header and obj location
#	--exe             : verilator build simulation exe file automatically
#   -Wno-lint         : disable linting
#	-o                : exe file location
vrlt_test: $(VRLTTESTFILES)
	for TESTFILE in $^ ; do \
		TOPFILENAME="$${TESTFILE##*/}"; \
		TOPBASENAME="$${TOPFILENAME%.*}"; \
		echo "====================================================================="; \
		echo "Building $${TESTFILE}"; \
		mkdir -p $(VRLTTESTBUILDDIR)/$${TOPBASENAME}; \
		verilator -Wall -sv -cc --trace --trace-underscore -Wno-lint \
			--build \
			-I$(VRLTINCLDIR) \
			--Mdir $(VRLTTESTBUILDDIR)/$${TOPBASENAME} \
			--exe \
			-o $(VRLTTESTBUILDDIR)/$${TOPBASENAME}/$${TOPBASENAME} \
			--top-module $${TOPBASENAME} \
			$${TESTFILE} $(VRLTINCLSRCFILES) $(RTLSRCFILES); \
	done

test: $(TARGETROM) vrlt_test

clean:
	rm -rf $(BUILDDIR) $(TESTBUILDDIR) *.svf *.bit *.config *.ys *.json

.PHONY: all prog clean bit svf test rom default
