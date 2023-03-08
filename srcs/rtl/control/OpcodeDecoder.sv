module OpcodeDecoder (
    input  logic [6:0] op,
    output logic       RegWrite,
    output logic [2:0] ImmSrc,
    output logic       PCAdderSrc,
    output logic       ALUSrcA,
    output logic       ALUSrcB,
    output logic       MemRequest,
    output logic       MemWrite,
    output logic [1:0] ResultSrc,
    output logic       Branch,
    output logic       Jump,
    output logic [1:0] ALUOp
);

    logic [14:0] controls;

    assign {RegWrite, ImmSrc, PCAdderSrc, ALUSrcA, ALUSrcB, MemRequest, MemWrite, ResultSrc, Branch, Jump, ALUOp} = controls;

    always_comb
        case(op)
            /* 0        1      2          3       4       5          6        7         8      9    10
             * RegWrite_ImmSrc_PCAdderSrc_ALUSrcA_ALUSrcB_MemRequest_MemWrite_ResultSrc_Branch_Jump_ALUOp
             * 0  RegWrite  : 1 bit : Enable register write to register specified with Rd
             * 1  ImmSrc    : 3 bits: Select format for immidiate extender based on instruction format (View immidiate extender src)
             * 2  PCAdderSrc: 1 bit : Select input for first input of PCtarget adder (0: PC, 1: Register output 1)
             * 3  ALUSrcA   : 1 bit : Select first input of the ALU (0: Register output 1 | 1: PC) 
             * 4  ALUSrcB   : 1 bit : Select second input of the ALU (0: Register output 2 | 1: Extended immidiate)
             * 5  MemRequest: 1 bit : Enable data access (0: Intr DOES NOT accesses memory | 1: Intr accesses memory)
             * 6  MemWrite  : 1 bit : Enable data write to data memory
             * 7  ResultSrc : 2 bits: Select data for register file input line (00: ALU | 01: Data mem | 10: PC + 4 | 11: Extended immidiate)
             * 8  Branch    : 1 bit : (Internal) Enable branch for branch decoder
             * 9  Jump      : 1 bit : (Internal) Enable jump for branch decoder
             * 10 ALUOp     : 2 bits: (Internal) Select mode for alu decoder
             */
            //                         0 1   2 3 4 5 6 7  8 9 10
            7'b0000011: controls = 15'b1_000_x_0_1_1_0_01_0_0_00; // OP 3   - I-type Memory
            7'b0010011: controls = 15'b1_000_x_0_1_0_0_00_0_0_10; // OP 19  - I-type ALU
            7'b0010111: controls = 15'b1_100_x_1_1_0_0_00_0_0_00; // OP 23  - U-type PC
            7'b0100011: controls = 15'b0_001_x_0_1_1_1_xx_0_0_00; // OP 35  - S-type
            7'b0110011: controls = 15'b1_xxx_x_0_0_0_0_00_0_0_10; // OP 51  - R-type
            7'b0110111: controls = 15'b1_100_x_x_x_0_0_11_0_0_xx; // OP 55  - U-type 
            7'b1100011: controls = 15'b0_010_0_0_0_0_0_xx_1_0_01; // OP 99  - B-type
            7'b1100111: controls = 15'b1_000_1_x_x_0_0_10_0_1_xx; // OP 103 - I-type jump link
            7'b1101111: controls = 15'b1_011_0_x_x_0_0_10_0_1_xx; // OP 111 - J-type
            // Branch and jump has to be 0 else will affect fetching
            default:    controls = 15'b0_xxx_x_x_x_0_0_xx_0_0_xx; // non-implemented instruction
    endcase


endmodule
