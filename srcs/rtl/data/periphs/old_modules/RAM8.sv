module RAM8 #(
    parameter  SIZE_BYTE = 2048,   // Byte
    localparam ARRAYSIZE = SIZE_BYTE - 1,
    localparam ADDRWIDTH = $clog2(ARRAYSIZE)
)(
    input  logic               i_clk,
    input  logic               i_we,
    input  logic               i_re,
    input  logic [ADDRWIDTH - 1:0] i_addr,
    input  logic [7:0]         i_wd,
    output logic [7:0]         o_rd
);

    logic [7:0] RAM [ARRAYSIZE:0];

    // Not synthesizable
    // initial begin
    //     for (int i = 0; i < SIZE_BYTE; i = i + 1)
    //         RAM[i] = 8'h0;
    // end

    always_ff @(posedge i_clk) begin
        if (i_we) begin
            RAM[i_addr] <= i_wd;
        end
        if (i_re) begin
            o_rd <= RAM[i_addr];
        end
    end

endmodule
