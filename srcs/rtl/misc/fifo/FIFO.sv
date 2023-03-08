/* Also check sub path of following links for more file
 *  - https://inst.eecs.berkeley.edu/~eecs151/sp19/files/lab6_spec_fpga.pdf
 *  - Async fifo behavior: https://inst.eecs.berkeley.edu/~eecs151/sp18/files/fpga_lab7_spec.pdf
 *  - http://www-classes.usc.edu/engr/ee-s/254/EE254L_CLASSNOTES/EE254_Ch11_memory/FIFO/FIFO_3.pdf
 *  - https://inst.eecs.berkeley.edu/~eecs151/sp18/files/fpga_lab7_spec.pdf
 */

/* Regarding gray counter:
 *  - gg: gray code double flop | why fifo gray counter
 *  - https://www.idc-online.com/technical_references/pdfs/electronic_engineering/FIFO_Pointers.pdf
 *  - https://electronics.stackexchange.com/questions/548509/why-do-we-use-a-gray-encoded-signal-by-2-stage-flip-flop-in-asynchronous-fifo-to
 *  - https://electronics.stackexchange.com/questions/432094/gray-code-clock-domain-crossing-fifo-fast-to-slow
 *  - https://www.quora.com/Why-do-we-use-gray-code-pointers-for-asynchronous-FIFO-design-and-binary-pointers-for-synchronous-FIFO-design
 */

/* Based on this paper:
 *  - http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO1.pdf
 */

 module FIFO #(
    parameter  FIFO_O_WIDTH = 32,
    parameter  FIFO_O_DEPTH = 8, // multiple of 2 
    parameter  FIFO_O_AF_THRESHOLD = FIFO_O_DEPTH - 2, // change
    parameter  FIFO_O_AE_THRESHOLD = 1, // change
    localparam FIFO_DEPTH_WIDTH = $clog2(FIFO_O_DEPTH) 
 ) (
    // Reset issue: https://github.com/m-labs/nmigen/issues/180
    // 
    // Read port
    input  logic                        i_rp_clk,
    input  logic                        i_rp_rst,
    input  logic                        i_rp_en,
    output logic [FIFO_O_WIDTH - 1 : 0] o_rp_data,
    output logic                        o_rp_ae, // almost empty
    output logic                        o_rp_empty,
    // Write port
    input  logic                        i_wp_clk,
    input  logic                        i_wp_rst,
    input  logic                        i_wp_en,
    input  logic [FIFO_O_WIDTH - 1 : 0] i_wp_data,
    output logic                        o_wp_af, // almost full
    output logic                        o_wp_full
 );

    always_comb begin
        if (FIFO_O_DEPTH[0] != 'b0)
            $fatal("%m: FIFO depth must be multiple of 2!");
    end

    // =======================================================
    // Data
    logic [FIFO_O_WIDTH - 1 : 0] _ram_rd_unused; // Do not use this port

    // Port 2 is always the read port since yosys does not suport write on second port
    DPBRAMVarWidth #(
        .WIDTH_BITS(FIFO_O_WIDTH),
        .SIZE_BITS(FIFO_O_WIDTH * FIFO_O_DEPTH)
    ) data (
        .i_p1_clk  (i_wp_clk),
        .i_p1_en   (_wp_en),
        .i_p1_we   (1'b1),
        .i_p1_addr (_wp_addr),
        .i_p1_wd   (i_wp_data),
        .o_p1_rd   (_ram_rd_unused),
        .i_p2_clk  (i_rp_clk),
        .i_p2_en   (_rp_en),
        .i_p2_we   (1'b0),
        .i_p2_addr (_rp_addr),
        .i_p2_wd   ('h0),
        .o_p2_rd   (o_rp_data)
    );

    // =======================================================
    // Sig gen
    logic [FIFO_DEPTH_WIDTH : 0]     _rp_gray, _wp_gray;
    logic                            _rp_en, _wp_en;
    logic [FIFO_DEPTH_WIDTH - 1 : 0] _rp_addr, _wp_addr;

    FIFOSigGen #(
        .MODE(0),
        .DEPTH(FIFO_O_DEPTH)
    ) readSig (
        .i_clk      (i_rp_clk),
        .i_rst      (i_rp_rst),
        .i_en       (i_rp_en),
        .i_gray     (_wp_gray),
        .o_fe       (o_rp_empty),
        .o_gray     (_rp_gray),
        .o_data_en  (_rp_en),
        .o_data_addr(_rp_addr)
    );
    
    FIFOSigGen #(
        .MODE(1),
        .DEPTH(FIFO_O_DEPTH)
    ) writeSig (
        .i_clk      (i_wp_clk),
        .i_rst      (i_wp_rst),
        .i_en       (i_wp_en),
        .i_gray     (_rp_gray),
        .o_fe       (o_wp_full),
        .o_gray     (_wp_gray),
        .o_data_en  (_wp_en),
        .o_data_addr(_wp_addr)
    );

    // almost...
    // unused for now
    assign o_rp_ae = 'b0;
    assign o_wp_af = 'b0;

 endmodule
