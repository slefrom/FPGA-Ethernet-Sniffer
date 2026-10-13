`resetall
`default_nettype none

module sniffer_core #(
    parameter logic        SIM               = 1'b0,
    parameter string       VENDOR            = "XILINX",
    parameter string       FAMILY            = "artix7",
    parameter int          SNAPLEN           = 64,
    parameter int          FIFO_DEPTH        = 16384,
    parameter logic [15:0] UART_PRESCALE     = 16'd33,    // 100 MHz / 3 Mbaud
    parameter logic [7:0]  MDIO_PRESCALE     = 8'd19,     // MDC = 100 MHz / 40 = 2.5 MHz
    parameter int          PHY_RESET_CYCLES  = 1000,
    parameter int          PHY_WAIT_CYCLES   = 20_000_000,
    parameter int          LED_STRETCH_W     = 20         // ~42 ms at 25 MHz
)
(
    // sys_clk domain
    input  wire logic        clk,
    input  wire logic        rst,

    // MII (receive only; TX is held idle)
    input  wire logic        mii_rx_clk,
    input  wire logic [3:0]  mii_rxd,
    input  wire logic        mii_rx_dv,
    input  wire logic        mii_rx_er,
    input  wire logic        mii_tx_clk,
    output wire logic [3:0]  mii_txd,
    output wire logic        mii_tx_en,

    // PHY management
    output wire logic        phy_rst_n,
    output wire logic        mdc,
    input  wire logic        mdio_i,
    output wire logic        mdio_o,
    output wire logic        mdio_t,

    // UART to the FT2232
    output wire logic        uart_txd,

    // LEDs: [0] record captured, [1] bad frame, [2] FIFO full drop, [3] PHY init done
    output wire logic [3:0]  led
);

// MAC (rx_clk domain)
logic rx_clk, rx_rst;

taxi_axis_if #(.DATA_W(8), .ID_W(8), .USER_EN(1), .USER_W(1)) mac_tx(), mac_rx();
taxi_axis_if #(.DATA_W(96), .KEEP_W(1), .ID_W(8)) mac_tx_cpl();
taxi_axis_if #(.DATA_W(16), .KEEP_W(1), .KEEP_EN(0), .LAST_EN(0), .USER_EN(1), .USER_W(1), .ID_EN(1), .ID_W(10)) mac_stat();

assign mac_tx.tdata  = '0;
assign mac_tx.tkeep  = '1;
assign mac_tx.tstrb  = '1;
assign mac_tx.tvalid = 1'b0;
assign mac_tx.tlast  = 1'b0;
assign mac_tx.tid    = '0;
assign mac_tx.tdest  = '0;
assign mac_tx.tuser  = '0;
assign mac_tx_cpl.tready = 1'b1;
assign mac_stat.tready   = 1'b1;

