`include "srcs/rtl/include/config.svh"

/* Memory bus interface - slave:
 *  i_clk         : ...
 *  i_rst         : ...
 *  i_en          : High during a memory request / enable
 *  i_we          : Write enable
 *  i_addr        : Access address
 *  i_wd          : Input data
 *  i_mask_type   : Output data mask mode (byte - 8, short - 16, word - 32)
 *  o_ack         : High when request done (data written or read data available)
 *  o_err         : Operation error like write to read-only mem, ... Not when access unsupported address
 *                  (_acc_en signal inside slave ensure that)
 *  o_rd          : Data output
 */

// This module act as interconnect between all memory components

/* NOTE ON CACHE OUTPUT COUPLING PROBLEM:
 * - Before the cache were introduced, slave modules within the mem stage return their output directly to the CPU's
 *   pipeline (data, ack, err). This ensure the pipeline gets it data as soon as the slaves return, sync it state with
 *   the slaves state. If somehow the ack from a slave does not reach the pipeline before the slave itself become
 *   available. Given that until receiving ack, the pipeline request line remain high, this lead to repeating requests...
 * - Now if the cache were to introduce delay to the way slave ack return to pipeline. The problem must be addressed by
 *   sync the output within the cache state machine itself and not accepting new request before giving out ack.
 *   So as far as the pipeline is concerned, nothing has changed.
 */

module DataMemStageBlock (
    input  logic        i_clk,
    input  logic        i_rst,
    //From control
    input  logic        i_req,
    input  logic        i_we,
    input  logic [1:0]  i_mask_type,
    input  logic        i_ext_type,
    // From exec
    input  logic [31:0] i_memory_address,
    input  logic [31:0] i_memory_data,
    // To Writeback
    output logic [31:0] o_memory_readout,
    // To Hazard
    // Ack when data is ready in read mode, or being writen in wire mode, not when request is accepted
    // Needed for stalling arbitrary cycle, currently if invalid address stall indefinitely
    output logic        o_memory_ack,
    // Not know what to do yet
    output logic        o_memory_err,
    // Connect to instr mem port 2
    output logic        o_rom_p2_clk,
    output logic        o_rom_p2_en,
    output logic [31:0] o_rom_p2_addr,
    input  logic [31:0] i_rom_p2_rd
`ifndef BRAM_AS_RAM
    ,
    input  logic        i_ram_clk,
    // Connect to SDRAM, passthrough
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
`endif /* BRAM_AS_RAM */
`ifdef GPIO_EN
    ,
    // input  logic [7:0]  i_gpio [`GPIO_SIZE_BYTE - 1:0],
    // output logic [7:0]  o_gpio [`GPIO_SIZE_BYTE - 1:0]
    input  logic [`GPIO_SIZE - 1:0] i_gpio,
    output logic [`GPIO_SIZE - 1:0] o_gpio
`endif
`ifdef HDMI_EN
    ,
    input  logic        i_hdmi_pixel_clk,
    input  logic        i_hdmi_tmds_clk,
    output logic [3:0]  o_hdmi_gpdi_dp, 
    output logic [3:0]  o_hdmi_gpdi_dn
