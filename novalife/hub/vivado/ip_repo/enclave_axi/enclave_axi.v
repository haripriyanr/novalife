// enclave_axi — AXI4-Lite register block around tag_engine (the PS <-> PL mailbox), NovaLife HUB
// ============================================================================
// Offsets 0x00..0x14 are the ones firmware/src/mailbox.h already uses; the rest extend it.
//
//   0x00 CMD        W   writing starts a command (mb_cmd_t numbering) and clears DONE:
//                       0 BUILD_TAG, 1 VERIFY_TAG, 4 STATUS, 5 ADMIN_LOAD_KEY, 7 ADMIN_WIPE_KEY
//   0x04 ARG0       RW  scratch (kept for the firmware's existing calls)
//   0x08 ARG1       RW  scratch
//   0x0C STATUS     R   [0] READY (PL present)  [1] key loaded  [2] busy  [15:8] tokens
//                       [31:16] 0x4E4C ("NL") so the firmware's probe cannot mistake a bus echo
//   0x10 DONE       R   [0] last command finished
//   0x14 RESULT     R   [1:0] tag_engine status (0 OK, 1 NO_KEY, 2 LIMITED, 3 BAD_OP)
//                       [8] VERIFY accepted   [16] command not supported by the PL
//   0x20 FIELDS     RW  [15:12] version  [11:0] hub_id
//   0x24 HANDLE_HI  RW  handle[63:32]
//   0x28 HANDLE_LO  RW  handle[31:0]
//   0x2C TAGIN_HI   RW  [15:0] tag_in[47:32]
//   0x30 TAGIN_LO   RW  tag_in[31:0]
//   0x34 RTAG_HI    R   [15:0] result tag[47:32]
//   0x38 RTAG_LO    R   result tag[31:0]
//   0x3C CYCLES     R   PL clock cycles from CMD write to DONE (on-board latency)
//   0x40..0x4C KEY0..KEY3  W only (reads return 0), key[127:96] .. key[31:0]; consumed and
//                       zeroed by ADMIN_LOAD_KEY.  Present only when ALLOW_AXI_KEY = 1.
//
// **ALLOW_AXI_KEY is a bring-up deviation from decision D5** ("the key never crosses Linux;
// ADMIN only from a PL-wired console").  With it set, anything that can write the AXI window can
// load a key.  It exists so the board can be tested over JTAG before the PL-wired console
// exists; a production bitstream must be built with ALLOW_AXI_KEY = 0.
// ============================================================================

