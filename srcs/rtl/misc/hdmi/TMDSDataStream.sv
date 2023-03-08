module TMDSDataStream (
    input  logic       i_pixel_clk,
    input  logic       i_tmds_clk,
    input  logic       i_rst,
    input  logic       i_hdmi_de,
    input  logic       i_hdmi_vsync,
    input  logic       i_hdmi_hsync,
    input  logic [7:0] i_pixel_r,
    input  logic [7:0] i_pixel_g,
    input  logic [7:0] i_pixel_b,
    output logic       o_r,
    output logic       o_g,
    output logic       o_b
);
    
    // Convert the 8-bit colours into 10-bit TMDS values
    logic [9:0] _TMDS_r, _TMDS_g, _TMDS_b;
    TMDSEncoder encode_r(.clk(i_pixel_clk), .VD(i_pixel_r), .CD(2'b00),
                                    .VDE(i_hdmi_de), .TMDS(_TMDS_r));
    TMDSEncoder encode_g(.clk(i_pixel_clk), .VD(i_pixel_g), .CD(2'b00),
                                    .VDE(i_hdmi_de), .TMDS(_TMDS_g));
    TMDSEncoder encode_b(.clk(i_pixel_clk), .VD(i_pixel_b), .CD({i_hdmi_vsync, i_hdmi_hsync}),
                                    .VDE(i_hdmi_de), .TMDS(_TMDS_b));
    
    // Strobe the TMDS_shift_load once every 10 i_tmds_clks
    // i.e. at the start of new pixel data
    reg [3:0] TMDS_mod10=0;
    reg TMDS_shift_load=0;
    always @(posedge i_tmds_clk) begin
    if (i_rst) begin
        TMDS_mod10 <= 0;
        TMDS_shift_load <= 0;
    end else begin
        TMDS_mod10 <= (TMDS_mod10==4'd9) ? 4'd0 : TMDS_mod10+4'd1;
        TMDS_shift_load <= (TMDS_mod10==4'd9);
    end
    end

    // Latch the TMDS colour values into three shift registers
    // at the start of the pixel, then shift them one bit each i_tmds_clk.
    // We will then output the LSB on each i_tmds_clk.
    reg [9:0] TMDS_shift_red=0, TMDS_shift_grn=0, TMDS_shift_blu=0;
    always @(posedge i_tmds_clk) begin
    if (i_rst) begin
        TMDS_shift_red <= 0;
        TMDS_shift_grn <= 0;
        TMDS_shift_blu <= 0;
    end else begin
        TMDS_shift_red <= TMDS_shift_load ? _TMDS_r: {1'b0, TMDS_shift_red[9:1]};
        TMDS_shift_grn <= TMDS_shift_load ? _TMDS_g: {1'b0, TMDS_shift_grn[9:1]};
        TMDS_shift_blu <= TMDS_shift_load ? _TMDS_b: {1'b0, TMDS_shift_blu[9:1]};
    end
    end

    // Finally output the LSB of each color bitstream
    assign o_r= TMDS_shift_red[0];
    assign o_g= TMDS_shift_grn[0];
    assign o_b= TMDS_shift_blu[0];

endmodule