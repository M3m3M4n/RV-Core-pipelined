module VarClkDivider #(
    /* base clock == 25Mhz
     */
    parameter FACTOR_BITS = 1 // divide by 2^<factorbits>, min 1
)(
    input  logic i_clk,
    input  logic i_rst,
    output logic o_clk
);

    logic [FACTOR_BITS - 1 : 0] counter;
    logic [FACTOR_BITS : 0]     counter_p_1; // +1 bit for carry chain
    assign counter_p_1 = counter + 1;

    always_ff @(posedge i_clk) begin
        if (~i_rst)
            counter <= 0;
        else
            counter <= counter_p_1[FACTOR_BITS - 1 : 0];
    end

    logic _fin_clk;
    always_ff @(posedge i_clk) begin
        if (~i_rst)
            _fin_clk <= 0;
        else begin
        if (counter_p_1[FACTOR_BITS])
            _fin_clk <= ~_fin_clk;
        end
    end

    assign o_clk = _fin_clk;

endmodule
