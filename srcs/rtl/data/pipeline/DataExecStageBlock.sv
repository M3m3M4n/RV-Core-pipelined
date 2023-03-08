module DataExecStageBlock (
    // input  logic        i_clk,
    // From decode stage
    input  logic [31:0] i_rd1, i_rd2,
    input  logic [31:0] i_immext,
    input  logic [31:0] i_pc,
    // Data forward lines
    input  logic [31:0] i_m_e_foward_data_alu,        // Data forward line from mem stage
    input  logic [31:0] i_m_e_foward_data_immext,
    input  logic [31:0] i_w_e_foward_data,        // Data forward line from wb stage
    // From control
    input  logic [3:0]  i_alu_control,            // See aluDecoder
    input  logic        i_mux_alu_src_a, i_mux_alu_src_b,
    input  logic        i_mux_pc_adder_src,
    // From hazard
    input  logic [1:0]  i_mux_alu_forward_src_a,
    input  logic [1:0]  i_mux_alu_forward_src_b,
    // To Memory stage
    output logic [31:0] o_alu_result,
    output logic [31:0] o_memory_data,
    // To control
    output logic [3:0]  o_alu_flags,
    // To fetch
    output logic [31:0] o_pc_adder_result
);

    logic [31:0] forward_a, forward_b;
    logic [31:0] alu_src_a, alu_src_b;
    logic [31:0] pc_adder_src;

    Mux4 mux_forward_alu_src_a (
        .i_d0(i_rd1),
        .i_d1(i_w_e_foward_data),
        .i_d2(i_m_e_foward_data_alu),
        .i_d3(i_m_e_foward_data_immext),
        .i_s(i_mux_alu_forward_src_a),
        .o_y(forward_a)
    ); 

    Mux4 mux_forward_alu_src_b (
        .i_d0(i_rd2),
        .i_d1(i_w_e_foward_data),
        .i_d2(i_m_e_foward_data_alu),
        .i_d3(i_m_e_foward_data_immext),
        .i_s(i_mux_alu_forward_src_b),
        .o_y(forward_b)
    );

    assign o_memory_data = forward_b;

    Mux2 mux_alu_src_a (
        .i_d0(forward_a),
        .i_d1(i_pc),
        .i_s(i_mux_alu_src_a),
        .o_y(alu_src_a)
    );

    Mux2 mux_alu_src_b (
        .i_d0(forward_b),
        .i_d1(i_immext),
        .i_s(i_mux_alu_src_b),
        .o_y(alu_src_b)
    );

    Mux2 mux_pc_adder_src (
        .i_d0(i_pc),
        .i_d1(forward_a),
        .i_s(i_mux_pc_adder_src),
        .o_y(pc_adder_src)
    );

    assign o_pc_adder_result = pc_adder_src + i_immext;

    ALU alu (
        .i_a(alu_src_a),
        .i_b(alu_src_b),
        .i_alu_control(i_alu_control),
        .o_result(o_alu_result),
        .o_alu_flags(o_alu_flags)
    );

endmodule
