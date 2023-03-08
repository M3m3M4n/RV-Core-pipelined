module DPBRAM32 #(
    parameter  SIZE_BYTE = 80, // Byte, should >= 4
    localparam ARRAYSIZE = (SIZE_BYTE << 2) - 1,
    localparam ADDRWIDTH = $clog2(ARRAYSIZE)
)(
    input  logic                   i_p1_clk,
    input  logic                   i_p1_en,
    input  logic                   i_p1_we,
    input  logic [ADDRWIDTH - 1:0] i_p1_addr,
    input  logic [31:0]            i_p1_wd,
    output logic [31:0]            o_p1_rd,
    input  logic                   i_p2_clk,
    input  logic                   i_p2_en,
    input  logic                   i_p2_we,
    input  logic [ADDRWIDTH - 1:0] i_p2_addr,
    input  logic [31:0]            i_p2_wd,
    output logic [31:0]            o_p2_rd
);

    logic [31:0] RAM [ARRAYSIZE:0];

    always_ff @(posedge i_p1_clk) begin
        if (i_p1_en) begin
            if (~i_p1_we)
                o_p1_rd <= RAM[i_p1_addr];
            else
                RAM[i_p1_addr] <= i_p1_wd;
        end
        else
            o_p1_rd <= 32'b0;
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
            o_p2_rd <= 32'b0;
    end

endmodule
