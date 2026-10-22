// tag_engine — the enclave's BUILD_TAG / VERIFY_TAG engine, NovaLife HUB
// ============================================================================
// Contract: tools/tag_reference/tag_block.compute_tag (48-bit truncated Ascon MAC over
// version | hub_id | handle), vectors from tools/tag_reference/vectors/gen_tag_engine_vectors.py.
// The MAC is computed by the verified ascon128_aead core (Ascon-AEAD128, NIST SP 800-232) with an empty
// plaintext and this 54-byte associated data, under the stored key and NONCE_MAC:
//
//     MAC_DOMAIN || MAC_DOMAIN || 0x0B || version(1) || hub_id(2, BE) || handle(8, BE)
//
// (MAC_DOMAIN twice is what the Python reference does; it is the contract.)
//
// Key store: write-only.  `key_we` loads `key_in` (meant for the PL-wired admin console only),
// `key_wipe` zeroes it.  There is no path from the key register to any output.  With no key
// loaded every command answers ST_NO_KEY and nothing is computed.
//
// Rate limit: a token bucket on FAILED verifies.  It holds up to CAP tokens, gains one every
// REFILL cycles, and a failed VERIFY spends one.  At zero tokens VERIFY answers ST_LIMITED
// without computing a MAC, so online forgery is bounded to CAP + t/REFILL attempts.
// NOTE (docs/improvement_review_2026-10-20.md A3): the software decoder makes up to 1125 tag
// checks per image, so if the geometry search calls VERIFY per hypothesis the bucket bounds
// hypotheses, not images, and must be sized with that in mind.
//
// Command interface: present op/fields/tag_in with cmd_valid; accepted when cmd_ready.
// One response (resp_valid for one cycle) per accepted command:
//   resp_status  0 OK, 1 NO_KEY, 2 LIMITED, 3 BAD_OP
//   resp_tag     the 48-bit tag (BUILD; also VERIFY, for logging by the caller)
//   resp_ok      VERIFY: tag_in == computed tag
// ============================================================================

