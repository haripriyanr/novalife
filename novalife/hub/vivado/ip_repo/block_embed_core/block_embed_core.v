// Block Embed Core (NovaLife) — integer sign-of-Hadamard embedding for 4x4 LL blocks
//
// Contract (frozen, algorithm.md 3.2):
//   tools/tag_reference/embed.py
//   tools/tag_reference/vectors/gen_block_embed_vectors.py
//
// Operations per 4x4 block (16 signed 16-bit LL samples):
//   1. isqrt: std = isqrt(var_in[31:0]) (16 cycles)
//      concurrently during input / isqrt: projection v = sum(H * x) (accumulated on input)
//   2. ST_CALC1:
//      - prod = 5 * root; delta = 64 + (prod >> 3); force even
//      - T = delta / 2; cap = 4 * T
//   3. ST_CALC2:
//      - error e = (+T - v) if bit 0 and v < T; (-T - v) if bit 1 and v > -T; else 0
//      - clamp e to [-cap, cap]
//      - q = e >>> 4; rem = e & 15
//   4. ST_OUT: stream 16 samples:
//        d_k = q + ((k < rem) ? 1 : 0)
//        y_k = x_k + H_k * d_k
//
// Meets 100 MHz timing constraint on Artix-7 / Zynq-7000 (-1 speed grade).

