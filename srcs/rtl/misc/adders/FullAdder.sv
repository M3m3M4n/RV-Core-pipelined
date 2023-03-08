module FullAdder (
    input  wire i_a, i_b, i_c,
    output wire o_s, o_c
);
    
    wire s_tmp, c_tmp, c_tmp_2;

    HalfAdder halfAdder_1 (
        .i_a(i_a),
        .i_b(i_b),
        .o_s(s_tmp),
        .o_c(c_tmp)
    );

    HalfAdder halfAdder_2 (
        .i_a(s_tmp),
        .i_b(i_c),
        .o_s(o_s),
        .o_c(c_tmp_2)
    );

    assign o_c = c_tmp | c_tmp_2;

endmodule
