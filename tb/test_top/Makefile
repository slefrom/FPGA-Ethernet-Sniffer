ROOT     := $(abspath ../..)
RTL_DIR  := $(ROOT)/rtl
TAXI_DIR := $(ROOT)/lib/taxi/src

COCOTB_TOPLEVEL     = sniffer_core
COCOTB_TEST_MODULES = test_top

# interfaces and packages 
VERILOG_SOURCES += $(RTL_DIR)/sniffer_pkg.sv
VERILOG_SOURCES += $(TAXI_DIR)/axis/rtl/taxi_axis_if.sv

# RTL
VERILOG_SOURCES += $(RTL_DIR)/sync_ff.sv
VERILOG_SOURCES += $(RTL_DIR)/async_frame_fifo.sv
VERILOG_SOURCES += $(RTL_DIR)/record_builder.sv
VERILOG_SOURCES += $(RTL_DIR)/phy_init.sv
VERILOG_SOURCES += $(RTL_DIR)/sniffer_core.sv

# Taxi: MII MAC and its dependencies
VERILOG_SOURCES += $(TAXI_DIR)/eth/rtl/taxi_eth_mac_mii.sv
VERILOG_SOURCES += $(TAXI_DIR)/eth/rtl/taxi_mii_phy_if.sv
VERILOG_SOURCES += $(TAXI_DIR)/eth/rtl/taxi_eth_mac_1g.sv
VERILOG_SOURCES += $(TAXI_DIR)/eth/rtl/taxi_axis_gmii_rx.sv
VERILOG_SOURCES += $(TAXI_DIR)/eth/rtl/taxi_axis_gmii_tx.sv
VERILOG_SOURCES += $(TAXI_DIR)/eth/rtl/taxi_mac_ctrl_rx.sv
VERILOG_SOURCES += $(TAXI_DIR)/eth/rtl/taxi_mac_ctrl_tx.sv
VERILOG_SOURCES += $(TAXI_DIR)/eth/rtl/taxi_mac_pause_ctrl_rx.sv
VERILOG_SOURCES += $(TAXI_DIR)/eth/rtl/taxi_mac_pause_ctrl_tx.sv
VERILOG_SOURCES += $(TAXI_DIR)/eth/rtl/taxi_eth_mac_stats.sv
VERILOG_SOURCES += $(TAXI_DIR)/stats/rtl/taxi_stats_collect.sv
VERILOG_SOURCES += $(TAXI_DIR)/axis/rtl/taxi_axis_async_fifo.sv
VERILOG_SOURCES += $(TAXI_DIR)/axis/rtl/taxi_axis_arb_mux.sv
VERILOG_SOURCES += $(TAXI_DIR)/axis/rtl/taxi_axis_pad.sv
VERILOG_SOURCES += $(TAXI_DIR)/axis/rtl/taxi_axis_null_src.sv
VERILOG_SOURCES += $(TAXI_DIR)/axis/rtl/taxi_axis_tie.sv
VERILOG_SOURCES += $(TAXI_DIR)/prim/rtl/taxi_arbiter.sv
VERILOG_SOURCES += $(TAXI_DIR)/prim/rtl/taxi_penc.sv
VERILOG_SOURCES += $(TAXI_DIR)/lfsr/rtl/taxi_lfsr.sv
VERILOG_SOURCES += $(TAXI_DIR)/io/rtl/taxi_ssio_sdr_in.sv
VERILOG_SOURCES += $(TAXI_DIR)/sync/rtl/taxi_sync_reset.sv
VERILOG_SOURCES += $(TAXI_DIR)/sync/rtl/taxi_sync_signal.sv

# Taxi: COBS encoder, UART, MDIO master
VERILOG_SOURCES += $(TAXI_DIR)/axis/rtl/taxi_axis_cobs_encode.sv
VERILOG_SOURCES += $(TAXI_DIR)/axis/rtl/taxi_axis_fifo.sv
VERILOG_SOURCES += $(TAXI_DIR)/lss/rtl/taxi_uart.sv
VERILOG_SOURCES += $(TAXI_DIR)/lss/rtl/taxi_uart_rx.sv
VERILOG_SOURCES += $(TAXI_DIR)/lss/rtl/taxi_uart_tx.sv
VERILOG_SOURCES += $(TAXI_DIR)/lss/rtl/taxi_uart_brg.sv
VERILOG_SOURCES += $(TAXI_DIR)/lss/rtl/taxi_mdio_master.sv

# simulation settings
export PARAM_SIM              := 1
export PARAM_SNAPLEN          := 300
export PARAM_FIFO_DEPTH       := 4096
export PARAM_UART_PRESCALE    := 8
export PARAM_PHY_RESET_CYCLES := 10
export PARAM_PHY_WAIT_CYCLES  := 100
export PARAM_LED_STRETCH_W    := 4

include ../cocotb.mk
