/* SDRAM controller for EM638325BK-6H on Colorlight-i5
 * https://github.com/ZipCPU/zipstormmx/blob/master/rtl/wbsdram.v
 * Search phase shift timing problem later "sdram controller phase shift" or "fpga clock phase shift sdram" or "calculate phase shift for clock fpga"
 * https://community.intel.com/t5/Programmable-Devices/SDRAM-Clock/td-p/239609
 * https://twitter.com/topapate/status/1125456054928719873?lang=en
 * https://electronics.stackexchange.com/questions/387908/how-to-determine-phase-shift-for-clock-being-generated-for-sdram-connected-to-fp
 * https://www.reddit.com/r/FPGA/comments/727yhq/question_about_sdram_controllers/
 * https://inst.eecs.berkeley.edu/~cs150/sp07/Lectures/10-SDRAMx2.pdf
 * https://github.com/lawrie/ulx3s_examples/blob/master/sdram16/testram.v shift 180?
 * Ported from https://github.com/nullobject/sdram-fpga
 */

/* Key DRAM timing parameters:
 * The -5, -6, -7 in data sheet are just tCK min, "speed grade" in some other datasheet (see first page)
 *     EM638325BK-6H tCK min = 6ns = 166 MHz max
 * t[RAC]: minimum time from RAS line falling to the valid data output
 * t[CAC]: minimum time from CAS line falling to valid data output
 * t[RC] : minimum time from the start of one row access to the start of the next
 * t[PC] : minimum time from the start of one column access to the start of the next
 */

 /* FOR MEMORY INTERFACE THAT CONNECTED TO THIS
  * READ | WRITE burst size == 1:
  *     - Hold request until received ack            => request received, data may or may not available, might duplicate request if slow
  *     - Hold request until received valid          => request duplication likely
  *     - Only request for 1 cycle, don't wait       => request might not be handled if controller busy
  *     - Only request for 1 cycle, wait ack | valid => same problem as prev, might not get ack | valid at all
  * WRITE: if burst size > 1: 
  *     - MUST NOT wait until received ack or valid, send entire burst first then wait
  */

