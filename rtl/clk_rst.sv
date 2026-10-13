`resetall
`default_nettype none

module clk_rst (
    input   logic  clk_100mhz,
    input  logic  rst_n,       // board reset button, active low

    output  logic  sys_clk,
    output  logic  sys_rst,
    output  logic  eth_ref_clk
);

wire clk_ibufg;
wire mmcm_clkfb;
wire mmcm_locked;
wire clk_sys_mmcm;
wire clk_25_mmcm;

IBUFG clk_ibufg_inst (
    .I(clk_100mhz),
    .O(clk_ibufg)
);

MMCME2_BASE #(
    .CLKIN1_PERIOD(10.0),
    .REF_JITTER1(0.010),
    .DIVCLK_DIVIDE(1),          // 100 MHz PFD
    .CLKFBOUT_MULT_F(10),       // 1000 MHz VCO
    .CLKFBOUT_PHASE(0),
    .CLKOUT0_DIVIDE_F(10),      // 100 MHz
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE(0),
    .CLKOUT1_DIVIDE(40),        // 25 MHz
    .CLKOUT1_DUTY_CYCLE(0.5),
    .CLKOUT1_PHASE(0),
    .CLKOUT2_DIVIDE(1),
    .CLKOUT3_DIVIDE(1),
    .CLKOUT4_DIVIDE(1),
    .CLKOUT5_DIVIDE(1),
    .CLKOUT6_DIVIDE(1),
    .CLKOUT4_CASCADE("FALSE"),
    .BANDWIDTH("OPTIMIZED"),
    .STARTUP_WAIT("FALSE")
)
mmcm_inst (
    .CLKIN1(clk_ibufg),
    .CLKFBIN(mmcm_clkfb),
    .CLKFBOUT(mmcm_clkfb),
    .CLKFBOUTB(),
    .CLKOUT0(clk_sys_mmcm),
    .CLKOUT0B(),
    .CLKOUT1(clk_25_mmcm),
    .CLKOUT1B(),
    .CLKOUT2(),
    .CLKOUT2B(),
    .CLKOUT3(),
    .CLKOUT3B(),
    .CLKOUT4(),
    .CLKOUT5(),
    .CLKOUT6(),
    .RST(!rst_n),
    .PWRDWN(1'b0),
    .LOCKED(mmcm_locked)
);

BUFG sys_clk_bufg_inst (
    .I(clk_sys_mmcm),
    .O(sys_clk)
);

BUFG eth_ref_clk_bufg_inst (
    .I(clk_25_mmcm),
    .O(eth_ref_clk)
);

taxi_sync_reset #(
    .N(4)
)
sys_rst_sync_inst (
    .clk(sys_clk),
    .rst(!mmcm_locked || !rst_n),
    .out(sys_rst)
);

endmodule

`resetall
