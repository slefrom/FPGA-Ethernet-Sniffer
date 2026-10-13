# Vivado batch build for the minimal Arty A7-100T sniffer.
#   cd syn && vivado -mode batch -source build.tcl
# Produces sniffer_top.bit plus utilization and timing reports in syn/out/.

set root [file normalize [file dirname [info script]]/..]
set taxi $root/lib/taxi/src
set out  $root/syn/out
file mkdir $out

create_project -force sniffer $out/proj -part xc7a100tcsg324-1

set rtl [list \
    $root/rtl/sniffer_pkg.sv \
    $root/rtl/sync_ff.sv \
    $root/rtl/async_frame_fifo.sv \
    $root/rtl/record_builder.sv \
    $root/rtl/phy_init.sv \
    $root/rtl/sniffer_core.sv \
    $root/rtl/clk_rst.sv \
    $root/rtl/sniffer_top.sv \
]

# Taxi sources (expanded from its .f lists)
set taxi_files [list \
    axis/rtl/taxi_axis_if.sv \
    axis/rtl/taxi_axis_fifo.sv \
    axis/rtl/taxi_axis_async_fifo.sv \
    axis/rtl/taxi_axis_arb_mux.sv \
    axis/rtl/taxi_axis_cobs_encode.sv \
    axis/rtl/taxi_axis_pad.sv \
    axis/rtl/taxi_axis_null_src.sv \
    axis/rtl/taxi_axis_tie.sv \
    eth/rtl/taxi_eth_mac_mii.sv \
    eth/rtl/taxi_eth_mac_1g.sv \
    eth/rtl/taxi_eth_mac_stats.sv \
    eth/rtl/taxi_axis_gmii_rx.sv \
    eth/rtl/taxi_axis_gmii_tx.sv \
    eth/rtl/taxi_mac_ctrl_rx.sv \
    eth/rtl/taxi_mac_ctrl_tx.sv \
    eth/rtl/taxi_mac_pause_ctrl_rx.sv \
    eth/rtl/taxi_mac_pause_ctrl_tx.sv \
    eth/rtl/taxi_mii_phy_if.sv \
    io/rtl/taxi_ssio_sdr_in.sv \
    lfsr/rtl/taxi_lfsr.sv \
    lss/rtl/taxi_uart.sv \
    lss/rtl/taxi_uart_rx.sv \
    lss/rtl/taxi_uart_tx.sv \
    lss/rtl/taxi_uart_brg.sv \
    lss/rtl/taxi_mdio_master.sv \
    prim/rtl/taxi_arbiter.sv \
    prim/rtl/taxi_penc.sv \
    stats/rtl/taxi_stats_collect.sv \
    sync/rtl/taxi_sync_reset.sv \
    sync/rtl/taxi_sync_signal.sv \
]
foreach f $taxi_files { lappend rtl $taxi/$f }

add_files -fileset sources_1 $rtl
set_property top sniffer_top [current_fileset]

add_files -fileset constrs_1 [list \
    $root/constr/arty_a7_100.xdc \
    $root/constr/timing.xdc \
    $root/constr/async_frame_fifo.tcl \
    $taxi/axis/syn/vivado/taxi_axis_async_fifo.tcl \
    $taxi/sync/syn/vivado/taxi_sync_reset.tcl \
    $taxi/sync/syn/vivado/taxi_sync_signal.tcl \
]

launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

open_run impl_1
report_utilization    -file $out/utilization.rpt
report_timing_summary -file $out/timing_summary.rpt
report_cdc            -file $out/cdc.rpt
file copy -force $out/proj/sniffer.runs/impl_1/sniffer_top.bit $out/sniffer_top.bit
