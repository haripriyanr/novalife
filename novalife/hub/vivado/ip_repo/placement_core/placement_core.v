// placement_core -- keyed block placement stream (contract: embed._placement_map_impl).
//
//   For copy c = 0..copies-1 and bit i = 0..255 (copy-major) it finds the block that carries
//   codeword bit i of copy c:  j = (i*stride + c*cstride) mod m,  stride = max(1, m/256),
//   cstride = max(1, stride/4); then scan j, j+1, ... (wrapping, at most m slots) for the first
//   slot that is neither used nor tainted, where slot j is block feistel_perm(key, m, j).
//   Each result is one record on (out_valid, out_copy, out_bit, out_block); out_block = 0xFFFFFF
//   is "none" (erasure mode only).  In encoder mode (erasure_mode = 0) the stream stops at the
//   first copy that cannot complete (that copy's earlier bits are NOT retracted: the consumer
//   writes only complete copies, see `copy_fail`).  `done` ends the stream.
//   Taint comes from an external memory: blk_addr -> blk_taint two cycles later.
//   used-slot bitmap: MAX_M bits, cleared at start.
`timescale 1ns / 1ps

module placement_core #(
    parameter integer MAX_M = 65536
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [127:0] key,
    input  wire [23:0]  m,
    input  wire [2:0]   copies,         // 1..4
    input  wire         erasure_mode,
    // taint memory (1 bit per block)
    output reg  [23:0]  blk_addr,
    input  wire         blk_taint,      // valid 2 cycles after blk_addr
    // result stream
    output reg          out_valid,
    output reg  [1:0]   out_copy,
    output reg  [7:0]   out_bit,
    output reg  [23:0]  out_block,
    output reg          copy_fail,      // pulse: copy out_copy could not be completed (encoder mode)
    output reg          done
);
    localparam [23:0] NONE = 24'hFFFFFF;

    // used bitmap (inferred RAM), clear sweep at start
    reg used_mem [0:MAX_M-1];
    reg [23:0] clr;
    reg [23:0] j, steps, base_j;
    reg [1:0]  c;
    reg [8:0]  bi;               // 0..256
    wire [23:0] stride  = (m >> 8) == 24'd0 ? 24'd1 : (m >> 8);
    wire [23:0] cs_raw  = stride >> 2;
    wire [23:0] cstride = (cs_raw == 24'd0) ? 24'd1 : cs_raw;
    reg  used_q;

    // permutation core
    reg         p_start;
    wire [23:0] p_block;
    wire        p_done;
    feistel_perm_core u_perm(.clk(clk), .rst_n(rst_n), .start(p_start), .key(key), .m(m),
                             .slot(j), .block_idx(p_block), .done(p_done));

    localparam S_IDLE = 4'd0, S_CLR = 4'd1, S_BASE = 4'd2, S_USED = 4'd3, S_USED2 = 4'd4,
               S_PERM = 4'd5, S_TAINT = 4'd6, S_TAINT2 = 4'd7, S_TAINT3 = 4'd8, S_EMIT = 4'd9,
               S_NEXT = 4'd10, S_END = 4'd11;
    reg [3:0] st;
    reg [23:0] mul_a;

    // base slot for (c, bi): bi*stride + c*cstride, reduced mod m (< 2m, one subtract)
    wire [31:0] raw_j = bi[7:0] * stride + c * cstride;
    wire [31:0] red_j = (raw_j >= {8'd0, m}) ? raw_j - {8'd0, m} : raw_j;

    always @(posedge clk) begin
        if (st == S_CLR) used_mem[clr[15:0]] <= 1'b0;
        else if (st == S_EMIT && out_block != NONE) used_mem[j[15:0]] <= 1'b1;
        used_q <= used_mem[j[15:0]];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; done <= 1'b0; out_valid <= 1'b0; copy_fail <= 1'b0; p_start <= 1'b0;
            clr <= 0; j <= 0; steps <= 0; c <= 0; bi <= 0; blk_addr <= 0; out_block <= 0;
            out_copy <= 0; out_bit <= 0;
        end else begin
            out_valid <= 1'b0; copy_fail <= 1'b0; p_start <= 1'b0;
            case (st)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin clr <= 24'd0; st <= S_CLR; end
                end
                S_CLR: begin
                    if (clr + 24'd1 >= m) begin c <= 2'd0; bi <= 9'd0; st <= S_BASE; end
                    else clr <= clr + 24'd1;
                end
                S_BASE: begin
                    j <= red_j[23:0]; steps <= 24'd0; st <= S_USED;
                end
                S_USED: st <= S_USED2;                 // used_q <= used_mem[j]
                S_USED2: begin
                    if (used_q) st <= S_NEXT;
                    else begin p_start <= 1'b1; st <= S_PERM; end
                end
                S_PERM: if (p_done) begin blk_addr <= p_block; out_block <= p_block; st <= S_TAINT; end
                S_TAINT: st <= S_TAINT2;
                S_TAINT2: st <= S_TAINT3;
                S_TAINT3: begin
                    if (blk_taint) st <= S_NEXT;
                    else begin
                        out_valid <= 1'b1; out_copy <= c; out_bit <= bi[7:0]; st <= S_EMIT;
                    end
                end
                S_EMIT: begin
                    // used bit written here for a real block; advance to the next bit
                    if (bi == 9'd255) begin
                        bi <= 9'd0;
                        if (c + 3'd1 >= copies) st <= S_END; else begin c <= c + 2'd1; st <= S_BASE; end
                    end else begin bi <= bi + 9'd1; st <= S_BASE; end
                end
                S_NEXT: begin
                    // slot j unusable: next slot, or give up after m slots
                    if (steps + 24'd1 >= m) begin
                        if (erasure_mode) begin
                            out_valid <= 1'b1; out_copy <= c; out_bit <= bi[7:0]; out_block <= NONE;
                            st <= S_EMIT;
                        end else begin
                            copy_fail <= 1'b1; out_copy <= c; st <= S_END;
                        end
                    end else begin
                        steps <= steps + 24'd1;
                        j <= (j + 24'd1 >= m) ? 24'd0 : j + 24'd1;
                        st <= S_USED;
                    end
                end
                S_END: begin done <= 1'b1; st <= S_IDLE; end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