`endif
);

`ifdef DCACHE_EN
    // DCACHE
    // ==================================================================================
    // Split input into 2 type of access: cacheable(RAM...) and non-cacheable(GPIO...)
    // Cacheable signal: _cachable_access  

    // Memstage-cache
    logic        _mem_cache_en;
    logic        _mem_cache_we;
    logic [31:0] _mem_cache_addr;
    logic [31:0] _mem_cache_data;
    logic [1:0]  _mem_cache_mask;
    // These will be muxed with output from WB master to mem
    logic        _cache_mem_ack;
    logic        _cache_mem_err;
    logic [31:0] _cache_mem_data;

    // Cache-bus
    logic        _cache_wb_en;
    logic        _cache_wb_we;
    logic [31:0] _cache_wb_addr;
    logic [31:0] _cache_wb_data;
    logic [1:0]  _cache_wb_mask;
    // From wb master output
    logic        _wb_cache_ack;
    logic        _wb_cache_err;
    logic [31:0] _wb_cache_data;

    // Assigns cache inputs
    // From mem stage
    assign _mem_cache_en   = _cachable_access ? i_req : 1'b0;
    assign _mem_cache_we   = i_we;
    assign _mem_cache_addr = i_memory_address;
    assign _mem_cache_data = i_memory_data;
    assign _mem_cache_mask = i_mask_type;
    // From WB master
    assign _wb_cache_ack   = _wbmaster_mem_o_ack;
    assign _wb_cache_err   = _wbmaster_mem_o_err;
    assign _wb_cache_data  = _wbmaster_mem_o_rd;

    TwoWaysCache32Bits #(
        .CACHE_O_CAPACITY_BYTE(`DCACHE_CAPACITY),
        .CACHE_O_BLOCK_SIZE_BYTE(`DCACHE_BLOCK_SIZE)
    ) dataCache (
        .i_clk        (i_clk),
        .i_rst        (i_rst),
        // Iface connected to memstage
        .i_m_en       (_mem_cache_en),
        .i_m_we       (_mem_cache_we),
        .i_m_addr     (_mem_cache_addr),
        .i_m_data     (_mem_cache_data),
        .i_m_mask_type(_mem_cache_mask),
        .o_m_ack      (_cache_mem_ack),
        .o_m_err      (_cache_mem_err),
        .o_m_data     (_cache_mem_data),
        // Memory interface with WB bus
        .o_s_en       (_cache_wb_en),
        .o_s_we       (_cache_wb_we),
        .o_s_addr     (_cache_wb_addr),
        .o_s_data     (_cache_wb_data),
        .o_s_mask_type(_cache_wb_mask),
        .i_s_ack      (_wb_cache_ack),
        .i_s_err      (_wb_cache_err),
        .i_s_data     (_wb_cache_data)
    ); 
`endif

    // WISHBONE MASTER
    // ==================================================================================
    // Memory bus master wishbone IOs
    // wishbone bus <-> memstage

    // WB master iface to arbiter
    logic [31:0] _wbmaster_wb_i_data;
    logic        _wbmaster_wb_i_stall;
    logic        _wbmaster_wb_i_ack;
    logic        _wbmaster_wb_i_err;
    logic [3:0]  _wbmaster_wb_o_sel;
    logic [31:0] _wbmaster_wb_o_addr;
    logic [31:0] _wbmaster_wb_o_data;
    logic        _wbmaster_wb_o_cyc;
    logic        _wbmaster_wb_o_stb;
    logic        _wbmaster_wb_o_we;
    // WB master iface to mem stage & cache
    // Inputs are cache outputs muxed with direct mem stage inputs
    logic        _wbmaster_mem_i_en;
    logic        _wbmaster_mem_i_we;
    logic [31:0] _wbmaster_mem_i_mem_addr;
    logic [31:0] _wbmaster_mem_i_wd;
    logic [1:0]  _wbmaster_mem_i_mask_type;
    logic        _wbmaster_mem_o_ack;
    logic        _wbmaster_mem_o_err;
    logic [31:0] _wbmaster_mem_o_rd;

    // Outputs out of mem stage
    logic        _mem_op_ack;
    // Wishbone master error signal will be or-ed with other access signals to indicate
    // valid access request, else set error output for mem stage high
    logic        _mem_op_err;
    // Readout is used for extension
    logic [31:0] _mem_op_readout;

    // Assigns
    always_comb begin : wb_master_input_mux
`ifdef DCACHE_EN
        if (_cachable_access) begin
            _wbmaster_mem_i_en        = _cache_wb_en;
            _wbmaster_mem_i_we        = _cache_wb_we;
            _wbmaster_mem_i_mem_addr  = _cache_wb_addr;
            _wbmaster_mem_i_wd        = _cache_wb_data;
            _wbmaster_mem_i_mask_type = _cache_wb_mask;
        end
        else 
