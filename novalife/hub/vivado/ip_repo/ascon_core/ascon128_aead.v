// ============================================================================
// ascon128_aead — Ascon-AEAD128 (NIST SP 800-232, Aug 2025) encryption core, NovaLife HUB
// ============================================================================
// Functional model: tools/tag_reference/ascon_primitives.ascon_aead_encrypt, which passes all
// 1089 official SP 800-232 known-answer vectors (ascon-c crypto_aead/asconaead128).  This core is
// checked bit-exact against it by ascon128_aead_tb.v (vectors/gen_ascon_vectors.py).
//
// History: until 2026-10-20 this file (and the Python model) implemented Ascon-128 **v1.2**
// (IV 0x80400C06..., 64-bit rate, big-endian lanes, p^6) while being called SP 800-232; before
// 2026-10-19 it was a stub with no S-box.  Moved to the standard on the owner's decision
// (docs/improvement_review_2026-10-20.md A6).
//
// SP 800-232 Ascon-AEAD128, as implemented here:
//   * 128-bit rate: the duplex block is S0||S1, 16 bytes; bytes enter lanes LITTLE-endian
//     (byte i of a block -> bits [8*(i%8)+7 : 8*(i%8)] of S[i/8]).
//   * init: S = (IV, K0, K1, N0, N1), IV = 0x00001000808C0001; p^12; S3 ^= K0; S4 ^= K1.
//     K0/N0 are the first 8 bytes of key/nonce read little-endian.
//   * AD (only if non-empty): full blocks XOR into S0||S1 then p^8; the last (possibly
//     empty) block is padded with 0x01 after its last byte, then p^8.
//   * domain separation: S4 ^= 0x80 << 56.
//   * plaintext: full blocks XOR into S0||S1 (that is the ciphertext), p^8; the last block
//     is XORed and padded the same way, without a permutation.
//   * final: S2 ^= K0; S3 ^= K1; p^12; T = LE(S3 ^ K0) || LE(S4 ^ K1).
//
// Structure: one permutation round per clock, 5 x 64-bit state, AEAD framing FSM.
//
// Interface (byte stream):
//   * pulse `start` with `key`/`nonce` held (byte 0 in bits [127:120]).
//   * AD bytes on ad_data/ad_valid while ad_ready, then pulse `ad_done` (ad_valid = 0).
//   * plaintext bytes on pt_data/pt_valid while pt_ready, then pulse `pt_done`.
//   * output: ciphertext blocks on ct_data/ct_bytes/ct_valid, ct_data[127:120] = first byte;
//     then `tag_out` (byte 0 in bits [127:120]) with `done`.
// ============================================================================

