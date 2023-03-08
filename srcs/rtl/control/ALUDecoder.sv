module ALUDecoder (
    input  logic       op_b5,
    input  logic [2:0] funct3,
    input  logic       funct7_b5, 
    input  logic [1:0] alu_op,
    output logic [3:0] alu_control
);

    logic  RtypeSub;
    assign RtypeSub = funct7_b5 & op_b5;  // TRUE for R-type subtract instruction

    always_comb
        case(alu_op)
            2'b00:          alu_control = 4'b0000; // addition
            2'b01:          alu_control = 4'b0001; // subtraction
            2'b10:
                case(funct3) // R-type or I-type ALU
                    3'b000:
                        if (RtypeSub) 
                            alu_control = 4'b0001; // sub
                        else          
                            alu_control = 4'b0000; // add, addi
                    3'b001: alu_control = 4'b0111; // sll, slli
                    3'b010: alu_control = 4'b0010; // slt, slti
                    3'b011: alu_control = 4'b0011; // sltu, sltiu
                    3'b100: alu_control = 4'b0100; // xor, xori
                    3'b101: 
                        if (funct7_b5)
                            alu_control = 4'b1001; // sra
                        else
                            alu_control = 4'b1000; // srl
                    3'b110: alu_control = 4'b0110; // or, ori
                    3'b111: alu_control = 4'b0101; // and, andi
                    default:alu_control = 4'bxxxx; // ???
                endcase
            // 2'b11: reserved
            default:        alu_control = 4'bxxxx;
        endcase

endmodule
