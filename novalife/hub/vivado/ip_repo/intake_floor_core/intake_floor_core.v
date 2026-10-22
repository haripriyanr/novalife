// intake_floor_core -- background floor, pass 2 of intake (contract: embed.floor_background).
//
//   ROI iff pixel >= cut (cut from roi_cut_core, pass 1);  out = ROI ? pixel : max(pixel, BG_FLOOR).
//   One registered stage, valid/ready pass-through.
`timescale 1ns / 1ps

module intake_floor_core #(
    parameter integer BG_FLOOR = 16
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [8:0]  cut,
    input  wire [7:0]  pixel_in,
    input  wire        valid_in,
    output wire        ready_out,
    output reg  [7:0]  pixel_out,
    output reg         valid_out,
    input  wire        ready_in
);
    assign ready_out = ready_in;
    wire roi = ({1'b0, pixel_in} >= cut);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_out <= 8'd0; valid_out <= 1'b0;
        end else if (ready_in) begin
            valid_out <= valid_in;
            if (valid_in)
                pixel_out <= (roi || pixel_in >= BG_FLOOR) ? pixel_in : BG_FLOOR[7:0];
        end
    end
endmodule
