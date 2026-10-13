ROOT     := $(abspath ../..)
RTL_DIR  := $(ROOT)/rtl
TAXI_DIR := $(ROOT)/lib/taxi/src

COCOTB_TOPLEVEL     = test_async_frame_fifo
COCOTB_TEST_MODULES = test_async_frame_fifo

VERILOG_SOURCES += $(RTL_DIR)/sniffer_pkg.sv
VERILOG_SOURCES += $(TAXI_DIR)/axis/rtl/taxi_axis_if.sv
VERILOG_SOURCES += $(RTL_DIR)/sync_ff.sv
VERILOG_SOURCES += $(RTL_DIR)/async_frame_fifo.sv
VERILOG_SOURCES += test_async_frame_fifo.sv

# must match DEPTH in test_async_frame_fifo.py
export PARAM_DEPTH := 256

include ../cocotb.mk
