// Polar SC decoder (N=256, K=128, list size 1) — bit-exact against the integer contract in
// tools/tag_reference/vectors/gen_polar_decode_vectors.py, and MEMORY-BACKED so it synthesises
// on the XC7Z010.
//
// Why memory-backed: the first version kept the whole SC tree in registers (`llr[9][256]` 16-bit
// + `bits[9][256]` = 39,168 flip-flops > the part's 35,200 slice registers), so Vivado was killed
// (OOM) inferring the variable-index multiplexers.  Here the same tree lives in two inferred
// simple-dual-port memories (llr 2304 x 16b = one RAMB36, bits 2304 x 1b = one RAMB18) and a small
// microsequencer walks the algorithm one element at a time.  ~4 bytes of state instead of 39k flops.
//
// The write data path is pipelined (abs registers -> min/sign -> conditional negate -> write) so a
// combinational F/G between the two RAM ports does not become the critical path.
//
// Arithmetic (the fixed-point contract; see polar_decode_vectors.json):
//   F(a,b) = sign(a)*sign(b)*min(|a|,|b|)      (sign(0)=0; sign XOR + conditional negate, no mult)
//   G(a,b,u) = b + (1-2u)*a
//   decision at leaf i: frozen -> 0, else 0 if llr[0][i] >= 0 else 1
//
// Memory addressing: A(stage, idx) = {stage[3:0], idx[7:0]}  (stage 0..8, idx 0..255).
//
// Interface: write the 256 channel LLRs (wr_addr = channel), pulse `start`, wait for `done`,
// read the 128 info bits (bit j = info bit j).
//
// Throughput (structural, the same for every codeword): ~0.46 M cycles = ~4.6 ms at 100 MHz,
// ~9.2 ms at 50 MHz.  Slow on purpose — the point is that it fits and is bit-exact.