// 32 bit address space
module SDRAMController #(
    // O == option, T == timing (ns), C == clock timing
    // ==================================================
    // SDRAM parameters
    // 64Mbits, 32bits granularity == 2097152 addressible location
    // Coming from byte-addressible address space, last 2 bits should be cut.
    // [bank][row][column]
    parameter SDRAM_O_CLK_FREQ     = 143, // MHz, same as sdram clk
    parameter SDRAM_O_SIZE         = 67108864, // Bits
    parameter SDRAM_O_DATA_WIDTH   = 32, // DQ0-DQ31
    parameter MEM_O_ADDR_WIDTH     = $clog2(SDRAM_O_SIZE / SDRAM_O_DATA_WIDTH), // Memory interface width
    parameter SDRAM_O_NBANK        = 4, // Number of banks
    parameter SDRAM_O_BANK_WIDTH   = $clog2(SDRAM_O_NBANK), // BA0-BA1
    parameter SDRAM_O_ADDR_WIDTH   = 11, // A0-A10
    parameter SDRAM_O_ROW_WIDTH    = SDRAM_O_ADDR_WIDTH, // A0-A10 in BankActive
    parameter SDRAM_O_COLUMN_WIDTH = MEM_O_ADDR_WIDTH - SDRAM_O_BANK_WIDTH - SDRAM_O_ROW_WIDTH,  // A0-7 in Read / Write
    // t[CAC] (min) ≤ CAS Latency X t[CK]
    // t[CAC] is not mentioned anywhere else in the datasheet except this formula
    // Use value from others 2=below 133MHz, 3=above 133MHz
    parameter SDRAM_C_CAS_LATENCY  = 3,
    parameter SDRAM_O_BURST_LENGTH = 1,  // 1, 2, 4, 8, whole page
    parameter SDRAM_O_PAGE_SIZE    = 256,
    // ==================================================
    // Timings in nanoseconds, some converted from tck @ 143MHz
    parameter real SDRAM_T_DESL    = 200000.0, // -- startup delay, power on sequence
    parameter real SDRAM_T_MRD     =     14.0, // -- mode register set cycle time
    parameter real SDRAM_T_RC      =     63.0, // -- row cycle time
    parameter real SDRAM_T_RCD     =     21.0, // -- RAS to CAS delay
    parameter real SDRAM_T_RP      =     21.0, // -- precharge to activate delay
    parameter real SDRAM_T_WR      =     14.0, // -- write recovery time
    parameter real SDRAM_T_REFI    =  15600.0  // -- average refresh interval
    
) (
    input  logic                              i_clk, // SDRAM clk
    input  logic                              i_rst,
    // ==================================================
    // Memory controller interface - connect to CDC module
    input  logic [MEM_O_ADDR_WIDTH - 1 : 0]   i_addr, // Block addr
    input  logic [SDRAM_O_DATA_WIDTH - 1 : 0] i_data,
    input  logic                              i_we,
    input  logic                              i_req, // Basically enable
    // For reading Ack is no longer represent data readiness, but only when request is accepted
    // For writing it is the same
    output logic                              o_ack,
    // This high when read data is available
    output logic                              o_valid,
    output logic [SDRAM_O_DATA_WIDTH - 1 : 0] o_data,
    // High when not idle
    output logic                              o_busy,
    // ==================================================
    // SDRAM interface
    // output logic                           o_r_clk, // Connect at top
    // output logic                           o_r_cke, // fixed vcc
    // output logic                           o_r_cs,  // fixed gnd
    // output logic [3:0]                     o_r_dqm, // fixed gnd
    output logic                              o_r_ras,
    output logic                              o_r_cas,
    output logic                              o_r_we,
    output logic [SDRAM_O_BANK_WIDTH - 1 : 0] o_r_ba,
    output logic [SDRAM_O_ADDR_WIDTH - 1 : 0] o_r_addr,
    // Bi-directional port does not play nice with verilator, split to test
`ifdef VERILATOR
    input  logic [SDRAM_O_DATA_WIDTH - 1 : 0] i_r_dq,  // from sdram model
    output logic [SDRAM_O_DATA_WIDTH - 1 : 0] o_r_dq   // to sdram model
`else
    inout  logic [SDRAM_O_DATA_WIDTH - 1 : 0] io_r_dq
`endif
);
    // ==================================================
    // Clock based timings, T = time, C = clock
    localparam real    SDRAM_T_CLK_PERIOD       = 1000.0 / SDRAM_O_CLK_FREQ;   // ns
    localparam integer SDRAM_C_INIT_WAIT        = $ceil(SDRAM_T_DESL / SDRAM_T_CLK_PERIOD);
    localparam integer SDRAM_C_LOAD_MODE_WAIT   = $ceil(SDRAM_T_MRD / SDRAM_T_CLK_PERIOD);
    localparam integer SDRAM_C_ACTIVE_WAIT      = $ceil(SDRAM_T_RCD / SDRAM_T_CLK_PERIOD);
    localparam integer SDRAM_C_REFRESH_WAIT     = $ceil(SDRAM_T_RC / SDRAM_T_CLK_PERIOD);
    localparam integer SDRAM_C_PRECHARGE_WAIT   = $ceil(SDRAM_T_RP / SDRAM_T_CLK_PERIOD);
    // This here is how cas latency can be determined (in this case)
    // SDRAM_C_READ_WAIT is required by datasheet to be >= T_RP + burst length (read + autoprecharge)
    // For a read operation it must wait for CAS so SDRAM_C_CAS_LATENCY must be >= T_RP
    localparam integer SDRAM_C_READ_WAIT        = SDRAM_C_CAS_LATENCY + SDRAM_O_BURST_LENGTH;
    localparam integer SDRAM_C_WRITE_WAIT       = SDRAM_O_BURST_LENGTH + $ceil((SDRAM_T_WR + SDRAM_T_RP) / SDRAM_T_CLK_PERIOD);
    // To avoid refresh wait is maxxed during read / write, subtract read / write time (whichever is greater)
    // from refresh wait time in order to hae time spare for refresh, + few more cycle for state change
    localparam integer SDRAM_C_REFRESH_INTERVAL = $floor(SDRAM_T_REFI / SDRAM_T_CLK_PERIOD) - SDRAM_C_ACTIVE_WAIT - SDRAM_C_WRITE_WAIT - 3;

    // ==================================================
    // Command list (RAS, CAS, WE)
    // CKE, CS, DQM is fixed, some commands are not available
    // Device Deselect (N/A)                (CS = "H")
    // Clock Suspend Mode Entry (N/A)       (CKE = "L")
    // Clock Suspend Mode Exit (N/A)        (CKE n-1 = "L")
    // SelfRefresh Entry (N/A)              (CKE = "L")
    // SelfRefresh Exit (N/A)               (CKE n-1 = "L")
    // Power Down Mode Entry (N/A)          (CKE = "L")
    // Power Down Mode Exit (N/A)           (CKE n-1 = "L")
    // Data Write/Output Enable (N/A)
    // Data Mask/Output Disable (N/A)
    // Mode Register Set                    (RAS# = "L", CAS# = "L", WE# = "L", A0-A10 = Register Data)
    // localparam [2:0] SDRAM_CMD_LOADMODE   = 3'b000;
    // AutoRefresh                          (RAS# = "L", CAS# = "L", WE# = "H", A0-A10 = Don't care)
    // localparam [2:0] SDRAM_CMD_REFRESH    = 3'b001;
    // Bank Precharge                       (RAS# = "L", CAS# = "H", WE# = "L", BAs = Bank, A10 = "L", A0-A9 = Don't care)
    // Precharge all                        (RAS# = "L", CAS# = "H", WE# = "L", BAs = Don’t care, A10 = "H", A0-A9 = Don't care)
    // localparam [2:0] SDRAM_CMD_PRECHARGE  = 3'b010;
    // BankActivate                         (RAS# = "L", CAS# = "H", WE# = "H", BAs = Bank, A0-A10 = Row Address)
    // localparam [2:0] SDRAM_CMD_ACTIVE     = 3'b011;
    // Write                                (RAS# = "H", CAS# = "L", WE# = "L", BAs = Bank, A10 = "L", A0-A7 = Column Address)
    // Write and AutoPrecharge              (RAS# = "H", CAS# = "L", WE# = "L", BAs = Bank, A10 = "H", A0-A7 = Column Address)
    // localparam [2:0] SDRAM_CMD_WRITE      = 3'b100;
    // Read                                 (RAS# = "H", CAS# = "L", WE# = "H", BAs = Bank, A10 = "L", A0-A7 = Column Address)
    // Read and AutoPrecharge               (RAS# = "H", CAS# = "L", WE# = "H", BAs = Bank, A10 = "H", A0-A7 = Column Address)
    // localparam [2:0] SDRAM_CMD_READ       = 3'b101;
    // Burst Stop                           (RAS# = "H", CAS# = "H", WE# = "L")
    // localparam [2:0] SDRAM_CMD_BURST_STOP = 3'b110;
    // No-Operation                         (RAS# = "H", CAS# = "H", WE# = "H")
    // localparam [2:0] SDRAM_CMD_NOP        = 3'b111;
    // This is nicer, the range is continuous anyway
    typedef enum logic [2:0] {  CMD_LOADMODE,   // 000
                                CMD_REFRESH,    // 001
                                CMD_PRECHARGE,  // 010
                                CMD_ACTIVE,     // 011
                                CMD_WRITE,      // 100
                                CMD_READ,       // 101
                                CMD_BURST_STOP, // 110
                                CMD_NOP         // 111
    } _sdram_cmd_t;
    _sdram_cmd_t _cmd, _next_cmd;

    // ==================================================
    // States
    typedef enum logic [2:0] {  STATE_INIT,   // 000
                                STATE_IDLE,   // 001
                                STATE_ACTIVE, // 010
                                STATE_READ,   // 011
                                STATE_WRITE,  // 100
                                STATE_REFRESH // 101
    } _controller_state_t;
    _controller_state_t _state, _next_state;

    always_ff @(posedge i_clk) begin
        if (~i_rst) begin
            _state <= STATE_INIT;
            _cmd <= CMD_NOP;
        end
        else begin
            _state <= _next_state;
            _cmd <= _next_cmd;
        end
    end

    // ==================================================
    // Wait counter
    logic [15:0] _wait_counter;
    logic [16:0] _wait_counter_p1;

    assign _wait_counter_p1 = _wait_counter + 1;

    always_ff @(posedge i_clk) begin : wait_counter
        if (~i_rst) begin
            _wait_counter <= 16'h0;
        end
        else begin
            if (_state != _next_state) begin
                _wait_counter <= 16'h0;
            end
            else begin
                if (_wait_counter_p1[16] == 0) // prevent overflow
                    _wait_counter <= _wait_counter_p1[15:0];
            end
        end
    end

    // ==================================================
    // Refresh counter
    logic [11:0] _refresh_counter;
    logic [12:0] _refresh_counter_p1;

    assign _refresh_counter_p1 = _refresh_counter + 1;

    always_ff @(posedge i_clk) begin : refresh_counter
        if (~i_rst) begin
            _refresh_counter <= 'h0;
        end
        else begin
            if (_state == STATE_REFRESH & _wait_counter == 'h0) begin
                _refresh_counter <= 'h0;
            end
            else begin
                if(_refresh_counter_p1[12] == 0) // prevent overflow
                    _refresh_counter <= _refresh_counter_p1[11:0];
            end
        end
    end

    // ==================================================
    // State machine control signals
    logic _sig_active_done;
    logic _sig_refresh_done;
    logic _sig_read_done;
    logic _sig_read_data_avail;
    logic _sig_write_done;
    logic _sig_need_refresh;
    logic _sig_state_changing;

    // Assign signals
    // Most of the time you would just need an edge, if these signal were to be lengthened (>=)
    // check the _next_state condition
    assign _sig_active_done     = (_state == STATE_ACTIVE) & (_wait_counter >= SDRAM_C_ACTIVE_WAIT - 1);
    assign _sig_refresh_done    = (_state == STATE_REFRESH) & (_wait_counter >= SDRAM_C_REFRESH_WAIT - 1);
    assign _sig_read_done       = (_state == STATE_READ) & (_wait_counter >= SDRAM_C_READ_WAIT - 1);
    assign _sig_read_data_avail = (~_sig_state_changing) & (_state == STATE_READ) & ((_wait_counter >= SDRAM_C_CAS_LATENCY) & (_wait_counter < (SDRAM_C_WRITE_WAIT - 1))); // held for burst
    assign _sig_write_done      = (_state == STATE_WRITE) & (_wait_counter >= SDRAM_C_WRITE_WAIT - 1);
    assign _sig_need_refresh    = (_refresh_counter >= (SDRAM_C_REFRESH_INTERVAL - 1));
    assign _sig_state_changing  = (_next_state != _state);

    // ==================================================
    // State machine

    // Wait timing parameters
    // Seems like yosys does not like having compare net to localparam arithmetic
    localparam integer SDRAM_C_INIT_WAIT_INIT      = SDRAM_C_INIT_WAIT - 1;
    localparam integer SDRAM_C_INIT_WAIT_PRECHARGE = SDRAM_C_INIT_WAIT_INIT + SDRAM_C_PRECHARGE_WAIT;      // already -1
    localparam integer SDRAM_C_INIT_WAIT_REFRESH_1 = SDRAM_C_INIT_WAIT_PRECHARGE + SDRAM_C_REFRESH_WAIT;   // already -1
    localparam integer SDRAM_C_INIT_WAIT_REFRESH_2 = SDRAM_C_INIT_WAIT_REFRESH_1 + SDRAM_C_REFRESH_WAIT;   // already -1
    localparam integer SDRAM_C_INIT_WAIT_LOAD_MODE = SDRAM_C_INIT_WAIT_REFRESH_2 + SDRAM_C_LOAD_MODE_WAIT; // already -1

    always_ff @(posedge i_clk) begin : state_machine
        if (~i_rst) begin
            // Set state and cmd
            _next_state <= STATE_INIT;
            _next_cmd <= CMD_NOP;
        end
        else begin
            case (_state)
                // Power on sequence
                STATE_INIT: begin
                    // Precharge all
                    if (_wait_counter == SDRAM_C_INIT_WAIT_INIT) begin
                        _next_cmd <= CMD_PRECHARGE;
                        // _local_r_addr <= {{(SDRAM_O_ADDR_WIDTH - 11){1'b0}}, 11'b10000000000}; // a[10] = 1
                    end
                    // Auto refresh x2
                    else if (_wait_counter == SDRAM_C_INIT_WAIT_PRECHARGE) begin
                        _next_cmd <= CMD_REFRESH;
                    end
                    else if (_wait_counter == SDRAM_C_INIT_WAIT_REFRESH_1) begin
                        _next_cmd <= CMD_REFRESH;
                    end
                    // Mode register set
                    // BA0-1: Reserved
                    // A10: Reserved
                    // A9: Write burst length 0: burst, 1: single bit
                    // A8-7: Test mode : 00: normal
                    // A6-4: CAS latency: 010: 2, 011: 3
                    // A3: BT: 0: sequential, 1: interleave
                    // A2-0: Burst length: 32bits multiple
                    //       000: 1
                    //       001: 2
                    //       010: 4
                    //       011: 8
                    //       111: Full Page (Sequential)
                    else if (_wait_counter == SDRAM_C_INIT_WAIT_REFRESH_2) begin
                        _next_cmd <= CMD_LOADMODE;
                    end
                    // Done
                    else if (_wait_counter == SDRAM_C_INIT_WAIT_LOAD_MODE) begin
                        _next_state <= STATE_IDLE;
                    end
                    else begin
                        _next_cmd <= CMD_NOP;
                    end
                end
                STATE_IDLE: begin
                    if (_sig_need_refresh) begin
                        if (_sig_state_changing) begin
                            _next_cmd <= CMD_NOP;
                        end
                        else begin
                            _next_state <= STATE_REFRESH;
                            _next_cmd <= CMD_REFRESH;
                        end
                    end
                    else if (i_req) begin
                        if (_sig_state_changing) begin
                            _next_cmd <= CMD_NOP;
                        end
                        else begin
                            _next_state <= STATE_ACTIVE;
                            _next_cmd <= CMD_ACTIVE;
                        end
                    end
                    else begin
                        _next_cmd <= CMD_NOP;
                    end
                end
                STATE_ACTIVE: begin
                    if (_sig_active_done) begin
                        if (_sig_state_changing) begin
                            _next_cmd <= CMD_NOP;
                        end
                        else begin
                            if (_we) begin
                                _next_state <= STATE_WRITE;
                                _next_cmd <= CMD_WRITE;
                            end
                            else begin
                                _next_state <= STATE_READ;
                                _next_cmd <= CMD_READ;
                            end
                        end
                    end
                    else begin
                        _next_cmd <= CMD_NOP;
                    end
                end
                // and AutoPrecharge
                STATE_READ: begin
                    if (_sig_read_done) begin
                        if (_sig_state_changing) begin
                            _next_cmd <= CMD_NOP;
                        end
                        else begin
                            if (_sig_need_refresh) begin
                                _next_state <= STATE_REFRESH;
                                _next_cmd <= CMD_REFRESH;
                            end
                            else if (i_req) begin
                                _next_state <= STATE_ACTIVE;
                                _next_cmd <= CMD_ACTIVE;
                            end
                            else begin
                                _next_state <= STATE_IDLE;
                                _next_cmd <= CMD_NOP;
                            end
                        end
                    end
                    else begin
                        _next_cmd <= CMD_NOP;
                    end
                end
                // and AutoPrecharge
                STATE_WRITE: begin
                    if (_sig_write_done) begin
                        if (_sig_state_changing) begin
                            _next_cmd <= CMD_NOP;
                        end
                        else begin
                            if (_sig_need_refresh) begin
                                _next_state <= STATE_REFRESH;
                                _next_cmd <= CMD_REFRESH;
                            end
                            else if (i_req) begin
                                _next_state <= STATE_ACTIVE;
                                _next_cmd <= CMD_ACTIVE;
                            end
                            else begin
                                _next_state <= STATE_IDLE;
                                _next_cmd <= CMD_NOP;
                            end
                        end
                    end
                    else begin
                        _next_cmd <= CMD_NOP;
                    end
                end
                // AutoRefresh
                STATE_REFRESH: begin
                    if(_sig_refresh_done) begin
                        if (_sig_state_changing) begin
                            _next_cmd <= CMD_NOP;
                        end
                        else begin
                            if(i_req) begin
                                _next_state <= STATE_ACTIVE;
                                _next_cmd <= CMD_ACTIVE;
                            end
                            else begin
                                _next_state <= STATE_IDLE;
                                _next_cmd <= CMD_NOP;
                            end
                        end
                    end
                    else begin
                        _next_cmd <= CMD_NOP;
                    end
                end
                default: begin
                    // DED
                    _next_state <= STATE_IDLE;
                    _next_cmd <= CMD_NOP;
                end
            endcase
        end
    end

    // ==================================================
    // Mem interface I/Os
    // Latching new request
    logic allow_new_req;
    // Does not allow latching new req when state changing
    assign allow_new_req =  (~_sig_state_changing) &
                            ((_state == STATE_IDLE) |
                            (_sig_read_done) |
                            (_sig_write_done) |
                            (_sig_refresh_done));

    logic _we;
    logic [MEM_O_ADDR_WIDTH - 1 : 0] _addr;
    // In case of write burst:
    // The data is sent since the start of request must be buffered else lost
    // Depth of _data needs to be the same as the number of write cycle delayed by the state machine
    // Buffer to hold data from: active wait time -> write = 
    //                           SDRAM_C_ACTIVE_WAIT + 2
    localparam integer C_DATA_DELAY = 2 + SDRAM_C_ACTIVE_WAIT; // number of cycle from request to read / write state
    // How big is too big? 32 words?
    logic [SDRAM_O_DATA_WIDTH - 1 : 0] _data [C_DATA_DELAY - 1 : 0];

    always_ff @(posedge i_clk) begin : saving_req
        if(allow_new_req) begin
            _we <= i_we;
            _addr <= i_addr;
            _data[0] <= i_data;
        end
    end
 
    always_ff @(posedge i_clk) begin : saving_data
        for (int i = C_DATA_DELAY - 2; i >= 0; i--) begin
            _data[i+1] <= _data[i];
        end
    end

    // Data I/Os
    assign o_busy = (_state != STATE_IDLE); 
    assign o_ack  = (_state == STATE_ACTIVE & _wait_counter == 0);

    always_ff @(posedge i_clk) begin : valid_sig
        if (~i_rst) begin
            o_valid <= 1'b0;
        end
        else begin
            if (_sig_read_data_avail) begin // valid on read data available
                o_valid <= 1'b1;
            end
            else begin
                o_valid <= 1'b0;
            end
        end
    end
    
    always_ff @(posedge i_clk) begin : latch_sdram_data
        if (~i_rst) begin
            o_data <= 'h0;
        end
        else begin
            if (_sig_read_data_avail) begin
`ifdef VERILATOR
                o_data <= i_r_dq;
`else
                o_data <= io_r_dq;
`endif
            end
            else begin
                o_data <= 'h0;
            end
        end
    end

    // ==================================================
    // Assigning ouputs to sdram
    // Cmds
    assign {o_r_ras, o_r_cas, o_r_we} = _cmd;

    // Address and bank address
    // In compatible sdram, o_r_ba and o_r_addr[10] is used in some commands
    always_comb begin : assigning_o_r_ba
        if (_state == STATE_ACTIVE | _state == STATE_READ | _state == STATE_WRITE)
            o_r_ba = _addr[MEM_O_ADDR_WIDTH - 1 : MEM_O_ADDR_WIDTH - SDRAM_O_BANK_WIDTH];
        else
            o_r_ba = 2'b00;
    end

    always_comb begin : assigning_o_r_addr
        case (_state)
            STATE_INIT: begin
                // Timing, roughly, doesn't need to be exact
                if (_wait_counter < SDRAM_C_INIT_WAIT_REFRESH_2) begin
                    // PrechargeAll
                    o_r_addr = {{(SDRAM_O_ADDR_WIDTH - 11){1'b0}}, 11'b1_0000000000};
                end
                else begin
                    // Mode register set
                    o_r_addr = {{(SDRAM_O_ADDR_WIDTH - 11){1'b0}}, 4'b0_0_00, SDRAM_C_CAS_LATENCY[2:0], 1'b0, SDRAM_O_BURST_LENGTH[2:0]};
                end
            end
            STATE_ACTIVE: begin
                o_r_addr = _addr[MEM_O_ADDR_WIDTH - SDRAM_O_BANK_WIDTH - 1 : MEM_O_ADDR_WIDTH - SDRAM_O_BANK_WIDTH - SDRAM_O_ROW_WIDTH]; // row
            end
            // and AutoPrecharge
            STATE_READ: begin
                o_r_addr = {{(SDRAM_O_ADDR_WIDTH - 11){1'b0}}, 1'b1, {(11 - (MEM_O_ADDR_WIDTH - SDRAM_O_BANK_WIDTH - SDRAM_O_ROW_WIDTH) - 1){1'b0}}, _addr[MEM_O_ADDR_WIDTH - SDRAM_O_BANK_WIDTH - SDRAM_O_ROW_WIDTH - 1 : 0]}; // column
            end
            // and AutoPrecharge
            STATE_WRITE: begin
                o_r_addr = {{(SDRAM_O_ADDR_WIDTH - 11){1'b0}}, 1'b1, {(11 - (MEM_O_ADDR_WIDTH - SDRAM_O_BANK_WIDTH - SDRAM_O_ROW_WIDTH) - 1){1'b0}}, _addr[MEM_O_ADDR_WIDTH - SDRAM_O_BANK_WIDTH - SDRAM_O_ROW_WIDTH - 1 : 0]}; // column
            end
            default: begin
                // STATE_IDLE || STATE_REFRESH || DED
                o_r_addr = 'h0;
            end 
        endcase
    end

`ifdef VERILATOR
    assign o_r_dq = _data[C_DATA_DELAY - 1];
`else
    // SDRAM data line, burst length = 1 as 32 bit interface
    assign io_r_dq = (_state == STATE_WRITE) ? _data[C_DATA_DELAY - 1] : 32'bZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ;
`endif

endmodule
