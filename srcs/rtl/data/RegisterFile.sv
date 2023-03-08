module RegisterFile (
    input  logic        i_clk,
    input  logic        i_rst,
    input  logic [ 4:0] i_a1, i_a2, i_a3,
    input  logic        i_we3,            // write enable for port 3
    input  logic [31:0] i_wd3,            // write data for port 3
    output logic [31:0] o_rd1, o_rd2
);

    logic [31:0] regs[31:0];

    // Not synthesizable
    /* initial begin
        for (int i = 0; i < 32; i=i+1)
            regs[i] = 32'h0;
    end */

    // three ported register file
    // read two ports on rising edge (A1/RD1, A2/RD2)
    // write third port on falling edge of clock (A3/WD3/WE3)
    // register 0 hardwired to 0

    always_ff @(posedge i_clk) begin
        o_rd1 <= (i_a1 != 0) ? regs[i_a1] : 0;
        o_rd2 <= (i_a2 != 0) ? regs[i_a2] : 0;
    end

    always_ff @(negedge i_clk)
        if (~i_rst) begin
            // Yosys does not support
            // regs <= '{default:32'b0};
            for (int i = 0; i < 32; i++) regs[i] <= 32'h0;
        end
        else begin
            if (i_we3) begin
                regs[i_a3] <= (i_a3 != 0) ? i_wd3 : 0;
            end
        end

endmodule
