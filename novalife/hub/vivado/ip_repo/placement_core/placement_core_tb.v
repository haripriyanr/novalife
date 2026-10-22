`timescale 1ns / 1ps
module placement_core_tb;
`include "pl_params.vh"
    reg clk = 0, rst_n = 0, start = 0, erasure = 0;
    reg [127:0] key = 0; reg [23:0] m = 1; reg [2:0] copies = 1;
    wire [23:0] blk_addr; reg taint_q1 = 0, taint_q2 = 0;
    wire out_valid; wire [1:0] out_copy; wire [7:0] out_bit; wire [23:0] out_block;
    wire copy_fail, done;
    reg [7:0] taint_mem [0:PL_TOTAL_TAINT-1];
    reg [31:0] meta [0:4*PL_NUM_CASES-1];
    reg [127:0] keys [0:PL_NUM_CASES-1];
    reg [23:0] exps [0:PL_TOTAL_EXP-1];
    integer taint_base = 0, exp_base = 0;
    always @(posedge clk) begin
        taint_q1 <= (blk_addr < m) ? taint_mem[taint_base + blk_addr][0] : 1'b1;
        taint_q2 <= taint_q1;
    end
    placement_core #(.MAX_M(65536)) dut(.clk(clk), .rst_n(rst_n), .start(start), .key(key), .m(m),
        .copies(copies), .erasure_mode(erasure), .blk_addr(blk_addr), .blk_taint(taint_q1),
        .out_valid(out_valid), .out_copy(out_copy), .out_bit(out_bit), .out_block(out_block),
        .copy_fail(copy_fail), .done(done));
    always #5 clk = ~clk;
    integer cs, n, errors, nrec, timeout, tot_cycles;
    initial begin
        $readmemh("pl_case.mem", meta); $readmemh("pl_key.mem", keys); $readmemh("pl_taint.mem", taint_mem);
        $readmemh("pl_exp.mem", exps);
        errors = 0;
        repeat (4) @(posedge clk); rst_n = 1; @(negedge clk);
        for (cs = 0; cs < PL_NUM_CASES; cs = cs + 1) begin
            key = keys[cs]; m = meta[4*cs][23:0]; erasure = meta[4*cs+1][0]; copies = meta[4*cs+2][2:0];
            nrec = meta[4*cs+3]; n = 0; timeout = 0;
            start = 1; @(negedge clk); start = 0;
            while (!done && timeout < 40000000) begin
                @(negedge clk); timeout = timeout + 1;
                if (out_valid) begin
                    if (n >= nrec) begin errors = errors + 1; $display("FAIL case %0d: extra record", cs); end
                    else if (out_block !== exps[exp_base + n]) begin
                        errors = errors + 1;
                        if (errors < 10) $display("FAIL case %0d rec %0d (copy %0d bit %0d): got %0d exp %0d", cs, n, out_copy, out_bit, out_block, exps[exp_base+n]);
                    end
                    n = n + 1;
                end
            end
            if (!done) begin errors = errors + 1; $display("FAIL case %0d: timeout", cs); end
            // encoder mode: records of a failing copy are streamed before copy_fail; the expected
            // list contains complete copies only, so allow the partial copy's extra records
            if (n < nrec || (erasure && n != nrec)) begin errors = errors + 1; $display("FAIL case %0d: %0d of %0d records", cs, n, nrec); end
            $display("  case %0d: m=%0d erasure=%0d copies=%0d records=%0d cycles=%0d", cs, m, erasure, copies, n, timeout);
            taint_base = taint_base + (m); exp_base = exp_base + nrec;
            @(negedge clk);
        end
        if (errors == 0) $display("placement_core_tb: PASS (%0d cases, %0d records)", PL_NUM_CASES, PL_TOTAL_EXP);
        else $display("placement_core_tb: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
