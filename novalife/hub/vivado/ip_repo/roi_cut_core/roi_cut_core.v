// roi_cut_core -- diagnostic-region threshold, exact integer (contract: embed.roi_cut).
//
//   pass 1: stream pixels in (pix_valid/pix); the core accumulates, with q = (p <= 16 ? 0 : p),
//           n = count, s = sum q, qq = sum q*q.
//   fin   : pulse after the last pixel.  The core then binary-searches the smallest p in 0..256
//           with  d = p*n - s > 0  and  25*d*d > D,  D = n*qq - s*s,  and raises `done` with
//           cut = that p (256 = nothing is ROI).  A pixel is ROI iff pixel >= cut.
//   Multi-cycle shift-add multiplies, no DSP; ~9 searches x ~110 cycles.
`timescale 1ns / 1ps

module roi_cut_core #(
    parameter integer STATS_FLOOR = 16
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,          // start a new image (also clears done)
    input  wire        pix_valid,
    input  wire [7:0]  pix,
    input  wire        fin,
    output reg         done,
    output reg  [8:0]  cut
);
    reg [31:0] n;      // up to 2^24 pixels used; wide for safety
    reg [39:0] s;
    reg [47:0] qq;

    wire [7:0] qv = (pix <= STATS_FLOOR) ? 8'd0 : pix;

    localparam S_IDLE = 4'd0, S_D1 = 4'd1, S_D2 = 4'd2, S_LOOP = 4'd3, S_A = 4'd4, S_A2 = 4'd5,
               S_CMP = 4'd6, S_FIN = 4'd7;
    reg [3:0]  st;

    // sequential unsigned multiplier: prod = ma * mb (up to 72 x 72 -> 144 truncated to 96)
    reg         mul_go, mul_busy;
    reg [95:0]  ma, prod;
    reg [47:0]  mb;
    reg [7:0]   mcnt;
    reg         mul_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mul_busy <= 1'b0; mul_done <= 1'b0; prod <= 96'd0; ma <= 96'd0; mb <= 48'd0; mcnt <= 8'd0;
        end else begin
            mul_done <= 1'b0;
            if (mul_go && !mul_busy) begin
                mul_busy <= 1'b1; prod <= 96'd0; mcnt <= 8'd0;
            end else if (mul_busy) begin
                if (mb[0]) prod <= prod + ma;
                ma <= ma << 1; mb <= mb >> 1; mcnt <= mcnt + 8'd1;
                if (mcnt == 8'd47) begin mul_busy <= 1'b0; mul_done <= 1'b1; end
            end
        end
    end

    reg [8:0]  lo, hi, mid;
    reg [95:0] dbig;        // D = n*qq - s*s
    reg [95:0] t1;          // n*qq
    reg [95:0] dd;          // d (signed value magnitude when positive)
    reg        dpos;
    reg [95:0] sq;
    reg        issue;       // a multiply operand load is pending

    // operand staging happens in the FSM; a multiply is started by loading ma/mb then mul_go
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; done <= 1'b0; cut <= 9'd0; n <= 0; s <= 0; qq <= 0;
            lo <= 0; hi <= 0; mid <= 0; dbig <= 0; t1 <= 0; dd <= 0; dpos <= 0; sq <= 0;
            mul_go <= 1'b0; issue <= 1'b0;
        end else begin
            mul_go <= 1'b0;
            if (clear) begin
                n <= 0; s <= 0; qq <= 0; done <= 1'b0; st <= S_IDLE;
            end else begin
                case (st)
                    S_IDLE: begin
                        if (pix_valid) begin
                            n  <= n + 32'd1;
                            s  <= s + {32'd0, qv};
                            qq <= qq + {40'd0, qv} * {40'd0, qv};
                        end
                        if (fin) begin
                            // t1 = n * qq
                            ma <= {64'd0, n}; mb <= qq; mul_go <= 1'b1; st <= S_D1;
                        end
                    end
                    S_D1: if (mul_done) begin
                        t1 <= prod;
                        ma <= {56'd0, s}; mb <= {8'd0, s}; mul_go <= 1'b1; st <= S_D2;
                    end
                    S_D2: if (mul_done) begin
                        dbig <= t1 - prod;       // D >= 0 by Cauchy-Schwarz
                        lo <= 9'd0; hi <= 9'd256; st <= S_LOOP;
                    end
                    S_LOOP: begin
                        if (lo >= hi) begin
                            cut <= lo; done <= 1'b1; st <= S_FIN;
                        end else begin
                            mid <= (lo + hi) >> 1;
                            // d = mid*n - s  (compare, then magnitude); mid*n <= 256*2^24 fits
                            st <= S_A;
                        end
                    end
                    S_A: begin
                        // mid*n via 9-bit shift-add is cheap: use the multiplier for uniformity
                        ma <= {87'd0, mid}; mb <= {16'd0, n}; mul_go <= 1'b1; st <= S_A2;
                    end
                    S_A2: if (mul_done) begin
                        if (prod > {56'd0, s}) begin
                            dpos <= 1'b1; dd <= prod - {56'd0, s};
                            // sq = 25 * d^2 : compute d^2 first
                            ma <= prod - {56'd0, s}; mb <= (prod - {56'd0, s}); mul_go <= 1'b1; st <= S_CMP;
                        end else begin
                            dpos <= 1'b0; lo <= mid + 9'd1; st <= S_LOOP;
                        end
                    end
                    S_CMP: if (mul_done) begin
                        if ((prod * 96'd25) > dbig) hi <= mid; else lo <= mid + 9'd1;
                        st <= S_LOOP;
                    end
                    S_FIN: ;
                    default: st <= S_IDLE;
                endcase
            end
        end
    end
endmodule
