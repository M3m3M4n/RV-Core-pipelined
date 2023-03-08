/* 2 ways cache data sructure
 * a set = [[valid1][dirty1][tag1][block1] | [valid2][dirty2][tag2][block2] | [usebit]]
 * ...
 * Address resolution
 * [tag_addr][set_addr][[data_unit_addr][byte_addr]]
 * [[data_unit_addr][byte_addr]] = CACHE_DATA_ADDR_WIDTH_BIT
 * data_unit = 4 bytes data block
 * ...
 * Request will hold until the ack arrived
 */

module TwoWaysCache32Bits #(
    parameter   CACHE_O_CAPACITY_BYTE     = 8192, // divisible by block size
    parameter   CACHE_O_BLOCK_SIZE_BYTE   = 64,   // divisible by 32

    // 2 ways, hardcoded, if need something else need to change metadata use bit and policies
    // DO NOT CHANGE
    localparam  CACHE_BLOCK_PER_SET       = 2,
    localparam  CACHE_N_BLOCK             = CACHE_O_CAPACITY_BYTE / CACHE_O_BLOCK_SIZE_BYTE, // default: 128
    localparam  CACHE_N_SET               = CACHE_N_BLOCK / CACHE_BLOCK_PER_SET,             // default: 64
    localparam  CACHE_N_DWORD             = CACHE_O_BLOCK_SIZE_BYTE / 4,                     // default: 16

    // For a given addr when access the cache from CPU side, addr decodes to:
    // [ADDR] = [TAG][SET ADDR][DATA ADDR]
    // [DATA ADDR] = [DWORD ADDR] + 2 bit byte addressing
    localparam  CACHE_DATA_ADDR_WIDTH_BIT = $clog2(CACHE_O_BLOCK_SIZE_BYTE - 1), // default: 6
    localparam  CACHE_DWORD_ADDR_WIDTH_BIT= $clog2(CACHE_N_DWORD - 1),           // default: 4
    localparam  CACHE_SET_ADDR_WIDTH_BIT  = $clog2(CACHE_N_SET - 1),             // default: 6
    // Hard to expand with arbitrary width, so lock to 32 bits
    localparam  CACHE_TAG_WIDTH_BIT  = 32 - CACHE_DATA_ADDR_WIDTH_BIT - CACHE_SET_ADDR_WIDTH_BIT // default: 20
) (
    input  logic        i_clk,
    input  logic        i_rst,
    // ==================================================
    // Memory interface from master
    input  logic        i_m_en,
    input  logic        i_m_we,
    input  logic [31:0] i_m_addr,
    input  logic [31:0] i_m_data,
    input  logic [1:0]  i_m_mask_type,  // 00: byte, 01: halfword, 10: word
    output logic        o_m_ack,
    output logic        o_m_err,
    output logic [31:0] o_m_data,

    // ==================================================
    // Memory interface to slave bus
    output logic        o_s_en,
    output logic        o_s_we,
    output logic [31:0] o_s_addr,
    output logic [31:0] o_s_data,
    output logic [1:0]  o_s_mask_type,  // 00: byte, 01: halfword, 10: word
    input  logic        i_s_ack,
    input  logic        i_s_err,
    input  logic [31:0] i_s_data
);
    
    // This contains metadata of a single set, quite large, if lack logic switch this to BRAM
    // E.G 2 ways: [[valid1][dirty1][tag1][valid2][dirty1][tag2]] [use][full]
    // valid = 1 bit, dirty = 1 bit, use = 1 bit
    logic                               _cache_metadata_valid_bit    [CACHE_N_SET - 1 : 0][CACHE_BLOCK_PER_SET - 1 : 0];
    logic                               _cache_metadata_dirty_bit    [CACHE_N_SET - 1 : 0][CACHE_BLOCK_PER_SET - 1 : 0];
    logic [CACHE_TAG_WIDTH_BIT - 1 : 0] _cache_metadata_tag          [CACHE_N_SET - 1 : 0][CACHE_BLOCK_PER_SET - 1 : 0];
    // Store index of LEAST recently used block (NOT LAST recently used)
    logic                               _cache_metadata_set_LRU_bit  [CACHE_N_SET - 1 : 0];
    logic                               _cache_metadata_set_full_bit [CACHE_N_SET - 1 : 0]; // When all valid flags in a set are set

    /*
    OLD BACKING MEMORY IMPLEMENTATION

    // Block data, bram ios
    // NOTE: The address line of backing memory is just CACHE_DATA_ADDR_WIDTH_BIT bit wide,
    //       even though it still has 32 bit port
    // Generae in a for loop, link ios in to array
    // Each has:
    //   i_addr,       CACHE_DATA_ADDR_WIDTH_BIT
    //   i_en,         1
    //   i_we,         1
    //   i_mask_type,  2
    //   i_data,      32
    //   o_data,      32
    //   o_ack,        1
    //   o_err         1
    //            =  (70 + CACHE_DATA_ADDR_WIDTH_BIT) bits not including clk
    // CANNOT connect these input directly into cache mem interface because we need to control
    // it internally to update cache data, technically can be muxed but nah...

    logic [(69 + CACHE_DATA_ADDR_WIDTH_BIT) : 0] _cache_data_io [CACHE_N_SET - 1 : 0][CACHE_BLOCK_PER_SET - 1 : 0];
    genvar i, j;
    // Create backing memory
    generate
        for (i = 0; i < CACHE_N_SET; i++) begin
            for (j = 0; j < CACHE_BLOCK_PER_SET; j++) begin
                BRAMArray32Bits #(
                    .SIZE_BYTE(CACHE_O_BLOCK_SIZE_BYTE)
                ) _cache_data (
                    .i_clk      (i_clk),
                    .i_addr     ({(32-CACHE_DATA_ADDR_WIDTH_BIT){1'b0}, _cache_data_io[i][j][69+CACHE_DATA_ADDR_WIDTH_BIT:70]}),
                    .i_en       (_cache_data_io[i][j][69]),
                    .i_we       (_cache_data_io[i][j][68]),
                    .i_mask_type(_cache_data_io[i][j][67:66]),
                    .i_data     (_cache_data_io[i][j][65:34]),
                    .o_data     (_cache_data_io[i][j][33:2]),
                    .o_ack      (_cache_data_io[i][j][1]),
                    .o_err      (_cache_data_io[i][j][0])
                );
            end
        end
    endgenerate
    */

    // To access data in this implementation set addr = {set, block/way, byte_addr}
    // This cache bus is only 32 bits, there is no parallel reading / writing to different
    // cache block, so it would be wasteful if using old implementation

    logic [31:0] _cache_data_i_addr;
    logic        _cache_data_i_en;
    logic        _cache_data_i_we;
    logic [1:0]  _cache_data_i_mask;
    logic [31:0] _cache_data_i_data;
    logic [31:0] _cache_data_o_data;
    logic        _cache_data_o_ack;
    logic        _cache_data_o_err;
    
    // ADDR to access internal cache data is a little different compare to main input addr:
    // [CACHE ADDR] = [SET ADDR][BLOCK ADDR / WAY][DATA ADDR]
    // [SET ADDR], [DATA ADDR] are the same as the main addr
    // [BLOCK ADDR / WAY] is 1 bit represent 2 ways

    localparam CACHE_INTERNAL_DATA_ADDR_WIDTH_BIT = 32 - CACHE_SET_ADDR_WIDTH_BIT - CACHE_DATA_ADDR_WIDTH_BIT - 1;

    logic [CACHE_SET_ADDR_WIDTH_BIT  - 1 : 0] _cache_data_addr_set;
    logic                                     _cache_data_addr_block;
    logic [CACHE_DATA_ADDR_WIDTH_BIT - 1 : 0] _cache_data_addr_byte;

    assign _cache_data_i_addr = {{CACHE_INTERNAL_DATA_ADDR_WIDTH_BIT{1'b0}}, 
                                _cache_data_addr_set, _cache_data_addr_block, _cache_data_addr_byte};

    BRAMArray32Bits #(
        .SIZE_BYTE(CACHE_O_CAPACITY_BYTE)
    ) _cache_data (
        .i_clk      (i_clk),
        .i_addr     (_cache_data_i_addr),
        .i_en       (_cache_data_i_en),
        .i_we       (_cache_data_i_we),
        .i_mask_type(_cache_data_i_mask),
        .i_data     (_cache_data_i_data),
        .o_data     (_cache_data_o_data),
        .o_ack      (_cache_data_o_ack),
        .o_err      (_cache_data_o_err)
    );

    // Full signal
    genvar i, j;
    generate
        for (i = 0; i < CACHE_N_SET; i++) begin
            assign _cache_metadata_set_full_bit[i] = _cache_metadata_valid_bit[i][0] &
                                                        _cache_metadata_valid_bit[i][1];
        end
    endgenerate

    // ==================================================================================
    // Addr decomposition
    logic [CACHE_TAG_WIDTH_BIT        - 1 : 0]  i_m_tag;
    logic [CACHE_SET_ADDR_WIDTH_BIT   - 1 : 0]  i_m_addr_set;
    logic [CACHE_DWORD_ADDR_WIDTH_BIT - 1 : 0]  i_m_addr_word;
    logic [1:0]                                 i_m_addr_byte;
    assign {i_m_tag, i_m_addr_set, i_m_addr_word, i_m_addr_byte} = i_m_addr;

    // ==================================================================================
    // Signals from inputs

    // Cache hit signals, 2 ways
    // Case of ~hit will need to & with i_m_en to confirm that enable is high
    logic  i_hit, i_hit0, i_hit1;
    assign i_hit  = i_hit0 | i_hit1;
    // Hit for a given way: valid & tag matches
    assign i_hit1 = _cache_metadata_valid_bit[i_m_addr_set][1] &
                    (i_m_tag == _cache_metadata_tag[i_m_addr_set][1]);
    assign i_hit0 = _cache_metadata_valid_bit[i_m_addr_set][0] &
                    (i_m_tag == _cache_metadata_tag[i_m_addr_set][0]);
    
    // LRU
    logic  i_lru;
    assign i_lru = _cache_metadata_set_LRU_bit[i_m_addr_set];

    // ==================================================================================
    // STATE MACHINE
    typedef enum logic [2:0] {   // Wait for request
                                STATE_IDLE, // 000                    
                                // Error on R/W external bus landed here
                                STATE_ERR, // 001
                                // ==============================
                                // Hit states
                                STATE_HIT_WAIT_CACHE_IO, // 010
                                // Need to stall for 1 extra cycle before set state back to idle,
                                // Else this will relatch the old request before the CPU handle it,
                                // repeating the request
                                STATE_HIT_WAIT_CPU, // 011
                                // ==============================
                                // Miss states
                                // Read new data from slave bus for cache insertion,
                                // and also old cache data for eject write if full;
                                STATE_MISS_WAIT_DATA_READ, // 100
                                STATE_MISS_WAIT_DATA_WRITE // 101
                            } _state_t;
    _state_t _state;

    always_ff @(posedge i_clk) begin : state_machine
        if (~i_rst) begin
            _state <= STATE_IDLE;
        end
        else begin
            case (_state)
                STATE_IDLE: begin
                    if (i_m_en) begin
                        if (i_hit) begin
                            _state <= STATE_HIT_WAIT_CACHE_IO;
                        end
                        // Need to & with i_m_en to confirm that enable is high
                        else begin
                            _state <= STATE_MISS_WAIT_DATA_READ;
                        end
                    end
                end
                STATE_ERR: begin
                    /* Do nothing, TODO? */
                end
                // ==============================
                // Hit sub-state-machine entry
                STATE_HIT_WAIT_CACHE_IO: begin
                    if (_cache_data_o_ack) begin
                        _state <= STATE_HIT_WAIT_CPU;
                    end
                end
                STATE_HIT_WAIT_CPU: begin
                    _state <= STATE_IDLE;
                end
                // ==============================
                // Miss sub-state-machine entry
                // Need to fetch (and replace) data in cache
                STATE_MISS_WAIT_DATA_READ: begin
                    // Don't need to wait for cache mem read since there is no way
                    // read from main periph bus (wishbone) is faster than 1 cycle (right?)
                    if (i_s_ack) begin
                        _state <= STATE_MISS_WAIT_DATA_WRITE;
                    end
                    else if (i_s_err) begin
                        _state <= STATE_ERR;
                    end
                end
                STATE_MISS_WAIT_DATA_WRITE: begin
                    // If full & dirty then wait for ext mem write
                    // else just wait for cache mem to update
                    // Again don't need to wait for cache write since there is no way
                    // wishbone write can be finished in 1 cycle (right?)
                    if (_miss_write_done) begin
                        // check counter
                        if (_miss_cache_block_fetch_done) begin
                            _state <= STATE_HIT_WAIT_CACHE_IO;
                        end
                        else begin
                            _state <= STATE_MISS_WAIT_DATA_READ;
                        end
                    end
                    else if (i_s_err) begin
                        _state <= STATE_ERR;
                    end
                end
            endcase
        end
    end

    // ==================================================================================
    // Latching_request
    logic        _m_en, _m_we;
    logic [31:0] _m_addr, _m_data;
    logic [1:0]  _m_mask_type;
    logic        _hit, _hit1;
    logic        _lru;

    always_ff @(posedge i_clk) begin : latch_request
        if (~i_rst) begin
            _m_en        <= 1'b0;
            _m_we        <= 1'b0;
            _m_addr      <= 32'h0;
            _m_data      <= 32'h0;
            _m_mask_type <= 2'b0;
            _hit         <= 1'b0;
            _hit1        <= 1'b0;
            _lru         <= 1'b0;
        end
        else begin
            case (_state)
                STATE_IDLE: begin
                    if (i_m_en) begin
                        _m_en        <= i_m_en;
                        _m_we        <= i_m_we;
                        _m_addr      <= i_m_addr;
                        _m_data      <= i_m_data;
                        _m_mask_type <= i_m_mask_type;
                        _hit         <= i_hit;
                        _hit1        <= i_hit1;
                        _lru         <= i_lru;
                    end
                end
            endcase
        end
    end

    // Addr decomposition
    logic [CACHE_TAG_WIDTH_BIT        - 1 : 0]  _m_tag;
    logic [CACHE_SET_ADDR_WIDTH_BIT   - 1 : 0]  _m_addr_set;
    logic [CACHE_DWORD_ADDR_WIDTH_BIT - 1 : 0]  _m_addr_word;
    logic [1:0]                                 _m_addr_byte;
    assign {_m_tag, _m_addr_set, _m_addr_word, _m_addr_byte} = _m_addr;

    // ==================================================================================
    // Signals with latched input

    logic _full_and_dirty;
    logic _miss_write_done;

    assign _full_and_dirty = _cache_metadata_set_full_bit[_m_addr_set] &
                             _cache_metadata_dirty_bit[_m_addr_set][_lru];

    assign _miss_write_done = _full_and_dirty ? i_s_ack : _cache_data_o_ack;
    
    // ==================================================================================
    // OUTPUT to cache memory 
    always_ff @(posedge i_clk) begin : cache_backing_mem_input
        if (~i_rst) begin
            _cache_data_i_en <= 1'b0;
        end
        else begin
            case (_state)
                // If hit then setup the input right away
                STATE_IDLE: begin
                    if (i_m_en) begin
                        if (i_hit) begin
                            _cache_data_addr_set   <= i_m_addr_set;
                            _cache_data_addr_block <= i_hit1;
                            _cache_data_addr_byte  <= {i_m_addr_word, i_m_addr_byte};
                            _cache_data_i_en       <= 1'b1;
                            _cache_data_i_we       <= i_m_we;
                            _cache_data_i_mask     <= i_m_mask_type;
                            _cache_data_i_data     <= i_m_data;
                        end
                        else begin
                            // For the case cache is full and need to eject old data (dirty), read old block data, started at 0
                            // if not full then only have to wait for external memory
                            // Technically we check for full and dirty here but since getting data from cache is short 
                            // we hit it any way, less comb logic.
                            _cache_data_addr_set   <= i_m_addr_set;
                            _cache_data_addr_block <= i_lru;
                            _cache_data_addr_byte  <= 'h0;
                            _cache_data_i_en       <= 1'b1;
                            _cache_data_i_we       <= 1'b0;  // read first
                            _cache_data_i_mask     <= 2'b10; // dword
                        end
                    end
                end
                // Entry to hit states
                STATE_HIT_WAIT_CACHE_IO: begin
                    // en to 0, result should be ready on next cycle
                    _cache_data_i_en       <= 1'b0;
                end
                // Entry to miss states
                STATE_MISS_WAIT_DATA_READ: begin
                    // Need to sync condition with state machine else request might hold for multiple cycle
                    if (i_s_ack) begin
                        // Write new data to previous read position in cache mem
                        _cache_data_addr_set   <= _m_addr_set;
                        _cache_data_addr_block <= _lru;
                        _cache_data_addr_byte  <= _cache_miss_dword_addr_counter_mul4;
                        _cache_data_i_en       <= 1'b1;
                        _cache_data_i_we       <= 1'b1;  // write after read
                        _cache_data_i_mask     <= 2'b10; // dword
                        _cache_data_i_data     <= i_s_data;
                    end
                    else begin
                        // Enable for only 1 cycle after request issued from IDLE to READ request ack
                        _cache_data_i_en       <= 1'b0;
                    end
                end
                STATE_MISS_WAIT_DATA_WRITE: begin
                    if (_miss_write_done) begin
                        // check counter
                        // considered a hit
                        if (_miss_cache_block_fetch_done) begin
                            _cache_data_addr_set   <= _m_addr_set;
                            _cache_data_addr_block <= _lru;
                            _cache_data_addr_byte  <= {_m_addr_word, _m_addr_byte};
                            _cache_data_i_en       <= 1'b1;
                            _cache_data_i_we       <= _m_we;
                            _cache_data_i_mask     <= _m_mask_type;
                            _cache_data_i_data     <= _m_data;
                        end
                        else begin
                            // Loop for another read
                            _cache_data_addr_set   <= _m_addr_set;
                            _cache_data_addr_block <= _lru;
                            _cache_data_addr_byte  <= _cache_miss_dword_addr_counter_mul4; // addr already added
                            _cache_data_i_en       <= 1'b1;
                            _cache_data_i_we       <= 1'b0;  // read after write
                            _cache_data_i_mask     <= 2'b10; // dword
                        end
                    end
                    else begin
                        _cache_data_i_en       <= 1'b0;
                    end
                end
            endcase
        end
    end

    // ==================================================================================
    // Cache miss addr counter

    // Fix for early fetch end bug:
    // Because counter get set during wait read -> wait write state to prepare for next read
    // if write state only check for highest bit of counter + 1 the state will change to hit
    // without read / write the last dword
    logic  _miss_cache_block_fetch_done;

    logic [CACHE_DWORD_ADDR_WIDTH_BIT - 1 : 0] _cache_miss_dword_addr_counter;
    logic [CACHE_DWORD_ADDR_WIDTH_BIT     : 0] _cache_miss_dword_addr_counter_p1;
    logic [CACHE_DWORD_ADDR_WIDTH_BIT + 1 : 0] _cache_miss_dword_addr_counter_mul4;

    assign _cache_miss_dword_addr_counter_p1   = _cache_miss_dword_addr_counter + 1;
    assign _cache_miss_dword_addr_counter_mul4 = {_cache_miss_dword_addr_counter, 2'b00};

    always_ff @(posedge i_clk) begin : cache_miss_addr_counter
        if (~i_rst) begin
            _cache_miss_dword_addr_counter <=  'h0;
            _miss_cache_block_fetch_done   <= 1'b0;
        end
        else begin
            case (_state)
                STATE_IDLE: begin
                    if (i_m_en) begin
                        _cache_miss_dword_addr_counter <=  'h0;
                        _miss_cache_block_fetch_done   <= 1'b0;
                    end
                end
                // CHANGE FROM READ STATE, NOT WRITE.
                // Because read state is where last count in that loop is used
                STATE_MISS_WAIT_DATA_READ : begin
                    if (i_s_ack) begin
                        if (_cache_miss_dword_addr_counter_p1[CACHE_DWORD_ADDR_WIDTH_BIT]) begin
                            // final write up next
                            _miss_cache_block_fetch_done <= 1'b1;
                        end
                        else begin
                            _cache_miss_dword_addr_counter <= _cache_miss_dword_addr_counter_p1[CACHE_DWORD_ADDR_WIDTH_BIT - 1 : 0];
                        end
                    end
                end
            endcase
        end
    end

    // ==================================================================================
    // OUTPUT to slave bus 
    always_ff @(posedge i_clk) begin : cache_slave_bus_mem_output
        if (~i_rst) begin
            o_s_en        <= 'h0;
            o_s_we        <= 'h0;
            o_s_addr      <= 'h0;
            o_s_data      <= 'h0;
            o_s_mask_type <= 'h0;
        end
        else begin
            case (_state)
                STATE_IDLE: begin
                    if (i_m_en) begin
                        if (~i_hit) begin
                            o_s_en        <= 1'b1;
                            o_s_we        <= 1'b0; // Need to read new data into cache first
                            // need to read whole block, started at block addr 0
                            // _cache_miss_dword_addr_counter is not available yet at this cycle -> use 0
                            o_s_addr      <= {i_m_tag, i_m_addr_set, {CACHE_DATA_ADDR_WIDTH_BIT{1'b0}}};
                            // o_s_data      <= i_m_data;
                            o_s_mask_type <= 2'b10; // read dword
                        end
                    end
                end
                STATE_MISS_WAIT_DATA_READ: begin
                    // Ack received, prepare for next state, writing old data if needed
                    if (i_s_ack) begin
                        if (_full_and_dirty) begin
                            o_s_en        <= 1'b1;
                            o_s_we        <= 1'b1;
                            o_s_mask_type <= 2'b10; // write dword
                            // Old data addr and value
                            o_s_addr      <= {  _cache_metadata_tag[_m_addr_set][_lru],
                                                _m_addr_set,
                                                _cache_miss_dword_addr_counter_mul4
                                            };
                            o_s_data      <= _miss_old_data_cache;
                        end
                    end
                    // En need to go down after IDLE
                    // After ack state will change out of this state
                    else begin
                        // Enable for only 1 cycle after request issued from IDLE ack
                        o_s_en <= 1'b0;
                    end
                end
                STATE_MISS_WAIT_DATA_WRITE: begin
                    if (_miss_write_done) begin
                        // check counter
                        if (~_miss_cache_block_fetch_done) begin
                            o_s_en        <= 1'b1;
                            o_s_we        <= 1'b0; // Need to read new data into cache first
                            o_s_addr      <= {_m_tag, _m_addr_set, _cache_miss_dword_addr_counter_mul4}; // already added
                            o_s_mask_type <= 2'b10; // read dword
                        end
                    end
                    else begin
                        o_s_en <= 1'b0;
                    end
                end
            endcase
        end
    end

    // ==================================================================================
    // INPUT from cache mem + slave bus
    // Store old and new data after a cache miss
    // TODO REMOVE UNUSED
    logic [31:0] _miss_new_data_ext;
    logic [31:0] _miss_old_data_cache;
    // Flags - STATE_MISS_WAIT_DATA_READ
    logic _flag_miss_data_read_ext;
    logic _flag_miss_data_read_cache;
    // Flags - STATE_MISS_WAIT_DATA_WRITE
    logic _flag_miss_data_write_ext;
    logic _flag_miss_data_write_cache;

    always_ff @(posedge i_clk) begin : cache_slave_bus_mem_input
        if (~i_rst) begin
            _flag_miss_data_read_ext    <= 1'b0;
            _flag_miss_data_read_cache  <= 1'b0;
            _flag_miss_data_write_ext   <= 1'b0;
            _flag_miss_data_write_cache <= 1'b0;
        end
        else begin
            case (_state)
                STATE_MISS_WAIT_DATA_READ: begin
                    _flag_miss_data_write_ext   <= 1'b0;
                    _flag_miss_data_write_cache <= 1'b0;
                    // Read new data
                    if (i_s_ack) begin
                        _miss_new_data_ext       <= i_s_data; // always read in fetch state
                        _flag_miss_data_read_ext <= 1'b1;
                    end
                    // Read old data
                    if (_full_and_dirty) begin 
                        if (_cache_data_o_ack) begin // ack
                            _flag_miss_data_read_cache <= 1'b1;
                            _miss_old_data_cache       <= _cache_data_o_data;
                        end
                    end
                end
                STATE_MISS_WAIT_DATA_WRITE: begin
                    _flag_miss_data_read_ext   <= 1'b0;
                    _flag_miss_data_read_cache <= 1'b0;
                    // Write old data to ext mem
                    if (_full_and_dirty & i_s_ack) begin 
                        _flag_miss_data_write_ext <= 1'b1;
                    end
                    // Write new data to cache mem
                    if (_cache_data_o_ack) begin
                        _flag_miss_data_write_cache <= 1'b1;
                    end
                end
            endcase
        end
    end

    // ==================================================================================
    // Set valid metadata flag
    // On block fetch done
    always_ff @(posedge i_clk) begin : set_valid
        if (~i_rst) begin
            for (int i = 0; i < CACHE_N_SET; i++) begin
                for (int j = 0; j < CACHE_BLOCK_PER_SET; j++ ) begin
                    _cache_metadata_valid_bit[i][j] <= 1'b0;
                end
            end
        end
        else begin
            case (_state)
                STATE_MISS_WAIT_DATA_WRITE: begin
                    if (_miss_write_done) begin
                        // check counter
                        if (_miss_cache_block_fetch_done) begin
                            _cache_metadata_valid_bit[_m_addr_set][_lru] <= 1'b1;
                        end
                    end
                end
            endcase
        end
    end

    // ==================================================================================
    // Set dirty metadata flag
    // dirty flag changes when:
    //  - hit write -> 1
    //  - miss fetch -> 0
    always_ff @(posedge i_clk) begin : set_cache_metadata_dirty
        if (~i_rst) begin
            for (int i = 0; i < CACHE_N_SET; i++) begin
                for (int j = 0; j < CACHE_BLOCK_PER_SET; j++ ) begin
                    _cache_metadata_dirty_bit[i][j] <= 1'b0;
                end
            end
        end
        else begin
            case (_state)
                STATE_IDLE: begin
                    if (i_m_en) begin
                        if (i_hit) begin
                            if (i_m_we) begin
                                _cache_metadata_dirty_bit[i_m_addr_set][i_hit1] <= 1'b1;
                            end
                        end
                    end
                end
                STATE_MISS_WAIT_DATA_WRITE: begin
                    if (_miss_write_done) begin
                        // check counter
                        if (_miss_cache_block_fetch_done) begin
                            _cache_metadata_dirty_bit[_m_addr_set][_lru] <= 1'b0;
                        end
                    end
                end
            endcase
        end
    end

    // ==================================================================================
    // Set tag metadata
    // On block fetch done
    // Does not need rst
    always_ff @(posedge i_clk) begin : set_tag
        case (_state)
            STATE_MISS_WAIT_DATA_WRITE: begin
                if (_miss_write_done) begin
                    // check counter
                    if (_miss_cache_block_fetch_done) begin
                        _cache_metadata_tag[_m_addr_set][_lru] <= _m_tag;
                    end
                end
            end
        endcase
    end

    // ==================================================================================
    // Set LRU metadata flag
    // LRU -> ~LRU when:
    //  - hit (on idle)
    //  - miss fetch done
    always_ff @(posedge i_clk) begin : set_cache_metadata_used_way
        if (~i_rst) begin
            for (int i = 0; i < CACHE_N_SET; i++) begin
                _cache_metadata_set_LRU_bit[i] <= 1'b0;
            end
        end
        else begin
            case (_state)
                STATE_IDLE: begin
                    if (i_m_en) begin
                        if (i_hit) begin
                            _cache_metadata_set_LRU_bit[i_m_addr_set] <= ~_cache_metadata_set_LRU_bit[i_m_addr_set];
                        end
                    end
                end
                STATE_MISS_WAIT_DATA_WRITE: begin
                    if (_miss_write_done) begin
                        // check counter
                        if (_miss_cache_block_fetch_done) begin
                            _cache_metadata_set_LRU_bit[_m_addr_set] <= ~_cache_metadata_set_LRU_bit[_m_addr_set];
                        end
                    end
                end
            endcase
        end
    end

    // ==================================================================================
    // OUTPUT to master
    always_ff @(posedge i_clk) begin : master_bus_output
        if (~i_rst) begin
            o_m_ack  <= 1'b0;
            o_m_err  <= 1'b0;
            o_m_data <= 'h0;
        end
        else begin
            case (_state)
                STATE_MISS_WAIT_DATA_READ: begin
                    if (i_s_err) begin
                        o_m_err <= 1'b1;
                    end
                end
                STATE_MISS_WAIT_DATA_WRITE: begin
                    if (i_s_err) begin
                        o_m_err <= 1'b1;
                    end
                end
                STATE_HIT_WAIT_CACHE_IO: begin
                    if (_cache_data_o_ack) begin
                        o_m_ack  <= 1'b1;
                        o_m_data <= _cache_data_o_data;
                    end
                end
                STATE_HIT_WAIT_CPU: begin
                    o_m_ack  <= 1'b0;
                end
            endcase
        end
    end

endmodule
