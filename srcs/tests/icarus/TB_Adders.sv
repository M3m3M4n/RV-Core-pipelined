`timescale 1ms/100us

module TB_Adder();

    logic [31:0] a = 32'b0;
    logic [31:0] b = 32'b0;
    logic c_in = 0;
    wire [31:0] s;
    wire c_out;

    FastAdder #(
        .BLOCKCOUNT(8),
        .BITPERBLOCK(4),
        .N(32)
    ) CLA32 (
        .i_a(a),
        .i_b(b),
        .i_c(c_in),
        .o_c(c_out),
        .o_s(s)
    );

    initial begin
        $dumpfile(`DUMPFILENAME);
        $dumpvars(0, TB_Adder);
        #5;
        a = a + 32'd3;
        b = b + 32'd8;
        #5;
        c_in = c_in + 1'b1;
        #5;
        a = a + 32'd2;
        #5;
        c_in = 1'b0;
        a = 32'hfffffffe;
        b = 32'h1;
        #5;
        c_in = 1'b1;
        a = 32'hffffffff;
        b = 32'h1;
        #10;
        $display("Done!");
        $finish;
    end

endmodule