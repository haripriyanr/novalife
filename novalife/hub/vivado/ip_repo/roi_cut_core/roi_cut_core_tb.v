`timescale 1ns / 1ps
module roi_cut_core_tb;
`include "roi_params.vh"
    reg clk = 0, rst_n = 0, clear = 0, pix_valid = 0, fin = 0;
    reg [7:0] pix = 0;
    wire done; wire [8:0] cut;
    roi_cut_core dut(.clk(clk), .rst_n(rst_n), .clear(clear), .pix_valid(pix_valid), .pix(pix),
                     .fin(fin), .done(done), .cut(cut));
    always #5 clk = ~clk;
    reg [31:0] lens [0:ROI_NUM_VECTORS-1];
    reg [7:0]  pixs [0:ROI_TOTAL_PIX-1];
    reg [8:0]  exps [0:ROI_NUM_VECTORS-1];
    integer v, i, base, errors, timeout;
    initial begin
        $readmemh("roi_len.mem", lens); $readmemh("roi_pix.mem", pixs); $readmemh("roi_exp.mem", exps);
        errors = 0; base = 0;
        repeat (4) @(posedge clk); rst_n = 1; @(negedge clk);
        for (v = 0; v < ROI_NUM_VECTORS; v = v + 1) begin
            clear = 1; @(negedge clk); clear = 0;
            for (i = 0; i < lens[v]; i = i + 1) begin
                pix = pixs[base + i]; pix_valid = 1; @(negedge clk);
            end
            pix_valid = 0; fin = 1; @(negedge clk); fin = 0;
            timeout = 0;
            while (!done && timeout < 5000) begin @(negedge clk); timeout = timeout + 1; end
            if (!done || cut !== exps[v]) begin
                errors = errors + 1;
                $display("FAIL vec %0d: len=%0d got cut=%0d done=%b exp=%0d", v, lens[v], cut, done, exps[v]);
            end
            base = base + lens[v];
        end
        if (errors == 0) $display("roi_cut_core_tb: PASS (%0d vectors, %0d pixels)", ROI_NUM_VECTORS, ROI_TOTAL_PIX);
        else $display("roi_cut_core_tb: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
