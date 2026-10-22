// Self-checking testbench for tag_engine.
//
// Vectors: te_key.mem / te_fields.mem / te_tag.mem from
// tools/tag_reference/vectors/gen_tag_engine_vectors.py (== tag_block.compute_tag).
// Checks: BUILD tag bit-exact; VERIFY accepts the right tag, rejects every single-bit flip
// tried and the right tag under the wrong key; NO_KEY before a key and after a wipe; BAD_OP;
// the token bucket locks VERIFY after CAP failures (BUILD still works) and a refill re-opens it.
// Run via `vivado/scripts/run_sim.sh tag_engine`.

`timescale 1ns / 1ps
`include "te_params.vh"

module tag_engine_tb;

    localparam integer NV     = TE_NUM_VECTORS;
    localparam integer CAP    = 4;
    localparam integer REFILL = 3000;

    reg clk = 1'b0, rst_n = 1'b0;
    reg key_we = 1'b0, key_wipe = 1'b0;
    reg [127:0] key_in = 128'd0;
    wire key_loaded;
    reg cmd_valid = 1'b0;
    wire cmd_ready;
    reg [1:0] cmd_op = 2'd0;
    reg [3:0] version = 4'd0;
    reg [11:0] hub_id = 12'd0;
    reg [63:0] handle = 64'd0;
    reg [47:0] tag_in = 48'd0;
    wire resp_valid, resp_ok;
    wire [1:0] resp_status;
    wire [47:0] resp_tag;
    wire [7:0] tokens;

    tag_engine #(.CAP(CAP), .REFILL(REFILL)) dut (
        .clk(clk), .rst_n(rst_n),
        .key_we(key_we), .key_in(key_in), .key_wipe(key_wipe), .key_loaded(key_loaded),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_op(cmd_op),
        .version(version), .hub_id(hub_id), .handle(handle), .tag_in(tag_in),
        .resp_valid(resp_valid), .resp_status(resp_status), .resp_tag(resp_tag),
        .resp_ok(resp_ok), .tokens(tokens)
    );

    always #5 clk = ~clk;

    reg [127:0] key_mem [0:NV-1];
    reg [79:0]  fld_mem [0:NV-1];
    reg [47:0]  tag_mem [0:NV-1];

    integer c, b, errors, timeout;
    reg [1:0]  r_status;
    reg [47:0] r_tag;
    reg        r_ok;

    task load_key(input [127:0] k);
        begin
            @(negedge clk); key_in = k; key_we = 1'b1;
            @(negedge clk); key_we = 1'b0;
        end
    endtask

    task wipe;
        begin
            @(negedge clk); key_wipe = 1'b1;
            @(negedge clk); key_wipe = 1'b0;
        end
    endtask

    task command(input [1:0] op, input [79:0] f, input [47:0] t);
        begin
            @(negedge clk);
            while (!cmd_ready) @(negedge clk);
            cmd_op = op; version = f[79:76]; hub_id = f[75:64]; handle = f[63:0]; tag_in = t;
            cmd_valid = 1'b1;
            @(negedge clk);
            cmd_valid = 1'b0;
            timeout = 0;
            while (!resp_valid && timeout < 2000) begin @(posedge clk); #1; timeout = timeout + 1; end
            if (!resp_valid && timeout >= 2000) begin
                errors = errors + 1; $display("FAIL: no response (op %0d)", op);
            end
            r_status = resp_status; r_tag = resp_tag; r_ok = resp_ok;
        end
    endtask

    task check_resp(input [1:0] st, input ok, input [8*40-1:0] what);
        begin
            if (r_status !== st || (st == 2'd0 && r_ok !== ok)) begin
                errors = errors + 1;
                $display("FAIL %0s: status %0d ok %0d (want %0d %0d)", what, r_status, r_ok, st, ok);
            end
        end
    endtask

    task wait_full;
        begin
            timeout = 0;
            while (tokens != CAP && timeout < REFILL * (CAP + 2)) begin @(negedge clk); timeout = timeout + 1; end
        end
    endtask

    initial begin
        errors = 0;
        $readmemh("te_key.mem", key_mem);
        $readmemh("te_fields.mem", fld_mem);
        $readmemh("te_tag.mem", tag_mem);
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // no key yet
        command(2'd1, fld_mem[0], 48'd0); check_resp(2'd1, 1'b0, "build without key");
        command(2'd2, fld_mem[0], tag_mem[0]); check_resp(2'd1, 1'b0, "verify without key");
        // bad ops
        load_key(key_mem[0]);
        command(2'd0, fld_mem[0], 48'd0); check_resp(2'd3, 1'b0, "op 0");
        command(2'd3, fld_mem[0], 48'd0); check_resp(2'd3, 1'b0, "op 3");

        for (c = 0; c < NV; c = c + 1) begin
            load_key(key_mem[c]);
            command(2'd1, fld_mem[c], 48'd0);
            check_resp(2'd0, 1'b0, "build");
            if (r_tag !== tag_mem[c]) begin
                errors = errors + 1;
                $display("FAIL case %0d: build tag %012x exp %012x", c, r_tag, tag_mem[c]);
            end
            command(2'd2, fld_mem[c], tag_mem[c]); check_resp(2'd0, 1'b1, "verify right tag");
            b = (c * 7) % 48;
            command(2'd2, fld_mem[c], tag_mem[c] ^ (48'd1 << b)); check_resp(2'd0, 1'b0, "verify flipped tag");
            // a flipped field bit (handle) must also be rejected
            command(2'd2, fld_mem[c] ^ (80'd1 << (c % 64)), tag_mem[c]); check_resp(2'd0, 1'b0, "verify flipped handle");
            wait_full;
        end

        // wrong key: case 1's tag under case 2's key
        load_key(key_mem[2]);
        command(2'd2, fld_mem[1], tag_mem[1]); check_resp(2'd0, 1'b0, "wrong key");
        wait_full;

        // rate limit: CAP failures empty the bucket, then even the right tag is refused
        load_key(key_mem[3]);
        for (b = 0; b < CAP; b = b + 1) begin
            command(2'd2, fld_mem[3], ~tag_mem[3]); check_resp(2'd0, 1'b0, "drain");
        end
        if (tokens !== 8'd0) begin errors = errors + 1; $display("FAIL: tokens %0d after drain", tokens); end
        command(2'd2, fld_mem[3], tag_mem[3]); check_resp(2'd2, 1'b0, "locked verify");
        command(2'd1, fld_mem[3], 48'd0); check_resp(2'd0, 1'b0, "build while locked");
        if (r_tag !== tag_mem[3]) begin errors = errors + 1; $display("FAIL: build while locked"); end
        // one refill period re-opens exactly one attempt
        repeat (REFILL + 10) @(negedge clk);
        command(2'd2, fld_mem[3], tag_mem[3]); check_resp(2'd0, 1'b1, "verify after refill");

        // wipe
        wipe;
        if (key_loaded !== 1'b0) begin errors = errors + 1; $display("FAIL: key_loaded after wipe"); end
        command(2'd1, fld_mem[3], 48'd0); check_resp(2'd1, 1'b0, "build after wipe");

        if (errors == 0)
            $display("tag_engine_tb: PASS (%0d vectors bit-exact; reject flips, wrong key; NO_KEY, BAD_OP, rate limit, wipe)", NV);
        else
            $display("tag_engine_tb: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
