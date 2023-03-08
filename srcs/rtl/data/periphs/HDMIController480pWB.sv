// Read from dedicated address to a dual port bram
// HAS HARD CODED ADDRESSES
module HDMIController480p #(
    // Frame buffer start address
    parameter START_ADDR = 32'h30000000
    // Buffer size is dictated by implementation
)(
`ifdef VERILATOR
    input  logic i_clk,
    input  logic i_rst,
`endif
    input  logic i_cpu_clk,
    input  logic i_cpu_rst,
    input  logic i_pixel_clk,// 25mhz
    input  logic i_tmds_clk, // 250mhz
    // WB interface - slave
    // CPU write to frame buffer via WB interface
    // Another possible implementation is using shared RAM as frame buffer,
    // transaction all via WB bus: CPU -> RAM -> controller,
    // but current bus is slow so avoid that for now
    input  logic        i_cyc,
    input  logic        i_stb,
    input  logic [31:0] i_addr,
    input  logic        i_we,
    input  logic [31:0] i_data,
    input  logic [3:0]  i_sel,
    output logic        o_ack,
    output logic        o_err,
    output logic [31:0] o_data,
    output logic        o_stall,
    // HDMI output
    output logic [3:0]  o_gpdi_dp, 
    output logic [3:0]  o_gpdi_dn
);

    // ==================================================================================
    // RESET FOR PIXEL CLOCK DOMAIN
    // Stretch 16 cpu clk?
    logic [3:0] _reset_cnt;
    logic [4:0] _reset_cnt_p1;
    logic       _reset;
    assign _reset_cnt_p1 = _reset_cnt + 1;
    assign _reset = i_cpu_rst & _reset_cnt_p1[4] ;
    
    always_ff @(posedge i_cpu_clk) begin
        if (~i_cpu_rst) begin
            _reset_cnt  <= 4'b0;
        end
        else
            if (~_reset_cnt_p1[4])
                _reset_cnt  <= _reset_cnt_p1[3:0];
    end

    // ==================================================================================
    // SIGNAL GENERATOR
    logic               _hdmi_hsync, _hdmi_vsync, _hdmi_de, _hdmi_frame, _hdmi_line;
    logic signed [15:0] _hdmi_sx, _hdmi_sy;

    HDMISigGen signals_480p (
        .i_clk_pix(i_pixel_clk),      // pixel clock 25mhz
        .i_rst_pix(~_reset),          // rst high, in pixel clock domain
        .o_hsync  (_hdmi_hsync),      // horizontal sync
        .o_vsync  (_hdmi_vsync),      // vertical sync
        .o_de     (_hdmi_de),         // data enable (low in blanking interval)
        .o_frame  (_hdmi_frame),      // high at start of frame (include prev frame blank)
        .o_line   (_hdmi_line),       // high at start of line (include prev frame blank)
        .o_sx     (_hdmi_sx),         // horizontal screen position
        .o_sy     (_hdmi_sy)          // vertical screen position
    );

    // ==================================================================================
    // CPU WB out
    assign o_data  = _fb_o_data  | _status_o_data;
    assign o_ack   = _fb_o_ack   | _status_o_ack;
    assign o_err   = _fb_o_err   | _status_o_err;
    assign o_stall = _fb_o_stall | _status_o_stall;

    // CPU access to register / frame buffer
    // Status registers @ 38400, 38404
    // 38400 takes 16 bits
    logic _access_frame_buffer;
    logic _access_status;
    logic _access_coord;
    logic _access_status_registers;
    // Lower bound is already checked in mem stage...
    assign _access_frame_buffer = i_addr[15:0] < 16'd38400;
    assign _access_status = (i_addr[15:0] == 16'd38400) ? 1 : 0;
    assign _access_coord = (i_addr[15:0] == 16'd38404) ? 1 : 0;
    assign _access_status_registers = ~_access_frame_buffer & // not needed?
                                    (_access_status | _access_coord);

    // ==================================================================================
    // STATUS REGISTERS
    // Due to nature of master WB bus, status register cannot be used for synchronization
    // with CPU
    logic [31:0] _status, _coord;
    assign _status = {27'b0, _hdmi_hsync, _hdmi_vsync, _hdmi_de, _hdmi_frame, _hdmi_line};
    // Use coordinates to approximately calculate time to write to frame buffer
    // Not the best...
    assign _coord  = {_hdmi_sx, _hdmi_sy}; // signed

    // WB status in
    logic _status_i_cyc;
    logic _status_i_stb;
    assign _status_i_cyc = _access_status_registers & i_cyc;
    assign _status_i_stb = _access_status_registers & i_stb;
    // WB status out
    logic [31:0] _status_o_data;
    logic        _status_o_ack;
    logic        _status_o_err;
    logic        _status_o_stall;

    // HANDLE WB READS (3 output modes), WRITE RETURN ERROR
    logic _status_en;
    assign _status_en = _status_i_cyc & _status_i_stb;
    logic _status_re;
    assign _status_re = ~i_we & _status_en;
    logic [31:0] _status_data;
    always_comb begin : status_reg_data
        if (_status_re) begin
            if (_access_status)
                _status_data = _status;
            else if (_access_coord)
                _status_data = _coord;
            else
                _status_data = 32'b0;
        end
        else
            _status_data = 32'b0;
    end

    always_ff @(posedge i_cpu_clk) begin : status_read
        if (_status_re) begin
            case(i_sel[2:1])
                2'b00:
                    _status_o_data <= {24'b0, _status_data[7:0]}; // or 31 24 ?
                2'b01:
                    _status_o_data <= {16'b0, _status_data[15:0]};
                2'b11:
                    _status_o_data <=  _status_data;
                default: begin
                    _status_o_data <= 32'bx; // invalid data
                end
            endcase
        end
        else
            _status_o_data <= 32'b0; // return 0 to databus
    end

    logic _status_we;
    assign _status_we = i_we & _status_en;
    always_ff @(posedge i_cpu_clk) begin : status_write
        _status_o_err <= _status_we; // err when write
    end

    always_ff @(posedge i_cpu_clk) begin : status_ack
        _status_o_ack <= _status_re; // ack when read
    end

    assign _status_o_stall = 1'b0;

    // ==================================================================================
    // FRAME BUFFER
    logic _fb_i_cyc;
    logic _fb_i_stb;
    assign _fb_i_cyc = _access_frame_buffer & i_cyc;
    assign _fb_i_stb = _access_frame_buffer & i_stb;
    logic [31:0] _fb_o_data;
    logic        _fb_o_ack;
    logic        _fb_o_err;
    logic        _fb_o_stall;

    // PIXEL DATA
    // Frame buffer port 2 read
    // 1 bit per pixel => READ EVERY 32 CLK!
    // Data will be fed to TMDS encoder
    // During blanking, set pixel to black
    // Output control signals to port 2 of frame buffer

    // Signals for setting up data before draw area
    logic _fb_p2_de_m1;
    logic _fb_p2_de_m2;
    logic _fb_p2_de_m3;
    logic _fb_p2_de_m4;
    assign _fb_p2_de_m1 = (_hdmi_sx >= -1) & (_hdmi_sy >= 0);
    assign _fb_p2_de_m2 = (_hdmi_sx >= -2) & (_hdmi_sy >= 0);
    assign _fb_p2_de_m3 = (_hdmi_sx >= -3) & (_hdmi_sy >= 0);
    assign _fb_p2_de_m4 = (_hdmi_sx >= -4) & (_hdmi_sy >= 0);

    // en line count to 32
    logic [4:0] _fb_p2_en_cnt;
    logic [5:0] _fb_p2_en_cnt_p1;
    assign _fb_p2_en_cnt_p1 = _fb_p2_en_cnt + 1;
    always_ff @(posedge i_pixel_clk) begin : p2_en_counter
        if(_fb_p2_de_m3 & ~_fb_p2_de_m2) begin
            _fb_p2_en_cnt <= 5'b11111;
        end
        else begin
            if (_fb_p2_de_m2)
                _fb_p2_en_cnt <= _fb_p2_en_cnt_p1[4:0];
        end
    end

    // addr line
    logic [4:0] _fb_p2_addr_cnt;
    logic [5:0] _fb_p2_addr_cnt_p1;
    assign _fb_p2_addr_cnt_p1 = _fb_p2_addr_cnt + 1;
    always_ff @(posedge i_pixel_clk) begin : p2_addr_counter
        if(_fb_p2_de_m4 & ~_fb_p2_de_m3) begin
            _fb_p2_addr_cnt <= 5'b11111;
        end
        else begin
            if (_fb_p2_de_m3)
                _fb_p2_addr_cnt <= _fb_p2_addr_cnt_p1[4:0];
        end
    end

    // output update line
    logic [4:0] _fb_p2_pix_update_cnt;
    logic [5:0] _fb_p2_pix_update_cnt_p1;
    assign _fb_p2_pix_update_cnt_p1 = _fb_p2_pix_update_cnt + 1;
    always_ff @(posedge i_pixel_clk) begin : p2_out_pixel_data_update_counter
        if(_fb_p2_de_m2 & ~_fb_p2_de_m1) begin
            _fb_p2_pix_update_cnt <= 5'b11111;
        end
        else begin
            if (_fb_p2_de_m1)
                _fb_p2_pix_update_cnt <= _fb_p2_pix_update_cnt_p1[4:0];
        end
    end

    // address line
    logic [31:0] _fb_p2_addr;
    always_ff @(posedge i_pixel_clk) begin : p2_addr
        if (_hdmi_frame) begin
            _fb_p2_addr <= 32'd0;
        end
        else begin
            if (_fb_p2_addr_cnt_p1[5] & _fb_p2_de_m1) begin // _fb_p2_de_m1 to avoid avancing addr when changing lines
                _fb_p2_addr <= _fb_p2_addr + 4; // read 4 bytes, though port 2 is not byte addressible
            end
        end
    end

    // en line
    logic _fb_p2_en;
    assign _fb_p2_en = _fb_p2_en_cnt_p1[5]; // buffer takes 1 cycle to read

    // data
    logic [31:0] _fb_p2_data; 
    // output data buffering
    logic [31:0] _pixel_data;
    always_ff @(posedge i_pixel_clk) begin
        if (_fb_p2_pix_update_cnt_p1[5]) 
            _pixel_data <= _fb_p2_data; // independant?????
            // _pixel_data <= 32'h02000040;
    end

    DPBRAMWB #(
        .SIZE_BYTE(38400), // 640*480/8
        .START_ADDR(START_ADDR)
    ) frame_buffer (
        // Port 1: WB
        .i_wb_clk  (i_cpu_clk),
        .i_wb_cyc  (_fb_i_cyc),
        .i_wb_stb  (_fb_i_stb),
        .i_wb_addr (i_addr),
        .i_wb_we   (i_we),
        .i_wb_data (i_data),
        .i_wb_sel  (i_sel),
        // Need to be or-ed
        .o_wb_ack  (_fb_o_ack),
        .o_wb_err  (_fb_o_err),
        .o_wb_data (_fb_o_data),
        .o_wb_stall(_fb_o_stall),
        // Port 2: 32 bit width only
        // Read only for now
        .i_p2_clk  (i_pixel_clk),
        .i_p2_en   (_fb_p2_en),
        .i_p2_we   (1'b0),
        .i_p2_addr (_fb_p2_addr),
        .i_p2_wd   (32'h0),
        .o_p2_rd   (_fb_p2_data)
    );
    
    // _fb_p2_data output correctly but the image is garbled
    // Need a way to test the output side
    // desync? should it resolve after 1st frame?
    // Something is wrong with which data is available the moment the output needed it !!!!
    // So at which moment which data is needed?

    // ==================================================================================
    // PIXEL TO TMDS
    logic [7:0] _pixel_r, _pixel_g, _pixel_b;
    always_comb begin : pixel_data_decode
        if (_pixel_data[_fb_p2_pix_update_cnt]) begin
            _pixel_r = 8'hff;
            _pixel_g = 8'hff; 
            _pixel_b = 8'hff;
        end
        else
        begin
            _pixel_r = 8'h00;
            _pixel_g = 8'h00;
            _pixel_b = 8'h00;
        end
    end

    logic _TMDS_r, _TMDS_g, _TMDS_b;
    TMDSDataStream tdms_stream (
        .i_pixel_clk (i_pixel_clk),
        .i_tmds_clk  (i_tmds_clk),
        .i_rst       (~_reset),
        .i_hdmi_de   (_hdmi_de),
        .i_hdmi_vsync(_hdmi_vsync),
        .i_hdmi_hsync(_hdmi_hsync),
        .i_pixel_r   (_pixel_r),
        .i_pixel_g   (_pixel_g),
        .i_pixel_b   (_pixel_b),
        .o_r         (_TMDS_r),
        .o_g         (_TMDS_g),
        .o_b         (_TMDS_b)
    );

    // ==================================================================================
    // DIFFERENTIAL OUTPUT
    OBUFDS OBUFDS_r(.I(_TMDS_r), .O(o_gpdi_dp[2]), .OB(o_gpdi_dn[2]));
    OBUFDS OBUFDS_g(.I(_TMDS_g), .O(o_gpdi_dp[1]), .OB(o_gpdi_dn[1]));
    OBUFDS OBUFDS_b(.I(_TMDS_b), .O(o_gpdi_dp[0]), .OB(o_gpdi_dn[0]));
    OBUFDS OBUFDS_clk(.I(i_pixel_clk), .O(o_gpdi_dp[3]), .OB(o_gpdi_dn[3]));

endmodule
