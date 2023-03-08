module testinterconnect (
	input  logic        i_clk,
	input  logic        i_rst,
	// master a
	input  logic        i_a_mem_en,
	input  logic        i_a_mem_we,
	input  logic [31:0] i_a_mem_addr,
	input  logic [31:0] i_a_mem_wd,
	input  logic [1:0]  i_a_mask_type,
	output logic        o_a_mem_ack,
	output logic        o_a_mem_err,
	output logic [31:0] o_a_mem_rd,
	// master b
	input  logic        i_b_mem_en,
	input  logic        i_b_mem_we,
	input  logic [31:0] i_b_mem_addr,
	input  logic [31:0] i_b_mem_wd,
	input  logic [1:0]  i_b_mask_type,
	output logic        o_b_mem_ack,
	output logic        o_b_mem_err,
	output logic [31:0] o_b_mem_rd
);

	// masters <-> wishbone arbiter
	// a
	logic [31:0] _a_w_m_data;
	logic        _a_w_m_stall;
	logic        _a_w_m_ack;
	logic        _a_w_m_err;
	logic [3:0]  _a_m_w_sel;
	logic [31:0] _a_m_w_addr;
	logic [31:0] _a_m_w_data;
	logic        _a_m_w_cyc;
	logic        _a_m_w_stb;
	logic        _a_m_w_we;
	// b
	logic [31:0] _b_w_m_data;
	logic        _b_w_m_stall;
	logic        _b_w_m_ack;
	logic        _b_w_m_err;
	logic [3:0]  _b_m_w_sel;
	logic [31:0] _b_m_w_addr;
	logic [31:0] _b_m_w_data;
	logic        _b_m_w_cyc;
	logic        _b_m_w_stb;
	logic        _b_m_w_we;
	// iface
	logic [63:0] _w_m_data;
	logic [1:0]  _w_m_stall;
	logic [1:0]  _w_m_ack;
	logic [1:0]  _w_m_err;
	logic [7:0]  _m_w_sel;
	logic [63:0] _m_w_addr;
	logic [63:0] _m_w_data;
	logic [1:0]  _m_w_cyc;
	logic [1:0]  _m_w_stb;
	logic [1:0]  _m_w_we;
	// iface assign
	assign {_b_w_m_data, _a_w_m_data}   = _w_m_data;
	assign {_b_w_m_stall, _a_w_m_stall} = _w_m_stall;
	assign {_b_w_m_ack, _a_w_m_ack}     = _w_m_ack;
	assign {_b_w_m_err, _a_w_m_err}     = _w_m_err;
	assign _m_w_sel   = {_b_m_w_sel, _a_m_w_sel};
	assign _m_w_addr  = {_b_m_w_addr, _a_m_w_addr};
	assign _m_w_data  = {_b_m_w_data, _a_m_w_data};
	assign _m_w_cyc   = {_b_m_w_cyc, _a_m_w_cyc};
	assign _m_w_stb   = {_b_m_w_stb, _a_m_w_stb};
	assign _m_w_we    = {_b_m_w_we, _a_m_w_we};
	

	// arbiter <-> slave
	logic        _w_s_cyc;
	logic        _w_s_stb;
	logic        _w_s_we;
	logic [31:0] _w_s_addr;
	logic [31:0] _w_s_data;
	logic [3:0]  _w_s_sel;
	// slave output bus
	// or all input from slaves then feed to arbiter
	logic [31:0] _s_w_data;
	logic        _s_w_stall;
	logic        _s_w_ack;
	logic        _s_w_err;

	DataMemWBMaster mastera(
		.i_clk(i_clk),
		.i_rst(i_rst),
		// WB ios
		.i_wb_data(_a_w_m_data),
		.i_wb_stall(_a_w_m_stall),
		.i_wb_ack(_a_w_m_ack),
		.i_wb_err(_a_w_m_err),
		.o_wb_sel(_a_m_w_sel),
		.o_wb_addr(_a_m_w_addr),
		.o_wb_data(_a_m_w_data),
		.o_wb_cyc(_a_m_w_cyc),
		.o_wb_stb(_a_m_w_stb),
		.o_wb_we(_a_m_w_we),
		// CPU interface
		.i_mem_en(i_a_mem_en),
		.i_mem_we(i_a_mem_we),
		.i_mem_addr(i_a_mem_addr),
		.i_mem_wd(i_a_mem_wd),
		.i_mem_mask_type(i_a_mask_type),
		.o_mem_ack(o_a_mem_ack),
		.o_mem_err(o_a_mem_err),
		.o_mem_rd(o_a_mem_rd)
	);

	DataMemWBMaster masterb(
		.i_clk(i_clk),
		.i_rst(i_rst),
		// WB ios
		.i_wb_data(_b_w_m_data),
		.i_wb_stall(_b_w_m_stall),
		.i_wb_ack(_b_w_m_ack),
		.i_wb_err(_b_w_m_err),
		.o_wb_sel(_b_m_w_sel),
		.o_wb_addr(_b_m_w_addr),
		.o_wb_data(_b_m_w_data),
		.o_wb_cyc(_b_m_w_cyc),
		.o_wb_stb(_b_m_w_stb),
		.o_wb_we(_b_m_w_we),
		// CPU interface
		.i_mem_en(i_b_mem_en),
		.i_mem_we(i_b_mem_we),
		.i_mem_addr(i_b_mem_addr),
		.i_mem_wd(i_b_mem_wd),
		.i_mem_mask_type(i_b_mask_type),
		.o_mem_ack(o_b_mem_ack),
		.o_mem_err(o_b_mem_err),
		.o_mem_rd(o_b_mem_rd)
	);

	// MASTER ARBITRATION DONE
	// BUT HOW ABOUT SLAVE ARBITRATION?
	// WE NEED TO USE ADDRESS TO FORM ENABLE SIGNAL HERE THEN AND IT WITH CYC
	// ELSE NEED TO PERFORM ADDRESS CHECK INSIDE SLAVES, THEN ALSO AND WITH CYC

	/*
		slave arbitration
		err: interconnect must check the access address, if in range, allow access
		else return bus error to master
		
	*/

	DataMemWBArbiter #(
		.MASTER_COUNT(2)
	) arbiter(
		.i_clk(i_clk),
		.i_rst(i_rst),
		// Masters
		.i_m_cyc(_m_w_cyc),
		.i_m_stb(_m_w_stb),
		.i_m_we(_m_w_we),
		.i_m_addr(_m_w_addr),
		.i_m_data(_m_w_data),
		.i_m_sel(_m_w_sel),
		.o_m_data(_w_m_data),
		.o_m_stall(_w_m_stall),
		.o_m_ack(_w_m_ack),
		.o_m_err(_w_m_err),
		// To slaves
		.o_s_cyc(_w_s_cyc),
		.o_s_stb(_w_s_stb),
		.o_s_we(_w_s_we),
		.o_s_addr(_w_s_addr),
		.o_s_data(_w_s_data),
		.o_s_sel(_w_s_sel),
		// from slaves
		.i_s_data(_s_w_data),
		.i_s_stall(_s_w_stall),
		.i_s_ack(_s_w_ack),
		.i_s_err(_s_w_err)
	);

	localparam RAM_SIZE_BYTE    = 8192;
	localparam RAM_ADDR_WIDTH   = $clog2(RAM_SIZE_BYTE - 1);
	localparam RAM_START_ADDR_1 = 32'h20000000;
	localparam RAM_START_ADDR_2 = 32'h30000000;

	logic        _bram1_acc_en;
	logic        _bram1_i_cyc;
	logic        _bram1_i_stb;
	logic        _bram1_o_ack;
	logic        _bram1_o_err;
	logic [31:0] _bram1_o_data;
	logic        _bram1_o_stall;

	BRAMWB #(
		.SIZE_BYTE(RAM_SIZE_BYTE),
		.START_ADDR(RAM_START_ADDR_1)
	) bram1 (
		.i_clk(i_clk),
		.i_cyc(_bram1_i_cyc),
		.i_stb(_bram1_i_stb),
		.i_addr(_w_s_addr),
		.i_we(_w_s_we),
		.i_data(_w_s_data),
		.i_sel(_w_s_sel),
		.o_ack(_bram1_o_ack),
		.o_err(_bram1_o_err),
		.o_data(_bram1_o_data),
		.o_stall(_bram1_o_stall)
	);

	assign _bram1_acc_en = (_w_s_addr[31:RAM_ADDR_WIDTH] == RAM_START_ADDR_1[31:RAM_ADDR_WIDTH]) ? 1 : 0;
	assign _bram1_i_cyc = _w_s_cyc & _bram1_acc_en;
	assign _bram1_i_stb = _w_s_stb & _bram1_acc_en;
	
	logic        _bram2_acc_en;
	logic        _bram2_i_cyc;
	logic        _bram2_i_stb;
	logic        _bram2_o_ack;
	logic        _bram2_o_err;
	logic [31:0] _bram2_o_data;
	logic        _bram2_o_stall;

	BRAMWB #(
		.SIZE_BYTE(RAM_SIZE_BYTE),
		.START_ADDR(RAM_START_ADDR_2)
	) bram2 (
		.i_clk(i_clk),
		.i_cyc(_bram2_i_cyc),
		.i_stb(_bram2_i_stb),
		.i_addr(_w_s_addr),
		.i_we(_w_s_we),
		.i_data(_w_s_data),
		.i_sel(_w_s_sel),
		.o_ack(_bram2_o_ack),
		.o_err(_bram2_o_err),
		.o_data(_bram2_o_data),
		.o_stall(_bram2_o_stall)
	);

	assign _bram2_acc_en = (_w_s_addr[31:RAM_ADDR_WIDTH] == RAM_START_ADDR_2[31:RAM_ADDR_WIDTH]) ? 1 : 0;
	assign _bram2_i_cyc = _w_s_cyc & _bram2_acc_en;
	assign _bram2_i_stb = _w_s_stb & _bram2_acc_en;

	// Valid access when ...
	// access enabled
	logic _acc_en;
	assign _acc_en = _w_s_cyc & _w_s_stb;
	// valid address
	logic _acc_valid_addr;
	assign _acc_valid_addr = (_bram1_acc_en | _bram2_acc_en);
	// and valid signal
	logic _acc_valid;
	assign _acc_valid = _acc_en & _acc_valid_addr;

	// Invalid access
	logic _acc_invalid;
	assign _acc_invalid = _acc_en & ~_acc_valid_addr;

	// wb slave oring
	// slave output signal must not be x
	assign _s_w_data  = _bram1_o_data | _bram2_o_data;
	assign _s_w_stall = _bram1_o_stall | _bram2_o_stall;
	assign _s_w_ack   = _bram1_o_ack | _bram2_o_ack;
	assign _s_w_err   = _acc_invalid | _bram1_o_err | _bram2_o_err;

endmodule
