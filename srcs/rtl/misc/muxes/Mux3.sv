module Mux3 #(
    parameter WIDTH = 32
) (
    input  wire [WIDTH - 1 : 0] i_d0, i_d1, i_d2, 
    input  wire [1 : 0] i_s, 
    output wire [WIDTH - 1 : 0] o_y
);

    assign o_y = i_s[1] ? i_d2 : (i_s[0] ? i_d1 : i_d0);

endmodule
