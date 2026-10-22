`timescale 1ns / 1ps
// Chains roi_cut_core (pass 1) and intake_floor_core (pass 2) and compares every output pixel
// with embed.floor_background (vectors from gen_roi_cut_vectors.py).
module intake_floor_core_tb;
`include "roi_params.vh"
    reg clk = 0, rst_n = 0, clear = 0, pix_valid = 0, fin = 0;
    reg [7:0] pix = 0;
    wire done; wire [8:0] cut;
    roi_cut_core rc(.clk(clk), .rst_n(rst_n), .clear(clear), .pix_valid(pix_valid), .pix(pix),
                    .fin(fin), .done(done), .cut(cut));
    reg [7:0] pin = 0; reg vin = 0;
    wire [7:0] pout; wire vout;
    intake_floor_core fl(.clk(clk), .rst_n(rst_n), .cut(cut), .pixel_in(pin), .valid_in(vin),
                         .ready_out(), .pixel_out(pout), .valid_out(vout), .ready_in(1'b1));
    always #5 clk = ~clk;
    reg [31:0] lens [0:ROI_NUM_VECTORS-1];
    reg [7:0]  pixs [0:ROI_TOTAL_PIX-1];
    reg [7:0]  flo  [0:ROI_TOTAL_PIX-1];
    integer v, i, base, errors, timeout, got;
    initial begin
        $readmemh("roi_len.mem", lens); $readmemh("roi_pix.mem", pixs); $readmemh("roi_floored.mem", flo);
        errors = 0; base = 0;
        repeat (4) @(posedge clk); rst_n = 1; @(negedge clk);
        for (v = 0; v < ROI_NUM_VECTORS; v = v + 1) begin
            clear = 1; @(negedge clk); clear = 0;
            for (i = 0; i < lens[v]; i = i + 1) begin pix = pixs[base+i]; pix_valid = 1; @(negedge clk); end
            pix_valid = 0; fin = 1; @(negedge clk); fin = 0;
            timeout = 0; while (!done && timeout < 5000) begin @(negedge clk); timeout = timeout + 1; end
            // pass 2
            got = 0;
            for (i = 0; i < lens[v] + 2; i = i + 1) begin
                if (i < lens[v]) begin pin = pixs[base+i]; vin = 1; end else vin = 0;
                @(posedge clk); #1;
                if (vout) begin
                    if (pout !== flo[base+got]) begin
                        errors = errors + 1;
                        if (errors < 10) $display("FAIL vec %0d px %0d: got %0d exp %0d", v, got, pout, flo[base+got]);
                    end
                    got = got + 1;
                end
            end
            if (got != lens[v]) begin errors = errors + 1; $display("FAIL vec %0d: %0d of %0d pixels", v, got, lens[v]); end
            vin = 0; @(negedge clk); base = base + lens[v];
        end
        if (errors == 0) $display("intake_floor_core_tb: PASS (%0d vectors, %0d pixels, cut + floor)", ROI_NUM_VECTORS, ROI_TOTAL_PIX);
        else $display("intake_floor_core_tb: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