`timescale 1ns / 1ps

module enclave_axi #(
    parameter integer ALLOW_AXI_KEY = 1,
    parameter integer CAP           = 16,
    parameter integer REFILL        = 100_000_000
)(
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,
    input  wire [7:0]  s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [7:0]  s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready
);

    wire clk = s_axi_aclk;
    wire rst_n = s_axi_aresetn;

    // ---- registers ----
    reg [31:0] arg0, arg1, fields, handle_hi, handle_lo, tagin_hi, tagin_lo;
    reg [31:0] key0, key1, key2, key3;
    reg        done_r, unsup_r;
    reg [1:0]  rstatus_r;
    reg        rok_r;
    reg [47:0] rtag_r;
    reg [31:0] cycles_r, cyc_cnt;
    reg        busy_r;

    // ---- tag engine ----
    reg         te_key_we, te_key_wipe, te_cmd_valid;
    reg  [1:0]  te_op;
    wire        te_cmd_ready, te_key_loaded, te_resp_valid, te_resp_ok;
    wire [1:0]  te_resp_status;
    wire [47:0] te_resp_tag;
    wire [7:0]  te_tokens;

    tag_engine #(.CAP(CAP), .REFILL(REFILL)) u_te (
        .clk(clk), .rst_n(rst_n),
        .key_we(te_key_we), .key_in({key0, key1, key2, key3}), .key_wipe(te_key_wipe),
        .key_loaded(te_key_loaded),
        .cmd_valid(te_cmd_valid), .cmd_ready(te_cmd_ready), .cmd_op(te_op),
        .version(fields[15:12]), .hub_id(fields[11:0]), .handle({handle_hi, handle_lo}),
        .tag_in({tagin_hi[15:0], tagin_lo}),
        .resp_valid(te_resp_valid), .resp_status(te_resp_status), .resp_tag(te_resp_tag),
        .resp_ok(te_resp_ok), .tokens(te_tokens)
    );

    // ---- AXI write channel: take address and data together ----
    wire wr_fire = s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid && !s_axi_awready;
    wire [7:0] waddr = s_axi_awaddr;

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b0; s_axi_wready <= 1'b0; s_axi_bvalid <= 1'b0; s_axi_bresp <= 2'b00;
            arg0 <= 0; arg1 <= 0; fields <= 0; handle_hi <= 0; handle_lo <= 0;
            tagin_hi <= 0; tagin_lo <= 0; key0 <= 0; key1 <= 0; key2 <= 0; key3 <= 0;
            done_r <= 1'b0; unsup_r <= 1'b0; rstatus_r <= 2'd0; rok_r <= 1'b0; rtag_r <= 48'd0;
            cycles_r <= 32'd0; cyc_cnt <= 32'd0; busy_r <= 1'b0;
            te_key_we <= 1'b0; te_key_wipe <= 1'b0; te_cmd_valid <= 1'b0; te_op <= 2'd0;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            te_key_we     <= 1'b0;
            te_key_wipe   <= 1'b0;
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;

            if (busy_r) cyc_cnt <= cyc_cnt + 32'd1;

            // tag-engine handshake
            if (te_cmd_valid && te_cmd_ready) te_cmd_valid <= 1'b0;
            if (te_resp_valid) begin
                rstatus_r <= te_resp_status;
                rok_r     <= te_resp_ok;
                rtag_r    <= te_resp_tag;
                done_r    <= 1'b1;
                busy_r    <= 1'b0;
                cycles_r  <= cyc_cnt + 32'd1;
            end

            if (wr_fire) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;
                case (waddr)
                    8'h00: if (!busy_r) begin
                        done_r <= 1'b0; unsup_r <= 1'b0; rok_r <= 1'b0; cyc_cnt <= 32'd0;
                        case (s_axi_wdata[3:0])
                            4'd0: begin te_op <= 2'd1; te_cmd_valid <= 1'b1; busy_r <= 1'b1; end
                            4'd1: begin te_op <= 2'd2; te_cmd_valid <= 1'b1; busy_r <= 1'b1; end
                            4'd4: begin done_r <= 1'b1; cycles_r <= 32'd0; end
                            4'd5: begin
                                if (ALLOW_AXI_KEY != 0) te_key_we <= 1'b1;
                                else unsup_r <= 1'b1;
                                done_r <= 1'b1;
                            end
                            4'd7: begin te_key_wipe <= 1'b1; done_r <= 1'b1; end
                            default: begin unsup_r <= 1'b1; done_r <= 1'b1; end
                        endcase
                    end
                    8'h04: arg0 <= s_axi_wdata;
                    8'h08: arg1 <= s_axi_wdata;
                    8'h20: fields <= s_axi_wdata;
                    8'h24: handle_hi <= s_axi_wdata;
                    8'h28: handle_lo <= s_axi_wdata;
                    8'h2C: tagin_hi <= s_axi_wdata;
                    8'h30: tagin_lo <= s_axi_wdata;
                    8'h40: if (ALLOW_AXI_KEY != 0) key0 <= s_axi_wdata;
                    8'h44: if (ALLOW_AXI_KEY != 0) key1 <= s_axi_wdata;
                    8'h48: if (ALLOW_AXI_KEY != 0) key2 <= s_axi_wdata;
                    8'h4C: if (ALLOW_AXI_KEY != 0) key3 <= s_axi_wdata;
                    default: ;
                endcase
            end

            // the key shadow lives one cycle after the load, then it is gone
            if (te_key_we) begin key0 <= 0; key1 <= 0; key2 <= 0; key3 <= 0; end
        end
    end

    // ---- AXI read channel ----
    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b0; s_axi_rvalid <= 1'b0; s_axi_rdata <= 32'd0; s_axi_rresp <= 2'b00;
        end else begin
            s_axi_arready <= 1'b0;
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
            if (s_axi_arvalid && !s_axi_rvalid && !s_axi_arready) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid  <= 1'b1;
                s_axi_rresp   <= 2'b00;
                case (s_axi_araddr)
                    8'h04: s_axi_rdata <= arg0;
                    8'h08: s_axi_rdata <= arg1;
                    8'h0C: s_axi_rdata <= {16'h4E4C, te_tokens, 5'd0, busy_r, te_key_loaded, 1'b1};
                    8'h10: s_axi_rdata <= {31'd0, done_r};
                    8'h14: s_axi_rdata <= {15'd0, unsup_r, 7'd0, rok_r, 6'd0, rstatus_r};
                    8'h20: s_axi_rdata <= fields;
                    8'h24: s_axi_rdata <= handle_hi;
                    8'h28: s_axi_rdata <= handle_lo;
                    8'h2C: s_axi_rdata <= tagin_hi;
                    8'h30: s_axi_rdata <= tagin_lo;
                    8'h34: s_axi_rdata <= {16'd0, rtag_r[47:32]};
                    8'h38: s_axi_rdata <= rtag_r[31:0];
                    8'h3C: s_axi_rdata <= cycles_r;
                    default: s_axi_rdata <= 32'd0;      // CMD and KEY* read as 0
                endcase
            end
        end
    end

endmodule
