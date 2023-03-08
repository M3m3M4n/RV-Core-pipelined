#include <csignal>
#include <cstdlib>

#include "include/config.h"

#include "include/utils.h"
#include "include/testbench.h"

#include "VSDRAMController.h"
#include "VSDRAMController___024root.h"

#include "include/models/SDRAM.h"

// ========================================================

// Globals
TestBench *p_tb;
ClockDomain *p_domain;
Module<VSDRAMController> *p_controller;
#define SDRAMControllerPtr ((VSDRAMController*)(p_controller->getUUTPtr()))
SDRAM *p_sdram;

// ========================================================

void sigint_handler(int num)
{
	DEBUG("SIGINT caught, exiting...");
	exit(EXIT_SUCCESS);
}

void install_signal_handlers()
{
	// SIGINT
	struct sigaction sa;
	sa.sa_handler = sigint_handler;
	sigemptyset(&sa.sa_mask);
	// Restart functions if interrupted by handler
	// (might just call signal() instead)
	sa.sa_flags = SA_RESTART; 
	if (sigaction(SIGINT, &sa, NULL) == -1) {
		DEBUG("SIGACTION failed!");
		exit(EXIT_FAILURE);
	}
}

// ========================================================

/* idx: memory byte index, this will be set to start of its block
 * source_buffer: byte data array
 * len: source buffer length in bytes
 * THIS USE VALUES DEFINED IN SDRAM.h, BE SURE TO MATCH THEM WITH SDRAMController.sv
 */
void sdram_write(uint32_t idx, const char *source_buffer, size_t len)
{
	assert(len <= strlen(source_buffer));
	// convert to data block, each has bit width of sdram data width
	uint32_t block_idx = idx / (SDRAM::s_data_block_size);
	SelectTypeWidth<SDRAM::s_data_bit_width>::type *p_block_buffer = (SelectTypeWidth<SDRAM::s_data_bit_width>::type *)source_buffer;
	size_t block_buffer_len = len / (SDRAM::s_data_block_size); // floor trunc to block size
	size_t burst_times = block_buffer_len / p_sdram->get_burst_length(); // trunc again to burst length

	for (int b = 0; b < burst_times; b++) {
		assert(block_idx < SDRAM::s_n_blocks);
		// Burst
		// Write signals
		SDRAMControllerPtr->i_we = 1;
		SDRAMControllerPtr->i_req = 1;
		SDRAMControllerPtr->i_addr = block_idx;
		SDRAMControllerPtr->i_data = p_block_buffer[0]; // first data block
		// cycle til ack
		while (SDRAMControllerPtr->o_ack == 0) {
			p_tb->evalUntilClockEdge(p_domain, 0);
		}
		SDRAMControllerPtr->i_req = 0;
		// send the rest of the data blocks
		// allow over write? warp around?
		for (int d = 1; d < p_sdram->get_burst_length(); d++){
			SDRAMControllerPtr->i_data = p_block_buffer[d];
			p_tb->evalUntilClockEdge(p_domain, 0);
		}
		SDRAMControllerPtr->i_we = 0;
		p_tb->evalUntilClockEdge(p_domain, 0);
		p_block_buffer += p_sdram->get_burst_length();
		block_idx += p_sdram->get_burst_length();
		block_buffer_len -= p_sdram->get_burst_length();
	}
}

/* idx: memory byte index, this will be set to start of its block
 * len: source buffer length in bytes
 * THIS USE VALUES DEFINED IN SDRAM.h, BE SURE TO MATCH THEM WITH SDRAMController.sv
 */
