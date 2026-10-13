`resetall
`default_nettype none

module async_frame_fifo #(
    parameter int    DEPTH       = 4096,     
    parameter int    DATA_W      = 8,
    parameter int    SYNC_STAGES = 2
)
(
    // write side
    input  wire logic   s_clk,
    input  wire logic   s_rst,
    taxi_axis_if.snk    s_axis,

    // read side
    input  wire logic   m_clk,
    input  wire logic   m_rst,
    taxi_axis_if.src    m_axis,

    // write-domain status: one pulse per frame
    output wire logic   s_status_good_frame,
    output wire logic   s_status_bad_frame,
    output wire logic   s_status_overflow
);

localparam int AW = $clog2(DEPTH);   

initial begin
    if (2**AW != DEPTH)
        $fatal(1, "async_frame_fifo: DEPTH must be a power of 2");
end

function automatic logic [AW:0] bin2gray(input logic [AW:0] b);
    return b ^ (b >> 1);
endfunction

function automatic logic [AW:0] gray2bin(input logic [AW:0] g);
    logic [AW:0] b;
    b[AW] = g[AW];
    for (int i = AW - 1; i >= 0; i--)
        b[i] = b[i+1] ^ g[i];
    return b;
endfunction

// to map onto block ram instead of LUTs
(* ram_style = "block" *) logic [DATA_W:0] mem [DEPTH];

// Write side (s_clk)
logic [AW:0] wr_ptr_reg = '0;       // next write address, runs ahead in a frame
logic [AW:0] wr_commit_reg = '0;    // end of the last committed frame
logic [AW:0] wr_pub_reg = '0;       // steps towards wr_commit_reg by 1 per cycle
logic [AW:0] wr_gray_reg = '0;      // Gray code of wr_pub_reg; crosses to m_clk
logic [AW:0] rd_gray_reg = '0;      // read side: Gray code of rd_ptr_reg; crosses to s_clk

wire  [AW:0] rd_gray_sync;          // read pointer, Gray, in s_clk
wire  [AW:0] rd_ptr_sync = gray2bin(rd_gray_sync);

sync_ff #(.WIDTH(AW+1), .N(SYNC_STAGES)) rd_gray_sync_inst (
    .clk(s_clk),
    .rst(s_rst),
    .in(rd_gray_reg),
    .out(rd_gray_sync)
);

wire beat = s_axis.tvalid;
wire last = s_axis.tlast;
wire bad  = s_axis.tuser[0];
wire full = (wr_ptr_reg - rd_ptr_sync) == (AW+1)'(DEPTH);

typedef enum logic [0:0] {
    W_ACCEPT,   // writing (or waiting for) a frame
    W_DROP      // current frame did not fit: discard to tlast
} wstate_t;

wstate_t wstate_reg = W_ACCEPT, wstate_next;

logic good_reg = 1'b0;
logic bad_reg = 1'b0;
logic overflow_reg = 1'b0;

wire wr_en = (wstate_reg == W_ACCEPT) && beat && !full;

always_ff @(posedge s_clk) begin
    if (s_rst)
        wstate_reg <= W_ACCEPT;
    else
        wstate_reg <= wstate_next;
end

always_comb begin
    wstate_next = wstate_reg;
    case (wstate_reg)
        W_ACCEPT: if (beat && full && !last) wstate_next = W_DROP;
        W_DROP:   if (beat && last)          wstate_next = W_ACCEPT;
        default:                             wstate_next = W_ACCEPT;
    endcase
end

always_ff @(posedge s_clk) begin
    good_reg     <= 1'b0;
    bad_reg      <= 1'b0;
    overflow_reg <= 1'b0;

    case (wstate_reg)
        W_ACCEPT: begin
            if (beat) begin
                if (full) begin
                    // no room: roll back; finish the drop in W_DROP unless this was the last beat
                    wr_ptr_reg   <= wr_commit_reg;
                    overflow_reg <= last;
                end else if (last && bad) begin
                    wr_ptr_reg <= wr_commit_reg;
                    bad_reg    <= 1'b1;
                end else if (last) begin
                    wr_ptr_reg    <= wr_ptr_reg + 1'b1;
                    wr_commit_reg <= wr_ptr_reg + 1'b1;
                    good_reg      <= 1'b1;
                end else begin
                    wr_ptr_reg <= wr_ptr_reg + 1'b1;
                end
            end
        end
        W_DROP: begin
            if (beat && last)
                overflow_reg <= 1'b1;
        end
        default: ;
    endcase

    // publish the committed pointer one entry at a time
    if (wr_pub_reg != wr_commit_reg)
        wr_pub_reg <= wr_pub_reg + 1'b1;
    wr_gray_reg <= bin2gray(wr_pub_reg);

    if (s_rst) begin
        wr_ptr_reg    <= '0;
        wr_commit_reg <= '0;
        wr_pub_reg    <= '0;
        wr_gray_reg   <= '0;
        good_reg      <= 1'b0;
        bad_reg       <= 1'b0;
        overflow_reg  <= 1'b0;
    end
end

always_ff @(posedge s_clk) begin
    if (wr_en)
        mem[wr_ptr_reg[AW-1:0]] <= {last, s_axis.tdata};
end

assign s_axis.tready = 1'b1;

assign s_status_good_frame = good_reg;
assign s_status_bad_frame  = bad_reg;
assign s_status_overflow   = overflow_reg;


// Read side (m_clk)
logic [AW:0]     rd_ptr_reg = '0;

wire  [AW:0]     wr_gray_sync;      // published write pointer, Gray, in m_clk
wire  [AW:0]     wr_ptr_sync = gray2bin(wr_gray_sync);

sync_ff #(.WIDTH(AW+1), .N(SYNC_STAGES)) wr_gray_sync_inst (
    .clk(m_clk),
    .rst(m_rst),
    .in(wr_gray_reg),
    .out(wr_gray_sync)
);

logic [DATA_W:0]   rd_data_reg;     // RAM read register: {tlast, tdata}
logic              m_tvalid_reg = 1'b0;

wire empty    = (rd_ptr_reg == wr_ptr_sync);
wire out_free = !m_tvalid_reg || m_axis.tready;
wire rd_en    = out_free && !empty;

// RAM read port (kept on its own for block RAM inference)
always_ff @(posedge m_clk) begin
    if (rd_en)
        rd_data_reg <= mem[rd_ptr_reg[AW-1:0]];
end

// Read pointer and output valid
always_ff @(posedge m_clk) begin
    if (rd_en) begin
        m_tvalid_reg <= 1'b1;
        rd_ptr_reg   <= rd_ptr_reg + 1'b1;
    end else if (out_free) begin
        m_tvalid_reg <= 1'b0;
    end
    rd_gray_reg <= bin2gray(rd_ptr_reg);

    if (m_rst) begin
        rd_ptr_reg   <= '0;
        rd_gray_reg  <= '0;
        m_tvalid_reg <= 1'b0;
    end
end

assign m_axis.tdata  = rd_data_reg[DATA_W-1:0];
assign m_axis.tkeep  = '1;
assign m_axis.tstrb  = '1;
assign m_axis.tvalid = m_tvalid_reg;
assign m_axis.tlast  = rd_data_reg[DATA_W];
assign m_axis.tid    = '0;
assign m_axis.tdest  = '0;
assign m_axis.tuser  = '0;

endmodule

`resetall
