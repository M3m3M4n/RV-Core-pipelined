module ImmExtender (
    input  logic [31:7] i_instr,
    input  logic [2:0]  i_mux_immext_src,
    output logic [31:0] o_immext
);

    always_comb begin
        case(i_mux_immext_src) 
            // I-type
            3'b000:   o_immext = {{20{i_instr[31]}}, i_instr[31:20]};  
            // S-type
            3'b001:   o_immext = {{20{i_instr[31]}}, i_instr[31:25], i_instr[11:7]}; 
            // B-type
            3'b010:   o_immext = {{20{i_instr[31]}}, i_instr[7], i_instr[30:25], i_instr[11:8], 1'b0}; 
            // J-type
            3'b011:   o_immext = {{12{i_instr[31]}}, i_instr[19:12], i_instr[20], i_instr[30:21], 1'b0}; 
            // U-type
            3'b100:   o_immext = {i_instr[31:12], 12'b0};
            // undefined
            default: o_immext = 32'bx;
        endcase   
    end

endmodule
