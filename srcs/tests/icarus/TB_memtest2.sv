`timescale 1ms/100us

module TB_MemTest2 (
);
    
logic clk = 1'b1;
logic        we;
logic [31:0] addr; 
logic [31:0] wd;
logic [31:0] rd1, rd2;
logic [1:0]  mask_type; // 00: byte, 01: halfword, 10: word
logic        ext_type;

DataMemory UUT (
    .i_clk(clk),
    .i_we(we),
    .i_addr(addr),
    .i_wd(wd),
    .i_mask_type(mask_type),
    .i_ext_type(ext_type),
    .o_rd()
);

always begin
    #5 clk = ~clk;
end

initial begin
    $dumpfile(`DUMPFILENAME);
    $dumpvars(0, TB_MemTest2);
    $display("MEMTEST BEGIN");
    we = 1'b0;
    mask_type = 2'b00;
    ext_type  = 1'b0;
    addr = 32'd1000;
    wd   = 32'h12345678;
    #10
    we = 1'b1;
    #10
    we = 1'b0;
    #10
    mask_type = 2'b01;
    we = 1'b1;
    #10
    we = 1'b0;
    #10
    mask_type = 2'b10;
    we = 1'b1;
    #10
    we = 1'b0;
    #10
    mask_type = 2'b11;
    we = 1'b1;
    #10
    we = 1'b0;
    #10
    we=1'b1;
    wd   = 32'hcba92b4;
    ext_type  = 1'b0;
    #10
    we = 1'b0;
    #10
    we=1'b1;
    mask_type = 2'b10;
    #10
    we = 1'b0;
    #10
    we=1'b1;
    mask_type = 2'b01;
    #10
    we = 1'b0;
    #10
    we=1'b1;
    mask_type = 2'b00;
    #10
    we = 1'b0;
    #100
    $display("MEMTEST DONE");
    $finish;
end

endmodule