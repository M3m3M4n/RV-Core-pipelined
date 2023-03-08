module DPBRAMVarWidth #(
    parameter  integer WIDTH_BITS = 32,
    parameter  integer SIZE_BITS  = 2048, // will get truc to width
    localparam integer ARRAYINDEX = (SIZE_BITS / WIDTH_BITS) - 1,
    localparam integer ADDRWIDTH  = $clog2(ARRAYINDEX)
)(
    input  logic                      i_p1_clk,
    input  logic                      i_p1_en,
    input  logic                      i_p1_we,
    input  logic [ADDRWIDTH  - 1 : 0] i_p1_addr,
    input  logic [WIDTH_BITS - 1 : 0] i_p1_wd,
    output logic [WIDTH_BITS - 1 : 0] o_p1_rd,
    input  logic                      i_p2_clk,
    input  logic                      i_p2_en,
    input  logic                      i_p2_we,
    input  logic [ADDRWIDTH  - 1 : 0] i_p2_addr,
    input  logic [WIDTH_BITS - 1 : 0] i_p2_wd,
    output logic [WIDTH_BITS - 1 : 0] o_p2_rd
);

    logic [WIDTH_BITS - 1 : 0] RAM [ARRAYINDEX : 0];

    // Not synthesizable
    // initial begin
    //     for (int i = 0; i < SIZE_BYTE; i = i + 1)
    //         RAM[i] = 8'h0;
    // end

    always_ff @(posedge i_p1_clk) begin
        if (i_p1_en) begin
            if (~i_p1_we)
                o_p1_rd <= RAM[i_p1_addr];
            else
                RAM[i_p1_addr] <= i_p1_wd;
        end
        else
            o_p1_rd <= 'h0;
    end

    always_ff @(posedge i_p2_clk) begin
        if (i_p2_en) begin
            if (~i_p2_we)
                o_p2_rd <= RAM[i_p2_addr];
            // Yosys does not support true dual port ram
            // check again later, port 2 is read only for now
            //else
                //RAM[i_p2_addr] <= i_p2_wd;
        end
        else
            o_p2_rd <= 'h0;
    end

endmodule
