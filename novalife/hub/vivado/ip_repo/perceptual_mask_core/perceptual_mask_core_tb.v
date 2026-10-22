// Self-checking testbench for perceptual_mask_core — bit-exact against
// tools/stego_research/sims/perceptual_mask.mask_block_decision
// (which is generate_perceptual_mask's tile decision: compute_dsp48_variance plus the
//  ROI-majority gate, written without floats).
//
// For every vector: drive BLOCK signed samples with their ROI bits, wait for valid_out,
// then compare the integer variance and the mask bit.
//
// Run: vivado/scripts/run_sim.sh perceptual_mask_core

`timescale 1ns / 1ps
`include "mask_params.vh"

module perceptual_mask_core_tb;

    localparam integer NV    = MASK_NUM_VECTORS;
    localparam integer BLOCK = MASK_BLOCK;
    localparam integer DW    = MASK_DATA_W;

    reg clk = 0;
    reg rst_n = 0;
    reg signed [DW-1:0] sample_in = 0;
    reg roi_mask_in = 0;
    reg valid_in = 0;

    wire                  ready_out;
    wire                  mask_out;
    wire [31:0]           var_out;
    wire                  valid_out;

    reg [DW-1:0] in_mem       [0:NV*BLOCK-1];
    reg [3:0]    roi_mem      [0:NV*BLOCK-1];
    reg [31:0]   exp_var_mem  [0:NV-1];
    reg [3:0]    exp_mask_mem [0:NV-1];

    reg [31:0]   got_var  [0:NV-1];
    reg          got_mask [0:NV-1];

    perceptual_mask_core #(
        .DATA_WIDTH(DW),
        .BLOCK_LOG2($clog2(BLOCK)),
        .VAR_THRESHOLD(MASK_VAR_THRESHOLD)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .sample_in(sample_in),
        .roi_mask_in(roi_mask_in),
        .valid_in(valid_in),
        .ready_out(ready_out),
        .mask_out(mask_out),
        .var_out(var_out),
        .valid_out(valid_out)
    );

    always #5 clk = ~clk;

    integer c, b, timeout, errors, ones, zeros;

    initial begin
        errors = 0;
        ones = 0;
        zeros = 0;

        $readmemh("mask_in.mem", in_mem);
        $readmemh("mask_roi.mem", roi_mem);
        $readmemh("mask_exp_var.mem", exp_var_mem);
        $readmemh("mask_exp_mask.mem", exp_mask_mem);

        repeat (3) @(posedge clk);
        rst_n = 1;
        @(negedge clk);

        for (c = 0; c < NV; c = c + 1) begin
            for (b = 0; b < BLOCK; b = b + 1) begin
                @(negedge clk);
                while (!ready_out) @(negedge clk);   // no byte is offered while computing
                sample_in   = in_mem[c*BLOCK + b];
                roi_mask_in = roi_mem[c*BLOCK + b][0];
                valid_in    = 1;
                @(negedge clk);
                valid_in    = 0;
            end

            timeout = 0;
            while (!valid_out && timeout < 1000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!valid_out) begin
                errors = errors + 1;
                $display("FAIL case %0d: timeout waiting for valid_out", c);
            end

            got_var[c]  = var_out;
            got_mask[c] = mask_out;

            if (var_out !== exp_var_mem[c]) begin
                errors = errors + 1;
                $display("FAIL case %0d: var got %08x exp %08x", c, var_out, exp_var_mem[c]);
            end
            if (mask_out !== exp_mask_mem[c][0]) begin
                errors = errors + 1;
                $display("FAIL case %0d: mask got %0d exp %0d", c, mask_out, exp_mask_mem[c][0]);
            end
            if (mask_out) ones = ones + 1; else zeros = zeros + 1;

            @(negedge clk);
        end

        if (errors == 0)
            $display("perceptual_mask_core_tb: PASS (%0d vectors, %0d mask=1, %0d mask=0, bit-exact vs perceptual_mask.mask_block_decision)",
                     NV, ones, zeros);
        else
            $display("perceptual_mask_core_tb: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
