// Testbench wrapper for async_frame_fifo

`resetall
`timescale 1ns / 1ps
`default_nettype none

module test_async_frame_fifo #(
    parameter int DEPTH = 256
)
();

logic s_clk;
logic s_rst;
logic m_clk;
logic m_rst;

taxi_axis_if #(.DATA_W(8), .USER_EN(1), .USER_W(1)) s_axis(), m_axis();

logic s_status_good_frame;
logic s_status_bad_frame;
logic s_status_overflow;

async_frame_fifo #(
    .DEPTH(DEPTH)
)
uut (
    .s_clk(s_clk),
    .s_rst(s_rst),
    .s_axis(s_axis),
    .m_clk(m_clk),
    .m_rst(m_rst),
    .m_axis(m_axis),
    .s_status_good_frame(s_status_good_frame),
    .s_status_bad_frame(s_status_bad_frame),
    .s_status_overflow(s_status_overflow)
);

endmodule

`resetall
