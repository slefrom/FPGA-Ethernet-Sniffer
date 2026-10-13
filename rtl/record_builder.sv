`resetall
`default_nettype none

module record_builder
    import sniffer_pkg::*;
#(
    parameter int SNAPLEN   = 64,   // bytes of each frame to keep, >= 1
    parameter int BUF_DEPTH = 16,   // delay line, power of 2
    parameter int Q_DEPTH   = 4     // timestamp / end-of-frame queues, power of 2
)
(
    input  wire logic             clk,
    input  wire logic             rst,

    taxi_axis_if.snk              s_axis,      // from the MAC
    taxi_axis_if.src              m_axis,      // to async_frame_fifo

    // async_frame_fifo write-side status (same clock domain)
    input  wire logic             fifo_good,
    input  wire logic             fifo_overflow,

    output wire logic [TS_W-1:0]  ts_count,
    output wire logic             overflow     // internal queue overflow (should never pulse)
);

localparam int BW = $clog2(BUF_DEPTH);
localparam int QW = $clog2(Q_DEPTH);


// Tick counter
logic [TS_W-1:0] ts_cnt_reg = '0;

always_ff @(posedge clk) begin
    ts_cnt_reg <= ts_cnt_reg + 1'b1;
    if (rst)
        ts_cnt_reg <= '0;
end

assign ts_count = ts_cnt_reg;


// delay line: {last_kept, data}
logic [8:0]      buf_mem [BUF_DEPTH];
logic [BW:0]     buf_wr_reg = '0, buf_rd_reg = '0;
// timestamps
logic [TS_W-1:0] tsq_mem [Q_DEPTH];
logic [QW:0]     tsq_wr_reg = '0, tsq_rd_reg = '0;
// end of frame: {bad, orig_len}
logic [16:0]     eq_mem [Q_DEPTH];
logic [QW:0]     eq_wr_reg = '0, eq_rd_reg = '0;

wire buf_empty = buf_wr_reg == buf_rd_reg;
wire buf_full  = buf_wr_reg == {~buf_rd_reg[BW], buf_rd_reg[BW-1:0]};
wire tsq_empty = tsq_wr_reg == tsq_rd_reg;
wire tsq_full  = tsq_wr_reg == {~tsq_rd_reg[QW], tsq_rd_reg[QW-1:0]};
wire eq_empty  = eq_wr_reg == eq_rd_reg;
wire eq_full   = eq_wr_reg == {~eq_rd_reg[QW], eq_rd_reg[QW-1:0]};

wire [7:0]       head_data      = buf_mem[buf_rd_reg[BW-1:0]][7:0];
wire             head_last_kept = buf_mem[buf_rd_reg[BW-1:0]][8];
wire [TS_W-1:0]  ts_head        = tsq_mem[tsq_rd_reg[QW-1:0]];
wire [15:0]      eq_orig_len    = eq_mem[eq_rd_reg[QW-1:0]][15:0];
wire             eq_bad         = eq_mem[eq_rd_reg[QW-1:0]][16];

logic        sof_reg = 1'b1;
logic [15:0] in_idx_reg = '0;       // bytes of the current frame so far
logic        overflow_reg = 1'b0;

