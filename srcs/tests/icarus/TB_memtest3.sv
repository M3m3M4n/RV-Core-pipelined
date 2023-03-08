`timescale 1ms/100us

module TB_MemTest3 (
);
    
logic clk = 1'b1;
logic we  = 1'b0;
logic [11:0] addr; 
logic [7:0] wd;
logic [7:0] rd;

RAM8 UUT (
    .i_clk(clk),
    .i_we(we),
    .i_addr(addr),
    .i_wd(wd),
    .o_rd()
);

always begin
    #5 clk = ~clk;
end


initial begin
    $dumpfile(`DUMPFILENAME);
    $dumpvars(0, TB_MemTest3);
    $display("MEMTEST RAM8 BEGIN");
    #10
    we = 1'b1;
    addr = 12'hFA;
    wd   = 8'h69;
    #10
    we = 1'b0;
    #10
    we = 1'b1;
    #10
    we = 1'b0;
    #10
    wd   = 8'h96;
    we = 1'b1;
    #10
    we = 1'b0;
    #100
    $display("MEMTEST RAM8 DONE");
    $finish;
end

endmodule