`timescale 1ns / 1ps

module tag_engine #(
    parameter integer CAP    = 16,
    parameter integer REFILL = 100_000_000      // one token per second at 100 MHz
)(
    input  wire         clk,
    input  wire         rst_n,

    // admin (PL-wired console)
    input  wire         key_we,
    input  wire [127:0] key_in,
    input  wire         key_wipe,
    output reg          key_loaded,

    // command
    input  wire         cmd_valid,
    output wire         cmd_ready,
    input  wire [1:0]   cmd_op,          // 1 = BUILD_TAG, 2 = VERIFY_TAG
    input  wire [3:0]   version,
    input  wire [11:0]  hub_id,
    input  wire [63:0]  handle,
    input  wire [47:0]  tag_in,

    output reg          resp_valid,
    output reg  [1:0]   resp_status,
    output reg  [47:0]  resp_tag,
    output reg          resp_ok,

    output reg  [7:0]   tokens
);

    localparam [1:0] OP_BUILD = 2'd1, OP_VERIFY = 2'd2;
    localparam [1:0] S_OK = 2'd0, S_NO_KEY = 2'd1, S_LIMITED = 2'd2, S_BAD_OP = 2'd3;

    localparam [127:0] NONCE_MAC  = 128'h4e6f76614c6966654d41435430303031; // "NovaLifeMACT0001"
    localparam [167:0] MAC_DOMAIN = 168'h4e6f76616c6966652f7461672d626c6f636b2f7631; // "Novalife/tag-block/v1"
    localparam integer AD_LEN = 54;

    localparam [2:0] T_IDLE = 3'd0, T_START = 3'd1, T_AD = 3'd2, T_ADDONE = 3'd3,
                     T_PTDONE = 3'd4, T_WAIT = 3'd5;

    reg [2:0]   st;
    reg [127:0] key;
    reg [1:0]   op_r;
    reg [3:0]   ver_r;
    reg [11:0]  hub_r;
    reg [63:0]  handle_r;
    reg [47:0]  tagin_r;
    reg [5:0]   ad_idx;
    reg [31:0]  refill_cnt;

    assign cmd_ready = (st == T_IDLE);

    // ---- the Ascon core ----
    wire [127:0] ct_data;
    wire [4:0]   ct_bytes;
    wire         ct_valid;
    wire [127:0] tag_out;
    wire         a_done, ad_ready, pt_ready;
    reg  [7:0]   ad_byte;
    wire         a_start   = (st == T_START);
    wire         ad_valid  = (st == T_AD) && ad_ready;
    wire         ad_done   = (st == T_ADDONE) && ad_ready;
    wire         pt_done   = (st == T_PTDONE) && pt_ready;

    ascon128_aead u_ascon (
        .clk(clk), .rst_n(rst_n), .start(a_start), .key(key), .nonce(NONCE_MAC),
        .ad_data(ad_byte), .ad_valid(ad_valid), .ad_done(ad_done),
        .pt_data(8'd0), .pt_valid(1'b0), .pt_done(pt_done),
        .ct_data(ct_data), .ct_bytes(ct_bytes), .ct_valid(ct_valid),
        .tag_out(tag_out), .done(a_done), .ad_ready(ad_ready), .pt_ready(pt_ready)
    );

    // AD byte ad_idx: 0..41 the domain twice, 42 the header length, 43.. the header
    wire [87:0] header = {4'd0, ver_r, 4'd0, hub_r, handle_r};    // 11 bytes, big-endian
    always @(*) begin
        if (ad_idx < 6'd21)       ad_byte = MAC_DOMAIN[167 - 8*ad_idx -: 8];
        else if (ad_idx < 6'd42)  ad_byte = MAC_DOMAIN[167 - 8*(ad_idx - 6'd21) -: 8];
        else if (ad_idx == 6'd42) ad_byte = 8'h0B;
        else                      ad_byte = header[87 - 8*(ad_idx - 6'd43) -: 8];
    end

    wire [47:0] tag48 = tag_out[127:80];   // first 6 bytes of the 128-bit Ascon tag

    wire refill_now = (refill_cnt == REFILL - 1);
    wire spend_now  = (st == T_WAIT) && a_done && (op_r == OP_VERIFY) &&
                      (tag48 != tagin_r) && (tokens != 8'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= T_IDLE; key <= 128'd0; key_loaded <= 1'b0;
            op_r <= 2'd0; ver_r <= 4'd0; hub_r <= 12'd0; handle_r <= 64'd0; tagin_r <= 48'd0;
            ad_idx <= 6'd0; refill_cnt <= 32'd0; tokens <= CAP[7:0];
            resp_valid <= 1'b0; resp_status <= 2'd0; resp_tag <= 48'd0; resp_ok <= 1'b0;
        end else begin
            resp_valid <= 1'b0;

            // token refill (independent of the command FSM); a failed verify in the same
            // cycle is folded in below so neither update is lost
            if (refill_now) refill_cnt <= 32'd0;
            else refill_cnt <= refill_cnt + 32'd1;
            if (refill_now && tokens < CAP[7:0] && !spend_now) tokens <= tokens + 8'd1;
            if (spend_now && !(refill_now && tokens < CAP[7:0])) tokens <= tokens - 8'd1;

            // admin port: only between commands, so a key never changes mid-MAC
            if (st == T_IDLE) begin
                if (key_wipe) begin
                    key <= 128'd0; key_loaded <= 1'b0;
                end else if (key_we) begin
                    key <= key_in; key_loaded <= 1'b1;
                end
            end

            case (st)
                T_IDLE: if (cmd_valid && !key_we && !key_wipe) begin
                    op_r <= cmd_op; ver_r <= version; hub_r <= hub_id;
                    handle_r <= handle; tagin_r <= tag_in;
                    resp_ok <= 1'b0; resp_tag <= 48'd0;
                    if (cmd_op != OP_BUILD && cmd_op != OP_VERIFY) begin
                        resp_status <= S_BAD_OP; resp_valid <= 1'b1;
                    end else if (!key_loaded) begin
                        resp_status <= S_NO_KEY; resp_valid <= 1'b1;
                    end else if (cmd_op == OP_VERIFY && tokens == 8'd0) begin
                        resp_status <= S_LIMITED; resp_valid <= 1'b1;
                    end else begin
                        ad_idx <= 6'd0;
                        st <= T_START;
                    end
                end
                T_START: st <= T_AD;
                T_AD: if (ad_valid) begin
                    if (ad_idx == AD_LEN - 1) st <= T_ADDONE;
                    else ad_idx <= ad_idx + 6'd1;
                end
                T_ADDONE: if (ad_done) st <= T_PTDONE;
                T_PTDONE: if (pt_done) st <= T_WAIT;
                T_WAIT: if (a_done) begin
                    resp_tag    <= tag48;
                    resp_status <= S_OK;
                    resp_valid  <= 1'b1;
                    if (op_r == OP_VERIFY) begin
                        resp_ok <= (tag48 == tagin_r);
                    end
                    st <= T_IDLE;
                end
                default: st <= T_IDLE;
            endcase
        end
    end

endmodule