`endif
        begin
            _wbmaster_mem_i_en        = i_req;
            _wbmaster_mem_i_we        = i_we;
            _wbmaster_mem_i_mem_addr  = i_memory_address;
            _wbmaster_mem_i_wd        = i_memory_data;
            _wbmaster_mem_i_mask_type = i_mask_type;
        end
    end

    always_comb begin : mem_stage_output_mux
`ifdef DCACHE_EN
        if (_cachable_access) begin
            _mem_op_ack     = _cache_mem_ack;
            _mem_op_err     = _cache_mem_err;
            _mem_op_readout = _cache_mem_data;
        end
        else
`endif
        begin
            _mem_op_ack     = _wbmaster_mem_o_ack;
            _mem_op_err     = _wbmaster_mem_o_err;
            _mem_op_readout = _wbmaster_mem_o_rd;
        end
    end

    // Memory bus master
    DataMemWBMaster dataMemWBMaster(
        .i_clk          (i_clk),
        .i_rst          (i_rst),
        // WB IOs
        .o_wb_cyc       (_wbmaster_wb_o_cyc),
        .o_wb_stb       (_wbmaster_wb_o_stb),
        .o_wb_sel       (_wbmaster_wb_o_sel),
        .o_wb_addr      (_wbmaster_wb_o_addr),
        .o_wb_data      (_wbmaster_wb_o_data),
        .o_wb_we        (_wbmaster_wb_o_we),
        .i_wb_data      (_wbmaster_wb_i_data),
        .i_wb_stall     (_wbmaster_wb_i_stall),
        .i_wb_ack       (_wbmaster_wb_i_ack),
        .i_wb_err       (_wbmaster_wb_i_err),
        // CPU interface
        .i_mem_en       (_wbmaster_mem_i_en),
        .i_mem_we       (_wbmaster_mem_i_we),
        .i_mem_addr     (_wbmaster_mem_i_mem_addr),
        .i_mem_wd       (_wbmaster_mem_i_wd),
        .i_mem_mask_type(_wbmaster_mem_i_mask_type),
        .o_mem_ack      (_wbmaster_mem_o_ack),
        .o_mem_err      (_wbmaster_mem_o_err),
        .o_mem_rd       (_wbmaster_mem_o_rd)  
    );

    // WISHBONE MASTER ARBITER
    // ==================================================================================
    // Wishbone arbiter interface
    // Scale up the master's signals to support more masters
    // The lowest signal range is prioritised, should reserve for CPU bus master
    // Master
	logic [63:0] _arb_master_data;
	logic [1:0]  _arb_master_stall;
	logic [1:0]  _arb_master_ack;
	logic [1:0]  _arb_master_err;
	logic [7:0]  _master_arb_sel;
	logic [63:0] _master_arb_addr;
	logic [63:0] _master_arb_data;
	logic [1:0]  _master_arb_cyc;
	logic [1:0]  _master_arb_stb;
	logic [1:0]  _master_arb_we;
    // Slave
	logic        _arb_slave_cyc;
	logic        _arb_slave_stb;
	logic        _arb_slave_we;
	logic [31:0] _arb_slave_addr;
	logic [31:0] _arb_slave_data;
	logic [3:0]  _arb_slave_sel;
    logic [31:0] _slave_arb_data;
	logic        _slave_arb_stall;
	logic        _slave_arb_ack;
	logic        _slave_arb_err;
    
    logic [31:0] unused32_0;
    logic unused1_0, unused1_1, unused1_2;

	// Master interface assign
    // Add more master line here if needed
	assign {unused32_0, _wbmaster_wb_i_data} = _arb_master_data;
	assign {unused1_0, _wbmaster_wb_i_stall} = _arb_master_stall;
	assign {unused1_1, _wbmaster_wb_i_ack}   = _arb_master_ack;
	assign {unused1_2, _wbmaster_wb_i_err}   = _arb_master_err;
	assign _master_arb_sel  = {4'b0,  _wbmaster_wb_o_sel};
	assign _master_arb_addr = {32'b0, _wbmaster_wb_o_addr};
	assign _master_arb_data = {32'b0, _wbmaster_wb_o_data};
	assign _master_arb_cyc  = {1'b0,  _wbmaster_wb_o_cyc};
	assign _master_arb_stb  = {1'b0,  _wbmaster_wb_o_stb};
	assign _master_arb_we   = {1'b0,  _wbmaster_wb_o_we};
    
    // Slave signal coming to arbiter must be or-ed here
    // Non active slave must output 0
    always_comb begin : slave_out
        _slave_arb_data  = _ROM_o_data  | _RAM_o_data; // | gpio...
        _slave_arb_stall = _ROM_o_stall | _RAM_o_stall;
        _slave_arb_ack   = _ROM_o_ack   | _RAM_o_ack;
        _slave_arb_err   = _ROM_o_err   | _RAM_o_err;
`ifdef BRAM_EN
        _slave_arb_data  = _slave_arb_data  | _BRAM_o_data;
        _slave_arb_stall = _slave_arb_stall | _BRAM_o_stall;
        _slave_arb_ack   = _slave_arb_ack   | _BRAM_o_ack;
        _slave_arb_err   = _slave_arb_err   | _BRAM_o_err;
