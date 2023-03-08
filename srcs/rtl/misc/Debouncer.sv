module Debouncer (
    input  logic i_clk,
    input  logic i_rst,
    input  logic i_signal,
    output logic o_state
);

// 3 bits shift register
logic [2:0] r;

// 16 bits counter
logic [15:0] counter;

// Use carry chain
logic [16:0] counter_p_1 = counter + 1'b1;
logic counter_tick = counter_p_1[16];

always_ff @(posedge i_clk or negedge i_rst)
begin
    if (~i_rst)
    begin
        r <= 3'b0;
        counter <= 16'b0;
        o_state <= 1'b0;
    end
    else
    begin
        r[2:0] <= {r[1:0], i_signal};
        counter <= (r[2] != r[1]) ? 16'b0 : counter_p_1[15:0];
        o_state <= counter_tick ? r[2] : o_state;
    end
end

endmodule
