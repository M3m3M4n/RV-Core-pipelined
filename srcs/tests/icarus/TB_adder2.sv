`timescale 1ms/100us

module TB_Adder2();

    logic [31:0] a = 32'b0;
    logic [31:0] b = 32'b0;
    logic [3:0]  alu_control = 0;
    wire  [31:0] result;
    wire  [3:0]  alu_flags;

    ALU alu (
        .a(a),
        .b(b),
        .alu_control(alu_control),
        .result(result),
        .alu_flags(alu_flags)
    );

    wire zero     = alu_flags[0];
    wire neg      = alu_flags[1];
    wire carry    = alu_flags[2];
    wire overflow = alu_flags[3];

    initial begin
        $dumpfile(`DUMPFILENAME);
        $dumpvars(0, TB_Adder2);
        $display("OVERFLOW TEST BEGIN");
        alu_control = 4'b0000; // +
        #4;
        $display("1");
        a = {4'b0100, 28'd0};
        b = {4'b0100, 28'd0};
        #1;
        assert (overflow == 1'b1) 
            $display ("Pass");
        else 
            $error("Failed");
        #4;
        $display("2");
        a = {4'b1000, 28'd0};
        b = {4'b1000, 28'd0};
        #1;
        if (overflow == 1'b1) 
            $display ("Pass");
        else 
            $error("Failed");
        #4;
        $display("3");
        a = {4'b0100, 28'd0};
        b = {4'b0001, 28'd0};
        #1;
        if (overflow == 1'b0) 
            $display ("Pass");
        else 
            $error("Failed");
        #4;
        $display("4");
        a = {4'b0110, 28'd0};
        b = {4'b1001, 28'd0};
        #1;
        if (overflow == 1'b0) 
            $display ("Pass");
        else 
            $error("Failed");
        #4;
        $display("5");
        a = {4'b1000, 28'd0};
        b = {4'b0001, 28'd0};
        #1;
        if (overflow == 1'b0) 
            $display ("Pass");
        else 
            $error("Failed");
        #4;
        $display("6");
        a = {4'b1100, 28'd0};
        b = {4'b1100, 28'd0};
        #1;
        if (overflow == 1'b0) 
            $display ("Pass");
        else 
            $error("Failed");
        $display("OVERFLOW TEST DONE");
        #10;
        $display("CARRY TEST BEGIN");
        // carry test
        // still +
        #4;
        $display("1");
        a = {4'b1010, 28'd0};
        b = {4'b1100, 28'd0};
        #1;
        if (carry == 1'b1) 
            $display ("Pass");
        else 
            $error("Failed");
        #4;
        $display("2");
        a = {32'd0};
        b = {32'hffffffff};
        #1;
        if (carry == 1'b0) 
            $display ("Pass");
        else 
            $error("Failed");
        #4;
        $display("3");
        alu_control = 4'b0001; // -
        a = {4'b1010, 28'd0};
        b = {4'b1100, 28'd0};
        #1;
        if (carry == 1'b1) 
            $display ("Pass");
        else 
            $error("Failed");
        #4;
        $display("4");
        a = {4'b1010, 28'd0};
        b = {4'b0100, 28'd0};
        #1;
        if (carry == 1'b0) 
            $display ("Pass");
        else 
            $error("Failed");
        #10;
        $display("All Done!");
        $finish;
    end

endmodule