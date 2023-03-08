module Mux2 #(
    parameter WIDTH = 32
) (
    input  wire [WIDTH-1:0] i_d0, i_d1, 
    input  wire i_s, 
    output wire [WIDTH-1:0] o_y
);

    assign o_y = i_s ? i_d1 : i_d0;

endmodule
