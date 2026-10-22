// Pilot Grid Sync core (NovaLife) -- **NOT the reference estimator. Placeholder; do not cite.**
//
// Audit 2026-10-20 (docs/improvement_review_2026-10-20.md): the header used to say this core's
// contract is tools/tag_reference/pilot_grid.measure_axis.  It is not.  It computes a raw
// autocorrelation sum_k x[k]x[k+lag] over lags 1..MAX_LAG and returns the argmax.  The reference
// additionally (1) subtracts a local baseline (the B samples before each sample), (2) removes the
// mean, (3) normalises each lag by (n - lag), (4) restricts the lag window to
// [SCALE_MIN*G, min(n/3, SCALE_MAX*G)], (5) refines the period with a Hann-windowed DFT (float),
// (6) searches the phase, and (7) computes a trust flag.  None of that is here, and there is no
// testbench and no vector set.
//
// Whether the PL needs a pilot estimator at all is an open design question: a pure resize takes
// its scale from the received/declared size ratio (no pilot), and the crop locator uses the size
// residual, not the period.  Recommendation: keep the geometry search on the PS and give the PL
// only VERIFY on the restored image.  Until that is decided this file is a placeholder.
//
// Interface (as written): pulse `start` with `len`; feed `len` samples while `ready_in`; emits
// `period` (the argmax lag) and `scale` (Q8.8), then pulses `done`.

`timescale 1ns / 1ps

module pilot_grid_sync #(
    parameter DATA_WIDTH = 16,
    parameter MAX_LOG2   = 9,
    parameter MAX_LAG    = 32,
    parameter G          = 16
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         start,
    input  wire [MAX_LOG2:0]            len,
    input  wire signed [DATA_WIDTH-1:0]  sample_in,
    input  wire                         valid_in,
    output wire                         ready_in,

    output reg  [MAX_LOG2:0]            period,
    output reg  [15:0]                  scale_q,
    output reg                          done
);

    localparam integer MW = MAX_LOG2;
    localparam integer AW = DATA_WIDTH * 2 + 8;

    localparam ST_IDLE    = 3'd0;
    localparam ST_LOAD    = 3'd1;
    localparam ST_COMPUTE = 3'd2;
    localparam ST_FIND    = 3'd3;
    localparam ST_DONE    = 3'd4;

    reg [2:0] st;

    reg [MW-1:0] N;
    reg [MW-1:0] idx;
    reg [5:0]    lag;
    reg [5:0]    best_lag;
    reg signed [AW-1:0] best_corr;
    reg signed [AW-1:0] corr;
    reg [MW-1:0] k;

    reg signed [DATA_WIDTH-1:0] sig [0:(1<<MAX_LOG2)-1];

    assign ready_in = (st == ST_LOAD);

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= ST_IDLE;
            done <= 1'b0;
            idx <= 0;
            lag <= 1;
            best_lag <= G;
            best_corr <= 0;
            corr <= 0;
            k <= 0;
        end else begin
            done <= 1'b0;

            case (st)
                ST_IDLE: begin
                    if (start) begin
                        N <= len;
                        idx <= 0;
                        lag <= 1;
                        best_lag <= G;
                        best_corr <= 0;
                        corr <= 0;
                        k <= 0;
                        st <= ST_LOAD;
                    end
                end

                ST_LOAD: begin
                    if (valid_in) begin
                        sig[idx] <= sample_in;
                        if (idx == N - 1) begin
                            idx <= 0;
                            lag <= 1;
                            k <= 0;
                            corr <= 0;
                            best_corr <= 0;
                            best_lag <= 1;
                            st <= ST_COMPUTE;
                        end else begin
                            idx <= idx + 1;
                        end
                    end
                end

                ST_COMPUTE: begin
                    if (k < N - lag) begin
                        corr <= corr + sig[k] * sig[k + lag];
                        k <= k + 1;
                    end else begin
                        if (corr > best_corr) begin
                            best_corr <= corr;
                            best_lag <= lag;
                        end
                        if (lag >= MAX_LAG) begin
                            st <= ST_FIND;
                        end else begin
                            lag <= lag + 1;
                            k <= 0;
                            corr <= 0;
                        end
                    end
                end

                ST_FIND: begin
                    period <= best_lag;
                    scale_q <= (best_lag << 8) / G;
                    st <= ST_DONE;
                end

                ST_DONE: begin
                    done <= 1'b1;
                    st <= ST_IDLE;
                end

                default: st <= ST_IDLE;
            endcase
        end
    end
endmodule
