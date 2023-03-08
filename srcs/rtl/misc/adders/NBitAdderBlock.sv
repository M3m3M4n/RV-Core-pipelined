module NBitAdderBlock #(
    parameter N = 4
) (
    input wire [(N - 1) : 0] i_a,
    input wire [(N - 1) : 0] i_b,
    input wire i_c,
    output wire [(N - 1) : 0] o_s,
    output wire o_c
);
    genvar i;

    /* Initialize adder column inside block
     * For in-block calculation
     * Carry of the last column is not routed out of the block
     */
    wire [(N - 1) : 0] column_c_array;
    generate
        for (i = 0; i < N; i = i + 1) begin : adderBlock
            FullAdder adder (
                .i_a(i_a[i]),
                .i_b(i_b[i]),
                .i_c((i == 0) ? i_c : column_c_array[i - 1]),
                .o_c(column_c_array[i]),
                .o_s(o_s[i])
            );
        end
    endgenerate

    /* Initialize carry look-ahead logic
     * The final carry is used as the carry of the block
     */
    wire [(N - 1) : 0] block_g_array;
    wire [(N - 1) : 0] block_p_array;
    generate
        for (i = 0; i < N; i = i + 1) begin : carryBlock
            /* G */
            assign block_g_array[i] = ((i == 0) ? i_a[i] & i_b[i]
                                    : (i_a[i] & i_b[i]) | (block_g_array[i - 1] & (i_a[i] | i_b[i])));
            /* P */
            assign block_p_array[i] = ((i == 0) ? (i_a[i] | i_b[i]) : (i_a[i] | i_b[i]) & block_p_array[i - 1]);
        end
    endgenerate

    /* C_out = G + P.C_in */
    assign o_c = block_g_array[N - 1] | (block_p_array[N - 1] & i_c);

endmodule
