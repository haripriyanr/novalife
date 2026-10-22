// Polar SCL decoder (N=256, K=128, list size L=8) — bit-exact (info bits AND winning path
// metric) against the integer contract in tools/tag_reference/vectors/gen_polar_scl_vectors.py,
// which is itself cross-checked against polar_codec.polar_scl_decode(llr, 8).
//
// Built on the memory-backed structure of polar_sc_decoder, with two observations that keep
// the list cheap on the XC7Z010:
//
//  1. The LLRs of a path are a pure function of the channel row and that path's partial sums,
//     and the reference recomputes every stage from the channel at each leaf anyway.  So the
//     paths share ONE llr scratch (2304 x 16b, one RAMB36); each leaf walks the tree once per
//     active path.  No per-path LLR memory, no LLR copy when the list is pruned.
//  2. The partial sums of all L paths sit in one L-bit word per (stage, idx) address
//     (bits 2304 x 8b, one RAMB18).  Pruning is an in-place PERMUTATION of every word
//     (child k <- parent sel_par[k]; leaf i's bit forced to sel_bit[k]), one pass of 2304
//     read-modify-writes; the partial-sum climb runs on all paths at once (XOR on words).
//
// List management (the reference's exact order): at an information leaf the 2P candidates are
// (parent 0 bit 0, parent 0 bit 1, parent 1 bit 0, ...) with
//   pm(p,0) = pm[p] + (llr<0 ? |llr| : 0),   pm(p,1) = pm[p] + (llr>0 ? llr : 0)
// and the first min(2P, L) are taken by repeated "first strict minimum not yet taken" scans,
// which is a stable sort.  Frozen leaf: pm[p] += (llr<0 ? |llr| : 0), bit 0.  The winner is the
// first minimum pm among the P active paths.
//
// Arithmetic: F(a,b) = sign(a)sign(b)min(|a|,|b|); G(a,b,u) = b + (1-2u)a; 16-bit LLRs
// (max internal |llr| over the vectors: 12775), 32-bit path metrics.
//
// Memory addressing: A(stage, idx) = {stage[3:0], idx[7:0]} = stage*256 + idx (0..2303).
//
// Interface: identical to polar_sc_decoder, plus pm_out (the winning path metric).
//
// Throughput (structural): ~5 cycles per F/G x 255 per walk x P walks per leaf x 256 leaves,
// plus one 2304-cycle permutation per information leaf: ~2.9 M cycles = ~29 ms at 100 MHz.
// Slow on purpose; see the core's results file for the measured count.

`timescale 1ns / 1ps
`include "polar_params.vh"

