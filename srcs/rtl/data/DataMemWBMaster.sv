// Address check will be done at interconnect, not here
module DataMemWBMaster (
    input  logic        i_clk,
    input  logic        i_rst,
    // Interconnect
    // Could try to set cyc, stb = i_mem_en, we = i_mem_we combinationally,
    // but need to make sure ALU result must always somewhat valid
    // Else violate WB spec when instr does not use ALU, lead to x
    // Registered for the time being, introduces 1 extra cycle when handling requests.
    output logic        o_wb_cyc,
    output logic        o_wb_stb,
    output logic        o_wb_we,
    output logic [3:0]  o_wb_sel,
    output logic [31:0] o_wb_addr,
    output logic [31:0] o_wb_data,
    input  logic [31:0] i_wb_data,
    input  logic        i_wb_stall,
    input  logic        i_wb_ack,
    input  logic        i_wb_err,
    // Mem Interface
    input  logic        i_mem_en,
    input  logic        i_mem_we,
    input  logic [31:0] i_mem_addr, i_mem_wd,
    input  logic [1:0]  i_mem_mask_type,  // 00: byte, 01: halfword, 10: word
    output logic        o_mem_ack,
    output logic        o_mem_err,
    output logic [31:0] o_mem_rd
    // Not impl
    // input  logic        i_wb_rty,
    // input  logic        i_wb_tgd,
    // output logic        o_wb_tgd,
    // output logic        o_wb_tga,
    // output logic        o_wb_tgc,
    // output logic        o_wb_lock
);

    // ==============================================================

    // sel decode
    logic [3:0] _sel;
    assign _sel = i_mem_mask_type[1] ? 4'b1111 :
                  i_mem_mask_type[0] ? 4'b0011 :
                                   4'b0001 ;

    // ==============================================================

    /* Master state machine:
     * - IDLE: setup cyc and stb, initiate request
     * - REQUEST: wait until stall is low -> means client accept
     * - WAIT: wait until ack? if wait then what is the point of pipelined mode
     */
    typedef enum logic [1:0] {IDLE, REQUEST, WAIT} _bus_master_state_t;
    _bus_master_state_t _state;

    always_ff @(posedge i_clk) begin : wb_state_machine
        // WB spec demands synchronous reset
        // Also reset bus interface on error?
        if (~i_rst | i_wb_err)
            _state <= IDLE;
        else begin
            case (_state)
                IDLE: begin
                    if (i_mem_en)
                        _state <= REQUEST;
                end
                REQUEST: begin
                    if (!i_wb_stall) begin
                        if (i_wb_ack)
                            _state <= IDLE;
                        else
                            // in normal pipelined you dont change to wait
                            // as master does not matter much, only send 1 request then w8 for ack
                            // also stay in request state until you want to quit
                            _state <= WAIT;
                    end
                end
                WAIT: begin
                    if (i_wb_ack)
                        _state <= IDLE;
                end
                default: begin
                    _state <= IDLE;
                end 
            endcase
        end
    end

    // ==============================================================

    // These 2 signals facilitates control
    always_ff @(posedge i_clk) begin : wb_strobe
        // WB spec demands synchronous reset
        // Also reset bus interface on error?
        if (~i_rst | i_wb_err) begin
            // Only cyc and stb must be negated, all others undefined
            o_wb_cyc <= 1'b0;
            o_wb_stb <= 1'b0;
            // what else
        end
        else begin
            case (_state)
                IDLE: begin
                    if (i_mem_en) begin
                        o_wb_cyc <= 1'b1;
                        o_wb_stb <= 1'b1;
                    end
                end
                REQUEST: begin
                    if (!i_wb_stall) begin
                        o_wb_stb <= 1'b0; // Only 1 access then change state to wait / idle
                        if (i_wb_ack)     // if access is combinational
                            o_wb_cyc <= 1'b0;
                    end
                end
                WAIT: begin
                    if (i_wb_ack)
                        o_wb_cyc <= 1'b0;
                end
                default: begin /* do nothing */ end
            endcase
        end
    end

    // ==============================================================

    // Have to change when support multi cycle r/w
    always @(posedge i_clk) begin : wb_on_new_req
        case (_state)
        IDLE: begin
            if (i_mem_en) begin
                o_wb_we   <= i_mem_we;
                o_wb_data <= i_mem_wd;
                o_wb_addr <= i_mem_addr;
                o_wb_sel  <= _sel; 
            end
        end
        default: begin /* do nothing */ end
        endcase
    end

    // ==============================================================

    // forward error, result, ack
    assign o_mem_err = i_wb_err; // or-ed with address check in intercon
    assign o_mem_rd  = i_wb_data;
    assign o_mem_ack = i_wb_ack;

endmodule
