/* To achieve individual byte access while inferring BRAM and single clock R/W,
 * must split BRAM into byte size array then combined vertically into original size.
 * Configuration: 4 RAM8 * 2048 bytes - 32 bits.
 * Convert addr to column: shift addr left 2 bits (align by 4)
 * Row selection: use last 2 bits for byte rw, shift left 1 if rw short
 * STRUCTURE:
 * Row \ Internal row addr| 0   1   2   3   4  ...
 * Row 0 - byte 3         |
 * Row 1 - byte 2         |
 * Row 2 - byte 1         |
 * Row 3 - byte 0         |
 * External addr          | 0   4   8   C   10 ...
 */

module BRAMWB #(
    parameter SIZE_BYTE  = 8192, 
    parameter START_ADDR = 32'h20000000
)(
    input  logic        i_clk,
    // input  logic        i_rst,
    // Intercon
    input  logic        i_cyc,
    input  logic        i_stb,
    input  logic [31:0] i_addr,
    input  logic        i_we,
    input  logic [31:0] i_data,
    input  logic [3:0]  i_sel,
    // input  logic      i_lock,
    output logic        o_ack,
    output logic        o_err,
    output logic [31:0] o_data,
    output logic        o_stall
);

    localparam ADDRWIDTH          = $clog2(SIZE_BYTE - 1);
    localparam SIZEDIV4           = SIZE_BYTE >> 2; // Div 4
    localparam ADDRWIDTH_SIZEDIV4 = $clog2(SIZEDIV4 - 1);

    // START_ADDR alignment check
    always_comb begin
        if (START_ADDR[ADDRWIDTH-1:0] != 'b0)
            $fatal("%m: Address range is not aligned!");
    end

    // High when both i_cyc and i_stb high
    logic       _en;
    // Bank select logic
    logic       _sel0, _sel1, _sel2, _sel3;
    // == _en & _selx
    logic       _en0, _en1, _en2, _en3;
    // == _we & _selx
    logic       _we0, _we1, _we2, _we3;
    // Data for banks
    logic [7:0] _rd0, _rd1, _rd2, _rd3;
    logic [7:0] _wd0, _wd1, _wd2, _wd3;
    // For writing bytes
    logic [1:0] _sel_encode;

    // Buffered for reading as ram need 1 cycle
    // Writes don't need buffering
    logic       _b_i_we;
    logic       _b_en;
    logic [3:0] _b_i_sel;
    logic       _b_sel0; //, _b_sel1, _b_sel2, _b_sel3
    logic [1:0] _b_sel_encode;

    BRAMVarWidth #(
        .WIDTH_BITS(8),
        .SIZE_BITS(SIZEDIV4 * 8)
    ) row0 (
        .i_clk(i_clk),
        .i_en(_en0),
        .i_we(_we0),
        .i_addr(i_addr[ADDRWIDTH_SIZEDIV4 + 1:2]), // -1 + 2 = +1 to compensate 2 bits
        .i_wd(_wd0),
        .o_rd(_rd0)
    );
    BRAMVarWidth #(
        .WIDTH_BITS(8),
        .SIZE_BITS(SIZEDIV4 * 8)
    ) row1 (
        .i_clk(i_clk),
        .i_en(_en1),
        .i_we(_we1),
        .i_addr(i_addr[ADDRWIDTH_SIZEDIV4 + 1:2]),
        .i_wd(_wd1),
        .o_rd(_rd1)
    );
    BRAMVarWidth #(
        .WIDTH_BITS(8),
        .SIZE_BITS(SIZEDIV4 * 8)
    ) row2 (
        .i_clk(i_clk),
        .i_en(_en2),
        .i_we(_we2),
        .i_addr(i_addr[ADDRWIDTH_SIZEDIV4 + 1:2]),
        .i_wd(_wd2),
        .o_rd(_rd2)
    );
    BRAMVarWidth #(
        .WIDTH_BITS(8),
        .SIZE_BITS(SIZEDIV4 * 8)
    ) row3 (
        .i_clk(i_clk),
        .i_en(_en3),
        .i_we(_we3),
        .i_addr(i_addr[ADDRWIDTH_SIZEDIV4 + 1:2]),
        .i_wd(_wd3),
        .o_rd(_rd3)
    );

    assign _en = i_cyc & i_stb;

    /* Memory byte select logic
     * i_sel:
     *  - From Wishbone master, has 4 possible input 0001, 0011, 1111. Use [2:1] for identificaton
     * i_addr:
     *  - Last 2 bits of addr are used to determine byte / short address, Other bits determine column
     *  - READING: 4 bytes are read at a time => need to know which is useful/correct for extension
     *  - WRITING: Need to enable correct we signal & select correct targeted wd to move data to
     * K-map for sel0
     * i_sel[2:1]\i_addr[1:0]   00  01  11  10
     *              00-byte     X
     *              01-short    X
     *              11-word     X   X   X   X
     *              10-unused
     * K-map for sel1
     * i_sel[2:1]\i_addr[1:0]   00  01  11  10
     *              00-byte         X
     *              01-short    X
     *              11-word     X   X   X   X
     *              10-unused
     * K-map for sel2
     * i_sel[2:1]\i_addr[1:0]   00  01  11  10
     *              00-byte                 X
     *              01-short                X
     *              11-word     X   X   X   X
     *              10-unused
     * K-map for sel3
     * i_sel[2:1]\i_addr[1:0]   00  01  11  10
     *              00-byte             X
     *              01-short                X
     *              11-word     X   X   X   X
     *              10-unused
     */
    assign _sel0 = ((i_sel[2] & i_sel[1]) |
                   (~i_sel[2] & ~i_addr[1] & ~i_addr[0]));
    assign _sel1 = ((i_sel[2] & i_sel[1]) |
                   ( i_sel[1] & ~i_addr[1] & ~i_addr[0]) |
                   (~i_sel[2] & ~i_sel[1] & ~i_addr[1] & i_addr[0]));
    assign _sel2 = ((i_sel[2] & i_sel[1]) |
                   (~i_sel[2] & i_addr[1] & ~i_addr[0]));
    assign _sel3 = ((i_sel[2] & i_sel[1]) |
                   ( i_sel[1] & i_addr[1] & ~i_addr[0]) |
                   (~i_sel[2] & ~i_sel[1] & i_addr[1] & i_addr[0]));

    // ENABLE
    assign _en0 = _en & _sel0;  
    assign _en1 = _en & _sel1;
    assign _en2 = _en & _sel2;
    assign _en3 = _en & _sel3;
    
    // WRITING
    // Where - select target byte(s) to write to
    assign _we0 = i_we & _sel0;
    assign _we1 = i_we & _sel1;
    assign _we2 = i_we & _sel2;
    assign _we3 = i_we & _sel3;

    /* Encode 4-2
     * _sel0    _sel1   _sel2   _sel3   _sel_en1   _sel_en0
     * 1        0       0       0       0          0
     * 0        1       0       0       0          1
     * 0        0       1       0       1          0
     * 0        0       0       1       1          1
     */
    assign _sel_encode[1] = ~(_sel0 | _sel1);
    assign _sel_encode[0] = ~(_sel0 | _sel2);

    // What - set correct wd
    always_comb begin
        case(i_sel[2:1])
            2'b00: begin // write byte
                case(_sel_encode)
                    2'b00: begin
                        _wd0 = i_data[7:0];
                        _wd1 = 8'hx;
                        _wd2 = 8'hx;
                        _wd3 = 8'hx;
                    end
                    2'b01: begin
                        _wd0 = 8'hx;
                        _wd1 = i_data[7:0];
                        _wd2 = 8'hx;
                        _wd3 = 8'hx;
                    end
                    2'b10: begin
                        _wd0 = 8'hx;
                        _wd1 = 8'hx;
                        _wd2 = i_data[7:0];
                        _wd3 = 8'hx;
                    end
                    2'b11: begin
                        _wd0 = 8'hx;
                        _wd1 = 8'hx;
                        _wd2 = 8'hx;
                        _wd3 = i_data[7:0];
                    end
                    default: begin
                        _wd0 = 8'hx;
                        _wd1 = 8'hx;
                        _wd2 = 8'hx;
                        _wd3 = 8'hx;
                    end
                endcase
            end
            2'b01: begin // write short
                case(_sel0)
                    1'b0: begin // 
                        _wd0 = 8'hx;
                        _wd1 = 8'hx;
                        _wd2 = i_data[15:8];
                        _wd3 = i_data[7:0];
                    end
                    1'b1: begin //
                        _wd0 = i_data[15:8];
                        _wd1 = i_data[7:0];
                        _wd2 = 8'hx;
                        _wd3 = 8'hx;
                    end
                    default begin
                        _wd0 = 8'hx;
                        _wd1 = 8'hx;
                        _wd2 = 8'hx;
                        _wd3 = 8'hx;
                    end
                endcase
            end
            2'b11: begin // write word
                _wd0 = i_data[31:24];
                _wd1 = i_data[23:16];
                _wd2 = i_data[15:8];
                _wd3 = i_data[7:0];
            end
            default: begin
                _wd0 = 8'hx;
                _wd1 = 8'hx;
                _wd2 = 8'hx;
                _wd3 = 8'hx;
            end
        endcase
    end

    // READING
    always_ff @(posedge i_clk) begin
        _b_i_we          <= i_we;
        _b_i_sel         <= i_sel;
        _b_en            <= _en;
        _b_sel0          <= _sel0;
        // _b_sel1          <= _sel1;
        // _b_sel2          <= _sel2;
        // _b_sel3          <= _sel3;
        _b_sel_encode    <= _sel_encode;
    end

    /* Encode 4-2
     * _b_sel0      _b_sel1     _b_sel2     _b_sel3     _b_sel_en1      _b_sel_en0
     * 1            0           0           0           0               0
     * 0            1           0           0           0               1
     * 0            0           1           0           1               0
     * 0            0           0           1           1               1
     */

    always_comb begin // Mask output
        if (_b_en & ~_b_i_we) begin
            case(_b_i_sel[2:1])
                2'b00: begin
                    case(_b_sel_encode)
                        2'b00:   o_data = {24'b0, _rd0};
                        2'b01:   o_data = {24'b0, _rd1};
                        2'b10:   o_data = {24'b0, _rd2};
                        2'b11:   o_data = {24'b0, _rd3};
                        default: o_data = 32'hx;
                    endcase
                end
                2'b01: begin
                    o_data = _b_sel0 ? {16'b0, _rd0, _rd1} : {16'b0, _rd2, _rd3};
                end
                2'b11:
                    o_data = {_rd0, _rd1, _rd2, _rd3};
                default:
                    o_data = 32'hx; // Read but invalid data
            endcase
        end
        else
            o_data = 32'h0; // Read not enabled, return 0 to databus
    end

    // ACK
    always_ff @(posedge i_clk) begin
        o_ack <= _en;
    end

    // ERR
    assign o_err = 1'b0;

    // STALL
    assign o_stall = 1'b0;

endmodule
