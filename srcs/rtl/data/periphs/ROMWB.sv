module ROMWB #(
    parameter SIZE_BYTE = 2048,
    // 32 bit address interface
    parameter START_ADDR = 32'h10000000
)(
    input  logic        i_clk,
    input  logic        i_cyc,
    input  logic        i_stb,
    input  logic [31:0] i_addr,
    input  logic        i_we,
    input  logic [3:0]  i_sel,
    output logic        o_ack,
    output logic        o_err,
    output logic [31:0] o_data,
    output logic        o_stall,

    // ROM interface
    output logic        o_rom_clk,
    output logic        o_rom_en,
    output logic [31:0] o_rom_addr,
    input  logic [31:0] i_rom_rd
);

    // Byte addressible
    localparam ADDRWIDTH = $clog2((SIZE_BYTE << 1) - 1); // SIZEBYTE * 2 for in and out regs

    // START_ADDR alignment check
    always_comb begin
        if (START_ADDR[ADDRWIDTH-1:0] != 'b0)
            $fatal("%m: Address range is not aligned!");
    end

    /* Read address and read mode alignment check
     * Kmap for align:
     * i_sel[2:1]\i_addr[1:0]   00  01  11  10
     *              00-byte     X   X   X   X
     *              01-short    X           X
     *              11-word     X
     *              10-unused
     */
    logic _align;
    assign _align = ~i_sel[2] & ~i_sel[1] |
                    ~i_sel[2] & ~i_addr[0] |
                    i_sel[1] & ~i_addr[1] & ~i_addr[0];

    // Wishbone controls 
    logic _en;
    assign _en = i_cyc & i_stb & ~i_we & _align;

    // Signal passthrough
    assign o_rom_clk  = i_clk;
    assign o_rom_en   = _en;
    // Unlike normal module, which addr partition part will be cut here,
    // pass full addr to module and snip out there.
    assign o_rom_addr = i_addr;

    /* Data readout byte selection
     * K-map for sel0
     * i_sel[2:1]\i_addr[1:0]   00  01  11  10
     *              00-byte     X
     *              01-short    X
     *              11-word     X
     *              10-unused
     * K-map for sel1
     * i_sel[2:1]\i_addr[1:0]   00  01  11  10
     *              00-byte         X
     *              01-short    X
     *              11-word     X
     *              10-unused
     * K-map for sel2
     * i_sel[2:1]\i_addr[1:0]   00  01  11  10
     *              00-byte                 X
     *              01-short                X
     *              11-word     X
     *              10-unused
     * K-map for sel3
     * i_sel[2:1]\i_addr[1:0]   00  01  11  10
     *              00-byte             X
     *              01-short                X
     *              11-word     X
     *              10-unused
     */
    logic _sel0, _sel1, _sel2, _sel3;
    logic _b_sel0, _b_sel2;
    assign _sel0 = ~i_sel[2] & ~i_addr[1] & ~i_addr[0] |
                    i_sel[1] & ~i_addr[1] & ~i_addr[0];
    assign _sel1 =  i_sel[1] & ~i_addr[1] & ~i_addr[0] |
                   ~i_sel[2] & ~i_sel[1] & ~i_addr[1] & i_addr[0];
    assign _sel2 = ~i_sel[2] & i_addr[1] & ~i_addr[0] |
                    i_sel[2] & i_sel[1] & ~i_addr[1] & ~i_addr[0];
    assign _sel3 =  i_sel[2] & i_sel[1] & ~i_addr[1] & ~i_addr[0] |
                   ~i_sel[2] & ~i_sel[1] & i_addr[1] & i_addr[0] |
                   ~i_sel[2] & i_sel[1] & i_addr[1] & ~i_addr[0];

    /* Encode 4-2 for byte reading case readability
     * _sel0    _sel1   _sel2   _sel3   _sel_en1   _sel_en0
     * 1        0       0       0       0          0
     * 0        1       0       0       0          1
     * 0        0       1       0       1          0
     * 0        0       0       1       1          1
     */
    logic [1:0] _sel_encode, _b_sel_encode;
    assign _sel_encode[1] = ~(_sel0 | _sel1);
    assign _sel_encode[0] = ~(_sel0 | _sel2);

    logic [3:0] _b_i_sel;
    always_ff @(posedge i_clk) begin
        if (_en) begin
            _b_i_sel      <= i_sel;
            _b_sel0       <= _sel0;
            _b_sel2       <= _sel2;
            _b_sel_encode <= _sel_encode;
        end
    end

    // ACK
    always_ff @(posedge i_clk) begin : ack
        o_ack <= _en;
    end

    // Data out
    always_comb begin : read
        if (o_ack) begin
            case (_b_i_sel[2:1])
                2'b00: begin
                    case(_b_sel_encode)
                        2'b00:   o_data = {24'b0, i_rom_rd[7:0]};
                        2'b01:   o_data = {24'b0, i_rom_rd[15:8]};
                        2'b10:   o_data = {24'b0, i_rom_rd[23:16]};
                        2'b11:   o_data = {24'b0, i_rom_rd[31:24]};
                        default: o_data = 32'hx;
                    endcase
                end
                2'b01: begin
                    o_data = _b_sel0 ? {16'b0, i_rom_rd[15:8], i_rom_rd[7:0]} :
                             _b_sel2 ? {16'b0, i_rom_rd[31:24], i_rom_rd[23:16]} :
                             32'hx;
                end
                2'b11:
                    o_data = i_rom_rd;
                default:
                    o_data = 32'hx; // Read but invalid data
            endcase
        end
        else
            o_data = 32'h0; // 0 out to bus
    end

    // ERR
    assign o_err = i_cyc & i_stb & (i_we | ~_align);

    // STALL
    assign o_stall = 1'b0;

endmodule
