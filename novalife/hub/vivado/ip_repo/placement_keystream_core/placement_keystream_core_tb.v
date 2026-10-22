`timescale 1ns / 1ps

module placement_keystream_core_tb;
    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg [10:0] num_blocks = 1024;
    reg [127:0] key_in = 128'h00112233445566778899aabbccddeeff;
    reg key_valid = 1;
    reg [1:0] query_copy = 0;
    reg [7:0] query_bit_idx = 0;
    reg query_valid = 0;

    wire [9:0] query_block_id;
    wire query_block_valid;
    wire ready;
    wire done;

    placement_keystream_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .num_blocks(num_blocks),
        .key_in(key_in),
        .key_valid(key_valid),
        .query_copy(query_copy),
        .query_bit_idx(query_bit_idx),
        .query_valid(query_valid),
        .query_block_id(query_block_id),
        .query_block_valid(query_block_valid),
        .ready(ready),
        .done(done)
    );

    always #5 clk = ~clk;

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(negedge clk);

        start = 1;
        @(negedge clk);
        start = 0;

        @(posedge clk);
        while (!done) @(posedge clk);

        query_copy = 0; query_bit_idx = 10; query_valid = 1;
        @(negedge clk);
        query_valid = 0;

        @(posedge clk);
        if (query_block_valid) begin
            $display("Query result: block_id = %d", query_block_id);
            $display("PASS: placement_keystream_core test passed!");
            $finish(0);
        end else begin
            $display("FAIL: no valid query response");
            $finish(1);
        end
    end
endmodule
