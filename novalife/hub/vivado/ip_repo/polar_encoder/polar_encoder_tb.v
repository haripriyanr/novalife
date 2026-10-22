// Self-checking testbench for polar_encoder — bit-exact against the Python reference.
//
// Reads the generating vectors (`polar_enc_info.mem`, `polar_enc_code.mem`) that
// tools/tag_reference/vectors/gen_polar_vectors.py produced from
// tools/stego_research/sims/polar_codec.py, drives every case, and FAILS if any
// codeword differs.  Run via `vivado/scripts/run_sim.sh polar_encoder`.

`timescale 1ns / 1ps
`include "polar_params.vh"

module polar_encoder_tb;

    reg          clk = 1'b0;
    reg          rst_n = 1'b0;
    reg  [127:0] info_bits_in = 128'h0;
    reg          valid_in = 1'b0;
    wire         ready_out;
    wire [255:0] encoded_bits_out;
    wire         valid_out;

    reg [127:0] info_mem [0:POLAR_NUM_VECTORS-1];
    reg [255:0] code_mem [0:POLAR_NUM_VECTORS-1];

    integer idx;
    integer errors;

    polar_encoder uut (
        .clk(clk),
        .rst_n(rst_n),
        .info_bits_in(info_bits_in),
        .valid_in(valid_in),
        .ready_out(ready_out),
        .encoded_bits_out(encoded_bits_out),
        .valid_out(valid_out)
    );

    always #5 clk = ~clk;

    initial begin
        errors = 0;
        $readmemh("polar_enc_info.mem", info_mem);
        $readmemh("polar_enc_code.mem", code_mem);

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        for (idx = 0; idx < POLAR_NUM_VECTORS; idx = idx + 1) begin
            info_bits_in = info_mem[idx];
            valid_in     = 1'b1;
            @(negedge clk);            // one posedge has now sampled the input word
            valid_in     = 1'b0;
            if (!valid_out || (encoded_bits_out !== code_mem[idx])) begin
                errors = errors + 1;
                $display("FAIL vec %0d: info=%h got=%h exp=%h",
                         idx, info_mem[idx], encoded_bits_out, code_mem[idx]);
            end
            @(negedge clk);
        end

        if (errors == 0)
            $display("polar_encoder_tb: PASS (%0d vectors, bit-exact vs polar_codec.py)",
                     POLAR_NUM_VECTORS);
        else
            $display("polar_encoder_tb: FAIL (%0d/%0d vectors wrong)",
                     errors, POLAR_NUM_VECTORS);
        $finish;
    end

endmodule
