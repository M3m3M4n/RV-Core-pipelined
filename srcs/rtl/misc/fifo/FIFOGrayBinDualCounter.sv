/* Dual counter based on Cummings paper
 */
module FIFOGrayBinDualCounter #(
    parameter WIDTH_BITS = 8
) (
    input  logic                      i_clk,
    input  logic                      i_rst,
    input  logic                      i_en,
    output logic [WIDTH_BITS - 1 : 0] o_bin,
    output logic [WIDTH_BITS : 0]     o_gry // Width + 1
);

    logic [WIDTH_BITS : 0] _bin, _gry;
    logic [WIDTH_BITS : 0] _gry_nxt, _bin_nxt;

    assign o_bin = _bin[WIDTH_BITS - 1 : 0];
    assign o_gry = _gry;

    assign _bin_nxt = _bin + i_en;

    always_ff @(posedge i_clk) begin
        if (~i_rst) begin
            _bin <= 'h0;
            _gry <= 'h0;
        end
        else begin
            _bin <= _bin_nxt;
            _gry <= _gry_nxt;
        end
    end

    Bin2Gray #(
        .WIDTH_BITS(WIDTH_BITS)
    ) b2g (
        .i_bin(_bin_nxt),
        .o_gray(_gry_nxt)
    );

endmodule
