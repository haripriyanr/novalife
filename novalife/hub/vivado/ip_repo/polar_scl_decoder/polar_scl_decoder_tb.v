// Self-checking testbench for polar_scl_decoder (L=8) — info bits AND winning path metric must
// match the integer contract (gen_polar_scl_vectors.py, itself == polar_scl_decode(llr, 8)).
//
// Reads `polar_scl_llr.mem` / `polar_scl_info.mem` / `polar_scl_pm.mem` (from
// tools/tag_reference/vectors/gen_polar_scl_vectors.py), loads each 256-LLR case, runs
// the decoder, and FAILS if any of the 128 info bits differs.
// Run via `vivado/scripts/run_sim.sh polar_scl_decoder`.

`timescale 1ns / 1ps
`include "polar_params.vh"
`include "polar_scl_params.vh"

module polar_scl_decoder_tb;

    localparam integer NV = POLAR_SCL_NUM_VECTORS;
    localparam integer W  = 16;

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
    reg  [31:0]            pm_mem   [0:NV-1];
    wire [31:0]            pm_out;
    integer                total_cycles;

    reg [127:0] expected;
    reg [127:0] got;
    integer     c, k, errors, timeout;

    polar_scl_decoder #(.N(256), .K(128), .W(W)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_llr(wr_llr),
        .start(start),
        .busy(busy),
        .done(done),
        .info_bits_out(info_bits_out),
        .pm_out(pm_out)
    );

    always #5 clk = ~clk;

    initial begin
        errors = 0;
        $readmemh("polar_scl_llr.mem", llr_mem);
        $readmemh("polar_scl_info.mem", info_mem);
        $readmemh("polar_scl_pm.mem", pm_mem);
        total_cycles = 0;

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
            // time, once per active path, so a codeword is ~2.5M cycles (measured) rather
            // than the ~thousands of an all-register version.  Budget well above that.
            timeout = 0;
            while (!done && (timeout < 6000000)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            total_cycles = total_cycles + timeout;
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

            if (pm_out !== pm_mem[c]) begin
                errors = errors + 1;
                $display("FAIL case %0d: pm got=%0d exp=%0d", c, pm_out, pm_mem[c]);
            end

            @(negedge clk);  // let done clear
        end

        if (errors == 0)
            $display("polar_scl_decoder_tb: PASS (%0d vectors, info bits + path metric bit-exact vs integer SCL L=8 contract; %0d cycles/codeword avg)",
                     NV, total_cycles / NV);
        else
            $display("polar_scl_decoder_tb: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
