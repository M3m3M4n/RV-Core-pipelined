`include "srcs/rtl/include/config.svh"

/* Forward logic:
 *  - Basically: Move data from available registers in the pipeline to current ones in exec
 *  - The earliest forwarding is needed is in exec stage 
 *  - Data from earier stages (mem, writeback) of atmost 2 prev instr
 *  - Possible forwading path is mem -> exec, wb -> exec 
 *  - wb -> mem is not needed in RV32I since data needed in mem stage
 *    are address (calc in exec, forward already needed in exec) and data
 *    which is supplied through a dedicated register.
 *  - To check if forward is needed, check current source for alu:
 *      - If reg is used then check it with destination reg of previous 
 *        instrs, if match, reg write enable and not 0 then forward
 *      - To avoid confusion with stall conditions, compare exec stage of current instr
 *        to mem and writeback of ealier instrs (compare forward)
 *  - To foward, add data lines and muxes from later pipeline to exec alu inputs
 */

/* Stall logic:
 *  - Condition for stall is almost the same as forward, except
 *    you only need to stall after reading memory data, everything else
 *    is forwardable (for RV32I). Thus load instrs.
 *  - To check if stall is needed check write destination with upcoming instr sources
 *    (Compare backward), and target matches load instrs
 *  - To stall, stop updating pc and stop fecting from instr mem
 *    Flush exec stage
 */ 

/* Branch flush logic:
 *  - If branch (pc != pc + 4) then initiate flush on both fd and de
 */

module HazardBlock (
    input  logic       i_clk,
    input  logic       i_rst,
    // Forward
    //   From data
    input  logic [4:0] i_data_e_rs1,
    input  logic [4:0] i_data_e_rs2,
    input  logic [4:0] i_data_m_rd,
    input  logic [4:0] i_data_w_rd,
    //   From control
    input  logic       i_ctrl_m_en_regfile_write,
    input  logic       i_ctrl_w_en_regfile_write,
    input  logic [1:0] i_ctrl_m_mux_final_result_src,
    //   To data
    output logic [1:0] o_data_mux_alu_forward_src_a,
    output logic [1:0] o_data_mux_alu_forward_src_b,
    // Stall, some will not be used if stall all
    //   From data
    input  logic [4:0] i_data_d_rs1,
    input  logic [4:0] i_data_d_rs2,
    input  logic [4:0] i_data_e_rd,
    input  logic       i_data_m_bus_ack, // Ored from modules
    //   From control
    input  logic [1:0] i_ctrl_e_mux_final_result_src,
    input  logic       i_ctrl_d_mux_alu_src_a,
    input  logic       i_ctrl_d_mux_alu_src_b,
    input  logic       i_ctrl_e_en_datamem_access, // for stalling on ALL memory accesses
    //   To data
    output logic       o_data_f_stall,
    output logic       o_data_fd_stall,
    //   To both 
    output logic       o_de_flush,
    output logic       o_em_stall,
    output logic       o_mw_flush,
    // Branch
    //   From control
    input  logic       i_ctrl_e_mux_pc_src,
    //   To data
    output logic       o_data_fd_flush // also o_de_flush 

);
    // Forward logic
    always_comb begin
        // Rs1 mux
        if ((i_data_e_rs1 == i_data_m_rd) & (i_data_e_rs1 != 0) & (i_ctrl_m_en_regfile_write))
            if (i_ctrl_m_mux_final_result_src == 2'b11) // forward from extend
                o_data_mux_alu_forward_src_a = 2'b11;
            else
                o_data_mux_alu_forward_src_a = 2'b10;
        else
        if ((i_data_e_rs1 == i_data_w_rd) & (i_data_e_rs1 != 0) & (i_ctrl_w_en_regfile_write))
            o_data_mux_alu_forward_src_a = 2'b01;
        else
            o_data_mux_alu_forward_src_a = 2'b00;

        // Rs2 mux
        if ((i_data_e_rs2 == i_data_m_rd) & (i_data_e_rs2 != 0) & (i_ctrl_m_en_regfile_write))
            if (i_ctrl_m_mux_final_result_src == 2'b11) // forward from extend
                o_data_mux_alu_forward_src_b = 2'b11; // eg lui a5,0xaaaa; sw a5,-20(s0)
            else
                o_data_mux_alu_forward_src_b = 2'b10;
        else
        if ((i_data_e_rs2 == i_data_w_rd) & (i_data_e_rs2 != 0) & (i_ctrl_w_en_regfile_write))
            o_data_mux_alu_forward_src_b = 2'b01;
        else
            o_data_mux_alu_forward_src_b = 2'b00;
    end

    // PROBLEM: In need of multi cycle loads (loads that takes arbitrary number of cycle to complete),
    //          the current stall detection logic does not suffice.
    // EXAMPLE: 
    //          lw   a4,...
    //          lw   a5,...
    //          add  a5,a5,a4
    //          Original stall logic only stall a5 load, because loads take only 1 cycle (BRAM).
    //          If loads need 2 cycle then a4 load also need to be stalled
    //          If you can't predict how many cycle a load will take then it won't work
    // SCORCHED EARTH:
    //          Stall ALL loads (and store) until periph flip ack signal

    logic _stall;
    // STALL ON ALL ACCESS
    assign _stall = i_ctrl_e_en_datamem_access;
    // When stall arbitrary number of cycles,
    // exec stage is flushed to will need to save stall state
    logic _stall_save;
    always_ff @(posedge i_clk) begin
        if (~i_rst) begin
            _stall_save <= 1'b0;
        end
        else begin
            if (_stall) _stall_save <= 1'b1; // delayed for 1 cycle
            // Stall until receive bus confirmation
            // Bus confirmation order of multiple loads may matter once selective stall is enabled again
            else if (_stall_save & i_data_m_bus_ack)
                _stall_save <= 1'b0;
        end
    end

    // This signal goes low 1 cycle earlier than _stall_save, align with ack
    // This is required because the pipeline must resume the moment ack is received,
    // else the signal from the pipeline will persist for an additional cycle,
    // messing up master transfer.
    logic _stall_save_ack; 
    assign _stall_save_ack = ~i_data_m_bus_ack & _stall_save;

    assign o_data_f_stall  = _stall | _stall_save_ack;
    assign o_data_fd_stall = _stall | _stall_save_ack;
    // Flush
    assign o_de_flush      = _stall | _branch_flush  | _stall_save_ack;
    assign o_em_stall      = _stall_save_ack;
    assign o_mw_flush      = _stall_save_ack;

    logic _branch_flush;
    // Branch detection logic
    assign _branch_flush   = i_ctrl_e_mux_pc_src;
    assign o_data_fd_flush = _branch_flush;

endmodule