`endif
`ifdef GPIO_EN
        _slave_arb_data  = _slave_arb_data  | _GPIO_o_data;
        _slave_arb_stall = _slave_arb_stall | _GPIO_o_stall;
        _slave_arb_ack   = _slave_arb_ack   | _GPIO_o_ack;
        _slave_arb_err   = _slave_arb_err   | _GPIO_o_err;
`endif
`ifdef HDMI_EN
        _slave_arb_data  = _slave_arb_data  | _HDMI_o_data;
        _slave_arb_stall = _slave_arb_stall | _HDMI_o_stall;
        _slave_arb_ack   = _slave_arb_ack   | _HDMI_o_ack;
        _slave_arb_err   = _slave_arb_err   | _HDMI_o_err;
`endif
    end

    // Bus arbiter
    DataMemWBArbiter #(
		.MASTER_COUNT(2) // 2 minimum
    ) dataMemWBArbiter(
		.i_clk(i_clk),
		.i_rst(i_rst),
		// Masters
		.i_m_cyc  (_master_arb_cyc),
		.i_m_stb  (_master_arb_stb),
		.i_m_we   (_master_arb_we),
		.i_m_addr (_master_arb_addr),
		.i_m_data (_master_arb_data),
		.i_m_sel  (_master_arb_sel),
		.o_m_data (_arb_master_data),
		.o_m_stall(_arb_master_stall),
		.o_m_ack  (_arb_master_ack),
		.o_m_err  (_arb_master_err),
		// Slaves
		.o_s_cyc  (_arb_slave_cyc),
		.o_s_stb  (_arb_slave_stb),
		.o_s_we   (_arb_slave_we),
		.o_s_addr (_arb_slave_addr),
		.o_s_data (_arb_slave_data),
		.o_s_sel  (_arb_slave_sel),
		.i_s_data (_slave_arb_data),
		.i_s_stall(_slave_arb_stall),
		.i_s_ack  (_slave_arb_ack),
		.i_s_err  (_slave_arb_err)
	);

    // WB SLAVES
    // ==================================================================================
    // Addressing scheme:
    // Pass full address to module (include address partition)
    // The module will do the extraction of real address, discarding partition part

`ifdef DCACHE_EN
    // =======================================
    // Cachable signal
    logic  _cachable_access;
    always_comb begin : cacheable_access
        _cachable_access = _rom_addr_access | _ram_addr_access;
    `ifdef BRAM_EN
        _cachable_access = _cachable_access | _bram_addr_access;
    `endif
    end
