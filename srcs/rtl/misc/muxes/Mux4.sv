module Mux4 #(
    parameter WIDTH = 32
) (
    input  logic [WIDTH - 1 : 0] i_d0, i_d1, i_d2, i_d3, 
    input  logic [1 : 0] i_s, 
    output logic [WIDTH - 1 : 0] o_y
);

    always_comb begin : sel
        case (i_s)
            2'b00:
                o_y = i_d0;
            2'b01:
                o_y = i_d1;
            2'b10:
                o_y = i_d2;
            2'b11: 
                o_y = i_d3;
            default: 
                o_y = 'hx;
        endcase
    end

endmodule