char *sdram_read(uint32_t idx, size_t len)
{
	// convert to data block, each has bit width of sdram data width
	uint32_t block_idx = idx / (SDRAM::s_data_block_size);
	size_t block_buffer_len = len / (SDRAM::s_data_block_size); // floor trunc to block size
	size_t burst_times = block_buffer_len / p_sdram->get_burst_length(); // trunc again to burst length
	char *target_buffer = new char[block_buffer_len * (SDRAM::s_data_block_size + 1)]();
	SelectTypeWidth<SDRAM::s_data_bit_width>::type *p_block_buffer = (SelectTypeWidth<SDRAM::s_data_bit_width>::type *)target_buffer;

	for (int b = 0; b < burst_times; b++) {
		// Burst
		// Read signals
		SDRAMControllerPtr->i_we = 0;
		SDRAMControllerPtr->i_req = 1;
		SDRAMControllerPtr->i_addr = block_idx + b * p_sdram->get_burst_length();
		// cycle til ack
		while (SDRAMControllerPtr->o_ack == 0) {
			p_tb->evalUntilClockEdge(p_domain, 0);
		}
		SDRAMControllerPtr->i_req = 0;
		// cycle til valid
		// valid high 1 cycle after data avail from sdram, so the data should be read the cycle before (from sdram)
		// because data is 1 cycle before valid, save that and write at valid
		while (SDRAMControllerPtr->o_valid == 0) { 
			p_tb->evalUntilClockEdge(p_domain, 0);
			if (SDRAMControllerPtr->o_valid) {
				p_block_buffer[b * p_sdram->get_burst_length()] = SDRAMControllerPtr->o_data;
			}
		}
		for (int d = 1; d < p_sdram->get_burst_length(); d++) {
			p_tb->evalUntilClockEdge(p_domain, 0);
			p_block_buffer[b * p_sdram->get_burst_length() + d] = SDRAMControllerPtr->o_data;
		}
	}
	return target_buffer;
}

// SDRAM does not have rst line
void resetController()
{
	SDRAMControllerPtr->i_rst = 0;
	p_tb->evalUntilClockEdge(p_domain, 0);
	SDRAMControllerPtr->i_rst = 1;
	p_tb->evalUntilClockEdge(p_domain, 0);
}

// ========================================================

int main(int argc, char **argv)
{
#ifdef BRAM_AS_RAM
	DEBUG("Abort, enable SDRAM in both simulation config and rtl config files");
	abort();
#else
	install_signal_handlers();
	// Create testbench
	p_tb = new TestBench(argc, argv);
	// Adding clock domains, modules, models.
	// Create Clock domains
	p_domain = new ClockDomain(143); // If change then also change in sv file aswell
	// Create modules, add clock lines to clock domains
	p_controller = new Module<VSDRAMController>(p_tb->getContextPtr(), "SDRAMController");
	p_domain->addModuleClock(&(SDRAMControllerPtr->i_clk));
	// Create models, add clock lines to clock domains
	// SDRAMController is top module, can use default or custom values
    p_sdram = new SDRAM();
	p_domain->addModelClock(&(p_sdram->i_clk));
	// Connect models to modules, models IOs should be pointers
	unsigned char one = 1;
	unsigned char zero = 0;
    p_sdram->i_cke   = &one;
    p_sdram->i_cs_n  = &zero;
    p_sdram->i_ras_n = &(SDRAMControllerPtr->o_r_ras);
    p_sdram->i_cas_n = &(SDRAMControllerPtr->o_r_cas);
    p_sdram->i_we_n  = &(SDRAMControllerPtr->o_r_we);
    p_sdram->i_ba    = &(SDRAMControllerPtr->o_r_ba);
    p_sdram->i_addr  = &(SDRAMControllerPtr->o_r_addr);
    p_sdram->i_data  = &(SDRAMControllerPtr->o_r_dq);
    p_sdram->o_data  = &(SDRAMControllerPtr->i_r_dq);
	// Add all into testbench
	p_tb->addClockDomain(p_domain);
	p_tb->addModule(p_controller);
	p_tb->addModel(p_sdram);
	// Setup tracer
	p_tb->setTracing(1, "SDRAMController.vcd");
	// ==========================================================
	// TESTING
	resetController();
	// Test data
	const char *sample_data = "Good evening twitter this is your boy edp445";
	sdram_write(0, sample_data, strlen(sample_data));
	char *output_data = sdram_read(0, strlen(sample_data));
	if (!strcmp(sample_data, output_data)) {
		DEBUG("Data verified: %s", output_data);
	}
	else {
		DEBUG("Output data mismatch: \"%s\" != \"%s\"", output_data, sample_data);
		DEBUG("Data dump length: %ld", strlen(sample_data));
		DEBUG("Hex dump:");
		std::cout << "\t";
		for (int i = 0 ; i < strlen(sample_data); i++) {
			std::cout << std::hex << (int)output_data[i] << " ";
		}
		std::cout << "\n";
	}
	delete output_data;
	
	for (int i = 0 ; i < 5; i++) {
		p_tb->evalUntilClockEdge(p_domain, 0);
	}
#endif
}
