module Gray2Bin #(
    parameter WIDTH_BITS = 8
) (
    input  logic [WIDTH_BITS - 1 : 0] i_gray,
    output logic [WIDTH_BITS - 1 : 0] o_bin
);

    assign o_bin[WIDTH_BITS - 1] = i_gray[WIDTH_BITS - 1];

    genvar i;
    generate
        for (i = WIDTH_BITS - 2; i >= 0; i--) begin
            assign o_bin[i] = i_bin[i + 1] ^ i_gray[i];
        end
    endgenerate

endmodule
