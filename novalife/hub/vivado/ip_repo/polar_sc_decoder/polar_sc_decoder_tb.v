// Self-checking testbench for polar_sc_decoder — bit-exact against the integer contract.
//
// Reads `polar_dec_llr.mem` / `polar_dec_info.mem` (from
// tools/tag_reference/vectors/gen_polar_decode_vectors.py), loads each 256-LLR case, runs
// the decoder, and FAILS if any of the 128 info bits differs.
// Run via `vivado/scripts/run_sim.sh polar_sc_decoder`.

`timescale 1ns / 1ps
`include "polar_params.vh"
`include "polar_dec_params.vh"

module polar_sc_decoder_tb;

    localparam integer NV = POLAR_DEC_NUM_VECTORS;
    localparam integer W  = POLAR_DEC_WIDTH;

    reg                    clk = 1'b0;
    reg                    rst_n = 1'b0;
    reg                    wr_en = 1'b0;
    reg  [7:0]             wr_addr = 8'd0;
    reg  signed [W-1:0]    wr_llr = {W{1'b0}};
    reg                    start = 1'b0;
    wire                   busy;
    wire                   done;
    wire [127:0]           info_bits_out;

    reg  signed [W-1:0]    llr_mem [0:NV*256-1];
    reg                    info_mem [0:NV*128-1];

    reg [127:0] expected;
    reg [127:0] got;
    integer     c, k, errors, timeout;

    polar_sc_decoder #(.N(256), .K(128), .W(W)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_llr(wr_llr),
        .start(start),
        .busy(busy),
        .done(done),
        .info_bits_out(info_bits_out)
    );

    always #5 clk = ~clk;

    initial begin
        errors = 0;
        $readmemh("polar_dec_llr.mem", llr_mem);
        $readmemh("polar_dec_info.mem", info_mem);

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        for (c = 0; c < NV; c = c + 1) begin
            // load 256 channel LLRs (index = channel)
            for (k = 0; k < 256; k = k + 1) begin
                wr_en   = 1'b1;
                wr_addr = k[7:0];
                wr_llr  = llr_mem[c*256 + k];
                @(negedge clk);
            end
            wr_en = 1'b0;
            @(negedge clk);

            // pulse start
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            // wait for done.  The memory-backed microsequencer walks the tree one element at a
            // time, so a codeword is ~460k cycles (structural: the same for every vector) rather
            // than the ~thousands of an all-register version.  Budget well above that.
            timeout = 0;
            while (!done && (timeout < 800000)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!done) begin
                errors = errors + 1;
                $display("FAIL case %0d: timeout after %0d cycles", c, timeout);
            end

            expected = 128'h0;
            for (k = 0; k < 128; k = k + 1)
                if (info_mem[c*128 + k]) expected[k] = 1'b1;
            got = info_bits_out;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL case %0d: got=%h exp=%h (mismatch bits=%0d)",
                         c, got, expected,
                         $countones(got ^ expected));
            end

            @(negedge clk);  // let done clear
        end

        if (errors == 0)
            $display("polar_sc_decoder_tb: PASS (%0d vectors, bit-exact vs integer SC contract)",
                     NV);
        else
            $display("polar_sc_decoder_tb: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
