`timescale 1ms/100us

module TB_MemTest (
);
    
logic clk = 1'b1;
logic        we3;
logic [ 4:0] a1, a2, a3; 
logic [31:0] wd3;
logic [31:0] rd1, rd2;


RegisterFile UUT (
    .clk(clk),
    .we3(we3),
    .a1(a1),
    .a2(a2),
    .a3(a3),
    .wd3(wd3),
    .rd1(rd1),
    .rd2(rd2)
);

always begin
    #5 clk = ~clk;
end

initial begin
    $dumpfile(`DUMPFILENAME);
    $dumpvars(0, TB_MemTest);
    $display("MEMTEST BEGIN");
    #5
    we3 = 1'b0;
    a1 = 4'h0;
    a2 = 4'h0;
    wd3 = 32'h6969;
    #5
    a1 = 4'h1;
    a2 = 4'h0;
    #5
    a3 = 4'h0;
    we3 = 1'b1;
    #5
    we3 = 1'b0;
    a1 = 4'h0;
    a2 = 4'h0;
    #100
    $display("MEMTEST DONE");
    $finish;
end

endmodule