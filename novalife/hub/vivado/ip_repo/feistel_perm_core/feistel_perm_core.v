// feistel_perm_core -- keyed block-index permutation (contract: embed.placement_permute).
//
//   slot -> block index in [0, m): 6-round balanced Feistel over 2h bits (h = ceil(bitlen(m-1)/2),
//   at least 1), cycle-walked until the value is < m.  Round function = first 4 bytes of the
//   Ascon-AEAD128 tag (key, nonce 0, no plaintext) of AD = "Novalife/placement/v2" || round(1)
//   || right(4, big-endian), masked to h bits.  The key is an input (the enclave holds it).
//   Cost: 6 Ascon tags (~60 cycles each) per walk step.
`timescale 1ns / 1ps

module feistel_perm_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [127:0] key,
    input  wire [23:0]  m,           // 1 .. 2^24
    input  wire [23:0]  slot,        // 0 .. m-1
    output reg  [23:0]  block_idx,
    output reg          done
);
    localparam [167:0] DOMAIN = "Novalife/placement/v2";   // 21 bytes, byte 0 in bits [167:160]

    // h = max(1, (bitlen(m-1)+1)/2)
    wire [23:0] mm1 = m - 24'd1;
    reg  [4:0]  bl;
    integer q;
    always @* begin
        bl = 5'd0;
        for (q = 0; q < 24; q = q + 1) if (mm1[q]) bl = q[4:0] + 5'd1;
    end
    wire [4:0] h_raw = (bl + 5'd1) >> 1;
    wire [4:0] h     = (h_raw == 5'd0) ? 5'd1 : h_raw;
    wire [23:0] mask = (24'd1 << h) - 24'd1;

    // ---- Ascon driver --------------------------------------------------------
    reg  [2:0]  st;
    localparam F_IDLE = 3'd0, F_START = 3'd1, F_AD = 3'd2, F_ADDONE = 3'd3, F_PTDONE = 3'd4,
               F_WAIT = 3'd5, F_ROUND = 3'd6;
    reg  [4:0]  ad_idx;
    reg  [2:0]  rnd;
    reg  [23:0] left, right;
    wire [127:0] tag_out;
    wire [127:0] ct_unused; wire [4:0] ctb_unused; wire ctv_unused;
    wire a_done, ad_ready, pt_ready;
    reg  [7:0]  ad_byte;
    wire a_start  = (st == F_START);
    wire ad_valid = (st == F_AD) && ad_ready;
    wire ad_donep = (st == F_ADDONE) && ad_ready;
    wire pt_donep = (st == F_PTDONE) && pt_ready;

    ascon128_aead u_ascon (
        .clk(clk), .rst_n(rst_n), .start(a_start), .key(key), .nonce(128'd0),
        .ad_data(ad_byte), .ad_valid(ad_valid), .ad_done(ad_donep),
        .pt_data(8'd0), .pt_valid(1'b0), .pt_done(pt_donep),
        .ct_data(ct_unused), .ct_bytes(ctb_unused), .ct_valid(ctv_unused),
        .tag_out(tag_out), .done(a_done), .ad_ready(ad_ready), .pt_ready(pt_ready));

    // AD byte ad_idx: 0..20 domain, 21 round, 22..25 right (big-endian 32-bit)
    wire [31:0] right32 = {8'd0, right};
    always @* begin
        if (ad_idx < 5'd21)       ad_byte = DOMAIN[167 - 8*ad_idx -: 8];
        else if (ad_idx == 5'd21) ad_byte = {5'd0, rnd};
        else                      ad_byte = right32[31 - 8*(ad_idx - 5'd22) -: 8];
    end

    wire [23:0] nl = right;
    wire [23:0] nr = left ^ (tag_out[119:96] & mask);   // 32-bit value & mask, mask < 2^24

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= F_IDLE; done <= 1'b0; block_idx <= 24'd0; ad_idx <= 5'd0; rnd <= 3'd0;
            left <= 24'd0; right <= 24'd0;
        end else begin
            case (st)
                F_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        left  <= (slot >> h);
                        right <= slot & mask;
                        rnd   <= 3'd0; ad_idx <= 5'd0; st <= F_START;
                    end
                end
                F_START: begin ad_idx <= 5'd0; st <= F_AD; end
                F_AD: if (ad_valid) begin
                    if (ad_idx == 5'd25) st <= F_ADDONE; else ad_idx <= ad_idx + 5'd1;
                end
                F_ADDONE: if (ad_donep) st <= F_PTDONE;
                F_PTDONE: if (pt_donep) st <= F_WAIT;
                F_WAIT: if (a_done) begin
                    left <= nl; right <= nr;       // (L, R) <- (R, L ^ F)
                    st <= F_ROUND;
                end
                F_ROUND: begin
                    if (rnd == 3'd5) begin
                        // x = (left << h) | right; walk again if x >= m
                        if (((left << h) | right) < m) begin
                            block_idx <= (left << h) | right; done <= 1'b1; st <= F_IDLE;
                        end else begin
                            left <= ((left << h) | right) >> h;
                            right <= ((left << h) | right) & mask;
                            rnd <= 3'd0; st <= F_START;
                        end
                    end else begin
                        rnd <= rnd + 3'd1; st <= F_START;
                    end
                end
                default: st <= F_IDLE;
            endcase
        end
    end
endmodule
