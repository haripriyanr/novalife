// Polar Encoder (N=256, K=128) — bit-exact against tools/stego_research/sims/polar_codec.py
//
// Bit-order contract (generated, see tools/tag_reference/vectors/polar_params.vh):
//   bit j of a vector is x[j]; int = sum(x[j] << j)  (bit 0 is the LSB).
//
// The reference is `polar_codec.polar_encode`:
//     u = 0; u[RELIABLE_INDICES] = info_bits; codeword = polar_transform(u)
// where `polar_transform` is the in-place fast transform:
//     step = 1; while step < N: for each block of 2*step: x[j] ^= x[j+step]
//
// This core reproduces that exactly, using the generated `polar_info_pos()` map instead
// of a hard-coded index list.  It replaces an earlier version that (a) implemented only 3
// of the 8 transform stages, (b) mapped the 128 info bits to channels 0..127 instead of
// the reliable set, and (c) mixed blocking and non-blocking assignments in one clocked
// block — so its output was not trusted (see AGENTS.md section 0.4).  Behaviour is now
// fixed by the conformance vectors, not by inspection.

`timescale 1ns / 1ps
`include "polar_params.vh"

module polar_encoder #(
    parameter N = 256,
    parameter K = 128
)(
    input  wire           clk,
    input  wire           rst_n,

    input  wire [K-1:0]   info_bits_in,
    input  wire           valid_in,
    output wire           ready_out,

    output reg  [N-1:0]   encoded_bits_out,
    output reg            valid_out
);

    localparam integer LOG2N = 8;  // N = 256

    assign ready_out = 1'b1;  // combinational transform: always able to accept a new word

    // --- 1. place the K info bits on the reliable channels -----------------------------
    reg [N-1:0] u;
    integer i;
    reg [7:0] pos;
    always @(*) begin
        u = {N{1'b0}};
        for (i = 0; i < N; i = i + 1) begin
            pos = polar_info_pos(i[7:0]);
            if (pos != 8'hFF)
                u[i] = info_bits_in[pos];
        end
    end

    // --- 2. in-place fast polar transform (8 stages) ------------------------------------
    reg [N-1:0] x;
    integer s, blk, j, step;
    always @(*) begin
        x = u;
        step = 1;
        for (s = 0; s < LOG2N; s = s + 1) begin
            for (blk = 0; blk < N; blk = blk + 2 * step) begin
                for (j = blk; j < blk + step; j = j + 1) begin
                    x[j] = x[j] ^ x[j + step];
                end
            end
            step = step * 2;
        end
    end

    // --- 3. register the output (one-cycle latency; valid aligned) ----------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            encoded_bits_out <= {N{1'b0}};
            valid_out        <= 1'b0;
        end else begin
            valid_out        <= valid_in;
            if (valid_in)
                encoded_bits_out <= x;
        end
    end

endmodule