`timescale 1ns / 1ps

module ascon128_aead (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [127:0] key,
    input  wire [127:0] nonce,

    input  wire [7:0]   ad_data,
    input  wire         ad_valid,
    input  wire         ad_done,

    input  wire [7:0]   pt_data,
    input  wire         pt_valid,
    input  wire         pt_done,

    output reg  [127:0] ct_data,
    output reg  [4:0]   ct_bytes,
    output reg          ct_valid,
    output reg  [127:0] tag_out,
    output reg          done,

    // valid/ready handshake: a byte is accepted only on a cycle where the matching
    // ready is high (the core is not busy running a permutation round block)
    output wire         ad_ready,
    output wire         pt_ready
);

    localparam [63:0] IV   = 64'h00001000808c0001;
    localparam [63:0] DSEP = 64'h8000000000000000;

    function [63:0] bswap64;
        input [63:0] x;
        integer k;
        begin
            for (k = 0; k < 8; k = k + 1) bswap64[8*k +: 8] = x[8*(7-k) +: 8];
        end
    endfunction

    // key/nonce lanes, little-endian (byte 0 = least significant byte of lane 0)
    wire [63:0] K0 = bswap64(key[127:64]);
    wire [63:0] K1 = bswap64(key[63:0]);
    wire [63:0] N0 = bswap64(nonce[127:64]);
    wire [63:0] N1 = bswap64(nonce[63:0]);

    // ---- state ---------------------------------------------------------------
    reg [63:0] S [0:4];
    reg [3:0]  perm_cnt;    // rounds done in the current permutation
    reg [3:0]  perm_runs;   // rounds requested (8 or 12)
    reg [2:0]  ret_state;   // where to go when the permutation finishes

    reg [127:0] blk;        // the 16-byte block being collected: {lane1, lane0}
    reg [4:0]   cnt;        // bytes collected (0..15)
    reg         ad_any;

    localparam [2:0] ST_IDLE = 3'd0,
                     ST_PERM = 3'd1,
                     ST_INITX = 3'd2,
                     ST_AD   = 3'd3,
                     ST_DSEP = 3'd4,
                     ST_PT   = 3'd5,
                     ST_FINAL = 3'd6,
                     ST_DONE  = 3'd7;

    reg [2:0] st;

    assign ad_ready = (st == ST_AD);
    assign pt_ready = (st == ST_PT);

    // ---- round helpers -------------------------------------------------------
    function [63:0] ror;
        input [63:0] x;
        input integer n;
        begin ror = (x >> n) | (x << (64 - n)); end
    endfunction

    function [63:0] rconst;
        input [3:0] idx;
        begin
            case (idx)
                4'd0:  rconst = 64'h00000000000000f0;
                4'd1:  rconst = 64'h00000000000000e1;
                4'd2:  rconst = 64'h00000000000000d2;
                4'd3:  rconst = 64'h00000000000000c3;
                4'd4:  rconst = 64'h00000000000000b4;
                4'd5:  rconst = 64'h00000000000000a5;
                4'd6:  rconst = 64'h0000000000000096;
                4'd7:  rconst = 64'h0000000000000087;
                4'd8:  rconst = 64'h0000000000000078;
                4'd9:  rconst = 64'h0000000000000069;
                4'd10: rconst = 64'h000000000000005a;
                4'd11: rconst = 64'h000000000000004b;
                default: rconst = 64'h0;
            endcase
        end
    endfunction

    // index into the 12 constants: p^r starts at 12-r
    wire [3:0] rc_idx = (4'd12 - perm_runs) + perm_cnt;

    // ---- one round (combinational; registered into S on each ST_PERM cycle) --
    // Python reference order:
    //   s2 ^= c; s0 ^= s4; s4 ^= s3; s2 ^= s1;
    //   t0 = s0 ^ (~s1 & s2); t1 = s1 ^ (~s2 & s3); t2 = s2 ^ (~s3 & s4);
    //   t3 = s3 ^ (~s4 & s0); t4 = s4 ^ (~s0 & s1);
    //   t1 ^= t0; t0 ^= t4; t3 ^= t2; t2 = ~t2;
    //   s0 = t0 ^ ror(t0,19) ^ ror(t0,28); ... etc.
    wire [63:0] a0 = S[0] ^ S[4];
    wire [63:0] a4 = S[4] ^ S[3];
    wire [63:0] a2 = S[2] ^ rconst(rc_idx) ^ S[1];
    wire [63:0] s1 = S[1];
    wire [63:0] s3 = S[3];

    wire [63:0] t0 = a0 ^ (~s1 & a2);
    wire [63:0] t1 = s1 ^ (~a2 & s3);
    wire [63:0] t2 = a2 ^ (~s3 & a4);
    wire [63:0] t3 = s3 ^ (~a4 & a0);
    wire [63:0] t4 = a4 ^ (~a0 & s1);

    wire [63:0] u0 = t0 ^ t4;
    wire [63:0] u1 = t1 ^ t0;
    wire [63:0] u3 = t3 ^ t2;
    wire [63:0] u2 = ~t2;

    wire [63:0] n0 = u0 ^ ror(u0, 19) ^ ror(u0, 28);
    wire [63:0] n1 = u1 ^ ror(u1, 61) ^ ror(u1, 39);
    wire [63:0] n2 = u2 ^ ror(u2, 1)  ^ ror(u2, 6);
    wire [63:0] n3 = u3 ^ ror(u3, 10) ^ ror(u3, 17);
    wire [63:0] n4 = t4 ^ ror(t4, 7)  ^ ror(t4, 41);

    // ---- block builders --------------------------------------------------------
    wire [7:0]   in_byte  = (st == ST_AD) ? ad_data : pt_data;
    wire [127:0] blk_next = blk | ({120'd0, in_byte} << (8 * cnt));
    wire [127:0] pad_blk  = 128'h01 << (8 * cnt);          // 0x01 after the last byte
    // ciphertext of a block = new S0||S1, presented big-endian (first byte in [127:120])
    function [127:0] ct_be;
        input [63:0] l0, l1;
        begin ct_be = {bswap64(l0), bswap64(l1)}; end
    endfunction

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st        <= ST_IDLE;
            done      <= 1'b0;
            ct_valid  <= 1'b0;
            ct_data   <= 128'd0;
            ct_bytes  <= 5'd0;
            tag_out   <= 128'd0;
            perm_cnt  <= 4'd0;
            perm_runs <= 4'd12;
            ret_state <= ST_IDLE;
            blk       <= 128'd0;
            cnt       <= 5'd0;
            ad_any    <= 1'b0;
            for (i = 0; i < 5; i = i + 1) S[i] <= 64'd0;
        end else begin
            case (st)
                ST_IDLE: begin
                    done     <= 1'b0;
                    ct_valid <= 1'b0;
                    if (start) begin
                        S[0] <= IV;
                        S[1] <= K0;
                        S[2] <= K1;
                        S[3] <= N0;
                        S[4] <= N1;
                        perm_runs <= 4'd12;
                        perm_cnt  <= 4'd0;
                        ret_state <= ST_INITX;
                        blk       <= 128'd0;
                        cnt       <= 5'd0;
                        ad_any    <= 1'b0;
                        st        <= ST_PERM;
                    end
                end

                ST_PERM: begin
                    ct_valid <= 1'b0;   // a ciphertext block is valid for exactly one cycle
                    S[0] <= n0;
                    S[1] <= n1;
                    S[2] <= n2;
                    S[3] <= n3;
                    S[4] <= n4;
                    if (perm_cnt == perm_runs - 1'b1) st <= ret_state;
                    else perm_cnt <= perm_cnt + 4'd1;
                end

                ST_INITX: begin
                    S[3] <= S[3] ^ K0;
                    S[4] <= S[4] ^ K1;
                    st   <= ST_AD;
                end

                ST_AD: begin
                    if (ad_valid) begin
                        ad_any <= 1'b1;
                        if (cnt == 5'd15) begin
                            S[0]      <= S[0] ^ blk_next[63:0];
                            S[1]      <= S[1] ^ blk_next[127:64];
                            blk       <= 128'd0;
                            cnt       <= 5'd0;
                            perm_runs <= 4'd8;
                            perm_cnt  <= 4'd0;
                            ret_state <= ST_AD;
                            st        <= ST_PERM;
                        end else begin
                            blk <= blk_next;
                            cnt <= cnt + 5'd1;
                        end
                    end else if (ad_done) begin
                        if (ad_any) begin
                            // last (possibly empty) block, 0x01-padded
                            S[0]      <= S[0] ^ blk[63:0]   ^ pad_blk[63:0];
                            S[1]      <= S[1] ^ blk[127:64] ^ pad_blk[127:64];
                            blk       <= 128'd0;
                            cnt       <= 5'd0;
                            perm_runs <= 4'd8;
                            perm_cnt  <= 4'd0;
                            ret_state <= ST_DSEP;
                            st        <= ST_PERM;
                        end else begin
                            st <= ST_DSEP;   // empty AD: nothing is absorbed
                        end
                    end
                end

                ST_DSEP: begin
                    S[4] <= S[4] ^ DSEP;
                    blk  <= 128'd0;
                    cnt  <= 5'd0;
                    st   <= ST_PT;
                end

                ST_PT: begin
                    ct_valid <= 1'b0;
                    if (pt_valid) begin
                        if (cnt == 5'd15) begin
                            ct_data   <= ct_be(S[0] ^ blk_next[63:0], S[1] ^ blk_next[127:64]);
                            ct_bytes  <= 5'd16;
                            ct_valid  <= 1'b1;
                            S[0]      <= S[0] ^ blk_next[63:0];
                            S[1]      <= S[1] ^ blk_next[127:64];
                            blk       <= 128'd0;
                            cnt       <= 5'd0;
                            perm_runs <= 4'd8;
                            perm_cnt  <= 4'd0;
                            ret_state <= ST_PT;
                            st        <= ST_PERM;
                        end else begin
                            blk <= blk_next;
                            cnt <= cnt + 5'd1;
                        end
                    end else if (pt_done) begin
                        // last (possibly empty) block: XOR, emit cnt bytes, pad, then finalise
                        ct_data  <= ct_be(S[0] ^ blk[63:0], S[1] ^ blk[127:64]);
                        ct_bytes <= cnt;
                        ct_valid <= (cnt != 5'd0);
                        S[0]     <= S[0] ^ blk[63:0]   ^ pad_blk[63:0];
                        S[1]     <= S[1] ^ blk[127:64] ^ pad_blk[127:64];
                        S[2]     <= S[2] ^ K0;
                        S[3]     <= S[3] ^ K1;
                        blk      <= 128'd0;
                        cnt      <= 5'd0;
                        perm_runs <= 4'd12;
                        perm_cnt  <= 4'd0;
                        ret_state <= ST_FINAL;
                        st        <= ST_PERM;
                    end
                end

                ST_FINAL: begin
                    tag_out  <= {bswap64(S[3] ^ K0), bswap64(S[4] ^ K1)};
                    ct_valid <= 1'b0;
                    done     <= 1'b1;
                    st       <= ST_DONE;
                end

                ST_DONE: st <= ST_IDLE;

                default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
