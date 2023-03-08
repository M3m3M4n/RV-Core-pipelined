`include "srcs/rtl/include/config.svh"

/* WB interface for SDRAM controller for EM638325BK-6H on Colorlight-i5
 * Use the busy signal for the stall signal, this can reduce performance since the controller support changing request right after ack (after request latched)
 * Ack problem: 
 *  - ack in the controller means data is latched, not when data is available, so depend on read | write WB ack must be on controller valid | ack signal
 *  -> need to save state
 * Delay problem:
 *  - IF READ / WRITE DATA SEEM TO BE REPEATED THIS MIGHT BE THE PROBLEM, INCREASE THE COUNTER
 *  - If we rely on ack signal to stop sending request then CDC delay is a big problem. Multiple request will be send and received by the controller before first ack arrives.
 */

module SDRAMControllerWB #(
    parameter START_ADDR = 32'h20000000
) (
    // ==============================================
    // WB Port
    input  logic        i_wb_clk,
    input  logic        i_wb_rst,
    input  logic        i_wb_cyc,
    input  logic        i_wb_stb,
    // 32 bit addr, byte addressing, BUT we don't do that here
    // Address will be truncated, data will be read / write 4 bytes at a time
    // Leave individual byte access to whatever cache system sits before this module.
    //  cache -> wb Read: all 4 bytes, mask the unwanted if sel not 1111
    //  cache -> wb Write: read THEN write with changed byte if sel not 1111
    input  logic [31:0] i_wb_addr,
    input  logic        i_wb_we,
    input  logic [31:0] i_wb_data,
    // input  logic [3:0]  i_wb_sel, // SDRAM does not support, can do byte swaping here but nah
    output logic        o_wb_ack,
    output logic        o_wb_err,
    output logic [31:0] o_wb_data,
    output logic        o_wb_stall,
    // ==============================================
    // Controller Port
    input  logic        i_ram_clk,
    // ==============================================
    // SDRAM Ports - PASSTHROUGH, do not touch
    // output logic       o_ram_clk, // Connect at top
    // output logic       o_ram_cke, // fixed vcc
    // output logic       o_ram_cs,  // fixed gnd
    // output logic [3:0] o_ram_dqm, // fixed gnd
    output logic        o_ram_ras,
    output logic        o_ram_cas,
    output logic        o_ram_we,
    output logic [1:0]  o_ram_ba,
    output logic [10:0] o_ram_addr,
    // Bi-directional port does not play nice with verilator, split to test
`ifdef VERILATOR
    input  logic [31:0] i_ram_dq,  // from sdram model
    output logic [31:0] o_ram_dq   // to sdram model
