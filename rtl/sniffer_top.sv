`resetall
`default_nettype none

module sniffer_top (
    input  wire logic        CLK100MHZ,
    input  wire logic        ck_rst,         // active low

    // DP83848 PHY (MII)
    output wire logic        eth_ref_clk,
    output wire logic        eth_rstn,
    input  wire logic        eth_rx_clk,
    input  wire logic [3:0]  eth_rxd,
    input  wire logic        eth_rx_dv,
    input  wire logic        eth_rxerr,
    input  wire logic        eth_tx_clk,
    output wire logic [3:0]  eth_txd,
    output wire logic        eth_tx_en,
    input  wire logic        eth_col,
    input  wire logic        eth_crs,
    output wire logic        eth_mdc,
    inout  wire logic        eth_mdio,

    output wire logic        uart_rxd_out,

    output wire logic [3:0]  led
);

wire sys_clk, sys_rst;

clk_rst clk_rst_inst (
    .clk_100mhz(CLK100MHZ),
    .rst_n(ck_rst),
    .sys_clk(sys_clk),
    .sys_rst(sys_rst),
    .eth_ref_clk(eth_ref_clk)
);

wire mdio_i, mdio_o, mdio_t;

IOBUF mdio_iobuf_inst (
    .I(mdio_o),
    .O(mdio_i),
    .T(mdio_t),
    .IO(eth_mdio)
);

sniffer_core #(
    .SIM(1'b0),
    .VENDOR("XILINX"),
    .FAMILY("artix7")
)
core_inst (
    .clk(sys_clk),
    .rst(sys_rst),

    .mii_rx_clk(eth_rx_clk),
    .mii_rxd(eth_rxd),
    .mii_rx_dv(eth_rx_dv),
    .mii_rx_er(eth_rxerr),
    .mii_tx_clk(eth_tx_clk),
    .mii_txd(eth_txd),
    .mii_tx_en(eth_tx_en),

    .phy_rst_n(eth_rstn),
    .mdc(eth_mdc),
    .mdio_i(mdio_i),
    .mdio_o(mdio_o),
    .mdio_t(mdio_t),

    .uart_txd(uart_rxd_out),

    .led(led)
);

endmodule

`resetall
