`include "srcs/rtl/include/config.svh"

module DataFetchStageBlock (
    input  logic        i_clk,
    input  logic        i_rst,         // Active low
    // From pc adder in exec stage
    input  logic [31:0] i_pc_ext_addr,
    // From control
    input  logic        i_mux_pc_src,
    // From hazard
    input  logic        i_f_en_pc,     // Active high
    input  logic        i_fd_en,
    input  logic        i_fd_clr,
    // To decode
    output logic [31:0] o_pc_p_4,
    output logic [31:0] o_pc,
    output logic [31:0] o_instr,
    // ROM - memory stage interface, 32 bits granularity only
    input  logic        i_rom_p2_clk,
    input  logic        i_rom_p2_en,
    input  logic [31:0] i_rom_p2_addr,
    output logic [31:0] o_rom_p2_rd
);

    parameter ROMADDRWIDTH = $clog2(`ROM_SIZE);

    InstrMemory #(
        .SIZE_BYTE(`ROM_SIZE)
    ) instrMemory(
        .i_clk(i_clk),
        .i_fd_en(i_fd_en),
        .i_fd_clr(i_fd_clr),
        .i_a(o_pc[ROMADDRWIDTH - 1 : 0]),
        .o_rd(o_instr),
        .i_p2_clk(i_rom_p2_clk),
        .i_p2_en(i_rom_p2_en),
        .i_p2_addr(i_rom_p2_addr[ROMADDRWIDTH - 1 : 0]),
        .o_p2_rd(o_rom_p2_rd) 
    );

    assign o_pc_p_4 = o_pc + 4;

    always_ff @(posedge i_clk) begin
        if (~i_rst)
            o_pc <= 0;
        else
            if (i_f_en_pc)
                o_pc <= i_mux_pc_src ? i_pc_ext_addr : o_pc_p_4;
    end

endmodule