`timescale 1ns / 1ps
`include "polar_params.vh"
`include "polar_dec_params.vh"

module polar_sc_decoder #(
    parameter N = 256,
    parameter K = 128,
    parameter W = 16
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // LLR load port (write before `start`, while idle)
    input  wire                 wr_en,
    input  wire [7:0]           wr_addr,
    input  wire signed [W-1:0]  wr_llr,

    input  wire                 start,
    output reg                  busy,
    output reg                  done,

    output reg  [K-1:0]         info_bits_out
);

    // ---- helpers (declared before use) --------------------------------------------------------
    function [W-1:0] f_abs_u;                 // |v| as an unsigned magnitude
        input signed [W-1:0] v;
        begin f_abs_u = v[W-1] ? -v : v; end
    endfunction

    localparam integer LOG2N  = 8;
    localparam integer DEPTH  = (LOG2N + 1) * N;      // 2304 addresses
    localparam [11:0]  CLR_LLR_LAST = LOG2N * N - 1;  // 2047: stages 0..7 (not the channel stage)

    // states
    localparam [3:0] ST_IDLE  = 4'd0,
                     ST_CLR   = 4'd1,
                     ST_UPD_A = 4'd2,
                     ST_UPD_B = 4'd3,
                     ST_UPD_C = 4'd4,
                     ST_UPD_D = 4'd5,
                     ST_UPD_E = 4'd6,
                     ST_DEC_A = 4'd7,
                     ST_DEC_B = 4'd8,
                     ST_PROP_A= 4'd9,
                     ST_PROP_B= 4'd10,
                     ST_PROP_C= 4'd11,
                     ST_PROP_D= 4'd12,
                     ST_END   = 4'd13;

    reg [3:0]  st;
    reg [7:0]  i_r;
    reg [3:0]  stage_r;
    reg [7:0]  j_r;
    reg [11:0] clr_cnt;

    // datapath registers
    reg signed [W-1:0] a_reg, b_reg;
    reg [W-1:0]        ma_r, mb_r;   // |a|, |b| magnitudes (registered)
    reg                sgn_r;        // sign(a) xor sign(b)
    reg signed [W-1:0] wdata_r;      // F/G result, registered before the llr write
    reg                u_reg, l_reg, r_reg;

    // ---- memories (inferred simple dual-port RAM: 1 write port + 1 registered read port) ----
    reg signed [W-1:0] llr_mem [0:DEPTH-1];
    reg signed [W-1:0] llr_rdata;
    reg                bits_mem [0:DEPTH-1];
    reg                bits_rdata;

    // ---- combinational address / control -----------------------------------------------------
    reg [3:0]  rd_stage_c, bd_stage_c, lw_stage_c, bw_stage_c;
    reg [7:0]  rd_idx_c,   bd_idx_c,   lw_idx_c,   bw_idx_c;
    reg        llr_we_c,   bits_we_c;
    reg [W-1:0] llr_wdata_c;
    reg        bits_wdata_c;
    reg [7:0]  bl_c, off_c;
    reg        left_c, right_c;
    reg        dec_val_c;
    reg [W-1:0] mag_c;

    always @(*) begin
        bl_c    = 8'd1 << stage_r;
        off_c   = (i_r >> (stage_r + 1)) << (stage_r + 1);
        left_c  = (((i_r >> stage_r) & 8'd1) == 8'd0);
        right_c = ~left_c;
        dec_val_c = POLAR_FROZEN_MASK[i_r] ? 1'b0 : (llr_rdata < 0);
        mag_c   = (ma_r < mb_r) ? ma_r : mb_r;
    end

    always @(*) begin
        rd_stage_c = 4'd0; rd_idx_c = 8'd0;
        bd_stage_c = 4'd0; bd_idx_c = 8'd0;
        lw_stage_c = 4'd0; lw_idx_c = 8'd0;
        bw_stage_c = 4'd0; bw_idx_c = 8'd0;
        llr_we_c = 1'b0; bits_we_c = 1'b0;
        llr_wdata_c = {W{1'b0}};
        bits_wdata_c = 1'b0;

        case (st)
            // clear: bits 0..2303, llr stages 0..7
            ST_CLR: begin
                bits_we_c  = 1'b1;
                bw_stage_c = clr_cnt[11:8];
                bw_idx_c   = clr_cnt[7:0];
                bits_wdata_c = 1'b0;
                if (clr_cnt <= CLR_LLR_LAST) begin
                    llr_we_c   = 1'b1;
                    lw_stage_c = clr_cnt[11:8];
                    lw_idx_c   = clr_cnt[7:0];
                    llr_wdata_c = {W{1'b0}};
                end
            end
            // descend: A reads a,u ; B reads b ; C/D pipeline the combine ; E writes llr[s]
            ST_UPD_A: begin
                rd_stage_c = stage_r + 4'd1; rd_idx_c = off_c + j_r;
                bd_stage_c = stage_r;        bd_idx_c = off_c + j_r;
            end
            ST_UPD_B: begin
                rd_stage_c = stage_r + 4'd1; rd_idx_c = off_c + bl_c + j_r;
            end
            ST_UPD_E: begin
                llr_we_c   = 1'b1;
                lw_stage_c = stage_r;
                lw_idx_c   = left_c ? (off_c + j_r) : (off_c + bl_c + j_r);
                llr_wdata_c = wdata_r;
            end
            // decide leaf i
            ST_DEC_A: begin
                rd_stage_c = 4'd0; rd_idx_c = i_r;
            end
            ST_DEC_B: begin
                bits_we_c = 1'b1; bw_stage_c = 4'd0; bw_idx_c = i_r; bits_wdata_c = dec_val_c;
            end
            // climb: read l, read r, write l^r, write r
            ST_PROP_A: if (right_c) begin bd_stage_c = stage_r; bd_idx_c = off_c + j_r; end
            ST_PROP_B: if (right_c) begin bd_stage_c = stage_r; bd_idx_c = off_c + bl_c + j_r; end
            ST_PROP_C: if (right_c) begin
                bits_we_c = 1'b1; bw_stage_c = stage_r + 4'd1; bw_idx_c = off_c + j_r;
                bits_wdata_c = l_reg ^ bits_rdata;
            end
            ST_PROP_D: if (right_c) begin
                bits_we_c = 1'b1; bw_stage_c = stage_r + 4'd1; bw_idx_c = off_c + bl_c + j_r;
                bits_wdata_c = r_reg;
            end
            default: ;
        endcase
    end

    // load port has priority while idle; the FSM owns the write port otherwise
    wire        idle_load = (st == ST_IDLE) && wr_en;
    wire        llr_we    = llr_we_c | idle_load;
    wire [11:0] llr_waddr = idle_load ? {4'd8, wr_addr} : {lw_stage_c, lw_idx_c};
    wire signed [W-1:0] llr_wdata = idle_load ? wr_llr : llr_wdata_c;
    wire [11:0] llr_raddr = {rd_stage_c, rd_idx_c};
    wire        bits_we    = bits_we_c;
    wire [11:0] bits_waddr = {bw_stage_c, bw_idx_c};
    wire        bits_wdata = bits_wdata_c;
    wire [11:0] bits_raddr = {bd_stage_c, bd_idx_c};

    always @(posedge clk) begin
        if (llr_we) llr_mem[llr_waddr] <= llr_wdata;
        llr_rdata <= llr_mem[llr_raddr];
    end

    always @(posedge clk) begin
        if (bits_we) bits_mem[bits_waddr] <= bits_wdata;
        bits_rdata <= bits_mem[bits_raddr];
    end

    // advance the climb to the next stage, or the next leaf
    task prop_advance;
        begin
            j_r <= 8'd0;
            if (stage_r == LOG2N - 1) begin
                if (i_r == N - 1) begin
                    st <= ST_END;
                end else begin
                    i_r     <= i_r + 8'd1;
                    stage_r <= LOG2N - 1;
                    st      <= ST_UPD_A;
                end
            end else begin
                stage_r <= stage_r + 4'd1;
                st      <= ST_PROP_A;
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st            <= ST_IDLE;
            busy          <= 1'b0;
            done          <= 1'b0;
            info_bits_out <= {K{1'b0}};
            i_r           <= 8'd0;
            stage_r       <= 4'd0;
            j_r           <= 8'd0;
            clr_cnt       <= 12'd0;
            a_reg <= {W{1'b0}}; b_reg <= {W{1'b0}};
            ma_r  <= {W{1'b0}}; mb_r  <= {W{1'b0}}; sgn_r <= 1'b0;
            wdata_r <= {W{1'b0}};
            u_reg <= 1'b0; l_reg <= 1'b0; r_reg <= 1'b0;
        end else begin
            case (st)
                ST_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        busy    <= 1'b1;
                        clr_cnt <= 12'd0;
                        st      <= ST_CLR;
                    end
                end

                ST_CLR: begin
                    if (clr_cnt == DEPTH - 1) begin
                        i_r     <= 8'd0;
                        stage_r <= LOG2N - 1;
                        j_r     <= 8'd0;
                        st      <= ST_UPD_A;
                    end else begin
                        clr_cnt <= clr_cnt + 12'd1;
                    end
                end

                ST_UPD_A: st <= ST_UPD_B;

                ST_UPD_B: begin
                    a_reg <= llr_rdata;          // a
                    ma_r  <= f_abs_u(llr_rdata); // |a|
                    u_reg <= bits_rdata;         // u_left
                    st    <= ST_UPD_C;
                end

                ST_UPD_C: begin
                    b_reg <= llr_rdata;          // b (last cycle it is on the read port)
                    mb_r  <= f_abs_u(llr_rdata); // |b|
                    sgn_r <= a_reg[W-1] ^ llr_rdata[W-1];
                    st    <= ST_UPD_D;
                end

                ST_UPD_D: begin
                    wdata_r <= left_c
                        ? (sgn_r ? -mag_c : mag_c)                       // F
                        : (b_reg + (u_reg ? -a_reg : a_reg));            // G
                    st      <= ST_UPD_E;
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
                    if (polar_info_pos(i_r) != 8'hFF)
                        info_bits_out[polar_info_pos(i_r)] <= dec_val_c;
                    stage_r <= 4'd0;
                    j_r     <= 8'd0;
                    st      <= ST_PROP_A;
                end

                ST_PROP_A: begin
                    if (right_c) st <= ST_PROP_B;
                    else         prop_advance;
                end

                ST_PROP_B: begin
                    l_reg <= bits_rdata;
                    st    <= ST_PROP_C;
                end

                ST_PROP_C: begin
                    r_reg <= bits_rdata;
                    st    <= ST_PROP_D;
                end

                ST_PROP_D: begin
                    if (j_r + 8'd1 < bl_c) begin
                        j_r <= j_r + 8'd1;
                        st  <= ST_PROP_A;
                    end else begin
                        prop_advance;
                    end
                end

                ST_END: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    st    <= ST_IDLE;
                end

                default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