`endif

    // =======================================
    // ROM
    logic _rom_addr_access;
    localparam ROMADDRWIDTH = $clog2(`ROM_SIZE - 1);
    localparam ROMSTARTADDR = `ROM_START_ADDR;
    // Should check upper bound too
    assign _rom_addr_access = ((i_memory_address[31:ROMADDRWIDTH] == ROMSTARTADDR[31:ROMADDRWIDTH]) ? 1 : 0);

    // ROM wishbone IOs
    logic        _ROM_i_cyc;
    logic        _ROM_i_stb;
    logic        _ROM_o_ack;
    logic        _ROM_o_err;
    logic        _ROM_o_stall;
    logic [31:0] _ROM_o_data;

    assign _ROM_i_cyc = _rom_addr_access & _arb_slave_cyc;
    assign _ROM_i_stb = _rom_addr_access & _arb_slave_stb;

    ROMWB #(
        .SIZE_BYTE(`ROM_SIZE),
        .START_ADDR(`ROM_START_ADDR)
    ) ROM (
        .i_clk(i_clk),
        .i_cyc(_ROM_i_cyc),
        .i_stb(_ROM_i_stb),
        .i_addr(_arb_slave_addr),
        .i_we(_arb_slave_we),
        .i_sel(_arb_slave_sel),
        .o_ack(_ROM_o_ack),
        .o_err(_ROM_o_err),
        .o_data(_ROM_o_data),
        .o_stall(_ROM_o_stall),
        .o_rom_clk(o_rom_p2_clk),
        .o_rom_en(o_rom_p2_en),
        .o_rom_addr(o_rom_p2_addr),
        .i_rom_rd(i_rom_p2_rd)
    );

    // =======================================
    // RAM
    logic _ram_addr_access;
    localparam RAMADDRWIDTH = $clog2(`RAM_SIZE - 1);
    localparam RAMSTARTADDR = `RAM_START_ADDR;
    // Should check upper bound too
    assign _ram_addr_access = ((i_memory_address[31:RAMADDRWIDTH] == RAMSTARTADDR[31:RAMADDRWIDTH]) ? 1 : 0);

    // RAM wishbone IOs
    logic        _RAM_i_cyc;
    logic        _RAM_i_stb;
    logic        _RAM_o_ack;
    logic        _RAM_o_err;
    logic        _RAM_o_stall;
    logic [31:0] _RAM_o_data;

    assign _RAM_i_cyc = _ram_addr_access & _arb_slave_cyc;
    assign _RAM_i_stb = _ram_addr_access & _arb_slave_stb;

`ifdef BRAM_AS_RAM
    BRAMWB #(
		.SIZE_BYTE (`RAM_SIZE),
		.START_ADDR(`RAM_START_ADDR)
	) RAM_BRAMWB (
		.i_clk  (i_clk),
		.i_cyc  (_RAM_i_cyc),
		.i_stb  (_RAM_i_stb),
		.i_addr (_arb_slave_addr),
		.i_we   (_arb_slave_we),
		.i_data (_arb_slave_data),
		.i_sel  (_arb_slave_sel),
		.o_ack  (_RAM_o_ack),
		.o_err  (_RAM_o_err),
		.o_data (_RAM_o_data),
		.o_stall(_RAM_o_stall)
	);
