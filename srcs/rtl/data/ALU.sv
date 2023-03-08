/* Flag behaviours:  http://personal.denison.edu/~bressoud/cs281-s08/homework/MIPSALU.html
 * Comparison:       https://people.cs.pitt.edu/~don/coe1502/current/Unit1/CompBlock/ALU_Comp.html
 * Overflow / carry: http://teaching.idallen.com/dat2343/10f/notes/040_overflow.txt
 * Subtract / comp:  https://mil.ufl.edu/3701/classes/11%20Add,%20Subtract,%20Compare,%20ALU.pdf
 */

module ALU (
    input  logic [31:0] i_a, i_b,
    input  logic [3:0]  i_alu_control,
    output logic [31:0] o_result,
    output logic [3:0]  o_alu_flags
);

    logic zero;
    logic neg;
    logic carry;
    logic overflow;

    logic [31:0] condinvb;
    logic [32:0] sum;
    logic        isAddSub; // true when is add or subtract operation
    logic        isSub;

    assign o_alu_flags[0] = zero;
    assign o_alu_flags[1] = neg;
    assign o_alu_flags[2] = carry;
    assign o_alu_flags[3] = overflow;

    /* Condition for subtraction must also statisfy when slt and sltu is active
     * Range from 4'b0000 to 4'b0011
     */
    assign isAddSub = ~i_alu_control[2] & ~i_alu_control[3];
    assign isSub    = isAddSub & (i_alu_control[0] | i_alu_control[1]);
    assign condinvb = isSub ? ~i_b : i_b;
    
    assign sum      = i_a + condinvb + {31'b0, isSub};

    assign zero     = (o_result == 32'b0);
    assign neg      = (o_result[31] == 1'b1);
    assign overflow = ~(isSub ^ i_a[31] ^ i_b[31]) & (i_a[31] ^ sum[31]) & isAddSub;

    /* Assumption about subtraction carry (borrow)
     * If addition of 2's complement result in carry => no subtraction carry
     * Else if addition does not result in a carry => subtraction carry
     * Boolean: isSub = C; sum[32] = S
     * Need prove: (C & ~S) | (~C & S) => C^S
     * Consider adding 2 complement = adding inverse bit with initial carry = 1
     * Subtraction: B(i+1) = ~MiSi + ~MiBi + SiBi
     * Add 2 complement: C(i+1) = Mi~Si + MiCi + ~SiCi
     * Assumption: B(out) == ~C(out)
     * ~C(i+1) = ~MiSi + ~Mi~Ci + Si~Ci => maybe prove by recursive back to C0 = 1 vs B0 = 0?
     */
    assign carry    = (isSub ^ sum[32]) & isAddSub;

    always_comb begin
        case (i_alu_control)
            4'b0000: o_result = sum[31:0];                     // add
            4'b0001: o_result = sum[31:0];                     // subtract
            4'b0010: o_result = {31'b0, {sum[31] ^ overflow}}; // slt
            4'b0011: o_result = {31'b0, carry};                // sltu
            4'b0100: o_result = i_a ^ i_b;                     // xor
            4'b0101: o_result = i_a & i_b;                     // and 
            4'b0110: o_result = i_a | i_b;                     // or
            4'b0111: o_result = i_a << i_b[4:0];               // sll
            4'b1000: o_result = i_a >> i_b[4:0];               // srl
            4'b1001: o_result = i_a >>> i_b[4:0];              // sra
            default: o_result = 32'bx;
        endcase
    end

endmodule
