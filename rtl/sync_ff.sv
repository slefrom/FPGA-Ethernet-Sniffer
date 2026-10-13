// N-stage flip-flop synchroniser.

`resetall
`timescale 1ns / 1ps
`default_nettype none

module sync_ff #(
    parameter int WIDTH = 1,
    parameter int N     = 2
)
(
    input  wire logic              clk,
    input  wire logic              rst,     
    input  wire logic [WIDTH-1:0]  in,
    output wire logic [WIDTH-1:0]  out
);

(* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] sync_reg [N];

always_ff @(posedge clk) begin
    sync_reg[0] <= in;
    for (int i = 1; i < N; i++)
        sync_reg[i] <= sync_reg[i-1];
    if (rst) begin
        for (int i = 0; i < N; i++)
        sync_reg[i] <= '0;
    end
end

assign out = sync_reg[N-1];

endmodule

`resetall