module polar_scl_decoder #(
    parameter N = 256,
    parameter K = 128,
    parameter W = 16
)(
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire                 wr_en,
    input  wire [7:0]           wr_addr,
    input  wire signed [W-1:0]  wr_llr,

    input  wire                 start,
    output reg                  busy,
    output reg                  done,

    output reg  [K-1:0]         info_bits_out,
    output reg  [31:0]          pm_out
);

    localparam integer L      = 8;
    localparam integer LOG2N  = 8;
    localparam integer DEPTH  = (LOG2N + 1) * N;      // 2304

    function [W-1:0] f_abs_u;
        input signed [W-1:0] v;
        begin f_abs_u = v[W-1] ? -v : v; end
    endfunction

    // pm increment when the decision disagrees with the LLR sign
    function [31:0] f_neg_cost;                       // cost of deciding 0: llr<0 ? |llr| : 0
        input signed [W-1:0] v;
        begin f_neg_cost = v[W-1] ? {{(32-W){1'b0}}, -v} : 32'd0; end
    endfunction
    function [31:0] f_pos_cost;                       // cost of deciding 1: llr>0 ? llr : 0
        input signed [W-1:0] v;
        begin f_pos_cost = (!v[W-1] && v != 0) ? {{(32-W){1'b0}}, v} : 32'd0; end
    endfunction

    localparam [4:0] ST_IDLE   = 5'd0,
                     ST_CLR    = 5'd1,
                     ST_UPD_A  = 5'd2,
                     ST_UPD_B  = 5'd3,
                     ST_UPD_C  = 5'd4,
                     ST_UPD_D  = 5'd5,
                     ST_UPD_E  = 5'd6,
                     ST_DEC_A  = 5'd7,
                     ST_DEC_B  = 5'd8,
                     ST_DECIDE = 5'd9,
                     ST_FRZ_W  = 5'd10,
                     ST_SCAN   = 5'd11,
                     ST_COMMIT = 5'd12,
                     ST_PERM   = 5'd13,
                     ST_PROP_A = 5'd14,
                     ST_PROP_B = 5'd15,
                     ST_PROP_C = 5'd16,
                     ST_PROP_D = 5'd17,
                     ST_BEST   = 5'd18,
                     ST_OUT    = 5'd19,
                     ST_END    = 5'd20;

    reg [4:0]  st;
    reg [7:0]  i_r;
    reg [3:0]  stage_r;
    reg [7:0]  j_r;
    reg [11:0] cnt;          // CLR / PERM / OUT address counter (one past the issued read)

    // list state
    reg [31:0]         pm      [0:L-1];
    reg signed [W-1:0] leaf    [0:L-1];
    reg [3:0]          P_r;              // active paths, 1..8
    reg [2:0]          p_r;              // path being walked
    reg [31:0]         cpm     [0:2*L-1];
    reg [2*L-1:0]      ctaken;
    reg [4:0]          ncand;            // 2P
    reg [3:0]          keep_r;           // min(2P, L)
    reg [3:0]          k_r;              // candidates committed so far
    reg [4:0]          c_r;              // scan index
    reg [4:0]          best_c;
    reg [31:0]         best_pm;
    reg                best_valid;
    reg [2:0]          sel_par [0:L-1];
    reg                sel_bit [0:L-1];
    reg [31:0]         sel_pm  [0:L-1];
    reg [2:0]          best_p;

    // datapath registers (as polar_sc_decoder)
    reg signed [W-1:0] a_reg, b_reg;
    reg [W-1:0]        ma_r, mb_r;
    reg                sgn_r;
    reg signed [W-1:0] wdata_r;
    reg                u_reg;
    reg [L-1:0]        lw_reg, rw_reg;

    // memories
    reg signed [W-1:0] llr_mem  [0:DEPTH-1];
    reg signed [W-1:0] llr_rdata;
    reg [L-1:0]        bits_mem [0:DEPTH-1];
    reg [L-1:0]        bits_rdata;

    // ---- combinational -----------------------------------------------------------------------
    reg [7:0]  bl_c, off_c;
    reg        left_c, right_c;
    reg [W-1:0] mag_c;
    always @(*) begin
        bl_c    = 8'd1 << stage_r;
        off_c   = (i_r >> (stage_r + 1)) << (stage_r + 1);
        left_c  = (((i_r >> stage_r) & 8'd1) == 8'd0);
        right_c = ~left_c;
        mag_c   = (ma_r < mb_r) ? ma_r : mb_r;
    end

    // the permuted word for address cnt-1 (data on the read port this cycle)
    reg [L-1:0] perm_word_c;
    wire [11:0] wb_addr = cnt - 12'd1;
    integer pk;
    always @(*) begin
        perm_word_c = {L{1'b0}};
        for (pk = 0; pk < L; pk = pk + 1)
            if (pk < keep_r)
                perm_word_c[pk] = (wb_addr == {4'd0, i_r}) ? sel_bit[pk]
                                                           : bits_rdata[sel_par[pk]];
    end

    // scan step: is candidate c_r a new strict minimum?
    wire scan_hit = (c_r < ncand) && !ctaken[c_r] && (!best_valid || cpm[c_r] < best_pm);
    // best-path step
    wire best_hit = (c_r[3:0] < P_r) && (c_r == 5'd0 || pm[c_r[2:0]] < pm[best_p]);

    reg [11:0] llr_raddr_c, bits_raddr_c, llr_waddr_c, bits_waddr_c;
    reg        llr_we_c, bits_we_c;
    reg signed [W-1:0] llr_wdata_c;
    reg [L-1:0] bits_wdata_c;

    always @(*) begin
        llr_raddr_c  = 12'd0; bits_raddr_c = 12'd0;
        llr_waddr_c  = 12'd0; bits_waddr_c = 12'd0;
        llr_we_c = 1'b0; bits_we_c = 1'b0;
        llr_wdata_c = {W{1'b0}}; bits_wdata_c = {L{1'b0}};
        case (st)
            ST_CLR: begin
                bits_we_c = 1'b1; bits_waddr_c = cnt; bits_wdata_c = {L{1'b0}};
            end
            ST_UPD_A: begin
                llr_raddr_c  = {stage_r + 4'd1, off_c + j_r};
                bits_raddr_c = {stage_r, off_c + j_r};
            end
            ST_UPD_B: llr_raddr_c = {stage_r + 4'd1, off_c + bl_c + j_r};
            ST_UPD_E: begin
                llr_we_c    = 1'b1;
                llr_waddr_c = {stage_r, left_c ? (off_c + j_r) : (off_c + bl_c + j_r)};
                llr_wdata_c = wdata_r;
            end
            ST_DEC_A: llr_raddr_c = {4'd0, i_r};
            ST_FRZ_W: begin
                bits_we_c = 1'b1; bits_waddr_c = {4'd0, i_r}; bits_wdata_c = {L{1'b0}};
            end
            ST_PERM: begin
                bits_raddr_c = cnt;
                if (cnt != 12'd0) begin
                    bits_we_c = 1'b1; bits_waddr_c = wb_addr; bits_wdata_c = perm_word_c;
                end
            end
            ST_PROP_A: if (right_c) bits_raddr_c = {stage_r, off_c + j_r};
            ST_PROP_B: if (right_c) bits_raddr_c = {stage_r, off_c + bl_c + j_r};
            ST_PROP_C: if (right_c) begin
                bits_we_c = 1'b1; bits_waddr_c = {stage_r + 4'd1, off_c + j_r};
                bits_wdata_c = lw_reg ^ bits_rdata;
            end
            ST_PROP_D: if (right_c) begin
                bits_we_c = 1'b1; bits_waddr_c = {stage_r + 4'd1, off_c + bl_c + j_r};
                bits_wdata_c = rw_reg;
            end
            ST_OUT: bits_raddr_c = {4'd0, cnt[7:0]};
            default: ;
        endcase
    end

    wire        idle_load = (st == ST_IDLE) && wr_en;
    wire        llr_we    = llr_we_c | idle_load;
    wire [11:0] llr_waddr = idle_load ? {4'd8, wr_addr} : llr_waddr_c;
    wire signed [W-1:0] llr_wdata = idle_load ? wr_llr : llr_wdata_c;

    always @(posedge clk) begin
        if (llr_we) llr_mem[llr_waddr] <= llr_wdata;
        llr_rdata <= llr_mem[llr_raddr_c];
    end
    always @(posedge clk) begin
        if (bits_we_c) bits_mem[bits_waddr_c] <= bits_wdata_c;
        bits_rdata <= bits_mem[bits_raddr_c];
    end

    // ---- sequencer ---------------------------------------------------------------------------
    task prop_advance;
        begin
            j_r <= 8'd0;
            if (stage_r == LOG2N - 1) begin
                if (i_r == N - 1) begin
                    c_r <= 5'd0;
                    best_p <= 3'd0;
                    st <= ST_BEST;
                end else begin
                    i_r     <= i_r + 8'd1;
                    stage_r <= LOG2N - 1;
                    p_r     <= 3'd0;
                    st      <= ST_UPD_A;
                end
            end else begin
                stage_r <= stage_r + 4'd1;
                st      <= ST_PROP_A;
            end
        end
    endtask

    integer q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_IDLE; busy <= 1'b0; done <= 1'b0;
            info_bits_out <= {K{1'b0}}; pm_out <= 32'd0;
            i_r <= 8'd0; stage_r <= 4'd0; j_r <= 8'd0; cnt <= 12'd0;
            P_r <= 4'd1; p_r <= 3'd0; ctaken <= {2*L{1'b0}}; ncand <= 5'd0; keep_r <= 4'd0;
            k_r <= 4'd0; c_r <= 5'd0; best_c <= 5'd0; best_pm <= 32'd0; best_valid <= 1'b0;
            best_p <= 3'd0;
            a_reg <= {W{1'b0}}; b_reg <= {W{1'b0}}; ma_r <= {W{1'b0}}; mb_r <= {W{1'b0}};
            sgn_r <= 1'b0; wdata_r <= {W{1'b0}}; u_reg <= 1'b0;
            lw_reg <= {L{1'b0}}; rw_reg <= {L{1'b0}};
            for (q = 0; q < L; q = q + 1) begin
                pm[q] <= 32'd0; leaf[q] <= {W{1'b0}};
                sel_par[q] <= 3'd0; sel_bit[q] <= 1'b0; sel_pm[q] <= 32'd0;
            end
            for (q = 0; q < 2*L; q = q + 1) cpm[q] <= 32'd0;
        end else begin
            case (st)
                ST_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        cnt  <= 12'd0;
                        st   <= ST_CLR;
                    end
                end

                ST_CLR: begin
                    if (cnt == DEPTH - 1) begin
                        i_r <= 8'd0; stage_r <= LOG2N - 1; j_r <= 8'd0;
                        P_r <= 4'd1; p_r <= 3'd0;
                        for (q = 0; q < L; q = q + 1) pm[q] <= 32'd0;
                        st <= ST_UPD_A;
                    end else cnt <= cnt + 12'd1;
                end

                // ---- leaf LLR walk for path p_r ----
                ST_UPD_A: st <= ST_UPD_B;
                ST_UPD_B: begin
                    a_reg <= llr_rdata;
                    ma_r  <= f_abs_u(llr_rdata);
                    u_reg <= bits_rdata[p_r];
                    st    <= ST_UPD_C;
                end
                ST_UPD_C: begin
                    b_reg <= llr_rdata;
                    mb_r  <= f_abs_u(llr_rdata);
                    sgn_r <= a_reg[W-1] ^ llr_rdata[W-1];
                    st    <= ST_UPD_D;
                end
                ST_UPD_D: begin
                    wdata_r <= left_c
                        ? ((ma_r == 0 || mb_r == 0) ? {W{1'b0}} : (sgn_r ? -mag_c : mag_c))
                        : (b_reg + (u_reg ? -a_reg : a_reg));
                    st <= ST_UPD_E;
                end
                ST_UPD_E: begin
                    if (j_r + 8'd1 < bl_c) begin
                        j_r <= j_r + 8'd1;
                        st  <= ST_UPD_A;
                    end else begin
                        j_r <= 8'd0;
                        if (stage_r == 0) st <= ST_DEC_A;
                        else begin stage_r <= stage_r - 4'd1; st <= ST_UPD_A; end
                    end
                end
                ST_DEC_A: st <= ST_DEC_B;
                ST_DEC_B: begin
                    leaf[p_r] <= llr_rdata;
                    if ({1'b0, p_r} + 4'd1 < P_r) begin
                        p_r <= p_r + 3'd1;
                        stage_r <= LOG2N - 1;
                        j_r <= 8'd0;
                        st <= ST_UPD_A;
                    end else st <= ST_DECIDE;
                end

                // ---- decision ----
                ST_DECIDE: begin
                    if (POLAR_FROZEN_MASK[i_r]) begin
                        for (q = 0; q < L; q = q + 1)
                            if (q < P_r) pm[q] <= pm[q] + f_neg_cost(leaf[q]);
                        st <= ST_FRZ_W;
                    end else begin
                        for (q = 0; q < 2*L; q = q + 1)
                            cpm[q] <= pm[q/2] + ((q % 2) ? f_pos_cost(leaf[q/2])
                                                         : f_neg_cost(leaf[q/2]));
                        ctaken     <= {2*L{1'b0}};
                        ncand      <= {P_r, 1'b0};
                        keep_r     <= (P_r > 4'd4) ? 4'd8 : {P_r[2:0], 1'b0};
                        k_r        <= 4'd0;
                        c_r        <= 5'd0;
                        best_valid <= 1'b0;
                        st         <= ST_SCAN;
                    end
                end
                ST_FRZ_W: begin
                    stage_r <= 4'd0; j_r <= 8'd0;
                    st <= ST_PROP_A;
                end
                ST_SCAN: begin
                    if (scan_hit) begin
                        best_c <= c_r; best_pm <= cpm[c_r]; best_valid <= 1'b1;
                    end
                    if (c_r + 5'd1 == ncand) st <= ST_COMMIT;
                    else c_r <= c_r + 5'd1;
                end
                ST_COMMIT: begin
                    sel_par[k_r[2:0]] <= best_c[3:1];
                    sel_bit[k_r[2:0]] <= best_c[0];
                    sel_pm[k_r[2:0]]  <= best_pm;
                    ctaken[best_c]    <= 1'b1;
                    best_valid        <= 1'b0;
                    c_r               <= 5'd0;
                    k_r               <= k_r + 4'd1;
                    if (k_r + 4'd1 == keep_r) begin
                        cnt <= 12'd0;
                        st  <= ST_PERM;
                    end else st <= ST_SCAN;
                end
                ST_PERM: begin
                    if (cnt == DEPTH) begin
                        for (q = 0; q < L; q = q + 1)
                            pm[q] <= (q < keep_r) ? sel_pm[q] : 32'd0;
                        P_r <= keep_r;
                        stage_r <= 4'd0; j_r <= 8'd0;
                        st <= ST_PROP_A;
                    end else cnt <= cnt + 12'd1;
                end

                // ---- partial-sum climb, all paths at once ----
                ST_PROP_A: begin
                    if (right_c) st <= ST_PROP_B;
                    else         prop_advance;
                end
                ST_PROP_B: begin lw_reg <= bits_rdata; st <= ST_PROP_C; end
                ST_PROP_C: begin rw_reg <= bits_rdata; st <= ST_PROP_D; end
                ST_PROP_D: begin
                    if (j_r + 8'd1 < bl_c) begin
                        j_r <= j_r + 8'd1;
                        st  <= ST_PROP_A;
                    end else prop_advance;
                end

                // ---- winner and read-out ----
                ST_BEST: begin
                    if (best_hit) best_p <= c_r[2:0];
                    if (c_r == 5'd7) begin
                        cnt <= 12'd0;
                        st  <= ST_OUT;
                    end else c_r <= c_r + 5'd1;
                end
                ST_OUT: begin
                    if (cnt != 12'd0 && polar_info_pos(wb_addr[7:0]) != 8'hFF)
                        info_bits_out[polar_info_pos(wb_addr[7:0])] <= bits_rdata[best_p];
                    if (cnt == N) begin
                        pm_out <= pm[best_p];
                        st <= ST_END;
                    end else cnt <= cnt + 12'd1;
                end
                ST_END: begin
                    busy <= 1'b0; done <= 1'b1; st <= ST_IDLE;
                end
                default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
