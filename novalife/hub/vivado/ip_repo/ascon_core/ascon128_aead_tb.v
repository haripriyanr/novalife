// Self-checking testbench for ascon128_aead — bit-exact against
// tools/tag_reference/ascon_primitives.ascon_aead_encrypt (itself checked against the
// all 1089 official SP 800-232 KAT vectors by ascon_primitives.selftest()).
//
// Loads ascon_meta/ad/pt/ct.mem (one hex byte per line) and, for every case:
//   start -> drive ad_len AD bytes -> ad_done -> drive pt_len PT bytes -> pt_done
//   -> collect the ciphertext words -> wait for done -> compare ciphertext and tag.
// Bytes are only presented while the core's ad_ready / pt_ready is high, so none are
// dropped while the core is running a permutation.
//
// Run: vivado/scripts/run_sim.sh ascon_core ascon128_aead_tb.v

`timescale 1ns / 1ps
`include "ascon_params.vh"

module ascon128_aead_tb;

    localparam integer NV     = ASCON_NUM_VECTORS;
    localparam integer AD_PAD = ASCON_AD_PAD;
    localparam integer PT_PAD = ASCON_PT_PAD;
    localparam integer CT_PAD = ASCON_CT_PAD;
    localparam integer META_B = ASCON_META_BYTES;

    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg [127:0] key = 0;
    reg [127:0] nonce = 0;
    reg [7:0] ad_data = 0;
    reg ad_valid = 0;
    reg ad_done = 0;
    reg [7:0] pt_data = 0;
    reg pt_valid = 0;
    reg pt_done = 0;

    wire [127:0] ct_data;
    wire [4:0]   ct_bytes;
    wire         ct_valid;
    wire [127:0] tag_out;
    wire         done;
    wire         ad_ready;
    wire         pt_ready;

    reg [7:0] meta_mem [0:NV*META_B-1];
    reg [7:0] ad_mem   [0:NV*AD_PAD-1];
    reg [7:0] pt_mem   [0:NV*PT_PAD-1];
    reg [7:0] ct_mem   [0:NV*CT_PAD-1];

    reg [7:0] got_ct [0:NV*PT_PAD-1];

    integer ct_len;          // ciphertext bytes captured for the current case
    integer c, b, j, errors, timeout;
    reg [7:0] adlen, ptlen;
    reg [127:0] exp_tag;

    ascon128_aead uut (
        .clk(clk), .rst_n(rst_n), .start(start), .key(key), .nonce(nonce),
        .ad_data(ad_data), .ad_valid(ad_valid), .ad_done(ad_done),
        .pt_data(pt_data), .pt_valid(pt_valid), .pt_done(pt_done),
        .ct_data(ct_data), .ct_bytes(ct_bytes), .ct_valid(ct_valid),
        .tag_out(tag_out), .done(done),
        .ad_ready(ad_ready), .pt_ready(pt_ready)
    );

    always #5 clk = ~clk;

    // capture ciphertext words as they are produced (big-endian byte order)
    always @(posedge clk) begin
        if (ct_valid && ct_bytes != 5'd0) begin
            for (j = 0; j < ct_bytes; j = j + 1)
                got_ct[ct_len + j] = ct_data[8*(15-j) +: 8];
            ct_len = ct_len + ct_bytes;
        end
    end

    // present one AD byte; the byte is consumed on the next posedge with ad_ready high
    task send_ad;
        input [7:0] d;
        begin
            @(negedge clk);
            while (!ad_ready) @(negedge clk);
            ad_data = d; ad_valid = 1;
            @(negedge clk);
            ad_valid = 0;
        end
    endtask

    task end_ad;
        begin
            @(negedge clk);
            while (!ad_ready) @(negedge clk);
            ad_done = 1;
            @(negedge clk);
            ad_done = 0;
        end
    endtask

    task send_pt;
        input [7:0] d;
        begin
            @(negedge clk);
            while (!pt_ready) @(negedge clk);
            pt_data = d; pt_valid = 1;
            @(negedge clk);
            pt_valid = 0;
        end
    endtask

    task end_pt;
        begin
            @(negedge clk);
            while (!pt_ready) @(negedge clk);
            pt_done = 1;
            @(negedge clk);
            pt_done = 0;
        end
    endtask

    initial begin
        errors = 0;
        $readmemh("ascon_meta.mem", meta_mem);
        $readmemh("ascon_ad.mem", ad_mem);
        $readmemh("ascon_pt.mem", pt_mem);
        $readmemh("ascon_ct.mem", ct_mem);

        repeat (3) @(posedge clk);
        rst_n = 1;
        @(negedge clk);

        for (c = 0; c < NV; c = c + 1) begin
            key = 128'h0;
            nonce = 128'h0;
            for (b = 0; b < 16; b = b + 1) begin
                key   = (key   << 8) | meta_mem[c*META_B + b];
                nonce = (nonce << 8) | meta_mem[c*META_B + 16 + b];
            end
            adlen = meta_mem[c*META_B + 32];
            ptlen = meta_mem[c*META_B + 33];
            ct_len = 0;

            start = 1;
            @(negedge clk);
            start = 0;

            for (b = 0; b < adlen; b = b + 1)
                send_ad(ad_mem[c*AD_PAD + b]);
            end_ad;

            for (b = 0; b < ptlen; b = b + 1)
                send_pt(pt_mem[c*PT_PAD + b]);
            end_pt;

            timeout = 0;
            while (!done && timeout < 100000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!done) begin
                errors = errors + 1;
                $display("FAIL case %0d (ad=%0d pt=%0d): timeout", c, adlen, ptlen);
            end

            if (ct_len !== ptlen) begin
                errors = errors + 1;
                $display("FAIL case %0d: got %0d ciphertext bytes, expected %0d",
                         c, ct_len, ptlen);
            end
            for (b = 0; b < ptlen; b = b + 1)
                if (got_ct[b] !== ct_mem[c*CT_PAD + b]) begin
                    errors = errors + 1;
                    $display("FAIL case %0d: ct byte %0d got %02x exp %02x",
                             c, b, got_ct[b], ct_mem[c*CT_PAD + b]);
                end

            exp_tag = 128'h0;
            for (b = 0; b < 16; b = b + 1)
                exp_tag = (exp_tag << 8) | ct_mem[c*CT_PAD + ptlen + b];
            if (tag_out !== exp_tag) begin
                errors = errors + 1;
                $display("FAIL case %0d: tag got %032x exp %032x", c, tag_out, exp_tag);
            end

            // let the core return to IDLE before the next start
            timeout = 0;
            while (uut.st !== 3'd0 && timeout < 100000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            @(negedge clk);
        end

        if (errors == 0)
            $display("ascon128_aead_tb: PASS (%0d vectors, bit-exact vs ascon_primitives)", NV);
        else
            $display("ascon128_aead_tb: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
