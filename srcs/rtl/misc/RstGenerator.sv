module RstGenerator (
    input  logic i_clk,
    input  logic i_rst,     // Input signal from rst pin
    input  logic i_rst_wdt,
    output logic o_ext_rst, // External reset <- FROM: rst pin | TO: watchdog, on chip debug.
    output logic o_int_rst  // Internal reset <- FROM: rst pin, watchdog, on chip debug | TO: every other modules
);
    // All rst active low
    logic [3:0] _ext_rst, _int_rst;

    always_ff @(negedge i_clk, negedge i_rst) begin
        if(~i_rst) begin
            // All rst active when get signal from pin
            _ext_rst  <= 4'b0;
            _int_rst  <= 4'b0;
            o_ext_rst <= 0;
            o_int_rst <= 0;
        end
        else begin // Release rst at negedge before flops trigger at rising edge
            _ext_rst  <= {_ext_rst[2:0], 1'b1};
            o_ext_rst <= _ext_rst[3] & _ext_rst[2] &_ext_rst[1] &_ext_rst[0];  // rst signal lasts 4 cycle after i_rst
            if (~i_rst_wdt)
                _int_rst <= 4'b0;
            else
                _int_rst <= {_int_rst[2:0], 1'b1};
            o_int_rst <= _int_rst[3] & _int_rst[2] & _int_rst[1] & _int_rst[0]; // rst signal lasts 4 cycle after i_rst
        end
    end

endmodule
