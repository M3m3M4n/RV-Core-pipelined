module Bin2Gray #(
    parameter WIDTH_BITS = 8
) (
    input  logic [WIDTH_BITS : 0] i_bin,
    output logic [WIDTH_BITS : 0] o_gray
);

    assign o_gray[WIDTH_BITS] = i_bin[WIDTH_BITS];

    genvar i;
    generate
        for (i = WIDTH_BITS - 1; i >= 0; i--) begin
            assign o_gray[i] = i_bin[i + 1] ^ i_bin[i];
        end
    endgenerate

endmodule
