ROOT     := $(abspath ../..)
RTL_DIR  := $(ROOT)/rtl
TAXI_DIR := $(ROOT)/lib/taxi/src

COCOTB_TOPLEVEL     = test_record_builder
COCOTB_TEST_MODULES = test_record_builder

VERILOG_SOURCES += $(RTL_DIR)/sniffer_pkg.sv
VERILOG_SOURCES += $(TAXI_DIR)/axis/rtl/taxi_axis_if.sv
VERILOG_SOURCES += $(RTL_DIR)/record_builder.sv
VERILOG_SOURCES += test_record_builder.sv

# make SNAPLEN=16 to test another snap length; each value gets its own build
SNAPLEN ?= 64
export PARAM_SNAPLEN := $(SNAPLEN)
export TB_SNAPLEN    := $(SNAPLEN)
SIM_BUILD := sim_build_snaplen$(SNAPLEN)
COCOTB_RESULTS_FILE := results_snaplen$(SNAPLEN).xml

include ../cocotb.mk
