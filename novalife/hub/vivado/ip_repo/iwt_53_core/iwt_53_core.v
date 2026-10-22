// Lifting 5/3 Integer Wavelet Transform (IWT) core (NovaLife) — one line, reversible
//
// Contract (frozen, G2 2026-10-19):
//   tools/stego_research/sims/iwt_lifting.iwt1d_53
//
//   even[k] = x[2k]      odd[k] = x[2k+1]        (len even, K = len/2)
//   d[k] = odd[k] - ((even[k] + even[k+1]) >> 1)      even[K] := even[K-1]  (replicated)
//   s[k] = even[k] + ((d[k-1] + d[k] + 2) >> 2)       d[-1]   := d[0]      (replicated)
//
//   `>>` is an arithmetic shift (floor), exactly as the reference's numpy int32 `>>`.
//   This is the *1D* kernel; the 2D transform is this kernel applied to the rows and then
//   to the columns, which is what the testbench composes and checks against `iwt2d_53`.
//
// The previous file was not this transform at all: it had one input register and computed
// `d = x - ((x + 0) >>> 1)` / `s = x + ((d + 0 + 2) >>> 2)` — no even/odd separation, no
// delay line, no edge replication, no second dimension — and its `m_axis_tuser` never
// distinguished LL/LH/HL/HH (it was hard-wired to 2'b00). Nothing integrates this core yet.
//
// Interface: pulse `start` with `len`; feed `len` samples while `ready_in`; the core emits
// d[k] (d_valid, d_idx=k) as soon as each one is known, then s[k] (s_valid, s_idx=k), then
// pulses `done`.  Two passes, ~2*len cycles per line.  The edge-replicated predictor is why
// the evens are buffered: d[k] is only known once even[k+1] has arrived.

