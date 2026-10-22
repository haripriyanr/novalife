// Perceptual Mask Engine Core (NovaLife) — block variance + ROI gate
//
// Contract (frozen, G2 2026-10-19):
//   tools/stego_research/sims/perceptual_mask.mask_block_decision
//
//   for a block of BLOCK signed 16-bit samples x_i and ROI bits r_i:
//       sum_x  = Σ x_i                    sum_x2 = Σ x_i^2
//       var    = mean_x2 - mean_x^2   clamped at 0
//                mean_x  = sum_x  / BLOCK   (FLOOR, i.e. an arithmetic shift)
//                mean_x2 = sum_x2 / BLOCK   (logical shift)
//       mask   = 1 iff  (roi_count * 2 < BLOCK)  and  (var > VAR_THRESHOLD)
//
//   `roi_count * 2 < BLOCK` is the reference's `np.mean(tile_roi) < 0.5` — a **majority**
//   test, not "any pixel is ROI".  `var > 1` is the reference's `var > 1.0`.
//
// This replaces an earlier core that was NOT the reference's arithmetic: it used an
// 8-bit sample input, `>=` on a Q16.8 threshold, an OR (any-ROI) gate, and no variance
// output, so it could not be checked bit-exactly against anything.  Nothing integrates
// this core yet (the tag pipeline is not built), so the interface changed.
//
// Interface: one sample per cycle while `ready_out` is high; after BLOCK samples the core
// takes two cycles to compute (mean, then variance+mask), then pulses `valid_out` with
// `var_out` and `mask_out`.  Latency: BLOCK + 2 cycles per block.  The two compute cycles
// exist because accumulation -> mean -> square -> clamp -> compare does not fit in one
// 100 MHz period on xc7z010-1 (measured: WNS -1.921 ns with a single cycle).

`timescale 1ns / 1ps

module perceptual_mask_core #(
    parameter DATA_WIDTH    = 16,   // signed sample width
    parameter BLOCK_LOG2    = 4,    // block length = 1 << BLOCK_LOG2 samples
    parameter VAR_THRESHOLD = 1     // mask requires var > VAR_THRESHOLD
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // one signed sub-band sample plus its ROI bit
    input  wire signed [DATA_WIDTH-1:0] sample_in,
    input  wire                         roi_mask_in,
    input  wire                         valid_in,
    output wire                         ready_out,

    // block result: the integer variance and the embeddable bit
    output reg                          mask_out,
    output reg  [31:0]                  var_out,
    output reg                          valid_out
);

    localparam integer BLOCK = (1 << BLOCK_LOG2);
    localparam integer SUM_W = DATA_WIDTH + BLOCK_LOG2 + 1;   // holds BLOCK * 2^(DATA_W-1)
    localparam integer SQ_W  = 2 * DATA_WIDTH + BLOCK_LOG2;   // holds BLOCK * 2^(2*DATA_W-2)
    localparam integer MEAN_W  = DATA_WIDTH + 1;              // block mean, floor-divided
    localparam integer MEAN2_W = SQ_W - BLOCK_LOG2;           // block mean of squares
    localparam integer MSQ_W   = 2 * MEAN_W;                  // mean_x^2
    localparam integer VAR_W   = ((MEAN2_W > MSQ_W) ? MEAN2_W : MSQ_W) + 1;

    localparam ST_ACC  = 2'd0;
    localparam ST_MEAN = 2'd1;
    localparam ST_CALC = 2'd2;

    reg [1:0] st;

    reg [BLOCK_LOG2-1:0]     cnt;
    reg signed [SUM_W-1:0]   sum_x;
    reg        [SQ_W-1:0]    sum_x2;
    reg [BLOCK_LOG2:0]       roi_cnt;

    reg signed [MEAN_W-1:0]  mean_x_r;
    reg        [MEAN2_W-1:0] mean_x2_r;

    wire signed [2*DATA_WIDTH-1:0] sq = sample_in * sample_in;

    assign ready_out = (st == ST_ACC);

    // ------------------------------------------------------------------ stage 1: the means
    // mean_x is a FLOOR division: `>>>` on a signed operand is an arithmetic shift, which
    // floors for two's complement exactly like Python's `//`.
    wire signed [MEAN_W-1:0]  mean_x_c  = sum_x >>> BLOCK_LOG2;
    wire        [MEAN2_W-1:0] mean_x2_c = sum_x2 >> BLOCK_LOG2;

    // ------------------------------------------------------------------ stage 2: the decision
    wire signed [MSQ_W-1:0]  mean_x_sq = mean_x_r * mean_x_r;
    wire signed [VAR_W-1:0]  var_raw   =
        $signed({{(VAR_W-MEAN2_W){1'b0}}, mean_x2_r})
        - $signed({{(VAR_W-MSQ_W){mean_x_sq[MSQ_W-1]}}, mean_x_sq});

    wire [31:0] var_c  = (var_raw < 0) ? 32'd0 : var_raw[31:0];
    wire        roi_ok = ((roi_cnt * 2) < BLOCK);
    wire        mask_c = roi_ok && (var_c > VAR_THRESHOLD);

    // ------------------------------------------------------------------ datapath
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st        <= ST_ACC;
            cnt       <= {BLOCK_LOG2{1'b0}};
            sum_x     <= {SUM_W{1'b0}};
            sum_x2    <= {SQ_W{1'b0}};
            roi_cnt   <= {(BLOCK_LOG2+1){1'b0}};
            mean_x_r  <= {MEAN_W{1'b0}};
            mean_x2_r <= {MEAN2_W{1'b0}};
            mask_out  <= 1'b0;
            var_out   <= 32'd0;
            valid_out <= 1'b0;
        end else begin
            case (st)
                ST_ACC: begin
                    valid_out <= 1'b0;
                    if (valid_in) begin
                        sum_x   <= sum_x + sample_in;
                        sum_x2  <= sum_x2 + $unsigned(sq);
                        roi_cnt <= roi_cnt + { {(BLOCK_LOG2){1'b0}}, roi_mask_in };
                        cnt     <= cnt + 1'b1;
                        if (cnt == (BLOCK - 1)) begin
                            // the accumulators now hold the whole block; compute next
                            cnt <= {BLOCK_LOG2{1'b0}};
                            st  <= ST_MEAN;
                        end
                    end
                end

                ST_MEAN: begin
                    valid_out <= 1'b0;
                    mean_x_r  <= mean_x_c;
                    mean_x2_r <= mean_x2_c;
                    st        <= ST_CALC;
                end

                ST_CALC: begin
                    var_out   <= var_c;
                    mask_out  <= mask_c;
                    valid_out <= 1'b1;
                    sum_x     <= {SUM_W{1'b0}};
                    sum_x2    <= {SQ_W{1'b0}};
                    roi_cnt   <= {(BLOCK_LOG2+1){1'b0}};
                    st        <= ST_ACC;
                end

                default: st <= ST_ACC;
            endcase
        end
    end

endmodule
