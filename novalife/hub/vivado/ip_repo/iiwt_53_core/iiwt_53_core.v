// Inverse Lifting 5/3 Integer Wavelet Transform (IWT) core (NovaLife)
//
// Contract (frozen):
//   tools/stego_research/sims/iwt_lifting.iiwt1d_53
//
//   Given s[k] (low-pass) and d[k] (high-pass), both length K:
//     prev_d[0] = d[0];  prev_d[k] = d[k-1] for k >= 1
//     even[k] = s[k] - ((prev_d[k] + d[k] + 2) >> 2)
//     next_even[k] = even[k+1] if k < K-1 else even[K-1]
//     odd[k] = d[k] + ((even[k] + next_even[k]) >> 1)
//     out[2k] = even[k];  out[2k+1] = odd[k]
//
// Interface: pulse `start` with `len` (= original signal length, even). Feed `len/2`
// s-samples then `len/2` d-samples (s first, then d) while `ready_in`. After all
// coefficients are loaded, the core computes and emits the original `len` samples
// as `sample_out` with `valid_out`, then pulses `done`.  ~2*len cycles per line.
//
// Memories: sbuf/dbuf/ebuf are written in a reset-free block with ONE read port each (the
// neighbour sample is held in a register), so they infer block RAM.  The first version read
// dbuf/ebuf at two addresses per cycle inside the reset block and synthesised to 7446 LUT /
// 13425 FF (42% of the part) -- results/g2_iiwt_2026-10-20.md.

`timescale 1ns / 1ps

module iiwt_53_core #(
    parameter DATA_WIDTH = 16,   // signed sample width (coefficients are DATA_WIDTH+2)
    parameter MAX_LOG2   = 9     // longest line = 1 << MAX_LOG2 samples
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         start,
    input  wire [MAX_LOG2:0]            len,
    input  wire signed [DATA_WIDTH+1:0]  coeff_in,
    input  wire                         valid_in,
    output wire                         ready_in,

    output reg  signed [DATA_WIDTH-1:0] sample_out,
    output reg                          valid_out,
    output reg  [MAX_LOG2-1:0]          sample_idx,

    output reg                          done
);

    localparam integer CW   = DATA_WIDTH + 2;
    localparam integer MW   = MAX_LOG2;
    localparam integer KA   = MAX_LOG2 - 1;
    localparam integer MAXK = (1 << KA);

    localparam [2:0] ST_IDLE   = 3'd0,
                     ST_LOAD_S = 3'd1,
                     ST_LOAD_D = 3'd2,
                     ST_COMP   = 3'd3,   // stream k: even[k] = s[k] - ((d[k-1] + d[k] + 2) >> 2)
                     ST_PRE    = 3'd4,   // read even[0]
                     ST_EMIT0  = 3'd5,   // emit even[k], read even[k+1] and d[k]
                     ST_EMIT1  = 3'd6,   // emit odd[k] = d[k] + ((even[k] + even[k+1]) >> 1)
                     ST_DONE   = 3'd7;

    reg [2:0]    st;
    reg [MW-1:0] K;
    reg [KA-1:0] ks, kd;
    reg [MW-1:0] kc;             // compute counter, one past the issued read (0..K)
    reg [KA-1:0] ke;             // emit index
    reg signed [CW-1:0] dprev;   // d[k-1] during compute
    reg signed [CW-1:0] e_cur;   // even[k] during emit

    assign ready_in = (st == ST_LOAD_S) || (st == ST_LOAD_D);

    // ---- memories: one write port, one registered read port each, no reset ----
    reg signed [CW-1:0] sbuf [0:MAXK-1];
    reg signed [CW-1:0] dbuf [0:MAXK-1];
    reg signed [CW-1:0] ebuf [0:MAXK-1];
    reg signed [CW-1:0] s_rd, d_rd, e_rd;

    wire [KA-1:0] kc_lo   = kc[KA-1:0];
    wire [KA-1:0] kc_prev = kc_lo - 1'b1;           // address of the sample on the read port
    wire [KA-1:0] ke_next = (ke == K - 1) ? ke : ke + 1'b1;

    // even[k] for the sample on the read port (k = kc-1); d[-1] := d[0]
    wire signed [CW-1:0] even_c =
        s_rd - (((((kc == 1) ? d_rd : dprev) + d_rd + 2) >>> 2));

    wire          s_we = (st == ST_LOAD_S) && valid_in;
    wire          d_we = (st == ST_LOAD_D) && valid_in;
    wire          e_we = (st == ST_COMP) && (kc != 0);
    reg  [KA-1:0] s_ra, d_ra, e_ra;
    always @(*) begin
        s_ra = kc_lo; d_ra = kc_lo; e_ra = {KA{1'b0}};
        if (st == ST_EMIT0) begin d_ra = ke; e_ra = ke_next; end
    end

    always @(posedge clk) begin
        if (s_we) sbuf[ks] <= coeff_in;
        s_rd <= sbuf[s_ra];
    end
    always @(posedge clk) begin
        if (d_we) dbuf[kd] <= coeff_in;
        d_rd <= dbuf[d_ra];
    end
    always @(posedge clk) begin
        if (e_we) ebuf[kc_prev] <= even_c;
        e_rd <= ebuf[e_ra];
    end

    // ---- sequencer ----
    always @(posedge clk) begin
        if (!rst_n) begin
            st <= ST_IDLE; done <= 1'b0; valid_out <= 1'b0;
            K <= 0; ks <= 0; kd <= 0; kc <= 0; ke <= 0;
            dprev <= 0; e_cur <= 0; sample_out <= 0; sample_idx <= 0;
        end else begin
            done <= 1'b0;
            valid_out <= 1'b0;
            case (st)
                ST_IDLE: if (start) begin
                    K  <= len >> 1;
                    ks <= 0; kd <= 0; kc <= 0; ke <= 0;
                    st <= ST_LOAD_S;
                end
                ST_LOAD_S: if (valid_in) begin
                    if (ks == K - 1) begin ks <= 0; st <= ST_LOAD_D; end
                    else ks <= ks + 1'b1;
                end
                ST_LOAD_D: if (valid_in) begin
                    if (kd == K - 1) begin kd <= 0; kc <= 0; st <= ST_COMP; end
                    else kd <= kd + 1'b1;
                end
                ST_COMP: begin
                    if (kc != 0) dprev <= d_rd;
                    if (kc == K) begin ke <= 0; st <= ST_PRE; end
                    else kc <= kc + 1'b1;
                end
                ST_PRE: st <= ST_EMIT0;           // e_ra = 0 issued in ST_PRE's cycle
                ST_EMIT0: begin
                    if (ke == 0) e_cur <= e_rd;   // even[0] arrives from ST_PRE
                    sample_out <= (ke == 0) ? e_rd[DATA_WIDTH-1:0] : e_cur[DATA_WIDTH-1:0];
                    valid_out  <= 1'b1;
                    sample_idx <= ke << 1;
                    st <= ST_EMIT1;
                end
                ST_EMIT1: begin
                    sample_out <= d_rd + ((e_cur + e_rd) >>> 1);
                    valid_out  <= 1'b1;
                    sample_idx <= (ke << 1) + 1'b1;
                    e_cur <= e_rd;
                    if (ke == K - 1) st <= ST_DONE;
                    else begin ke <= ke + 1'b1; st <= ST_EMIT0; end
                end
                ST_DONE: begin done <= 1'b1; st <= ST_IDLE; end
                default: st <= ST_IDLE;
            endcase
        end
    end
endmodule
