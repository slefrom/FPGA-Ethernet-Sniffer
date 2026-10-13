`resetall
`default_nettype none

module phy_init #(
    parameter int          RESET_CYCLES = 1000,        // 10 us at 100 MHz
    parameter int          WAIT_CYCLES  = 20_000_000,  // 200 ms at 100 MHz
    parameter logic [4:0]  PHY_ADDR     = 5'd1,        // DP83848 strap on Arty A7
    parameter logic [15:0] BMCR_VALUE   = 16'h2100     // speed 100, full duplex, AN off
)
(
    input  logic   clk,
    input  logic   rst,

    output  logic   phy_rst_n,

    taxi_axis_if.src    m_axis_mdio_cmd,   // to taxi_mdio_master
    input  logic   mdio_busy,

    output logic   init_done
);

localparam int CNT_W = $clog2((RESET_CYCLES > WAIT_CYCLES ? RESET_CYCLES : WAIT_CYCLES) + 1);

typedef enum logic [2:0] {
    P_RESET,    // PHY held in reset
    P_WAIT,     // power-up / strap latch time
    P_WRITE,    // BMCR write command offered to the MDIO master
    P_FLUSH,    // write in progress on the wire
    P_DONE
} state_t;

state_t state_reg = P_RESET, state_next;

logic [CNT_W-1:0] cnt_reg = '0;
logic             cmd_valid_reg = 1'b0;
logic             phy_rst_n_reg = 1'b0;
logic             done_reg = 1'b0;

wire cmd_accepted = cmd_valid_reg && m_axis_mdio_cmd.tready;

always_ff @(posedge clk) begin
    if (rst)
        state_reg <= P_RESET;
    else
        state_reg <= state_next;
end

always_comb begin
    state_next = state_reg;
    case (state_reg)
        P_RESET: if (cnt_reg == CNT_W'(RESET_CYCLES - 1)) state_next = P_WAIT;
        P_WAIT:  if (cnt_reg == CNT_W'(WAIT_CYCLES - 1))  state_next = P_WRITE;
        P_WRITE: if (cmd_accepted)                         state_next = P_FLUSH;
        // short guard so the master's busy flag has time to rise
        P_FLUSH: if (cnt_reg >= CNT_W'(3) && !mdio_busy)   state_next = P_DONE;
        P_DONE:  state_next = P_DONE;
        default: state_next = P_RESET;
    endcase
end

always_ff @(posedge clk) begin
    cnt_reg       <= (state_next != state_reg) ? '0 : cnt_reg + 1'b1;
    phy_rst_n_reg <= (state_next != P_RESET);
    done_reg      <= (state_next == P_DONE);

    if (state_reg != P_WRITE && state_next == P_WRITE)
        cmd_valid_reg <= 1'b1;
    else if (cmd_accepted)
        cmd_valid_reg <= 1'b0;

    if (rst) begin
        cnt_reg       <= '0;
        phy_rst_n_reg <= 1'b0;
        done_reg      <= 1'b0;
        cmd_valid_reg <= 1'b0;
    end
end

// MDIO command: {ST=01, OP=01 (write), PHYAD, REGAD=0 (BMCR), TA, DATA}
assign m_axis_mdio_cmd.tdata  = {2'b01, 2'b01, PHY_ADDR, 5'd0, 2'b10, BMCR_VALUE};
assign m_axis_mdio_cmd.tkeep  = '1;
assign m_axis_mdio_cmd.tstrb  = '1;
assign m_axis_mdio_cmd.tvalid = cmd_valid_reg;
assign m_axis_mdio_cmd.tlast  = 1'b1;
assign m_axis_mdio_cmd.tid    = '0;
assign m_axis_mdio_cmd.tdest  = '0;
assign m_axis_mdio_cmd.tuser  = '0;

assign phy_rst_n = phy_rst_n_reg;
assign init_done = done_reg;

endmodule

`resetall
