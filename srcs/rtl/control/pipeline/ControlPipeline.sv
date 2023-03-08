module ControlPipeline (
    input  logic       i_clk,
    input  logic       i_rst,

    input  logic [6:0] i_opcode,
    input  logic [2:0] i_funct3,
    input  logic       i_funct7_b5,
    input  logic [3:0] i_alu_flags,
    // See opcodeDecoder
    output logic       o_en_regfile_write,
    output logic [2:0] o_mux_immext_src,
    output logic       o_mux_pc_adder_src,
    output logic       o_mux_alu_src_a,
    output logic       o_mux_alu_src_b,
    output logic       o_en_datamem_access,
    output logic       o_en_datamem_write,
    output logic [1:0] o_w_mux_final_result_src,
    // See branchDecoder
    output logic       o_mux_pc_src,
    // See aluDecoder
    output logic [3:0] o_alu_control,
    // See dataMaskDecoder
    output logic [1:0] o_mask_type,
    output logic       o_ext_type,
    // From hazard
    //   Flush
    input  logic       i_de_clr,      // Clear decode -> exec registers
    input  logic       i_mw_clr,      // Clear mem -> write register
    input  logic       i_em_en,       // Enable exec -> mem registers
    // To hazard
    //   Forward
    output logic       o_m_en_regfile_write,
    output logic       o_w_en_regfile_write,
    output logic [1:0] o_m_mux_final_result_src,
    //   Stall
    output logic       o_e_en_datamem_access,
    output logic [1:0] o_e_mux_final_result_src,
    output logic       o_d_mux_alu_src_a,
    output logic       o_d_mux_alu_src_b

);

    // ====================================================================================
    // Decode stage
    // Because register file read / write needs 1 cycle, so we need to buffer / delay
    // Before passing to exec
    // Later might consider a single signal register instead
    logic       d_en_regfile_write;
    logic       d_mux_pc_adder_src;
    logic       d_mux_alu_src_a;
    logic       d_mux_alu_src_b;
    logic       d_en_datamem_access;
    logic       d_en_datamem_write;
    logic [1:0] d_mux_final_result_src;
    logic [3:0] d_alu_control;
    logic [1:0] d_mask_type;
    logic       d_ext_type;
    logic       d_branch;
    logic       d_jump;
    logic [2:0] d_funct3;
    // Exec stage
    logic       e_en_regfile_write;
    logic       e_mux_pc_adder_src;
    logic       e_mux_alu_src_a;
    logic       e_mux_alu_src_b;
    logic       e_en_datamem_access;
    logic       e_en_datamem_write;
    logic [1:0] e_mux_final_result_src;
    logic [3:0] e_alu_control;
    logic [1:0] e_mask_type;
    logic       e_ext_type;
    logic       e_branch;
    logic       e_jump;
    logic [2:0] e_funct3;
    // Mem stage
    logic       m_en_regfile_write;
    logic [1:0] m_mux_final_result_src;
    logic       m_en_datamem_access;
    logic       m_en_datamem_write;
    logic [1:0] m_mask_type;
    logic       m_ext_type;
    // Writeback stage
    logic       w_en_regfile_write;
    logic [1:0] w_mux_final_result_src;

    // ====================================================================================
    // Assign input
    assign d_funct3                 = i_funct3;
    // Assign output
    assign o_en_regfile_write       = w_en_regfile_write;
    assign o_mux_pc_adder_src       = e_mux_pc_adder_src;
    assign o_mux_alu_src_a          = e_mux_alu_src_a;
    assign o_mux_alu_src_b          = e_mux_alu_src_b;
    assign o_en_datamem_access      = m_en_datamem_access;
    assign o_en_datamem_write       = m_en_datamem_write;
    assign o_w_mux_final_result_src = w_mux_final_result_src;
    assign o_alu_control            = e_alu_control;
    assign o_mask_type              = m_mask_type;
    assign o_ext_type               = m_ext_type;
    //   Hazard
    assign o_m_en_regfile_write     = m_en_regfile_write;
    assign o_w_en_regfile_write     = w_en_regfile_write;
    assign o_m_mux_final_result_src = m_mux_final_result_src;
    assign o_e_mux_final_result_src = e_mux_final_result_src;
    assign o_e_en_datamem_access    = e_en_datamem_access;
    assign o_d_mux_alu_src_a        = d_mux_alu_src_a;
    assign o_d_mux_alu_src_b        = d_mux_alu_src_b;

   // ==================================================================================== 
    ControlBlock controlBlock (
        .i_opcode(i_opcode),
        .i_funct3(i_funct3),
        .i_funct7_b5(i_funct7_b5),
        .o_en_regfile_write(d_en_regfile_write),
        .o_mux_immext_src(o_mux_immext_src), // Straight to ouput
        .o_mux_pc_adder_src(d_mux_pc_adder_src),
        .o_mux_alu_src_a(d_mux_alu_src_a),
        .o_mux_alu_src_b(d_mux_alu_src_b),
        .o_en_datamem_access(d_en_datamem_access),
        .o_en_datamem_write(d_en_datamem_write),
        .o_mux_final_result_src(d_mux_final_result_src),
        .o_alu_control(d_alu_control),
        .o_mask_type(d_mask_type),
        .o_ext_type(d_ext_type),
        .o_branch(d_branch),
        .o_jump(d_jump)
    );

    // Taken out of control block due to pipelining
    BranchDecoder branchDecoder (
        .alu_flags(i_alu_flags),
        .funct3(e_funct3),
        .branch(e_branch),
        .jump(e_jump),
        .pc_src(o_mux_pc_src) // Straight to ouput
    );

    // ====================================================================================
    // Assert async rst on branch decoder input for second fetch cycle
    // After that pipeline is established
    always_ff @( posedge i_clk) begin : d2e
        if (~i_rst) begin
            e_branch <= 1'b0;
            e_jump   <= 1'b0;
        end
        else begin
            e_en_regfile_write     <= i_de_clr ? 1'd0 : d_en_regfile_write;
            e_mux_pc_adder_src     <= i_de_clr ? 1'd0 : d_mux_pc_adder_src;
            e_mux_alu_src_a        <= i_de_clr ? 1'd0 : d_mux_alu_src_a;
            e_mux_alu_src_b        <= i_de_clr ? 1'd0 : d_mux_alu_src_b;
            e_en_datamem_access    <= i_de_clr ? 1'd0 : d_en_datamem_access;
            e_en_datamem_write     <= i_de_clr ? 1'd0 : d_en_datamem_write;
            e_mux_final_result_src <= i_de_clr ? 2'd0 : d_mux_final_result_src;
            e_alu_control          <= i_de_clr ? 4'd0 : d_alu_control;
            e_mask_type            <= i_de_clr ? 2'd0 : d_mask_type;
            e_ext_type             <= i_de_clr ? 1'd0 : d_ext_type;
            e_branch               <= i_de_clr ? 1'd0 : d_branch;
            e_jump                 <= i_de_clr ? 1'd0 : d_jump;
            e_funct3               <= i_de_clr ? 3'd0 : d_funct3;
        end
    end

    always_ff @( posedge i_clk ) begin : e2m
        if (i_em_en) begin
            m_en_regfile_write        <= e_en_regfile_write;
            m_mux_final_result_src    <= e_mux_final_result_src;
            m_en_datamem_access       <= e_en_datamem_access;
            m_en_datamem_write        <= e_en_datamem_write;
            m_mask_type               <= e_mask_type;
            m_ext_type                <= e_ext_type;
        end
    end

    always_ff @( posedge i_clk ) begin : m2w
        w_en_regfile_write     <= i_mw_clr ? 1'd0 : m_en_regfile_write;
        w_mux_final_result_src <= i_mw_clr ? 2'd0 :m_mux_final_result_src;
    end

endmodule
