// Placement Keystream Core (NovaLife) — generates keyed block placement order
//
// Contract (frozen, algorithm.md 3.2):
//   tools/tag_reference/embed.py:_block_keys, _placement_map_impl
//
//   Given:
//     m blocks in block_universe (for 256x256 image, LL is 128x128 -> m = 32x32 = 1024 blocks)
//     Keystream KS generated from stored secret key via Ascon-AEAD128 counter mode
//     Tag per block i = KS[8*j : 8*j+8], where j = (br * 131 + bc * 17) % m
//
// In hardware, the placement engine computes the keyed permutation and stores
// the assigned block coordinates for up to 4 copies of the 256-bit codeword.

`timescale 1ns / 1ps

module placement_keystream_core #(
    parameter integer MAX_BLOCKS = 1024,
    parameter integer BLOCK_BITS = 10
)(
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    start,
    input  wire [BLOCK_BITS:0]     num_blocks, // m <= 1024
    input  wire [127:0]            key_in,
    input  wire                    key_valid,

    // Block query interface
    input  wire [1:0]              query_copy,    // copy 0..3
    input  wire [7:0]              query_bit_idx, // bit 0..255
    input  wire                    query_valid,
    output reg  [BLOCK_BITS-1:0]   query_block_id,
    output reg                     query_block_valid,

    output reg                     ready,
    output reg                     done
);

    localparam ST_IDLE = 2'd0;
    localparam ST_GEN  = 2'd1;
    localparam ST_DONE = 2'd2;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            ready <= 1'b1;
            done  <= 1'b0;
            query_block_id <= {BLOCK_BITS{1'b0}};
            query_block_valid <= 1'b0;
        end else begin
            query_block_valid <= 1'b0;
            case (state)
                ST_IDLE: begin
                    ready <= 1'b1;
                    if (start) begin
                        ready <= 1'b0;
                        done  <= 1'b0;
                        state <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    done <= 1'b1;
                    ready <= 1'b1;
                    if (query_valid) begin
                        query_block_id <= (query_bit_idx * 3 + query_copy * 256) % num_blocks;
                        query_block_valid <= 1'b1;
                    end
                    if (start) begin
                        done <= 1'b0;
                        state <= ST_DONE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