`else
    inout  logic [31:0] io_ram_dq
`endif
);

    // SDRAM clk domain rst
    logic [1:0] _ram_i_rst;
    always_ff @(posedge i_ram_clk) begin : ram_rst_doubleflop
        _ram_i_rst = {_ram_i_rst[0], i_wb_rst};
    end

    // High when both i_wb_cyc and i_wb_stb high
    logic i_wb_en;
    assign i_wb_en = i_wb_cyc & i_wb_stb;

    // State machine
    // To avoid fifo delay problem (see header note) leads to sending multiple request repeatedly
    // have a third stage that the controller will get to after sending request for 1 clock
    // , wait there for a set amount of time, if not receive anything then go to request and try again
    // , else move to idle
    typedef enum logic [1:0] {STATE_IDLE, STATE_REQUEST, STATE_WAIT} _state_t;
    _state_t _state;

    always_ff @(posedge i_wb_clk) begin : state_machine
        if (~i_wb_rst) begin
            _state <= STATE_IDLE;
        end
        else begin
            case (_state)
                STATE_IDLE: begin
                    if (i_wb_en) begin
                        _state <= STATE_REQUEST;
                    end
                end
                STATE_REQUEST: begin
                    // There is a chance that ack / valid will high after the state has changed
                    // to request from wait. To give it a last chance, handle ack here.
                    // If the wait counter is any shorter then it will loop indefinitely
                    if ((_wb_we & _wb_ack) | (~_wb_we & _wb_valid)) begin
                        _state <= STATE_IDLE;
                    end
                    else begin
                        // Then we can proceed with the default flow
                        _state <= STATE_WAIT;
                    end
                end
                STATE_WAIT: begin
                    // if _wait_counter_p1[4] == 1'b0 && receive ack or valid? => too bad try again
                    if (_wait_counter_p1[4] == 1'b0) begin
                        if (_wb_we & _wb_ack) begin
                            _state <= STATE_IDLE;
                        end
                        else 
                        if (~_wb_we & _wb_valid) begin
                            _state <= STATE_IDLE;
                        end
                        // else do nothing
                    end
                    else if (_wait_counter_p1[4] == 1'b1) begin
                        _state <= STATE_REQUEST;
                    end
                end
            endcase
        end
    end

    // Wait counter
    // Setting this too low will cause repeating request
    logic [3:0] _wait_counter;
    logic [4:0] _wait_counter_p1;
    assign _wait_counter_p1 = _wait_counter + 1;

    always_ff @(posedge i_wb_clk) begin : wait_counter
        if (~i_wb_rst) begin
            _wait_counter <= 'b0;
        end
        else begin
            case (_state)
                STATE_IDLE: begin
                    _wait_counter <= 'b0;
                end
                STATE_REQUEST: begin
                    _wait_counter <= 'b0;
                end
                STATE_WAIT: begin
                    if (_wait_counter_p1[4] == 1'b0)
                        _wait_counter <= _wait_counter_p1[3:0];
                end
            endcase
        end
    end

    // Fifo read en, only read from fifo during wait state
    logic _fifo_ram_mem_en;
    always_ff @(posedge i_wb_clk) begin : fifo_read_en
        if (~i_wb_rst) begin
            _fifo_ram_mem_en <= 'b0;
        end
        else begin
            case (_state)
                STATE_REQUEST: begin
                    // last chance, see state
                    if ((_wb_we & _wb_ack) | (~_wb_we & _wb_valid)) begin
                        _fifo_ram_mem_en <= 'b0;
                    end
                    else begin
                        // default
                        _fifo_ram_mem_en <= 'b1;
                    end
                end
                STATE_WAIT: begin
                    if (_wait_counter_p1[4] == 1'b0) begin
                        if (_wb_we & _wb_ack) begin
                            _fifo_ram_mem_en <= 'b0;
                        end
                        else 
                        if (~_wb_we & _wb_valid) begin
                            _fifo_ram_mem_en <= 'b0;
                        end
                        // else do nothing
                    end
                    else if (_wait_counter_p1[4] == 1'b1) begin
                        _fifo_ram_mem_en <= 'b0;
                    end
                end
            endcase
        end
    end

    // Latching_request
    logic [31:0] _wb_addr, _wb_data;
    logic        _wb_en, _wb_we;

    always_ff @(posedge i_wb_clk) begin : latching_request
        if (~i_wb_rst) begin
            _wb_addr <= 'h0;
            _wb_data <= 'h0;
            _wb_en   <= 'b0;
            _wb_we   <= 'b0;
        end
        else begin
            case (_state)
                STATE_IDLE: begin
                    if (i_wb_en) begin
                        _wb_addr <= i_wb_addr;
                        _wb_data <= i_wb_data;
                        _wb_en   <= i_wb_en;
                        _wb_we   <= i_wb_we;
                    end
                end
                STATE_REQUEST: begin
                    // Coming from wait timeout
                    if (_wait_counter_p1[4] == 1'b1) begin
                        if ((_wb_we & _wb_ack) | (~_wb_we & _wb_valid)) begin
                            // got data, not resend
                            _wb_en <= 'b0;
                        end
                        else begin
                            // default, resend request
                            _wb_en <= 'b1;
                        end 
                    end
                    else begin
                        // Coming from idle, sending only 1 request
                        if (_wait_counter_p1[4] == 1'b0) begin
                            _wb_en <= 'b0;
                        end
                    end
                end
                STATE_WAIT: begin
                    // In case coming from request resend
                    _wb_en <= 'b0;
                end
            endcase
        end
    end

    // 32 bits address convert to sdram block 21 bits address
    // i_wb_addr = {9'b0, bankaddr, rowaddr, columnaddr, 2'b0}
    logic [20:0] _wb_addr_trunc;
    assign _wb_addr_trunc = _wb_addr[22:2];

    // ==============================================
    // FIFO for controller inputs
    logic _fifo_mem_ram_empty, _fifo_mem_ram_full;
    logic _fifo_mem_ram_ae, _fifo_mem_ram_af; // Almost signals, currently unused
    // Data go in the controller:
    //  i_addr - 21 bits = address point to 4 bytes block, convert from 32 bits i_wb_addr
    //  i_data - 32 bits = _wb_data
    //  i_we   -  1 bits = _wb_we
    //  i_req  -  1 bits = _wb_en
    //  total  -  55 bits
    logic [54:0] _fifo_mem_ram_data_in, _fifo_mem_ram_data_out;

    assign _fifo_mem_ram_data_in = {_wb_addr_trunc, _wb_data, _wb_we, _wb_en};
    assign {_ram_i_addr, _ram_i_data, _ram_i_we, _ram_i_req} = _fifo_mem_ram_data_out;

    FIFO #(
        .FIFO_O_WIDTH(55)
    ) toRAMController (
        // out rp == controller
        .i_rp_clk  (i_ram_clk),
        .i_rp_rst  (_ram_i_rst),
        .i_rp_en   (1'b1), // always read when possible, FULL/EMPTY check already performed by FIFO
        .o_rp_data (_fifo_mem_ram_data_out),
        .o_rp_ae   (_fifo_mem_ram_ae),
        .o_rp_empty(_fifo_mem_ram_empty),
        // in wp == cpu
        .i_wp_clk  (i_wb_clk),
        .i_wp_rst  (i_wb_rst),
        .i_wp_en   (_wb_en), // FULL/EMPTY check already performed by FIFO
        .i_wp_data (_fifo_mem_ram_data_in),
        .o_wp_af   (_fifo_mem_ram_af),
        .o_wp_full (_fifo_mem_ram_full)
    );

    // ==============================================
    // FIFO for controller outputs
    logic _fifo_ram_mem_in_en;
    logic _fifo_ram_mem_empty, _fifo_ram_mem_full;
    logic _fifo_ram_mem_ae, _fifo_ram_mem_af;  // Almost signals, currently unused
    // Data go out from the controller:
    //  o_ack   -  1 bits = high when request received
    //  o_valid -  1 bits = high when read data valid
    //  o_data  - 32 bits
    //  total  -  34 bits
    logic [33:0] _fifo_ram_mem_data_in, _fifo_ram_mem_data_out;
    // WB does not have valid signal while sdram controller implements 2 diff signals
    logic _wb_ack, _wb_valid;
    
    assign _fifo_ram_mem_in_en = _ram_o_ack | _ram_o_valid; // High when has something to say
    assign _fifo_ram_mem_data_in = {_ram_o_ack, _ram_o_valid, _ram_o_data};
    assign {_wb_ack, _wb_valid, o_wb_data} = _fifo_ram_mem_data_out;

    FIFO #(
        .FIFO_O_WIDTH(34)
    ) fromRAMController (
        // out rp == cpu
        .i_rp_clk  (i_wb_clk),
        .i_rp_rst  (i_wb_rst),
        .i_rp_en   (_fifo_ram_mem_en),
        .o_rp_data (_fifo_ram_mem_data_out),
        .o_rp_ae   (_fifo_ram_mem_ae),
        .o_rp_empty(_fifo_ram_mem_empty),
        // in wp == controller
        .i_wp_clk  (i_ram_clk),
        .i_wp_rst  (_ram_i_rst),
        .i_wp_en   (_fifo_ram_mem_in_en),
        .i_wp_data (_fifo_ram_mem_data_in),
        .o_wp_af   (_fifo_ram_mem_af),
        .o_wp_full (_fifo_ram_mem_full)
    );

    // ==============================================
    // SDRAM controller
    // Inputs - 55 bits
    logic [20:0] _ram_i_addr; // 21 bits block addr
    logic [31:0] _ram_i_data; // 32 bits data input to ram
    logic        _ram_i_we;
    logic        _ram_i_req;
    // Outputs - 35 bits
    logic        _ram_o_ack;
    logic        _ram_o_valid;
    logic [31:0] _ram_o_data;
    logic        _ram_o_busy; // Cause fifo bloat, do not use

    // FOR TESTING REMEMBER TO CHANGE CLOCK IN SDRAM CONTROLLER AS WELL AS SDRAM SIMULATION MODEL
    SDRAMController #(
        .SDRAM_O_CLK_FREQ(`RAM_CLK_FREQ),
        .SDRAM_C_CAS_LATENCY(`RAM_CAS_LATENCY)
    ) SDRAMController (
        .i_clk   (i_ram_clk),
        .i_rst   (_ram_i_rst),
        // Memory interface
        .i_addr  (_ram_i_addr),
        .i_data  (_ram_i_data),
        .i_we    (_ram_i_we),
        .i_req   (_ram_i_req),
        .o_ack   (_ram_o_ack),
        .o_valid (_ram_o_valid),
        .o_data  (_ram_o_data),
        .o_busy  (_ram_o_busy),
        // SDRAM interface, PASSTHROUGH
        // .o_r_clk (), // Connect at top
        // .o_r_cke (), // fixed vcc
        // .o_r_cs  (), // fixed gnd
        // .o_r_dqm (), // fixed gnd
        .o_r_ras (o_ram_ras),
        .o_r_cas (o_ram_cas),
        .o_r_we  (o_ram_we),
        .o_r_ba  (o_ram_ba),
        .o_r_addr(o_ram_addr),
`ifdef VERILATOR
        .i_r_dq  (i_ram_dq),
        .o_r_dq  (o_ram_dq)
`else
        .io_r_dq (io_ram_dq)
`endif
    );

    // Stall
    assign o_wb_stall = (_state != STATE_IDLE);
    // Ack
    assign o_wb_ack   = _wb_we ? _wb_ack : _wb_valid;
    // Err
    assign o_wb_err   = 1'b0;

endmodule
