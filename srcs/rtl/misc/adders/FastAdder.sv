module FastAdder #(
    parameter BLOCKCOUNT = 8,
    parameter BITPERBLOCK = 4,
    parameter N = 32
    /* localparam N = BLOCKCOUNT * BITPERBLOCK
     * SystemVerilog supports localparam in port list, but icarus verilog fuzz out
     * https://www.eunchan.kim/research/localparam.html
     */
) (
    input wire [(N - 1) : 0] i_a,
    input wire [(N - 1) : 0] i_b,
    input wire i_c,
    output wire [(N - 1) : 0] o_s,
    output wire o_c
);

/* Assertion for testing N
 * Iverilog does not support generate if?
 * Have to put in always
 */
localparam N_LOCAL = BLOCKCOUNT * BITPERBLOCK;
generate
    if (N != N_LOCAL) begin
        always
            $fatal();
    end
endgenerate

/* Connect between blocks
 * (BLOCKCOUNT - 1)th bit not used
 */
wire [BLOCKCOUNT - 1 : 0] c_array; 
assign c_array[BLOCKCOUNT - 1] = 0 ;
genvar i, j;
generate
    for (i = 0; i < BLOCKCOUNT; i = i + 1) begin
        /* Have to split to if else instead of ternary for output, mentioned in:
         * https://electronics.stackexchange.com/questions/493517/conditional-port-connectivity-during-module-wrapper-instantiation
         */
        if (i == (BLOCKCOUNT - 1)) begin
            NBitAdderBlock #(
                .N(BITPERBLOCK)
            ) adderBlock (
                .i_a(i_a[i * BITPERBLOCK + BITPERBLOCK - 1 : i * BITPERBLOCK]),
                .i_b(i_b[i * BITPERBLOCK + BITPERBLOCK - 1 : i * BITPERBLOCK]),
                .i_c((i == 0) ? i_c : c_array[i - 1]),
                .o_s(o_s[i * BITPERBLOCK + BITPERBLOCK - 1 : i * BITPERBLOCK]),
                .o_c(o_c)
            );
        end
        else begin
            NBitAdderBlock #(
                .N(BITPERBLOCK)
            ) adderBlock (
                .i_a(i_a[i * BITPERBLOCK + BITPERBLOCK - 1 : i * BITPERBLOCK]),
                .i_b(i_b[i * BITPERBLOCK + BITPERBLOCK - 1 : i * BITPERBLOCK]),
                .i_c((i == 0) ? i_c : c_array[i - 1]),
                .o_s(o_s[i * BITPERBLOCK + BITPERBLOCK - 1 : i * BITPERBLOCK]),
                .o_c(c_array[i])
            );
        end
    end
endgenerate

endmodule
