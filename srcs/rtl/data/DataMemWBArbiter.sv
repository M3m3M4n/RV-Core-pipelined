module DataMemWBArbiter #(
    parameter MASTER_COUNT = 2 // 2 Minimum ?
)(
    input  logic i_clk,
    input  logic i_rst,
    // <-> masters
    // Vectorized master buses in case yosys act up
    input  logic [MASTER_COUNT - 1 : 0]        i_m_cyc,
    input  logic [MASTER_COUNT - 1 : 0]        i_m_stb,
    input  logic [MASTER_COUNT - 1 : 0]        i_m_we,
    input  logic [(32 * MASTER_COUNT) - 1 : 0] i_m_addr,
    input  logic [(32 * MASTER_COUNT) - 1 : 0] i_m_data,
    input  logic [(4  * MASTER_COUNT) - 1 : 0] i_m_sel,
    output logic [(32 * MASTER_COUNT) - 1 : 0] o_m_data,
    output logic [MASTER_COUNT - 1 : 0]        o_m_stall,
    output logic [MASTER_COUNT - 1 : 0]        o_m_ack,
    output logic [MASTER_COUNT - 1 : 0]        o_m_err,
    // <-> slaves
    output logic        o_s_cyc,
    output logic        o_s_stb,
    output logic        o_s_we,
    output logic [31:0] o_s_addr,
    output logic [31:0] o_s_data,
    output logic [3:0]  o_s_sel,
    input  logic [31:0] i_s_data,
    input  logic        i_s_stall,
    input  logic        i_s_ack,
    input  logic        i_s_err
);

    // Unflattening ports
    // https://stackoverflow.com/questions/34186734/in-systemverilog-are-indexing-a-parameter-array-in-a-for-loop-a-constant-express
    logic        _i_m_cyc   [MASTER_COUNT - 1 : 0];
    logic        _i_m_stb   [MASTER_COUNT - 1 : 0];
    logic        _i_m_we    [MASTER_COUNT - 1 : 0];
    logic [31:0] _i_m_addr  [MASTER_COUNT - 1 : 0];
    logic [31:0] _i_m_data  [MASTER_COUNT - 1 : 0];
    logic [3:0]  _i_m_sel   [MASTER_COUNT - 1 : 0];
    logic [31:0] _o_m_data  [MASTER_COUNT - 1 : 0];
    logic        _o_m_stall [MASTER_COUNT - 1 : 0];
    logic        _o_m_ack   [MASTER_COUNT - 1 : 0];
    logic        _o_m_err   [MASTER_COUNT - 1 : 0];
    genvar c;
    generate
        for(c = 0; c < MASTER_COUNT; c++) begin
            assign _i_m_cyc[c]  = i_m_cyc[c]; // uhh, nesscessary?
            assign _i_m_stb[c]  = i_m_stb[c];
            assign _i_m_we[c]   = i_m_we[c];
            assign _i_m_addr[c] = i_m_addr[(c * 32 + 31) : (c * 32)];
            assign _i_m_data[c] = i_m_data[(c * 32 + 31) : (c * 32)];
            assign _i_m_sel[c]  = i_m_sel[(c * 4 + 3) : (c * 4)];

            assign o_m_stall[c] = _o_m_stall[c];
            assign o_m_ack[c]   = _o_m_ack[c];
            assign o_m_err[c]   = _o_m_err[c];
            assign o_m_data[(c * 32 + 31) : (c * 32)] = _o_m_data[c];
        end
    endgenerate

    // Size check
    always_comb begin
        if (MASTER_COUNT < 2)
            $fatal("[DataMemWBArbiter.sv] Master count must >= 2 !");
    end
    localparam MASTERCOUNTBITS = $clog2(MASTER_COUNT);
    logic [MASTERCOUNTBITS - 1 : 0] _owner;

    // Bus active signal
    logic _bus_active;
    always_comb begin
        _bus_active = 1'b0;
        for(int i = 0; i < MASTER_COUNT; i++) begin
            _bus_active = _bus_active | _i_m_cyc[i];
        end
    end
    
    // Generate if does not work with non-parameter
    // also not work with break
    // https://stackoverflow.com/questions/63463776/the-generate-if-condition-must-be-a-constant-expression
    always_ff @(posedge i_clk) begin : set_owner
        if (~_bus_active | ~i_rst)
            _owner <= 'b0;
        else begin
            // Break is not synthesizable
            // After loop unrolling, last assignment win. So do this in reverse to prioritize lower ports
            for(int i = MASTER_COUNT - 1; i >= 0; i--) begin
                // ~_i_m_cyc[_owner] instance below cause combinational circular logic
                // so switch to sequential
                if (_i_m_cyc[i] & ~_i_m_cyc[_owner]) begin
                    _owner <= i[MASTERCOUNTBITS - 1 : 0];
                end
            end
        end
    end

    always_comb begin : to_slaves
        o_s_cyc  = _i_m_cyc[_owner];
        o_s_stb  = _i_m_stb[_owner];
        o_s_we   = _i_m_we[_owner];
        o_s_addr = _i_m_addr[_owner];
        o_s_data = _i_m_data[_owner];
        o_s_sel  = _i_m_sel[_owner];
    end

    always_comb begin : to_master
        for(int i = 0; i < MASTER_COUNT; i++) begin
            if (_owner == i[MASTERCOUNTBITS - 1 : 0]) begin
                _o_m_data[i]  = i_s_data;
                _o_m_stall[i] = i_s_stall;
                _o_m_ack[i]   = i_s_ack;
                _o_m_err[i]   = i_s_err;
            end
            else begin
                _o_m_data[i]  = 32'b0;
                _o_m_stall[i] = 1'b1;
                _o_m_ack[i]   = 1'b0;
                _o_m_err[i]   = 1'b0;
            end
        end
    end

endmodule
