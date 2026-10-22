// Self-checking testbench for iwt_53_core — bit-exact against
// tools/stego_research/sims/iwt_lifting.py
//
//   part 1: the 1D kernel against `iwt1d_53` on the line vectors;
//   part 2: the 2D transform, composed here exactly as the reference composes it
//           (`iwt2d_53`: rows with one core, then columns of the row-low and row-high
//           results with a second core), checked sub-band by sub-band against `iwt2d_53`.
//           The 8x16 frame is deliberately non-square: a row/column swap in this harness
//           does not survive it.
//
// Run: vivado/scripts/run_sim.sh iwt_53_core

`timescale 1ns / 1ps
`include "iwt_params.vh"

module iwt_53_core_tb;

    localparam integer ML     = IWT_MAX_LOG2;
    localparam integer MAX_LEN = IWT_MAX_LEN;
    localparam integer MAXK   = IWT_MAXK;
    localparam integer NL     = IWT_NLINES;
    localparam integer DW     = IWT_DATA_W;
    localparam integer CW     = IWT_COEFF_W;
    localparam integer CW2    = IWT_COEFF2_W;
    localparam integer NF     = IWT_MAX_FRAMES;
    localparam integer MAXH   = IWT_MAX_H;
    localparam integer MAXW   = IWT_MAX_W;
    localparam integer FWORDS = IWT_FRAME_WORDS;
    localparam integer SWORDS = IWT_SUB_WORDS;
    localparam integer SW_    = MAXW / 2;      // sub-band row stride (both frames are 16 wide)

    reg clk = 0;
    reg rst_n = 0;

    // ---- row core (16-bit samples) ----
    reg                  start_r = 0;
    reg [ML:0]           len_r = 0;
    reg signed [DW-1:0]  sample_r = 0;
    reg                  valid_r = 0;
    wire                 ready_r;
    wire signed [CW-1:0] s_r, d_r;
    wire                 svalid_r, dvalid_r;
    wire [ML-2:0]        sidx_r, didx_r;
    wire                 done_r;

    // ---- column core (18-bit samples = the row core's output) ----
    reg                  start_c = 0;
    reg [ML:0]           len_c = 0;
    reg signed [CW-1:0]  sample_c = 0;
    reg                  valid_c = 0;
    wire                 ready_c;
    wire signed [CW2-1:0] s_c, d_c;
    wire                  svalid_c, dvalid_c;
    wire [ML-2:0]         sidx_c, didx_c;
    wire                  done_c;

    iwt_53_core #(.DATA_WIDTH(DW), .MAX_LOG2(ML)) u_row (
        .clk(clk), .rst_n(rst_n), .start(start_r), .len(len_r),
        .sample_in(sample_r), .valid_in(valid_r), .ready_in(ready_r),
        .d_out(d_r), .d_valid(dvalid_r), .d_idx(didx_r),
        .s_out(s_r), .s_valid(svalid_r), .s_idx(sidx_r), .done(done_r)
    );

    iwt_53_core #(.DATA_WIDTH(CW), .MAX_LOG2(ML)) u_col (
        .clk(clk), .rst_n(rst_n), .start(start_c), .len(len_c),
        .sample_in(sample_c), .valid_in(valid_c), .ready_in(ready_c),
        .d_out(d_c), .d_valid(dvalid_c), .d_idx(didx_c),
        .s_out(s_c), .s_valid(svalid_c), .s_idx(sidx_c), .done(done_c)
    );

    always #5 clk = ~clk;

    // ---- vectors ----
    reg [31:0] line_len_mem [0:NL-1];
    reg [31:0] line_in_mem  [0:NL*MAX_LEN-1];
    reg [31:0] line_s_mem   [0:NL*MAXK-1];
    reg [31:0] line_d_mem   [0:NL*MAXK-1];
    reg [31:0] frame_spec_mem [0:2*NF-1];
    reg [31:0] frame_in_mem   [0:NF*FWORDS-1];
    reg [31:0] frame_sub_mem  [0:NF*4*SWORDS-1];

    // ---- captured coefficients (sign-extended to 32 bits) ----
    reg [31:0] tmp_s [0:MAXK-1];
    reg [31:0] tmp_d [0:MAXK-1];
    reg [31:0] tmp_cs [0:MAXK-1];
    reg [31:0] tmp_cd [0:MAXK-1];

    reg [31:0] rs [0:MAXH*SW_-1];
    reg [31:0] rd [0:MAXH*SW_-1];
    reg [31:0] LL [0:SWORDS-1];
    reg [31:0] LH [0:SWORDS-1];
    reg [31:0] HL [0:SWORDS-1];
    reg [31:0] HH [0:SWORDS-1];

    always @(posedge clk) begin
        if (dvalid_r) tmp_d[didx_r]   = {{(32-CW){d_r[CW-1]}}, d_r};
        if (svalid_r) tmp_s[sidx_r]   = {{(32-CW){s_r[CW-1]}}, s_r};
        if (dvalid_c) tmp_cd[didx_c]  = {{(32-CW2){d_c[CW2-1]}}, d_c};
        if (svalid_c) tmp_cs[sidx_c]  = {{(32-CW2){s_c[CW2-1]}}, s_c};
    end

    integer i, tmo, errors;
    integer li, f, r, c, k, ln, hh, ww, sw, sh, idx;

    // drive one line into the row core; src 0 = line_in_mem, 1 = frame_in_mem
    task run_row;
        input integer length;
        input integer base;
        input integer src;
        begin
            @(negedge clk);
            start_r = 1; len_r = length;
            @(negedge clk);
            start_r = 0;
            for (i = 0; i < length; i = i + 1) begin
                @(negedge clk);
                while (!ready_r) @(negedge clk);
                sample_r = (src == 0) ? line_in_mem[base + i] : frame_in_mem[base + i];
                valid_r  = 1;
                @(negedge clk);
                valid_r  = 0;
            end
            tmo = 0;
            while (!done_r && tmo < 200000) begin @(negedge clk); tmo = tmo + 1; end
            if (!done_r) begin
                errors = errors + 1;
                $display("FAIL row line: timeout (len %0d)", length);
            end
        end
    endtask

    // drive one column of rs (src 0) or rd (src 1) into the column core
    task run_col;
        input integer length;
        input integer col;
        input integer src;
        begin
            @(negedge clk);
            start_c = 1; len_c = length;
            @(negedge clk);
            start_c = 0;
            for (i = 0; i < length; i = i + 1) begin
                @(negedge clk);
                while (!ready_c) @(negedge clk);
                sample_c = (src == 0) ? rs[i*SW_ + col] : rd[i*SW_ + col];
                valid_c  = 1;
                @(negedge clk);
                valid_c  = 0;
            end
            tmo = 0;
            while (!done_c && tmo < 200000) begin @(negedge clk); tmo = tmo + 1; end
            if (!done_c) begin
                errors = errors + 1;
                $display("FAIL column line: timeout (len %0d)", length);
            end
            @(negedge clk);
        end
    endtask

    initial begin
        errors = 0;

        $readmemh("iwt_line_len.mem",   line_len_mem);
        $readmemh("iwt_line_in.mem",    line_in_mem);
        $readmemh("iwt_line_s.mem",     line_s_mem);
        $readmemh("iwt_line_d.mem",     line_d_mem);
        $readmemh("iwt_frame_spec.mem", frame_spec_mem);
        $readmemh("iwt_frame_in.mem",   frame_in_mem);
        $readmemh("iwt_frame_sub.mem",  frame_sub_mem);

        repeat (3) @(posedge clk);
        rst_n = 1;
        @(negedge clk);

        // ---------------- part 1: the 1D kernel ----------------
        for (li = 0; li < NL; li = li + 1) begin
            ln = line_len_mem[li];
            for (k = 0; k < MAXK; k = k + 1) begin tmp_s[k] = 0; tmp_d[k] = 0; end
            run_row(ln, li*MAX_LEN, 0);
            for (k = 0; k < (ln/2); k = k + 1) begin
                if (tmp_s[k] !== line_s_mem[li*MAXK + k]) begin
                    errors = errors + 1;
                    $display("FAIL line %0d (len %0d): s[%0d] got %08x exp %08x",
                             li, ln, k, tmp_s[k], line_s_mem[li*MAXK + k]);
                end
                if (tmp_d[k] !== line_d_mem[li*MAXK + k]) begin
                    errors = errors + 1;
                    $display("FAIL line %0d (len %0d): d[%0d] got %08x exp %08x",
                             li, ln, k, tmp_d[k], line_d_mem[li*MAXK + k]);
                end
            end
        end

        // ---------------- part 2: the 2D transform ----------------
        for (f = 0; f < NF; f = f + 1) begin
            hh = frame_spec_mem[f*2];
            ww = frame_spec_mem[f*2 + 1];
            sw = ww / 2;
            sh = hh / 2;

            // rows: source pixels -> rs (low) / rd (high)
            for (r = 0; r < hh; r = r + 1) begin
                for (k = 0; k < MAXK; k = k + 1) begin tmp_s[k] = 0; tmp_d[k] = 0; end
                run_row(ww, f*FWORDS + r*MAXW, 1);
                for (c = 0; c < sw; c = c + 1) begin
                    rs[r*SW_ + c] = tmp_s[c];
                    rd[r*SW_ + c] = tmp_d[c];
                end
            end

            // columns of rs -> LL (low) / LH (high)
            for (c = 0; c < sw; c = c + 1) begin
                for (k = 0; k < MAXK; k = k + 1) begin tmp_cs[k] = 0; tmp_cd[k] = 0; end
                run_col(hh, c, 0);
                for (k = 0; k < sh; k = k + 1) begin
                    LL[k*SW_ + c] = tmp_cs[k];
                    LH[k*SW_ + c] = tmp_cd[k];
                end
            end

            // columns of rd -> HL (low) / HH (high)
            for (c = 0; c < sw; c = c + 1) begin
                for (k = 0; k < MAXK; k = k + 1) begin tmp_cs[k] = 0; tmp_cd[k] = 0; end
                run_col(hh, c, 1);
                for (k = 0; k < sh; k = k + 1) begin
                    HL[k*SW_ + c] = tmp_cs[k];
                    HH[k*SW_ + c] = tmp_cd[k];
                end
            end

            for (idx = 0; idx < sh*sw; idx = idx + 1) begin
                if (LL[idx] !== frame_sub_mem[(f*4+0)*SWORDS + idx]) begin
                    errors = errors + 1;
                    $display("FAIL frame %0d (%0dx%0d): LL[%0d] got %08x exp %08x",
                             f, hh, ww, idx, LL[idx], frame_sub_mem[(f*4+0)*SWORDS + idx]);
                end
                if (LH[idx] !== frame_sub_mem[(f*4+1)*SWORDS + idx]) begin
                    errors = errors + 1;
                    $display("FAIL frame %0d (%0dx%0d): LH[%0d] got %08x exp %08x",
                             f, hh, ww, idx, LH[idx], frame_sub_mem[(f*4+1)*SWORDS + idx]);
                end
                if (HL[idx] !== frame_sub_mem[(f*4+2)*SWORDS + idx]) begin
                    errors = errors + 1;
                    $display("FAIL frame %0d (%0dx%0d): HL[%0d] got %08x exp %08x",
                             f, hh, ww, idx, HL[idx], frame_sub_mem[(f*4+2)*SWORDS + idx]);
                end
                if (HH[idx] !== frame_sub_mem[(f*4+3)*SWORDS + idx]) begin
                    errors = errors + 1;
                    $display("FAIL frame %0d (%0dx%0d): HH[%0d] got %08x exp %08x",
                             f, hh, ww, idx, HH[idx], frame_sub_mem[(f*4+3)*SWORDS + idx]);
                end
            end
        end

        if (errors == 0)
            $display("iwt_53_core_tb: PASS (%0d 1D lines bit-exact vs iwt1d_53, %0d frames bit-exact vs iwt2d_53)",
                     NL, NF);
        else
            $display("iwt_53_core_tb: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
