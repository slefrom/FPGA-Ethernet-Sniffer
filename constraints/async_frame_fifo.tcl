proc afifo_clk_period {pattern} {
    set pins [get_pins -quiet -filter {REF_PIN_NAME == C} -of_objects [get_cells -quiet $pattern]]
    set clks [get_clocks -quiet -of_objects $pins]
    if {[llength $clks]} {
        return [list [get_property -min PERIOD $clks] $clks]
    }
    puts "CRITICAL WARNING: async_frame_fifo.tcl: no clock found on $pattern; using 10.0 ns"
    return [list 10.0 {}]
}

foreach fifo [get_cells -hier -filter {ORIG_REF_NAME == async_frame_fifo || REF_NAME == async_frame_fifo}] {
    lassign [afifo_clk_period "$fifo/wr_gray_reg_reg\[*\]"] wr_period wr_clk
    lassign [afifo_clk_period "$fifo/rd_gray_reg_reg\[*\]"] rd_period rd_clk
    puts "Inserting CDC constraints for async_frame_fifo instance $fifo (write clock $wr_clk ${wr_period} ns, read clock $rd_clk ${rd_period} ns)"

    set src [get_cells "$fifo/wr_gray_reg_reg\[*\]"]
    set dst [get_cells "$fifo/wr_gray_sync_inst/sync_reg_reg\[0\]\[*\]"]
    set_property ASYNC_REG TRUE [get_cells "$fifo/wr_gray_sync_inst/sync_reg_reg\[*\]\[*\]"]
    set_max_delay -from $src -to $dst -datapath_only $wr_period
    set_bus_skew  -from $src -to $dst $rd_period

    set src [get_cells "$fifo/rd_gray_reg_reg\[*\]"]
    set dst [get_cells "$fifo/rd_gray_sync_inst/sync_reg_reg\[0\]\[*\]"]
    set_property ASYNC_REG TRUE [get_cells "$fifo/rd_gray_sync_inst/sync_reg_reg\[*\]\[*\]"]
    set_max_delay -from $src -to $dst -datapath_only $rd_period
    set_bus_skew  -from $src -to $dst $wr_period

    set out_regs [get_cells -quiet "$fifo/rd_data_reg_reg\[*\]"]
    if {[llength $out_regs] && [llength $wr_clk]} {
        set_false_path -from $wr_clk -to $out_regs
    }
}
