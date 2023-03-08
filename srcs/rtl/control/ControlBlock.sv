module ControlBlock (
    input  logic [6:0] i_opcode,
    input  logic [2:0] i_funct3,
    input  logic       i_funct7_b5,
    // See opcodeDecoder
    output logic       o_en_regfile_write,
    output logic [2:0] o_mux_immext_src,
    output logic       o_mux_pc_adder_src,
    output logic       o_mux_alu_src_a,
    output logic       o_mux_alu_src_b,
    output logic       o_en_datamem_access,
    output logic       o_en_datamem_write,
    output logic [1:0] o_mux_final_result_src,
    // See aluDecoder
    output logic [3:0] o_alu_control,
    // See dataMaskDecoder
    output logic [1:0] o_mask_type,
    output logic       o_ext_type,
    // See branchDecoder
    output logic       o_branch, o_jump
);
    logic [1:0] ALUOp;        // for opcodeDecoder - aluDecoder
    
    OpcodeDecoder opcodeDecoder (
        .op(i_opcode),
        .RegWrite(o_en_regfile_write),
        .ImmSrc(o_mux_immext_src),
        .PCAdderSrc(o_mux_pc_adder_src),
        .ALUSrcA(o_mux_alu_src_a),
        .ALUSrcB(o_mux_alu_src_b),
        .MemRequest(o_en_datamem_access),
        .MemWrite(o_en_datamem_write),
        .ResultSrc(o_mux_final_result_src),
        .Branch(o_branch),
        .Jump(o_jump),
        .ALUOp(ALUOp)
    );
    
    ALUDecoder aluDecoder(
        .op_b5(i_opcode[5]),
        .funct3(i_funct3),
        .funct7_b5(i_funct7_b5), 
        .alu_op(ALUOp),
        .alu_control(o_alu_control)
    );
    DataMaskDecoder dataMaskDecoder(
        .funct3(i_funct3),
        .mask_type(o_mask_type),
        .ext_type(o_ext_type)
    );

endmodule