`else
    SDRAMControllerWB #(
        .START_ADDR(`RAM_START_ADDR)
    ) SDRAMControllerWB (
        .i_wb_clk  (i_clk),
        .i_wb_rst  (i_rst),
        .i_wb_cyc  (_RAM_i_cyc),
        .i_wb_stb  (_RAM_i_stb),
        .i_wb_addr (_arb_slave_addr),
        .i_wb_we   (_arb_slave_we),
        .i_wb_data (_arb_slave_data),
        // .i_wb_sel (_arb_slave_sel),
        .o_wb_ack  (_RAM_o_ack),
        .o_wb_err  (_RAM_o_err),
        .o_wb_data (_RAM_o_data),
        .o_wb_stall(_RAM_o_stall),
        // Remember to change freq inside
        .i_ram_clk (i_ram_clk),
        .o_ram_ras (o_ram_ras),
        .o_ram_cas (o_ram_cas),
        .o_ram_we  (o_ram_we),
        .o_ram_ba  (o_ram_ba),
        .o_ram_addr(o_ram_addr),
    `ifdef VERILATOR
        .i_ram_dq  (i_ram_dq),
        .o_ram_dq  (o_ram_dq)
    `else
        .io_ram_dq (io_ram_dq)
    `endif
    );
`endif /* BRAM_AS_RAM */

`ifdef BRAM_EN
    // =======================================
    // BRAM
    logic _bram_addr_access;
    localparam BRAMADDRWIDTH = $clog2(`BRAM_SIZE - 1);
    localparam BRAMSTARTADDR = `BRAM_START_ADDR;
    // Should check upper bound too
    assign _bram_addr_access = ((i_memory_address[31:BRAMADDRWIDTH] == BRAMSTARTADDR[31:BRAMADDRWIDTH]) ? 1 : 0);

    // BRAM wishbone IOs
    logic        _BRAM_i_cyc;
    logic        _BRAM_i_stb;
    logic        _BRAM_o_ack;
    logic        _BRAM_o_err;
    logic        _BRAM_o_stall;
    logic [31:0] _BRAM_o_data;

    assign _BRAM_i_cyc = _bram_addr_access & _arb_slave_cyc;
    assign _BRAM_i_stb = _bram_addr_access & _arb_slave_stb;

    BRAMWB #(
		.SIZE_BYTE(`BRAM_SIZE),
		.START_ADDR(`BRAM_START_ADDR)
	) BRAM (
		.i_clk  (i_clk),
		.i_cyc  (_BRAM_i_cyc),
		.i_stb  (_BRAM_i_stb),
		.i_addr (_arb_slave_addr),
		.i_we   (_arb_slave_we),
		.i_data (_arb_slave_data),
		.i_sel  (_arb_slave_sel),
		.o_ack  (_BRAM_o_ack),
		.o_err  (_BRAM_o_err),
		.o_data (_BRAM_o_data),
		.o_stall(_BRAM_o_stall)
	);
`endif /* BRAM_EN */

`ifdef GPIO_EN
    // =======================================
    // GPIO
    logic _gpio_addr_access;
    localparam GPIOADDRWIDTH = $clog2((`GPIO_SIZE_BYTE << 1) - 1); // SIZEBYTE * 2 for in and out regs
    localparam GPIOSTARTADDR = `GPIO_START_ADDR;
    // Should check upper bound too
    assign _gpio_addr_access = ((i_memory_address[31:GPIOADDRWIDTH] == GPIOSTARTADDR[31:GPIOADDRWIDTH]) ? 1 : 0);

    // GPIO wishbone IOs
    logic        _GPIO_i_cyc;
    logic        _GPIO_i_stb;
    logic        _GPIO_o_ack;
    logic        _GPIO_o_err;
    logic        _GPIO_o_stall;
    logic [31:0] _GPIO_o_data;

    assign _GPIO_i_cyc = _gpio_addr_access & _arb_slave_cyc;
    assign _GPIO_i_stb = _gpio_addr_access & _arb_slave_stb;

    GPIOWB #(
        .SIZE_BIT(32),
        .START_ADDR(32'hfffffff8)
    ) GPIO (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_cyc(_GPIO_i_cyc),
        .i_stb(_GPIO_i_stb),
        .i_addr(_arb_slave_addr),
        .i_we(_arb_slave_we),
        .i_data(_arb_slave_data),
        .i_sel(_arb_slave_sel),
        .o_ack(_GPIO_o_ack),
        .o_err(_GPIO_o_err),
        .o_data(_GPIO_o_data),
        .o_stall(_GPIO_o_stall),
        .i_gpio(i_gpio),
        .o_gpio(o_gpio)
    );
`endif /* GPIO_EN */

