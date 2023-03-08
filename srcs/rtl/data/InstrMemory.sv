module InstrMemory #(
    parameter  SIZE_BYTE = 2048,
    localparam ARRAYSIZE = SIZE_BYTE - 1,
    localparam ADDRWIDTH = $clog2(ARRAYSIZE)
)(
    // port 1 instr fetch interface
    input  logic                     i_clk,
    input  logic                     i_fd_en,
    input  logic                     i_fd_clr,
    input  logic [ADDRWIDTH - 1 : 0] i_a,
    output logic [31:0]              o_rd, // 32 bit width locked
    // port 2 connects to wishbone mem interface
    input  logic                     i_p2_clk,
    input  logic                     i_p2_en,
    input  logic [ADDRWIDTH - 1 : 0] i_p2_addr,
    output logic [31:0]              o_p2_rd // 32 bit width locked
);

    logic [31:0] ROM [ARRAYSIZE : 0];

    // Memory initialization, yosys can synthesize readmem, but can't handle DPI-C
    // So stick with static name, verilator exe need to be run from make dir
`ifdef VERILATOR
    // Redefined error, so create a wrapper then call from it
    // Provide ROMFILE as env when running verilator binary
    import "DPI-C" function string fetchenv(input string env_name);
    string ROMFILE;
    initial begin
        ROMFILE = fetchenv("ROMFILE");
        $readmemh(ROMFILE,ROM);
    end 
`else
    /*
    import "DPI-C" function string getenv(input string env_name);
    string ROMFILE;
    initial begin
        ROMFILE = getenv("ROMFILE");
        $readmemh(ROMFILE,ROM);
    end 
    */
    initial begin
        $readmemh("build/rom.txt",ROM);
    end
`endif

    always_ff @(posedge i_clk) begin
        if (i_fd_en) begin
            if (i_fd_clr)
                o_rd <= 32'd0;
            else
                o_rd <= ROM[{2'b00, i_a[ADDRWIDTH - 1 : 2]}]; // == ROM[i_a >> 2]
        end
        else begin /* Do nothing, hold value */ end
    end

    always_ff @(posedge i_p2_clk) begin
        if (i_p2_en) begin
            o_p2_rd <= ROM[{2'b00, i_p2_addr[ADDRWIDTH - 1 : 2]}];
        end
        else
            o_p2_rd <= 32'd0;
    end

endmodule
