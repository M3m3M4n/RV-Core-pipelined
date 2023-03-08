module testslave (
    input  logic       i_clk,
    input  logic       i_rst,
    // intercon
    input  logic [31:0] i_wb_addr,
    input  logic [31:0] i_wb_data,
    input  logic        i_wb_cyc,
    input  logic        i_wb_stb,
    input  logic        i_wb_we,
    // input  logic      i_wb_lock,
    // input  logic      i_wb_rty,
    // input  logic      i_wb_sel,
    // input  logic      i_wb_tga,
    // input  logic      i_wb_tgc,
    // input  logic      i_wb_tgd,
    // output logic      o_wb_tgd,
    // output logic      o_wb_err,
    // output logic      o_wb_rty,
    output logic [31:0] o_wb_data,
    output logic        o_wb_ack,
    output logic        o_wb_stall
);
    
    // Addr range + i_wb_cyc + i_wb_stb check
    logic _acc_en = i_wb_cyc & i_wb_stb; // & validaddr

    // Something to work with as example
    logic [31:0] _databuf [2:0];

    typedef enum {READY, WORKING} _states_t;
    _states_t _state;
    assign o_wb_stall = (_state != READY) ? 1'b1 : 1'b0;

    always @(posedge i_clk, negedge i_rst) begin : testsm
        if (~i_rst) begin
            _state <= READY;
            o_wb_ack <= 1'b0;
        end
        else begin
            case(_state)
                READY: begin
                    if (_acc_en) begin
                        o_wb_ack <= ~i_wb_we; // Assume write takes 2 cycles
                        if (i_wb_we) begin 
                            _state <= WORKING;
                            _databuf[2] <= _databuf[1];
                            _databuf[1] <= _databuf[0];
                            _databuf[0] <= i_wb_data;
                        end
                        else begin
                            o_wb_data <= _databuf[2];
                        end
                    end
                end
                WORKING: begin
                    o_wb_ack <= 1'b1;
                    _databuf[2] <= _databuf[1];
                    _databuf[1] <= _databuf[0];
                    _databuf[0] <= i_wb_data ^ 32'hffffffff;
                    _state <= READY;
                end
                default: begin
                    o_wb_ack <= 1'b0;
                    _state <= READY;
                end
            endcase
        end
    end

endmodule