`timescale 1ns / 1ps

module iwt_53_core #(
    parameter DATA_WIDTH = 16,   // signed sample width
    parameter MAX_LOG2   = 9     // longest line = 1 << MAX_LOG2 samples
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         start,      // latch `len`, begin a line
    input  wire [MAX_LOG2:0]            len,        // even, 2 <= len <= 1<<MAX_LOG2
    input  wire signed [DATA_WIDTH-1:0] sample_in,
    input  wire                         valid_in,
    output wire                         ready_in,

    output reg  signed [DATA_WIDTH+1:0] d_out,      // high-pass coefficient
    output reg                          d_valid,
    output reg  [MAX_LOG2-2:0]          d_idx,

    output reg  signed [DATA_WIDTH+1:0] s_out,      // low-pass coefficient
    output reg                          s_valid,
    output reg  [MAX_LOG2-2:0]          s_idx,

    output reg                          done
);

    localparam integer OW   = DATA_WIDTH + 2;      // |d|,|s| <= 2^(DATA_WIDTH-1) * 2
    localparam integer MW   = MAX_LOG2;            // sample index width (0..len-1)
    localparam integer KA   = MAX_LOG2 - 1;        // coefficient index width (0..K-1)
    localparam integer MAXK = (1 << KA);           // buffer depth

    localparam ST_IDLE = 3'd0;
    localparam ST_LOAD = 3'd1;
    localparam ST_S    = 3'd2;
    localparam ST_DONE = 3'd3;

    reg [2:0] st;

    reg [MW-1:0] K;             // len >> 1   (may be 2^(MW-1))
    reg [MW-1:0] wr;            // sample index while loading
    reg [KA-1:0] ke;            // index of the next even sample to buffer
    reg [KA-1:0] kd;            // index of the next high-pass coefficient
    reg [KA-1:0] k;             // output index in the s pass
    reg          phase;         // s pass: 0 = fetch, 1 = emit
    reg          have_odd;

    reg signed [DATA_WIDTH-1:0] odd_r;        // the pending odd sample
    reg signed [DATA_WIDTH-1:0] even_prev;    // even[k] for the pending odd
    reg signed [OW-1:0]         prev_d;       // d[k-1] in the s pass
    reg signed [OW-1:0]         d_r, even_r;  // s-pass fetch registers

    // The line buffers must land in block RAM, not in flip-flops: without the attribute
    // Vivado inferred 8682 FFs (24.7%) for 8704 bits of storage.  Reads are synchronous and
    // one port per array is used per phase, which is the standard single-port BRAM template.
    (* ram_style = "block" *) reg signed [DATA_WIDTH-1:0] ebuf [0:MAXK-1];   // evens
    (* ram_style = "block" *) reg signed [OW-1:0]         dbuf [0:MAXK-1];   // high-pass coeffs

    assign ready_in = (st == ST_LOAD);

    // ---- streaming predictor: d[k] = odd[k] - ((even[k] + even[k+1]) >> 1) --------------
    wire signed [OW-1:0] even_prev_x = even_prev;
    wire signed [OW-1:0] odd_x       = odd_r;
    wire signed [OW-1:0] sample_in_x = sample_in;
    wire signed [OW-1:0] pair_x      = even_prev_x + sample_in_x;
    wire signed [OW-1:0] d_stream    = odd_x - (pair_x >>> 1);
    wire signed [OW-1:0] d_last      = sample_in_x - even_prev_x;   // replicated even[K-1]

    // ---- update: s[k] = even[k] + ((d[k-1] + d[k] + 2) >> 2), d[-1] := d[0] -------------
    wire signed [OW-1:0] even_r_x = even_r;
    wire signed [OW-1:0] prev_eff = (k == {KA{1'b0}}) ? d_r : prev_d;
    wire signed [OW+2:0] acc      = prev_eff + d_r + 2;
    wire signed [OW-1:0] s_c      = even_r_x + (acc >>> 2);

    // ---- line memories ------------------------------------------------------------------
    // These live in a separate, RESET-FREE always block on purpose.  Vivado cannot map an
    // array written inside an asynchronous-reset block to block RAM (measured:
    // `WARNING: [Synth 8-4767] ... RAM is sensitive to asynchronous reset signal`), and the
    // buffers then fell back to 8682 flip-flops (24.7% of the part) for 8704 bits.
    // One port per array per phase: written while loading, read while updating.
    wire mem_wr_even = (st == ST_LOAD) && valid_in && !wr[0];
    wire mem_wr_det  = (st == ST_LOAD) && valid_in &&
                       ((wr[0] && (wr == (K << 1) - 1'b1)) || (!wr[0] && have_odd));
    wire mem_rd      = (st == ST_S) && !phase;

    always @(posedge clk) begin
        if (mem_wr_even) ebuf[ke] <= sample_in;
        if (mem_wr_det)  dbuf[kd] <= wr[0] ? d_last : d_stream;
        if (mem_rd) begin
            d_r    <= dbuf[k];      // fetched one cycle before it is used
            even_r <= ebuf[k];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st        <= ST_IDLE;
            K         <= {MW{1'b0}};
            wr        <= {MW{1'b0}};
            ke        <= {KA{1'b0}};
            kd        <= {KA{1'b0}};
            k         <= {KA{1'b0}};
            phase     <= 1'b0;
            have_odd  <= 1'b0;
            odd_r     <= {DATA_WIDTH{1'b0}};
            even_prev <= {DATA_WIDTH{1'b0}};
            prev_d    <= {OW{1'b0}};
            d_out     <= {OW{1'b0}};
            s_out     <= {OW{1'b0}};
            d_valid   <= 1'b0;
            s_valid   <= 1'b0;
            d_idx     <= {KA{1'b0}};
            s_idx     <= {KA{1'b0}};
            done      <= 1'b0;
        end else begin
            d_valid <= 1'b0;
            s_valid <= 1'b0;
            done    <= 1'b0;

            case (st)
                ST_IDLE: begin
                    if (start) begin
                        K        <= len[MAX_LOG2:1];
                        wr       <= {MW{1'b0}};
                        ke       <= {KA{1'b0}};
                        kd       <= {KA{1'b0}};
                        k        <= {KA{1'b0}};
                        phase    <= 1'b0;
                        have_odd <= 1'b0;
                        st       <= ST_LOAD;
                    end
                end

                ST_LOAD: begin
                    if (valid_in) begin
                        if (wr[0]) begin
                            // odd sample: hold it.  The last one has a replicated even
                            // neighbour, so its detail is known immediately.
                            odd_r    <= sample_in;
                            have_odd <= 1'b1;
                            if (wr == (K << 1) - 1'b1) begin
                                d_out    <= d_last;
                                d_idx    <= kd;
                                d_valid  <= 1'b1;
                                kd       <= kd + 1'b1;
                            end
                        end else begin
                            // even sample: it completes d[kd] whenever an odd is pending
                            if (have_odd) begin
                                d_out    <= d_stream;
                                d_idx    <= kd;
                                d_valid  <= 1'b1;
                                kd       <= kd + 1'b1;
                            end
                            ke        <= ke + 1'b1;
                            even_prev <= sample_in;
                        end

                        wr <= wr + 1'b1;
                        if (wr == (K << 1) - 1'b1) begin
                            st <= ST_S;
                        end
                    end
                end

                ST_S: begin
                    if (!phase) begin
                        phase  <= 1'b1;         // d_r/even_r are fetched by the memory block
                    end else begin
                        s_out   <= s_c;
                        s_idx   <= k;
                        s_valid <= 1'b1;
                        prev_d  <= d_r;
                        phase   <= 1'b0;
                        if (k == K - 1'b1) begin
                            st <= ST_DONE;
                        end else begin
                            k <= k + 1'b1;
                        end
                    end
                end

                ST_DONE: begin
                    done <= 1'b1;
                    st   <= ST_IDLE;
                end

                default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
