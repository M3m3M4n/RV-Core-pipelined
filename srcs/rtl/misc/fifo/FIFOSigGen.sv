/* Signal generator to FIFO memory
 * Based on Cummings paper
 * A FIFO needs 2 of these for both read / write clock domain
 */
module FIFOSigGen #(
    parameter  MODE = 0, // 0 == read, else == write
    parameter  DEPTH = 8,
    localparam DEPTH_WIDTH = $clog2(DEPTH)
) (
    //
    input  logic                       i_clk,
    input  logic                       i_rst,
    //
    input  logic                       i_en,       // external en signal, inc 1 in rd / wr addr
    input  logic [DEPTH_WIDTH : 0]     i_gray,     // unsync gray pointer from other domain, width +1
    output logic                       o_fe,       // full / empty signal
    output logic [DEPTH_WIDTH : 0]     o_gray,     // unsync gray pointer to other domain, width +1
    output logic                       o_data_en,  // en signal to FIFO memory (i_en & not full)
    output logic [DEPTH_WIDTH - 1 : 0] o_data_addr
);

    // Counter
    FIFOGrayBinDualCounter #(
        .WIDTH_BITS(DEPTH_WIDTH)
    ) counter (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_en (o_data_en),
        .o_bin(o_data_addr),
        .o_gry(o_gray) // Width + 1
    );

    // Sync input gray signal
    logic [DEPTH_WIDTH : 0] _gray [1:0];
    always_ff @(posedge i_clk) begin : gray_synchronizer
        _gray[1] <= _gray[0];
        _gray[0] <= i_gray;
    end

    // Full / empty signal
    generate
        if (MODE == 0) begin
            // READ - empty signal
            assign o_fe = (_gray[1] == o_gray);
        end
        else begin
            // WRITE - full signal
            assign o_fe = (_gray[1][DEPTH_WIDTH] == ~o_gray[DEPTH_WIDTH]) &
                            (_gray[1][DEPTH_WIDTH - 1] == ~o_gray[DEPTH_WIDTH - 1]) &
                            (_gray[1][DEPTH_WIDTH - 2 : 0] == o_gray[DEPTH_WIDTH - 2 : 0]);
        end
    endgenerate

    // Memory en
    // Never write full & read empty
    assign o_data_en = i_en & ~o_fe;

endmodule
