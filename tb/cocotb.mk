# Shared settings for the cocotb Makefiles in tb/*/Makefile.
# Each test Makefile sets ROOT, COCOTB_TOPLEVEL, COCOTB_TEST_MODULES,
# VERILOG_SOURCES and any PARAM_<name> overrides, then includes this file.
#
#   make              build and run
#   make WAVES=1      also dump an FST waveform into the sim build directory
#   make clean

TOPLEVEL_LANG = verilog
SIM ?= verilator
WAVES ?= 0

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

# test helpers (tb/) and the host protocol module (host/) for the Python side
export PYTHONPATH := $(ROOT)/tb:$(ROOT)/host:$(PYTHONPATH)

ifeq ($(SIM), verilator)

    COMPILE_ARGS += -Wno-fatal -Wno-PINMISSING -Wno-PINCONNECTEMPTY -Wno-PROCASSINIT
    COMPILE_ARGS += --x-assign unique --x-initial unique
    COMPILE_ARGS += $(foreach v,$(filter PARAM_%,$(.VARIABLES)),-G$(subst PARAM_,,$(v))=$($(v)))
    COCOTB_PLUSARGS += +verilator+rand+reset+2
    ifeq ($(WAVES), 1)
        COMPILE_ARGS += --trace-fst --trace-structs
        VERILATOR_TRACE = 1
    endif
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