`ifdef HDMI_EN
    // =======================================
    // HDMI
    logic _hdmi_addr_access;
    localparam HDMIADDRWIDTH = $clog2(`HDMI_SIZE - 1);
    localparam HDMISTARTADDR = `HDMI_START_ADDR;
    // Should check upper bound too
    assign _hdmi_addr_access = ((i_memory_address[31:HDMIADDRWIDTH] == HDMISTARTADDR[31:HDMIADDRWIDTH]) ? 1 : 0);

    // HDMI wishbone IOs
    logic        _HDMI_i_cyc;
    logic        _HDMI_i_stb;
    logic        _HDMI_o_ack;
    logic        _HDMI_o_err;
    logic        _HDMI_o_stall;
    logic [31:0] _HDMI_o_data;

    assign _HDMI_i_cyc = _hdmi_addr_access & _arb_slave_cyc;
    assign _HDMI_i_stb = _hdmi_addr_access & _arb_slave_stb;

    HDMIController480p #(
        .START_ADDR(`HDMI_START_ADDR)
    ) HDMI (
        .i_cpu_clk(i_clk),
        .i_cpu_rst(i_rst),
        .i_pixel_clk(i_hdmi_pixel_clk), // 25 Mhz
        .i_tmds_clk(i_hdmi_tmds_clk),  // 250 Mhz
        .i_cyc(_HDMI_i_cyc),
        .i_stb(_HDMI_i_stb),
        .i_addr(_arb_slave_addr),
        .i_we(_arb_slave_we),
        .i_data(_arb_slave_data),
        .i_sel(_arb_slave_sel),
        .o_data(_HDMI_o_data),
        .o_ack(_HDMI_o_ack),
        .o_err(_HDMI_o_err),
        .o_stall(_HDMI_o_stall),
        // HDMI PINS
        .o_gpdi_dp(o_hdmi_gpdi_dp), 
        .o_gpdi_dn(o_hdmi_gpdi_dn)
    );
`endif /* HDMI_EN */


    // =======================================
    // Other signals
    // Add more err from slaves here
    // This signal indicate whether or not input address match any valid ranges,
    // or-ed with errors from slave.
    logic _access_valid;
    always_comb begin : access_valid
        _access_valid = _rom_addr_access | _ram_addr_access;  // | gpio...
`ifdef BRAM_EN
        _access_valid = _access_valid | _bram_addr_access;
`endif
`ifdef GPIO_EN
        _access_valid = _access_valid | _gpio_addr_access;
`endif
`ifdef HDMI_EN
        _access_valid = _access_valid | _hdmi_addr_access;
`endif
        _access_valid = _access_valid & i_req;
    end

    assign o_memory_ack = _mem_op_ack;
    assign o_memory_err = _mem_op_err | ~_access_valid; // or with other errors

    // =======================================
    // Output extension
    // Keeping here in case another module with direct access to mem interface is needed
    // should move into wb master if use solely wb
    // though output of that should be ored with wishbone bus readout
    // THIS ASSUME I_REQ DOES NOT CHANGE DURING REQUESTS (UNTIL ACK)
    // AND READ TAKES AT LEAST 1 CYCLE
    // Wishbone bus can only return data after 1+ cycle so use this in extension logic
    // Should really tie i_req and o_memory_ack together... state machine?
    // In this state one can mistakenly triggered a request before previous ack -> bug
    logic [1:0] _mask_type_saved;
    logic       _ext_type_saved;
    always_ff @(posedge i_clk) begin
        if(i_req) begin
            _mask_type_saved <= i_mask_type;
            _ext_type_saved  <= i_ext_type;
        end
    end
    // Sign extend
    always_comb begin
        if(o_memory_ack) begin
            case(_mask_type_saved)
                2'b00: begin
                    o_memory_readout = _ext_type_saved ? {24'b0, _mem_op_readout[7:0]} : {{24{_mem_op_readout[7]}}, _mem_op_readout[7:0]};
                end
                2'b01: begin
                    o_memory_readout = _ext_type_saved ? {16'b0, _mem_op_readout[15:0]} : {{16{_mem_op_readout[15]}}, _mem_op_readout[15:0]};
                end
                2'b10:
                    o_memory_readout = _mem_op_readout;
                default:
                    o_memory_readout = 32'hx;
            endcase
        end
        else begin
            o_memory_readout = 32'h0;
        end
    end

endmodule
