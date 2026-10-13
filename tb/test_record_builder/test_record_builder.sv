// Testbench wrapper for record_builder

`resetall
`timescale 1ns / 1ps
`default_nettype none

module test_record_builder #(
    parameter int SNAPLEN = 64
)
();

logic        clk;
logic        rst;
logic        fifo_good;
logic        fifo_overflow;
logic [47:0] ts_count;
logic        overflow;

taxi_axis_if #(.DATA_W(8), .USER_EN(1), .USER_W(1)) s_axis(), m_axis();

record_builder #(
    .SNAPLEN(SNAPLEN)
)
uut (
    .clk(clk),
    .rst(rst),
    .s_axis(s_axis),
    .m_axis(m_axis),
    .fifo_good(fifo_good),
    .fifo_overflow(fifo_overflow),
    .ts_count(ts_count),
    .overflow(overflow)
);

endmodule

`resetall
