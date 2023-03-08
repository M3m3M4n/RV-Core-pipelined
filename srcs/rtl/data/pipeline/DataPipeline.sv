`include "srcs/rtl/include/config.svh"

module DataPipeline (
    input  logic       i_clk,
    input  logic       i_rst,
    // From control
    input  logic       i_mux_pc_src,
    input  logic       i_en_regfile_write,
    input  logic [2:0] i_mux_immext_src,
    input  logic       i_mux_pc_adder_src,
    input  logic       i_mux_alu_src_a,
    input  logic       i_mux_alu_src_b,
    input  logic [3:0] i_alu_control,
    input  logic [1:0] i_mask_type,
    input  logic       i_ext_type,
    input  logic       i_en_datamem_access,
    input  logic       i_en_datamem_write,
    input  logic [1:0] i_m_mux_final_result_src, // Can derive i_en_datamem_read from this, or just set it = ~write
    input  logic [1:0] i_w_mux_final_result_src,
    // To control
    output logic [3:0] o_alu_flags,
    output logic [6:0] o_opcode,
    output logic [2:0] o_funct3,
    output logic       o_funct7_b5,
    // From hazard
    //   Forward
    input  logic [1:0] i_mux_alu_forward_src_a,
    input  logic [1:0] i_mux_alu_forward_src_b,
    //   Stall
    input  logic       i_f_en_pc,     // Enable new pc fetching
    input  logic       i_fd_en,       // Enable fetch -> decode registers
    input  logic       i_em_en,       // Enable exec -> mem registers
    //   Flush
    input  logic       i_fd_clr,      // Clear fetch -> decode registers
    input  logic       i_de_clr,      // Clear decode -> exec registers
    input  logic       i_mw_clr,      // Clear mem -> write register
    // To hazard
    //   Forward
    output logic [4:0] o_e_rs1,
    output logic [4:0] o_e_rs2,
    output logic [4:0] o_m_rd,
    output logic [4:0] o_w_rd,
    //   Stall
    output logic [4:0] o_d_rs1,
    output logic [4:0] o_d_rs2,
    output logic [4:0] o_e_rd,
    output logic       o_m_ack
`ifndef BRAM_AS_RAM
    ,
    input  logic        i_ram_clk,
    // Connect to SDRAM, passthrough
    output logic        o_ram_ras,
    output logic        o_ram_cas,
    output logic        o_ram_we,
    output logic [1:0]  o_ram_ba,
    output logic [10:0] o_ram_addr,
    // Bi-directional port does not play nice with verilator, split to test
    `ifdef VERILATOR
    input  logic [31:0] i_ram_dq,  // from sdram model
    output logic [31:0] o_ram_dq   // to sdram model
    `else
    inout  logic [31:0] io_ram_dq
    `endif
`endif
`ifdef GPIO_EN
    ,
    // input  logic [7:0] i_gpio [`GPIO_SIZE_BYTE - 1:0],
    // output logic [7:0] o_gpio [`GPIO_SIZE_BYTE - 1:0]
    input  logic [`GPIO_SIZE - 1:0] i_gpio,
    output logic [`GPIO_SIZE - 1:0] o_gpio
`endif
`ifdef HDMI_EN
    ,
    input  logic        i_hdmi_pixel_clk,
    input  logic        i_hdmi_tmds_clk,
    output logic [3:0]  o_hdmi_gpdi_dp, 
    output logic [3:0]  o_hdmi_gpdi_dn
`endif
);
    // Signals that are just passing through don't need to go inside logic blocks

    // ====================================================================================
    // Fetch stage
    // Register file will be connected straight into f_instr
    logic [31:0] f_instr, f_pc, f_pc_p_4;
    // Decode stage
    // Because register file read / write needs 1 cycle, so we need to buffer / delay
    // Before passing to exec
    // Later might consider a single signal register instead
    logic [31:0] d_instr; // consumed, no buffer, needed for control unit
    logic [31:0] d_rd1, d_rd2; // already delayed
    logic [31:0] d_pc, d_pc_p_4;
    logic [31:0] d_immext;
    logic [4:0]  d_rs1, d_rs2, d_rd;
    // Exec stage
    logic [31:0] e_rd1, e_rd2;
    logic [31:0] e_immext;
    logic [31:0] e_pc
`ifdef VERILATOR
    /* verilator public */
