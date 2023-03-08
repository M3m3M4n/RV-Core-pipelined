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

module DPBRAMWB #(
    parameter SIZE_BYTE  = 8192, 
    parameter START_ADDR = 32'h20000000
)(
`ifdef VERILATOR
    // dummy sigs
    input logic         i_clk,
    input logic         i_rst,
`endif
    // Port 1: WB
    input  logic        i_wb_clk,
    input  logic        i_wb_cyc,
    input  logic        i_wb_stb,
    input  logic [31:0] i_wb_addr,
    input  logic        i_wb_we,
    input  logic [31:0] i_wb_data,
    input  logic [3:0]  i_wb_sel,
    output logic        o_wb_ack,
    output logic        o_wb_err,
    output logic [31:0] o_wb_data,
    output logic        o_wb_stall,
    // Port 2: 32 bit width only
    input  logic        i_p2_clk,
    input  logic        i_p2_en,
    input  logic        i_p2_we,
    input  logic [31:0] i_p2_addr,
    input  logic [31:0] i_p2_wd,
    output logic [31:0] o_p2_rd
);

    localparam ADDRWIDTH          = $clog2(SIZE_BYTE - 1);
    localparam SIZEDIV4           = SIZE_BYTE >> 2; // Div 4
    localparam ADDRWIDTH_SIZEDIV4 = $clog2(SIZEDIV4 - 1);

    // START_ADDR alignment check
    always_comb begin
        if (START_ADDR[ADDRWIDTH-1:0] != 'b0)
            $fatal("%m: Address range is not aligned!");
    end

    // High when both i_wb_cyc and i_wb_stb high
    logic       _wb_en;
    // Bank select logic
    logic       _wb_sel0, _wb_sel1, _wb_sel2, _wb_sel3;
    // == _wb_en & _wb_selx
    logic       _wb_en0, _wb_en1, _wb_en2, _wb_en3;
    // == _wb_we & _wb_selx
    logic       _wb_we0, _wb_we1, _wb_we2, _wb_we3;
    // Data for banks
    logic [7:0] _wb_rd0, _wb_rd1, _wb_rd2, _wb_rd3;
    logic [7:0] _wb_wd0, _wb_wd1, _wb_wd2, _wb_wd3;
    // For writing bytes
    logic [1:0] _wb_sel_encode;

    // Buffered for reading as ram need 1 cycle
    // Writes don't need buffering
    logic       _b_i_wb_we;
    logic       _b_wb_en;
    logic [3:0] _b_i_wb_sel;
    logic       _b_wb_sel0; //, _b_wb_sel1, _b_wb_sel2, _b_wb_sel3
    logic [1:0] _b_wb_sel_encode;

    DPBRAMVarWidth #(
        .WIDTH_BITS(8),
        .SIZE_BITS(SIZEDIV4 * 8)
    ) row0 (
        .i_p1_clk (i_wb_clk),
        .i_p1_en  (_wb_en0),
        .i_p1_we  (_wb_we0),
        .i_p1_addr(i_wb_addr[ADDRWIDTH_SIZEDIV4 + 1:2]), // -1 + 2 = +1 to compensate 2 bits
        .i_p1_wd  (_wb_wd0),
        .o_p1_rd  (_wb_rd0),
        .i_p2_clk (i_p2_clk),
        .i_p2_en  (i_p2_en),
        .i_p2_we  (i_p2_we),
        .i_p2_addr(i_p2_addr[ADDRWIDTH_SIZEDIV4 + 1:2]),
        .i_p2_wd  (i_p2_wd[7:0]),
        .o_p2_rd  (o_p2_rd[7:0])
    );
    DPBRAMVarWidth #(
        .WIDTH_BITS(8),
        .SIZE_BITS(SIZEDIV4 * 8)
    ) row1 (
        .i_p1_clk (i_wb_clk),
        .i_p1_en  (_wb_en1),
        .i_p1_we  (_wb_we1),
        .i_p1_addr(i_wb_addr[ADDRWIDTH_SIZEDIV4 + 1:2]),
        .i_p1_wd  (_wb_wd1),
        .o_p1_rd  (_wb_rd1),
        .i_p2_clk (i_p2_clk),
        .i_p2_en  (i_p2_en),
        .i_p2_we  (i_p2_we),
        .i_p2_addr(i_p2_addr[ADDRWIDTH_SIZEDIV4 + 1:2]),
        .i_p2_wd  (i_p2_wd[15:8]),
        .o_p2_rd  (o_p2_rd[15:8])
    );
    DPBRAMVarWidth #(
        .WIDTH_BITS(8),
        .SIZE_BITS(SIZEDIV4 * 8)
    ) row2 (
        .i_p1_clk (i_wb_clk),
        .i_p1_en  (_wb_en2),
        .i_p1_we  (_wb_we2),
        .i_p1_addr(i_wb_addr[ADDRWIDTH_SIZEDIV4 + 1:2]),
        .i_p1_wd  (_wb_wd2),
        .o_p1_rd  (_wb_rd2),
        .i_p2_clk (i_p2_clk),
        .i_p2_en  (i_p2_en),
        .i_p2_we  (i_p2_we),
        .i_p2_addr(i_p2_addr[ADDRWIDTH_SIZEDIV4 + 1:2]),
        .i_p2_wd  (i_p2_wd[23:16]),
        .o_p2_rd  (o_p2_rd[23:16])
    );
    DPBRAMVarWidth #(
        .WIDTH_BITS(8),
        .SIZE_BITS(SIZEDIV4 * 8)
    ) row3 (
        .i_p1_clk (i_wb_clk),
        .i_p1_en  (_wb_en3),
        .i_p1_we  (_wb_we3),
        .i_p1_addr(i_wb_addr[ADDRWIDTH_SIZEDIV4 + 1:2]),
        .i_p1_wd  (_wb_wd3),
        .o_p1_rd  (_wb_rd3),
        .i_p2_clk (i_p2_clk),
        .i_p2_en  (i_p2_en),
        .i_p2_we  (i_p2_we),
        .i_p2_addr(i_p2_addr[ADDRWIDTH_SIZEDIV4 + 1:2]),
        .i_p2_wd  (i_p2_wd[31:24]),
        .o_p2_rd  (o_p2_rd[31:24])
    );

    assign _wb_en = i_wb_cyc & i_wb_stb;

    /* Memory byte select logic
     * i_wb_sel:
     *  - From Wishbone master, has 4 possible input 0001, 0011, 1111. Use [2:1] for identificaton
     * i_wb_addr:
     *  - Last 2 bits of addr are used to determine byte / short address, Other bits determine column
     *  - READING: 4 bytes are read at a time => need to know which is useful/correct for extension
     *  - WRITING: Need to enable correct we signal & select correct targeted wd to move data to
     * K-map for sel0
     * i_wb_sel[2:1]\i_wb_addr[1:0]   00  01  11  10
     *                    00-byte     X
     *                    01-short    X
     *                    11-word     X   X   X   X
     *                    10-unused
     * K-map for sel1
     * i_wb_sel[2:1]\i_wb_addr[1:0]   00  01  11  10
     *                    00-byte         X
     *                    01-short    X
     *                    11-word     X   X   X   X
     *                    10-unused
     * K-map for sel2
     * i_wb_sel[2:1]\i_wb_addr[1:0]   00  01  11  10
     *                    00-byte                 X
     *                    01-short                X
     *                    11-word     X   X   X   X
     *                    10-unused
     * K-map for sel3
     * i_wb_sel[2:1]\i_wb_addr[1:0]   00  01  11  10
     *                    00-byte             X
     *                    01-short                X
     *                    11-word     X   X   X   X
     *                    10-unused
     */
    assign _wb_sel0 = ((i_wb_sel[2] & i_wb_sel[1]) |
                   (~i_wb_sel[2] & ~i_wb_addr[1] & ~i_wb_addr[0]));
    assign _wb_sel1 = ((i_wb_sel[2] & i_wb_sel[1]) |
                   ( i_wb_sel[1] & ~i_wb_addr[1] & ~i_wb_addr[0]) |
                   (~i_wb_sel[2] & ~i_wb_sel[1] & ~i_wb_addr[1] & i_wb_addr[0]));
    assign _wb_sel2 = ((i_wb_sel[2] & i_wb_sel[1]) |
                   (~i_wb_sel[2] & i_wb_addr[1] & ~i_wb_addr[0]));
    assign _wb_sel3 = ((i_wb_sel[2] & i_wb_sel[1]) |
                   ( i_wb_sel[1] & i_wb_addr[1] & ~i_wb_addr[0]) |
                   (~i_wb_sel[2] & ~i_wb_sel[1] & i_wb_addr[1] & i_wb_addr[0]));

    // ENABLE
    assign _wb_en0 = _wb_en & _wb_sel0;  
    assign _wb_en1 = _wb_en & _wb_sel1;
    assign _wb_en2 = _wb_en & _wb_sel2;
    assign _wb_en3 = _wb_en & _wb_sel3;
    
    // WRITING
    // Where - select target byte(s) to write to
    assign _wb_we0 = i_wb_we & _wb_sel0;
    assign _wb_we1 = i_wb_we & _wb_sel1;
    assign _wb_we2 = i_wb_we & _wb_sel2;
    assign _wb_we3 = i_wb_we & _wb_sel3;

    /* Encode 4-2
     * _wb_sel0    _wb_sel1   _wb_sel2   _wb_sel3   _sel_en1   _sel_en0
     * 1        0       0       0       0          0
     * 0        1       0       0       0          1
     * 0        0       1       0       1          0
     * 0        0       0       1       1          1
     */
    assign _wb_sel_encode[1] = ~(_wb_sel0 | _wb_sel1);
    assign _wb_sel_encode[0] = ~(_wb_sel0 | _wb_sel2);

    // What - set correct wd
    always_comb begin
        case(i_wb_sel[2:1])
            2'b00: begin // write byte
                case(_wb_sel_encode)
                    2'b00: begin
                        _wb_wd0 = i_wb_data[7:0];
                        _wb_wd1 = 8'hx;
                        _wb_wd2 = 8'hx;
                        _wb_wd3 = 8'hx;
                    end
                    2'b01: begin
                        _wb_wd0 = 8'hx;
                        _wb_wd1 = i_wb_data[7:0];
                        _wb_wd2 = 8'hx;
                        _wb_wd3 = 8'hx;
                    end
                    2'b10: begin
                        _wb_wd0 = 8'hx;
                        _wb_wd1 = 8'hx;
                        _wb_wd2 = i_wb_data[7:0];
                        _wb_wd3 = 8'hx;
                    end
                    2'b11: begin
                        _wb_wd0 = 8'hx;
                        _wb_wd1 = 8'hx;
                        _wb_wd2 = 8'hx;
                        _wb_wd3 = i_wb_data[7:0];
                    end
                    default: begin
                        _wb_wd0 = 8'hx;
                        _wb_wd1 = 8'hx;
                        _wb_wd2 = 8'hx;
                        _wb_wd3 = 8'hx;
                    end
                endcase
            end
            2'b01: begin // write short
                case(_wb_sel0)
                    1'b0: begin // 
                        _wb_wd0 = 8'hx;
                        _wb_wd1 = 8'hx;
                        _wb_wd2 = i_wb_data[15:8];
                        _wb_wd3 = i_wb_data[7:0];
                    end
                    1'b1: begin //
                        _wb_wd0 = i_wb_data[15:8];
                        _wb_wd1 = i_wb_data[7:0];
                        _wb_wd2 = 8'hx;
                        _wb_wd3 = 8'hx;
                    end
                    default begin
                        _wb_wd0 = 8'hx;
                        _wb_wd1 = 8'hx;
                        _wb_wd2 = 8'hx;
                        _wb_wd3 = 8'hx;
                    end
                endcase
            end
            2'b11: begin // write word
                _wb_wd0 = i_wb_data[31:24];
                _wb_wd1 = i_wb_data[23:16];
                _wb_wd2 = i_wb_data[15:8];
                _wb_wd3 = i_wb_data[7:0];
            end
            default: begin
                _wb_wd0 = 8'hx;
                _wb_wd1 = 8'hx;
                _wb_wd2 = 8'hx;
                _wb_wd3 = 8'hx;
            end
        endcase
    end

    // READING

    always_ff @(posedge i_wb_clk) begin
        _b_i_wb_we          <= i_wb_we;
        _b_i_wb_sel         <= i_wb_sel;
        _b_wb_en            <= _wb_en;
        _b_wb_sel0          <= _wb_sel0;
        // _b_wb_sel1          <= _wb_sel1;
        // _b_wb_sel2          <= _wb_sel2;
        // _b_wb_sel3          <= _wb_sel3;
        _b_wb_sel_encode    <= _wb_sel_encode;
    end

    /* Encode 4-2
     * _b_wb_sel0      _b_wb_sel1     _b_wb_sel2     _b_wb_sel3     _b_sel_en1      _b_sel_en0
     * 1            0           0           0           0               0
     * 0            1           0           0           0               1
     * 0            0           1           0           1               0
     * 0            0           0           1           1               1
     */

    always_comb begin // Mask output
        if (_b_wb_en & ~_b_i_wb_we) begin
            case(_b_i_wb_sel[2:1])
                2'b00: begin
                    case(_b_wb_sel_encode)
                        2'b00:   o_wb_data = {24'b0, _wb_rd0};
                        2'b01:   o_wb_data = {24'b0, _wb_rd1};
                        2'b10:   o_wb_data = {24'b0, _wb_rd2};
                        2'b11:   o_wb_data = {24'b0, _wb_rd3};
                        default: o_wb_data = 32'hx;
                    endcase
                end
                2'b01: begin
                    o_wb_data = _b_wb_sel0 ? {16'b0, _wb_rd0, _wb_rd1} : {16'b0, _wb_rd2, _wb_rd3};
                end
                2'b11:
                    o_wb_data = {_wb_rd0, _wb_rd1, _wb_rd2, _wb_rd3};
                default:
                    o_wb_data = 32'hx; // Read but invalid data
            endcase
        end
        else
            o_wb_data = 32'h0; // Read not enabled, return 0 to databus
    end

    // ACK
    always_ff @(posedge i_wb_clk) begin
        o_wb_ack <= _wb_en;
    end

    // ERR
    assign o_wb_err = 1'b0;

    // STALL
    assign o_wb_stall = 1'b0;

endmodule
