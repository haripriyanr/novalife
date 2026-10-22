// Self-checking testbench for iiwt_53_core — the inverse of the 12 frozen IWT line vectors.
//
// For every line in iwt_line_{len,s,d,in}.mem (tools/tag_reference/vectors/gen_iwt_vectors.py,
// produced by iwt_lifting.iwt1d_53), feed s then d and require the core to emit the original
// samples exactly (perfect reconstruction == iiwt1d_53), at the right index, exactly once each.
// Run via `vivado/scripts/run_sim.sh iiwt_53_core`.

`timescale 1ns / 1ps
`include "iwt_params.vh"

module iiwt_53_core_tb;

    localparam integer NL   = IWT_NLINES;
    localparam integer MAXL = IWT_MAX_LEN;
    localparam integer MK   = IWT_MAXK;

    reg clk = 1'b0, rst_n = 1'b0, start = 1'b0, valid_in = 1'b0;
    reg signed [17:0] coeff_in = 18'sd0;
    reg [9:0] len = 10'd0;
    wire ready_in, valid_out, done;
    wire signed [15:0] sample_out;
    wire [8:0] sample_idx;

    iiwt_53_core #(.DATA_WIDTH(16), .MAX_LOG2(9)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .len(len),
        .coeff_in(coeff_in), .valid_in(valid_in), .ready_in(ready_in),
        .sample_out(sample_out), .valid_out(valid_out), .sample_idx(sample_idx),
        .done(done)
    );

    always #5 clk = ~clk;

    reg [31:0] len_mem [0:NL-1];
    reg [31:0] s_mem   [0:NL*MK-1];
    reg [31:0] d_mem   [0:NL*MK-1];
    reg [31:0] x_mem   [0:NL*MAXL-1];

    integer l, k, n, K, errors, seen, timeout;
    reg [MAXL-1:0] got_mask;

    // collect outputs on every rising edge
    always @(posedge clk) begin
        if (valid_out) begin
            if (sample_idx >= n) begin
                errors = errors + 1;
                $display("FAIL line %0d: index %0d out of range (len %0d)", l, sample_idx, n);
            end else begin
                if (got_mask[sample_idx]) begin
                    errors = errors + 1;
                    $display("FAIL line %0d: index %0d emitted twice", l, sample_idx);
                end
                got_mask[sample_idx] = 1'b1;
                if (sample_out !== $signed(x_mem[l*MAXL + sample_idx][15:0])) begin
                    errors = errors + 1;
                    $display("FAIL line %0d idx %0d: got %0d exp %0d", l, sample_idx,
                             sample_out, $signed(x_mem[l*MAXL + sample_idx][15:0]));
                end
            end
            seen = seen + 1;
        end
    end

    initial begin
        errors = 0;
        $readmemh("iwt_line_len.mem", len_mem);
        $readmemh("iwt_line_s.mem", s_mem);
        $readmemh("iwt_line_d.mem", d_mem);
        $readmemh("iwt_line_in.mem", x_mem);

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        for (l = 0; l < NL; l = l + 1) begin
            n = len_mem[l];
            K = n / 2;
            seen = 0;
            got_mask = {MAXL{1'b0}};

            start = 1'b1; len = n[9:0];
            @(negedge clk);
            start = 1'b0;

            for (k = 0; k < n; k = k + 1) begin
                coeff_in = (k < K) ? s_mem[l*MK + k][17:0] : d_mem[l*MK + (k - K)][17:0];
                valid_in = 1'b1;
                timeout = 0;
                while (!ready_in && timeout < 100) begin
                    @(negedge clk); timeout = timeout + 1;
                end
                @(negedge clk);
            end
            valid_in = 1'b0;

            timeout = 0;
            while (!done && timeout < 4 * MAXL) begin
                @(negedge clk); timeout = timeout + 1;
            end
            if (!done) begin
                errors = errors + 1;
                $display("FAIL line %0d: no done", l);
            end
            @(negedge clk);
            if (seen != n) begin
                errors = errors + 1;
                $display("FAIL line %0d: %0d samples emitted, expected %0d", l, seen, n);
            end
        end

        if (errors == 0)
            $display("iiwt_53_core_tb: PASS (%0d lines, perfect reconstruction of every iwt1d_53 vector)", NL);
        else
            $display("iiwt_53_core_tb: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