`endif
    ;
    logic [31:0] e_pc_p_4;
    logic [4:0]  e_rs1, e_rs2, e_rd;
    logic [31:0] e_alu_result;
    logic [31:0] e_mem_data;
    // Mem stage, also need delay buffer
    logic [31:0] m_alu_result;
    logic [31:0] m_mem_data;
    logic [31:0] m_pc_p_4;
    logic [4:0]  m_rd;
    logic [31:0] m_immext;
    logic [31:0] m_memory_readout;
    logic        m_memory_ack;
    // Writeback stage
    logic [31:0] w_memory_readout;
    logic [31:0] w_alu_result;
    logic [31:0] w_pc_p_4;
    logic [4:0]  w_rd;
    logic [31:0] w_immext;
    logic [31:0] w_final_result;
    // Interconnect
    logic [31:0] pc_adder_result;

    // ====================================================================================
    // Assign output
    //   Hazard
    assign o_d_rs1 = d_rs1;
    assign o_d_rs2 = d_rs2;

    assign o_e_rs1 = e_rs1;
    assign o_e_rs2 = e_rs2;
    assign o_e_rd  = e_rd;

    assign o_m_rd  = m_rd;
    assign o_m_ack = m_memory_ack;

    assign o_w_rd  = w_rd;

    // ====================================================================================

    logic _rom_p2_clk, _rom_p2_en;
    logic [31:0] _rom_p2_addr, _rom_p2_rd;

    DataFetchStageBlock dataFetchStageBlock (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_pc_ext_addr(pc_adder_result),
        .i_mux_pc_src(i_mux_pc_src),
        .i_f_en_pc(i_f_en_pc),
        .i_fd_en(i_fd_en),
        .i_fd_clr(i_fd_clr),
        .o_pc_p_4(f_pc_p_4),
        .o_pc(f_pc),
        .o_instr(f_instr),
        .i_rom_p2_clk(_rom_p2_clk),
        .i_rom_p2_en(_rom_p2_en),
        .i_rom_p2_addr(_rom_p2_addr),
        .o_rom_p2_rd(_rom_p2_rd)
    );

    DataDecodeStageBlock dataDecodeStageBlock (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_d_instr(d_instr),
        .i_result_addr(w_rd),
        .i_en_regfile_write(i_en_regfile_write),
        .i_final_result(w_final_result),
        .i_mux_immext_src(i_mux_immext_src),
        .o_rd1(d_rd1),
        .o_rd2(d_rd2),
        .o_immext(d_immext)
    );

    DataExecStageBlock dataExecStageBlock (
        .i_rd1(e_rd1),
        .i_rd2(e_rd2),
        .i_immext(e_immext),
        .i_pc(e_pc),
        .i_m_e_foward_data_alu(m_alu_result),
        .i_m_e_foward_data_immext(m_immext),
        .i_w_e_foward_data(w_final_result),
        .i_alu_control(i_alu_control),
        .i_mux_alu_src_a(i_mux_alu_src_a),
        .i_mux_alu_src_b(i_mux_alu_src_b),
        .i_mux_pc_adder_src(i_mux_pc_adder_src),
        .i_mux_alu_forward_src_a(i_mux_alu_forward_src_a),
        .i_mux_alu_forward_src_b(i_mux_alu_forward_src_b),
        .o_alu_result(e_alu_result),
        .o_memory_data(e_mem_data),
        .o_alu_flags(o_alu_flags),
        .o_pc_adder_result(pc_adder_result)
    );

    logic _err_unused; // Not sure what to do yet

    DataMemStageBlock dataMemStageBlock (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_req(i_en_datamem_access),
        .i_we(i_en_datamem_write),
        .i_mask_type(i_mask_type),
        .i_ext_type(i_ext_type),
        .i_memory_address(m_alu_result),
        .i_memory_data(m_mem_data),
        .o_memory_readout(m_memory_readout),
        .o_memory_ack(m_memory_ack),
        .o_memory_err(_err_unused),
        .o_rom_p2_clk(_rom_p2_clk),
        .o_rom_p2_en(_rom_p2_en),
        .o_rom_p2_addr(_rom_p2_addr),
        .i_rom_p2_rd(_rom_p2_rd)
`ifndef BRAM_AS_RAM
        ,
        .i_ram_clk(i_ram_clk),
        .o_ram_ras(o_ram_ras),
        .o_ram_cas(o_ram_cas),
        .o_ram_we(o_ram_we),
        .o_ram_ba(o_ram_ba),
        .o_ram_addr(o_ram_addr),
    `ifdef VERILATOR
        .i_ram_dq(i_ram_dq),
        .o_ram_dq(o_ram_dq)
    `else
        .io_ram_dq(io_ram_dq)
    `endif
`endif
`ifdef GPIO_EN
        ,
        .i_gpio(i_gpio),
        .o_gpio(o_gpio)
`endif
`ifdef HDMI_EN
        ,
        .i_hdmi_pixel_clk(i_hdmi_pixel_clk),
        .i_hdmi_tmds_clk(i_hdmi_tmds_clk),
        .o_hdmi_gpdi_dp(o_hdmi_gpdi_dp), 
        .o_hdmi_gpdi_dn(o_hdmi_gpdi_dn)
`endif
    );

    DataWritebackStageBlock dataWritebackStageBlock (
        .i_alu_result(w_alu_result),
        .i_memory_readout(w_memory_readout),
        .i_pc_p_4(w_pc_p_4),
        .i_immext(w_immext),
        .i_mux_final_result_src(i_w_mux_final_result_src),
        .o_wb(w_final_result)
    );

    // ====================================================================================
    // Fetch short
    // Moved flush logic into fetch block
    assign d_instr          = f_instr;
    // OPs
    assign o_opcode         = d_instr[6:0];
    assign o_funct3         = d_instr[14:12];
    assign o_funct7_b5      = d_instr[30];
    // Decode stage line
    assign d_rs1            = d_instr[19:15];
    assign d_rs2            = d_instr[24:20];
    assign d_rd             = d_instr[11:7];
    // Data out of regfile in decode
    assign e_rd1            = d_rd1;
    assign e_rd2            = d_rd2;
    // Data mem readout
    // assign w_memory_readout = m_memory_readout;

    always_ff @(posedge i_clk) begin : f2d
        if (i_fd_en) begin
            // d_instr  <= i_fd_clr ? 32'd0 : f_instr;
            d_pc     <= i_fd_clr ? 32'd0 : f_pc;
            d_pc_p_4 <= i_fd_clr ? 32'd0 : f_pc_p_4;
        end
    end

    always_ff @(posedge i_clk) begin : d2e
        e_immext <= i_de_clr ? 32'd0 : d_immext;
        e_pc     <= i_de_clr ? 32'd0 : d_pc;
        e_pc_p_4 <= i_de_clr ? 32'd0 : d_pc_p_4;
        e_rs1    <= i_de_clr ?  5'd0 : d_rs1;
        e_rs2    <= i_de_clr ?  5'd0 : d_rs2;
        e_rd     <= i_de_clr ?  5'd0 : d_rd;
    end

    always_ff @(posedge i_clk) begin : e2m
        if (i_em_en) begin
            m_rd         <= e_rd;
            m_pc_p_4     <= e_pc_p_4;
            m_alu_result <= e_alu_result;
            m_mem_data   <= e_mem_data;
            m_immext     <= e_immext;
        end
    end

    always_ff @(posedge i_clk) begin : m2w
        w_memory_readout <= m_memory_readout;
        w_alu_result     <= i_mw_clr ? 32'd0 : m_alu_result;
        w_rd             <= i_mw_clr ? 5'd0  : m_rd;
        w_pc_p_4         <= i_mw_clr ? 32'd0 : m_pc_p_4;
        w_immext         <= i_mw_clr ? 32'd0 : m_immext;
    end
    
endmodule