`timescale 1ns / 1ps

module block_embed_core #(
    parameter DATA_WIDTH = 16
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // Block inputs
    input  wire signed [DATA_WIDTH-1:0] sample_in,
    input  wire                         valid_in,
    input  wire [31:0]                  var_in,
    input  wire                         bit_in,
    output wire                         ready_out,

    // Output block
    output reg  signed [DATA_WIDTH-1:0] sample_out,
    output reg  [3:0]                   sample_idx_out,
    output reg  [15:0]                  delta_out,
    output reg  signed [31:0]           v_out,
    output reg                          rbit_out,
    output reg                          valid_out
);

    // Hadamard flattened: outer([1,1,-1,-1], [1,1,-1,-1])
    function signed [1:0] hadamard_sign;
        input [3:0] idx;
        begin
            case (idx)
                4'd0,  4'd1,  4'd4,  4'd5,  4'd10, 4'd11, 4'd14, 4'd15: hadamard_sign = 2'sd1;
                default:                                                 hadamard_sign = -2'sd1;
            endcase
        end
    endfunction

    // Sequential states
    localparam ST_IDLE    = 3'd0;
    localparam ST_IN      = 3'd1;
    localparam ST_ISQRT   = 3'd2;
    localparam ST_CALC1   = 3'd3;
    localparam ST_CALC2   = 3'd4;
    localparam ST_OUT     = 3'd5;

    reg [2:0] state;

    // Buffer for 16 input samples
    reg signed [DATA_WIDTH-1:0] x_mem [0:15];
    reg [3:0] in_cnt;
    reg [3:0] out_cnt;

    reg [31:0] var_reg;
    reg        bit_reg;

    // isqrt engine registers (16 steps for 32-bit input)
    reg [31:0] sq_rem;
    reg [15:0] sq_root;
    reg [4:0]  sq_step;

    // Computed values
    reg signed [31:0] v_proj;
    reg [15:0] delta_reg;
    reg signed [15:0] t_reg;
    reg signed [17:0] cap_reg; // 4 * T
    reg signed [20:0] e_val;
    reg signed [20:0] q_val;
    reg [3:0]         rem_val;
    reg               rbit_reg;

    // Combinational / temporary signals
    reg [33:0] r_shifted;
    reg [17:0] trial;
    reg [31:0] prod;
    reg [15:0] d0;
    reg [15:0] d_val;
    reg signed [15:0] t_val;
    reg signed [17:0] cap_val;
    reg signed [20:0] e_init;
    reg signed [20:0] e_capped;
    reg signed [20:0] d_k;
    reg signed [DATA_WIDTH-1:0] adj_sample;
    integer i;

    assign ready_out = (state == ST_IDLE) || (state == ST_IN);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            in_cnt         <= 4'd0;
            out_cnt        <= 4'd0;
            var_reg        <= 32'd0;
            bit_reg        <= 1'b0;
            sq_rem         <= 32'd0;
            sq_root        <= 16'd0;
            sq_step        <= 5'd0;
            v_proj         <= 32'sd0;
            delta_reg      <= 16'd0;
            t_reg          <= 16'sd0;
            cap_reg        <= 18'sd0;
            e_val          <= 21'sd0;
            q_val          <= 21'sd0;
            rem_val        <= 4'd0;
            rbit_reg       <= 1'b0;
            sample_out     <= {DATA_WIDTH{1'b0}};
            sample_idx_out <= 4'd0;
            delta_out      <= 16'd0;
            v_out          <= 32'sd0;
            rbit_out       <= 1'b0;
            valid_out      <= 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                x_mem[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            valid_out <= 1'b0;

            case (state)
                ST_IDLE: begin
                    in_cnt <= 4'd0;
                    if (valid_in) begin
                        x_mem[0] <= sample_in;
                        var_reg  <= var_in;
                        bit_reg  <= bit_in;
                        // Accumulate sample 0 into v_proj: idx 0 has hadamard_sign +1
                        v_proj   <= $signed(sample_in);
                        in_cnt   <= 4'd1;
                        state    <= ST_IN;
                    end
                end

                ST_IN: begin
                    if (valid_in) begin
                        x_mem[in_cnt] <= sample_in;
                        if (hadamard_sign(in_cnt) == 2'sd1)
                            v_proj <= v_proj + $signed(sample_in);
                        else
                            v_proj <= v_proj - $signed(sample_in);

                        if (in_cnt == 4'd15) begin
                            sq_rem  <= 32'd0;
                            sq_root <= 16'd0;
                            sq_step <= 5'd16;
                            state   <= ST_ISQRT;
                        end else begin
                            in_cnt <= in_cnt + 4'd1;
                        end
                    end
                end

                ST_ISQRT: begin
                    r_shifted = {sq_rem[31:0], var_reg[31:30]};
                    var_reg   <= {var_reg[29:0], 2'b00};
                    trial     = {sq_root, 2'b01};
                    if (r_shifted >= trial) begin
                        sq_rem  <= r_shifted - trial;
                        sq_root <= {sq_root[14:0], 1'b1};
                    end else begin
                        sq_rem  <= r_shifted[31:0];
                        sq_root <= {sq_root[14:0], 1'b0};
                    end

                    if (sq_step == 5'd1) begin
                        state <= ST_CALC1;
                    end else begin
                        sq_step <= sq_step - 5'd1;
                    end
                end

                ST_CALC1: begin
                    // Compute delta, T, and cap from sq_root
                    prod     = 32'd5 * sq_root;
                    d0       = 16'd64 + prod[18:3];
                    d_val    = d0 + {15'd0, d0[0]};
                    t_val    = $signed(d_val >> 1);
                    cap_val  = t_val <<< 2; // 4 * T

                    delta_reg <= d_val;
                    t_reg     <= t_val;
                    cap_reg   <= cap_val;
                    rbit_reg  <= (v_proj < 0);
                    state     <= ST_CALC2;
                end

                ST_CALC2: begin
                    // Compute error e, clamp to [-cap_reg, cap_reg], and split into q and rem
                    if (bit_reg == 1'b0) begin
                        e_init = (v_proj < $signed({16'd0, t_reg})) ? ($signed({16'd0, t_reg}) - v_proj) : 21'sd0;
                    end else begin
                        e_init = (v_proj > -$signed({16'd0, t_reg})) ? (-$signed({16'd0, t_reg}) - v_proj) : 21'sd0;
                    end

                    // Cap to [-cap_reg, cap_reg]
                    if (e_init > $signed({3'd0, cap_reg}))
                        e_capped = $signed({3'd0, cap_reg});
                    else if (e_init < -$signed({3'd0, cap_reg}))
                        e_capped = -$signed({3'd0, cap_reg});
                    else
                        e_capped = e_init;

                    e_val   <= e_capped;
                    q_val   <= e_capped >>> 4;
                    rem_val <= e_capped[3:0];

                    out_cnt <= 4'd0;
                    state   <= ST_OUT;
                end

                ST_OUT: begin
                    d_k = q_val + ((out_cnt < rem_val) ? 21'sd1 : 21'sd0);
                    if (hadamard_sign(out_cnt) == 2'sd1)
                        adj_sample = x_mem[out_cnt] + d_k[DATA_WIDTH-1:0];
                    else
                        adj_sample = x_mem[out_cnt] - d_k[DATA_WIDTH-1:0];

                    sample_out     <= adj_sample;
                    sample_idx_out <= out_cnt;
                    delta_out      <= delta_reg;
                    v_out          <= v_proj;
                    rbit_out       <= rbit_reg;
                    valid_out      <= 1'b1;

                    if (out_cnt == 4'd15) begin
                        state <= ST_IDLE;
                    end else begin
                        out_cnt <= out_cnt + 4'd1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
