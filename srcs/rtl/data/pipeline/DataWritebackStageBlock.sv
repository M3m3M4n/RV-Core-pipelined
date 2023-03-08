module DataWritebackStageBlock (
    // From mem
    input logic  [31:0] i_alu_result,
    input logic  [31:0] i_memory_readout,
    input logic  [31:0] i_pc_p_4,
    input logic  [31:0] i_immext,
    // From control
    input logic  [1:0]  i_mux_final_result_src,
    // To decode
    output logic [31:0] o_wb
);
    
    Mux4 wb_mux (
        .i_d0(i_alu_result),
        .i_d1(i_memory_readout),
        .i_d2(i_pc_p_4),
        .i_d3(i_immext),
        .i_s(i_mux_final_result_src),
        .o_y(o_wb)
    );

endmodule