wire        beat      = s_axis.tvalid;
wire        last      = s_axis.tlast;
wire [15:0] idx       = sof_reg ? 16'd0 : in_idx_reg;
wire        keep      = idx < 16'(SNAPLEN);
wire        last_kept = last || (idx == 16'(SNAPLEN - 1));
wire [15:0] orig_len  = (idx == 16'hFFFF) ? idx : idx + 1'b1;

assign s_axis.tready = 1'b1;
assign overflow      = overflow_reg;

always_ff @(posedge clk) begin
    overflow_reg <= 1'b0;
    if (beat) begin
        sof_reg    <= last;
        in_idx_reg <= last ? '0 : orig_len;

        if (sof_reg) begin
            if (!tsq_full) begin
                tsq_mem[tsq_wr_reg[QW-1:0]] <= ts_cnt_reg;
                tsq_wr_reg <= tsq_wr_reg + 1'b1;
            end else begin
                overflow_reg <= 1'b1;
            end
        end

        if (keep) begin
            if (!buf_full) begin
                buf_mem[buf_wr_reg[BW-1:0]] <= {last_kept, s_axis.tdata};
                buf_wr_reg <= buf_wr_reg + 1'b1;
            end else begin
                overflow_reg <= 1'b1;
            end
        end

        if (last) begin
            if (!eq_full) begin
                eq_mem[eq_wr_reg[QW-1:0]] <= {s_axis.tuser[0], orig_len};
                eq_wr_reg <= eq_wr_reg + 1'b1;
            end else begin
                overflow_reg <= 1'b1;
            end
        end
    end
    if (rst) begin
        sof_reg      <= 1'b1;
        in_idx_reg   <= '0;
        buf_wr_reg   <= '0;
        tsq_wr_reg   <= '0;
        eq_wr_reg    <= '0;
        overflow_reg <= 1'b0;
    end
end

// Drop counter
logic [15:0] drop_cnt_reg = '0;
logic [15:0] drop_pend_reg = '0;    // value carried by the last trailer sent
logic [15:0] drop_rep_reg = '0;     // value being written into the current trailer

always_ff @(posedge clk) begin
    if (fifo_overflow)
        drop_cnt_reg <= (drop_cnt_reg == 16'hFFFF) ? drop_cnt_reg : drop_cnt_reg + 1'b1;
    else if (fifo_good)
        drop_cnt_reg <= drop_cnt_reg - drop_pend_reg;
    if (rst)
        drop_cnt_reg <= '0;
end

typedef enum logic [1:0] {
    S_IDLE,     // waiting for a frame; emits timestamp byte 0
    S_TS,       // timestamp bytes 1..5
    S_DATA,     // kept frame bytes, up to the "last kept" byte
    S_TRAILER   // orig_len and drops, once the frame has ended
} state_t;

state_t state_reg = S_IDLE, state_next;

logic [2:0] ts_idx_reg = '0;
logic [1:0] tr_idx_reg = '0;

logic [7:0] m_tdata_reg = '0;
logic       m_tvalid_reg = 1'b0;
logic       m_tlast_reg = 1'b0;
logic       m_tuser_reg = 1'b0;

wire out_free = !m_tvalid_reg || m_axis.tready;

always_ff @(posedge clk) begin
    if (rst)
        state_reg <= S_IDLE;
    else
        state_reg <= state_next;
end

always_comb begin
    state_next = state_reg;
    if (out_free) begin
        case (state_reg)
            S_IDLE:    if (!tsq_empty)                          state_next = S_TS;
            S_TS:      if (ts_idx_reg == 3'(TS_BYTES - 1))      state_next = S_DATA;
            S_DATA:    if (!buf_empty && head_last_kept)        state_next = S_TRAILER;
            S_TRAILER: if (!eq_empty && tr_idx_reg == 2'd3)     state_next = S_IDLE;
            default:                                            state_next = S_IDLE;
        endcase
    end
end

always_ff @(posedge clk) begin
    if (out_free) begin
        m_tvalid_reg <= 1'b0;
        m_tlast_reg  <= 1'b0;
        m_tuser_reg  <= 1'b0;
        case (state_reg)
            S_IDLE: begin
                if (!tsq_empty) begin
                    m_tdata_reg  <= ts_head[7:0];
                    m_tvalid_reg <= 1'b1;
                    ts_idx_reg   <= 3'd1;
                end
            end
            S_TS: begin
                m_tdata_reg  <= ts_head[ts_idx_reg*8 +: 8];
                m_tvalid_reg <= 1'b1;
                ts_idx_reg   <= ts_idx_reg + 1'b1;
                if (ts_idx_reg == 3'(TS_BYTES - 1))
                    tsq_rd_reg <= tsq_rd_reg + 1'b1;
            end
            S_DATA: begin
                if (!buf_empty) begin
                    m_tdata_reg  <= head_data;
                    m_tvalid_reg <= 1'b1;
                    buf_rd_reg   <= buf_rd_reg + 1'b1;
                    tr_idx_reg   <= '0;
                end
            end
            
            S_TRAILER: begin
                if (!eq_empty) begin
                    m_tvalid_reg <= 1'b1;
                    tr_idx_reg   <= tr_idx_reg + 1'b1;
                    case (tr_idx_reg)
                        2'd0: begin
                            m_tdata_reg  <= eq_orig_len[7:0];
                            drop_rep_reg <= drop_cnt_reg;
                        end
                        2'd1: m_tdata_reg <= eq_orig_len[15:8];
                        2'd2: m_tdata_reg <= drop_rep_reg[7:0];
                        2'd3: begin
                            m_tdata_reg   <= drop_rep_reg[15:8];
                            m_tlast_reg   <= 1'b1;
                            m_tuser_reg   <= eq_bad;
                            drop_pend_reg <= drop_rep_reg;
                            eq_rd_reg     <= eq_rd_reg + 1'b1;
                        end
                    endcase
                end
            end
            default: ;
        endcase
    end

    if (rst) begin
        tsq_rd_reg    <= '0;
        buf_rd_reg    <= '0;
        eq_rd_reg     <= '0;
        ts_idx_reg    <= '0;
        tr_idx_reg    <= '0;
        drop_pend_reg <= '0;
        drop_rep_reg  <= '0;
        m_tvalid_reg  <= 1'b0;
        m_tlast_reg   <= 1'b0;
        m_tuser_reg   <= 1'b0;
    end
end

assign m_axis.tdata  = m_tdata_reg;
assign m_axis.tkeep  = 1'b1;
assign m_axis.tstrb  = 1'b1;
assign m_axis.tvalid = m_tvalid_reg;
assign m_axis.tlast  = m_tlast_reg;
assign m_axis.tid    = '0;
assign m_axis.tdest  = '0;
assign m_axis.tuser  = m_tuser_reg;

endmodule

`resetall
