module BRAMVarWidth #(
    parameter  integer WIDTH_BITS = 32,
    parameter  integer SIZE_BITS  = 2048, // will get truc to width
    localparam integer ARRAYINDEX = (SIZE_BITS / WIDTH_BITS) - 1,
    localparam integer ADDRWIDTH  = $clog2(ARRAYINDEX)
)(
    input  logic                      i_clk,
    input  logic                      i_en,
    input  logic                      i_we,
    input  logic [ADDRWIDTH - 1 : 0]  i_addr,
    input  logic [WIDTH_BITS - 1 : 0] i_wd,
    output logic [WIDTH_BITS - 1 : 0] o_rd
);

    logic [WIDTH_BITS - 1 : 0] RAM [ARRAYINDEX:0];

    // Not synthesizable
    // initial begin
    //     for (int i = 0; i < SIZE_BYTE; i = i + 1)
    //         RAM[i] = 8'h0;
    // end

    always_ff @(posedge i_clk) begin
        if (i_en) begin
            if (~i_we)
                o_rd <= RAM[i_addr];
            else
                RAM[i_addr] <= i_wd;
        end
        else
            o_rd <= 'h0;
    end

endmodule