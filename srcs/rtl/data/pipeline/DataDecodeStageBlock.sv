module DataDecodeStageBlock (
    input  logic        i_clk,
    input  logic        i_rst,
    // From fetch
    input  logic [31:0] i_d_instr,
    // From writeback
    input  logic [4:0]  i_result_addr,
    input  logic [31:0] i_final_result,
    // From control
    input  logic        i_en_regfile_write,
    input  logic [2:0]  i_mux_immext_src,
    // To exec
    output logic [31:0] o_rd1, o_rd2,      // Register file output
    output logic [31:0] o_immext
);

    RegisterFile registerFile(
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_a1(i_d_instr[19:15]),
        .i_a2(i_d_instr[24:20]),
        .i_a3(i_result_addr),
        .i_we3(i_en_regfile_write),
        .i_wd3(i_final_result),
        .o_rd1(o_rd1),
        .o_rd2(o_rd2)
    );

    ImmExtender  immExtender(
        .i_instr(i_d_instr[31:7]),
        .i_mux_immext_src(i_mux_immext_src),
        .o_immext(o_immext)
    );

endmodule
