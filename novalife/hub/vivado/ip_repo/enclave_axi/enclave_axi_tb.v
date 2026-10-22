// Self-checking AXI4-Lite testbench for enclave_axi: the exact register sequence that
// vivado/scripts/board_tag_test.tcl runs on the board over JTAG, on every te_* vector.
// Run via `vivado/scripts/run_sim.sh enclave_axi`.

`timescale 1ns / 1ps
`include "te_params.vh"

module enclave_axi_tb;

    localparam integer NV = TE_NUM_VECTORS;

    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    reg  [7:0]  awaddr = 0, araddr = 0;
    reg         awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
    reg  [31:0] wdata = 0;
    wire        awready, wready, bvalid, arready, rvalid;
    wire [1:0]  bresp, rresp;
    wire [31:0] rdata;

    enclave_axi #(.ALLOW_AXI_KEY(1), .CAP(4), .REFILL(1000000)) dut (
        .s_axi_aclk(clk), .s_axi_aresetn(rst_n),
        .s_axi_awaddr(awaddr), .s_axi_awprot(3'd0), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(4'hF), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arprot(3'd0), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready)
    );

    reg [127:0] key_mem [0:NV-1];
    reg [79:0]  fld_mem [0:NV-1];
    reg [47:0]  tag_mem [0:NV-1];
    integer c, errors, t;
    reg [31:0] v, hi, lo, cyc;

    task axi_write(input [7:0] a, input [31:0] d);
        begin
            @(negedge clk); awaddr = a; wdata = d; awvalid = 1; wvalid = 1; bready = 1;
            t = 0;
            while (!(awready && wready) && t < 50) begin @(negedge clk); t = t + 1; end
            awvalid = 0; wvalid = 0;
            while (!bvalid && t < 100) begin @(negedge clk); t = t + 1; end
            @(negedge clk); bready = 0;
            if (t >= 100) begin errors = errors + 1; $display("FAIL: write 0x%02x timed out", a); end
        end
    endtask

    task axi_read(input [7:0] a, output [31:0] d);
        begin
            @(negedge clk); araddr = a; arvalid = 1; rready = 1;
            t = 0;
            while (!rvalid && t < 50) begin @(negedge clk); t = t + 1; end
            d = rdata; arvalid = 0;
            @(negedge clk); rready = 0;
            if (t >= 50) begin errors = errors + 1; $display("FAIL: read 0x%02x timed out", a); end
        end
    endtask

    task run_cmd(input [3:0] cmd);
        begin
            axi_write(8'h00, {28'd0, cmd});
            v = 0; t = 0;
            while (v[0] == 1'b0 && t < 400) begin axi_read(8'h10, v); end
            if (v[0] == 1'b0) begin errors = errors + 1; $display("FAIL: cmd %0d no DONE", cmd); end
        end
    endtask

    initial begin
        errors = 0;
        $readmemh("te_key.mem", key_mem);
        $readmemh("te_fields.mem", fld_mem);
        $readmemh("te_tag.mem", tag_mem);
        repeat (5) @(negedge clk);
        rst_n = 1;

        axi_read(8'h0C, v);
        if (v[31:16] !== 16'h4E4C || v[0] !== 1'b1 || v[1] !== 1'b0) begin
            errors = errors + 1; $display("FAIL: STATUS after reset %08x", v);
        end
        // BUILD without a key -> NO_KEY
        run_cmd(4'd0); axi_read(8'h14, v);
        if (v[1:0] !== 2'd1) begin errors = errors + 1; $display("FAIL: no-key RESULT %08x", v); end

        for (c = 0; c < NV; c = c + 1) begin
            axi_write(8'h40, key_mem[c][127:96]); axi_write(8'h44, key_mem[c][95:64]);
            axi_write(8'h48, key_mem[c][63:32]);  axi_write(8'h4C, key_mem[c][31:0]);
            run_cmd(4'd5);
            axi_read(8'h40, v);
            if (v !== 32'd0) begin errors = errors + 1; $display("FAIL: KEY0 readable %08x", v); end
            axi_write(8'h20, {16'd0, fld_mem[c][79:76], fld_mem[c][75:64]});
            axi_write(8'h24, fld_mem[c][63:32]); axi_write(8'h28, fld_mem[c][31:0]);
            run_cmd(4'd0);
            axi_read(8'h14, v); axi_read(8'h34, hi); axi_read(8'h38, lo); axi_read(8'h3C, cyc);
            if (v[1:0] !== 2'd0 || {hi[15:0], lo} !== tag_mem[c]) begin
                errors = errors + 1;
                $display("FAIL case %0d: BUILD result %08x tag %04x%08x exp %012x", c, v, hi[15:0], lo, tag_mem[c]);
            end
            if (c == 0) $display("BUILD_TAG latency: %0d PL cycles", cyc);
            // VERIFY with the right tag
            axi_write(8'h2C, {16'd0, tag_mem[c][47:32]}); axi_write(8'h30, tag_mem[c][31:0]);
            run_cmd(4'd1); axi_read(8'h14, v);
            if (v[1:0] !== 2'd0 || v[8] !== 1'b1) begin errors = errors + 1; $display("FAIL case %0d: VERIFY good %08x", c, v); end
            // VERIFY with a flipped tag (only on a few cases, so the bucket of 4 is not drained)
            if (c < 3) begin
                axi_write(8'h30, tag_mem[c][31:0] ^ 32'h1);
                run_cmd(4'd1); axi_read(8'h14, v);
                if (v[1:0] !== 2'd0 || v[8] !== 1'b0) begin errors = errors + 1; $display("FAIL case %0d: VERIFY bad %08x", c, v); end
            end
        end
        axi_read(8'h0C, v);
        if (v[15:8] !== 8'd1) begin errors = errors + 1; $display("FAIL: tokens %0d, expected 1", v[15:8]); end
        // unsupported command, then wipe
        run_cmd(4'd2); axi_read(8'h14, v);
        if (v[16] !== 1'b1) begin errors = errors + 1; $display("FAIL: MARK_IMAGE not flagged unsupported"); end
        run_cmd(4'd7); axi_read(8'h0C, v);
        if (v[1] !== 1'b0) begin errors = errors + 1; $display("FAIL: key still loaded after wipe"); end

        if (errors == 0) $display("enclave_axi_tb: PASS (%0d vectors over AXI4-Lite)", NV);
        else             $display("enclave_axi_tb: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
