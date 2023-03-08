module HalfAdder (
    input  wire i_a,
    input  wire i_b,
    output wire o_s,
    output wire o_c
);

    assign o_s = i_a ^ i_b;
    assign o_c = i_a & i_b;

endmodule
