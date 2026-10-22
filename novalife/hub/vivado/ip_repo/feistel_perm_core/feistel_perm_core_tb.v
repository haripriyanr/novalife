`timescale 1ns / 1ps
module feistel_perm_core_tb;
`include "fp_params.vh"
    reg clk = 0, rst_n = 0, start = 0;
    reg [127:0] key = 0; reg [23:0] m = 1, slot = 0;
    wire [23:0] bidx; wire done;
    feistel_perm_core dut(.clk(clk), .rst_n(rst_n), .start(start), .key(key), .m(m), .slot(slot),
                          .block_idx(bidx), .done(done));
    always #5 clk = ~clk;
    reg [127:0] keys [0:FP_NUM_VECTORS-1];
    reg [31:0] ms [0:FP_NUM_VECTORS-1], slots [0:FP_NUM_VECTORS-1], exps [0:FP_NUM_VECTORS-1];
    integer v, errors, timeout, maxcyc;
    initial begin
        $readmemh("fp_key.mem", keys); $readmemh("fp_m.mem", ms); $readmemh("fp_slot.mem", slots); $readmemh("fp_exp.mem", exps);
        errors = 0; maxcyc = 0;
        repeat (4) @(posedge clk); rst_n = 1; @(negedge clk);
        for (v = 0; v < FP_NUM_VECTORS; v = v + 1) begin
            key = keys[v]; m = ms[v][23:0]; slot = slots[v][23:0];
            start = 1; @(negedge clk); start = 0;
            timeout = 0;
            while (!done && timeout < 200000) begin @(negedge clk); timeout = timeout + 1; end
            if (timeout > maxcyc) maxcyc = timeout;
            if (!done || bidx !== exps[v][23:0]) begin
                errors = errors + 1;
                if (errors < 10) $display("FAIL vec %0d: m=%0d slot=%0d got %0d exp %0d done=%b", v, m, slot, bidx, exps[v][23:0], done);
            end
            @(negedge clk);
        end
        if (errors == 0) $display("feistel_perm_core_tb: PASS (%0d vectors, worst %0d cycles)", FP_NUM_VECTORS, maxcyc);
        else $display("feistel_perm_core_tb: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