taxi_eth_mac_mii #(
    .SIM(SIM),
    .VENDOR(VENDOR),
    .FAMILY(FAMILY),
    .PTP_TS_EN(1'b0),
    .PFC_EN(1'b0),
    .PAUSE_EN(1'b0),
    .STAT_EN(1'b0)
)
mac_inst (
    .rst(rst),
    .rx_clk(rx_clk),
    .rx_rst(rx_rst),
    .tx_clk(),
    .tx_rst(),

    .s_axis_tx(mac_tx),
    .m_axis_tx_cpl(mac_tx_cpl),
    .m_axis_rx(mac_rx),

    .mii_rx_clk(mii_rx_clk),
    .mii_rxd(mii_rxd),
    .mii_rx_dv(mii_rx_dv),
    .mii_rx_er(mii_rx_er),
    .mii_tx_clk(mii_tx_clk),
    .mii_txd(mii_txd),
    .mii_tx_en(mii_tx_en),
    .mii_tx_er(),

    .stat_clk(clk),
    .stat_rst(rst),
    .m_axis_stat(mac_stat),

    .cfg_rx_max_pkt_len(16'd1522-1),
    .cfg_rx_enable(1'b1),
    .cfg_tx_enable(1'b0)
);

// Record builder (rx_clk) and the clock crossing
taxi_axis_if #(.DATA_W(8), .USER_EN(1), .USER_W(1)) rec_axis(), fifo_axis();

wire fifo_good, fifo_bad, fifo_overflow;

record_builder #(
    .SNAPLEN(SNAPLEN)
)
record_inst (
    .clk(rx_clk),
    .rst(rx_rst),
    .s_axis(mac_rx),
    .m_axis(rec_axis),
    .fifo_good(fifo_good),
    .fifo_overflow(fifo_overflow),
    .ts_count(),
    .overflow()
);

async_frame_fifo #(
    .DEPTH(FIFO_DEPTH)
)
fifo_inst (
    .s_clk(rx_clk),
    .s_rst(rx_rst),
    .s_axis(rec_axis),
    .m_clk(clk),
    .m_rst(rst),
    .m_axis(fifo_axis),
    .s_status_good_frame(fifo_good),
    .s_status_bad_frame(fifo_bad),
    .s_status_overflow(fifo_overflow)
);


// COBS framing and UART (sys_clk)
taxi_axis_if #(.DATA_W(8), .USER_EN(1), .USER_W(1)) uart_tx_axis();
taxi_axis_if #(.DATA_W(8), .LAST_EN(0), .USER_EN(1), .USER_W(1)) uart_rx_axis();

assign uart_rx_axis.tready = 1'b1;

taxi_axis_cobs_encode #(
    .APPEND_ZERO(1'b1)
)
cobs_inst (
    .clk(clk),
    .rst(rst),
    .s_axis(fifo_axis),
    .m_axis(uart_tx_axis)
);

taxi_uart #(.PRE_W(16)) uart_inst (
    .clk(clk),
    .rst(rst),
    .s_axis_tx(uart_tx_axis),
    .m_axis_rx(uart_rx_axis),
    .rxd(1'b1),
    .txd(uart_txd),
    .tx_busy(),
    .rx_busy(),
    .rx_overrun_error(),
    .rx_frame_error(),
    .prescale(UART_PRESCALE)
);


// PHY bring-up over MDIO (sys_clk)

taxi_axis_if #(.DATA_W(32), .KEEP_W(1)) mdio_cmd();
taxi_axis_if #(.DATA_W(16), .KEEP_W(1)) mdio_rd();

wire mdio_busy;
wire init_done;

assign mdio_rd.tready = 1'b1;

taxi_mdio_master mdio_inst (
    .clk(clk),
    .rst(rst),
    .s_axis_cmd(mdio_cmd),
    .m_axis_rd_data(mdio_rd),
    .mdc_o(mdc),
    .mdio_i(mdio_i),
    .mdio_o(mdio_o),
    .mdio_t(mdio_t),
    .busy(mdio_busy),
    .prescale(MDIO_PRESCALE)
);

phy_init #(
    .RESET_CYCLES(PHY_RESET_CYCLES),
    .WAIT_CYCLES(PHY_WAIT_CYCLES)
)
phy_init_inst (
    .clk(clk),
    .rst(rst),
    .phy_rst_n(phy_rst_n),
    .m_axis_mdio_cmd(mdio_cmd),
    .mdio_busy(mdio_busy),
    .init_done(init_done)
);


// LEDs: stretch the FIFO's per-frame pulses (rx_clk) so they are visible

logic [LED_STRETCH_W-1:0] led_cnt_reg [3];
wire  [2:0]               led_ev = {fifo_overflow, fifo_bad, fifo_good};

always_ff @(posedge rx_clk) begin
    for (int i = 0; i < 3; i++) begin
        if (led_ev[i])
            led_cnt_reg[i] <= '1;
        else if (led_cnt_reg[i] != '0)
            led_cnt_reg[i] <= led_cnt_reg[i] - 1'b1;
        if (rx_rst)
            led_cnt_reg[i] <= '0;
    end
end

assign led[0] = led_cnt_reg[0] != '0;
assign led[1] = led_cnt_reg[1] != '0;
assign led[2] = led_cnt_reg[2] != '0;
assign led[3] = init_done;

endmodule

`resetall
