#include <csignal>
#include <cstdlib>

#include "include/config.h"

#include "include/utils.h"
#include "include/testbench.h"

#include "VSDRAMControllerWB.h"
#include "VSDRAMControllerWB___024root.h"

#include "include/models/SDRAM.h"

// ========================================================

// Globals
TestBench *p_tb;
ClockDomain *p_ram_domain;
ClockDomain *p_wb_domain;
Module<VSDRAMControllerWB> *p_controller;
#define SDRAMControllerWBPtr ((VSDRAMControllerWB*)(p_controller->getUUTPtr()))
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
/* addr: memory byte address, will be trunc-ed to align to 4 bytes, mark start addr
 * source_buffer: byte data array
 * len: source buffer length in bytes
 * THIS USE VALUES DEFINED IN SDRAM.h, BE SURE TO MATCH THEM WITH SDRAMController.sv
 */
void sdram_write(uint32_t addr, const char *source_buffer, size_t len)
{
	DEBUG("START WRITING...");
	assert(len <= strlen(source_buffer));
	// align addr to 4 bytes
	uint32_t addr_aligned = addr & 0xfffffffc;
	uint32_t *p_block_buffer = (uint32_t *)source_buffer;
	// only do burstlen = 1
	size_t block_buffer_len = len / 4; // floor trunc to block size

	for (int b = 0; b < block_buffer_len; b++) {
		assert((addr_aligned >> 2) < SDRAM::s_n_blocks);
		// Burst
		// Write signals
		SDRAMControllerWBPtr->i_wb_cyc  = 1;
		SDRAMControllerWBPtr->i_wb_stb  = 1;
		SDRAMControllerWBPtr->i_wb_addr = addr_aligned;
		SDRAMControllerWBPtr->i_wb_we   = 1;
		SDRAMControllerWBPtr->i_wb_data = p_block_buffer[0]; // first data block
		// cycle til ack, else hang
		while (SDRAMControllerWBPtr->o_wb_ack == 0) {
			p_tb->evalUntilClockEdge(p_wb_domain, 0);
		}
		SDRAMControllerWBPtr->i_wb_cyc  = 0;
		SDRAMControllerWBPtr->i_wb_stb  = 0;
		SDRAMControllerWBPtr->i_wb_data = 0;
		p_tb->evalUntilClockEdge(p_wb_domain, 0);
		// only do burstlen = 1
		p_block_buffer += 1;
		addr_aligned += 4;
	}
	DEBUG("END WRITING...");
}

/* idx: memory byte index, this will be set to start of its block
 * len: source buffer length in bytes
 * THIS USE VALUES DEFINED IN SDRAM.h, BE SURE TO MATCH THEM WITH SDRAMController.sv
 */
char *sdram_read(uint32_t addr, size_t len)
{
	DEBUG("START READING...");
	// align addr to 4 bytes
	uint32_t addr_aligned = addr & 0xfffffffc;
	size_t block_buffer_len = len / 4; // floor trunc to block size
	char *target_buffer = new char[(block_buffer_len + 1) * 4]();
	uint32_t *p_block_buffer = (uint32_t *)target_buffer;

	for (int b = 0; b < block_buffer_len; b++) {
		// Burst
		// Read signals
		SDRAMControllerWBPtr->i_wb_cyc  = 1;
		SDRAMControllerWBPtr->i_wb_stb  = 1;
		SDRAMControllerWBPtr->i_wb_addr = addr_aligned;
		SDRAMControllerWBPtr->i_wb_we   = 0;
		// cycle til ack
		while (SDRAMControllerWBPtr->o_wb_ack == 0) {
			p_tb->evalUntilClockEdge(p_wb_domain, 0);
		}
		p_block_buffer[b] = SDRAMControllerWBPtr->o_wb_data;
		SDRAMControllerWBPtr->i_wb_cyc  = 0;
		SDRAMControllerWBPtr->i_wb_stb  = 0;
		p_tb->evalUntilClockEdge(p_wb_domain, 0);
		// only do burstlen = 1
		addr_aligned += 4;
	}
	DEBUG("END READING...");
	return target_buffer;
}

// ========================================================

// SDRAM does not have rst line
void resetController()
{
	SDRAMControllerWBPtr->i_wb_rst = 0;
	p_tb->evalUntilClockEdge(p_wb_domain, 0);
	SDRAMControllerWBPtr->i_wb_rst = 1;
	p_tb->evalUntilClockEdge(p_wb_domain, 0);
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
	p_wb_domain = new ClockDomain(20);
	// Clock follow RTL file since SDRAMController is not standalone module anymore
	p_ram_domain = new ClockDomain(RAM_CLK_FREQ); // if change then change in the sv file aswell
	// Create modules, add clock lines to clock domains
	p_controller = new Module<VSDRAMControllerWB>(p_tb->getContextPtr(), "SDRAMControllerWB");
	p_wb_domain->addModuleClock(&(SDRAMControllerWBPtr->i_wb_clk));
	p_ram_domain->addModuleClock(&(SDRAMControllerWBPtr->i_ram_clk));
	// Create models, add clock lines to clock domains
	// Follow RTL file since SDRAMController is not standalone module anymore
    p_sdram = new SDRAM(RAM_CLK_FREQ, RAM_CAS_LATENCY);
	p_ram_domain->addModelClock(&(p_sdram->i_clk));
	// Connect models to modules, models IOs should be pointers
	unsigned char one = 1;
	unsigned char zero = 0;
    p_sdram->i_cke   = &one;
    p_sdram->i_cs_n  = &zero;
    p_sdram->i_ras_n = &(SDRAMControllerWBPtr->o_ram_ras);
    p_sdram->i_cas_n = &(SDRAMControllerWBPtr->o_ram_cas);
    p_sdram->i_we_n  = &(SDRAMControllerWBPtr->o_ram_we);
    p_sdram->i_ba    = &(SDRAMControllerWBPtr->o_ram_ba);
    p_sdram->i_addr  = &(SDRAMControllerWBPtr->o_ram_addr);
    p_sdram->i_data  = &(SDRAMControllerWBPtr->o_ram_dq);
    p_sdram->o_data  = &(SDRAMControllerWBPtr->i_ram_dq);
	// Add all into testbench
	p_tb->addClockDomain(p_wb_domain);
	p_tb->addClockDomain(p_ram_domain);
	p_tb->addModule(p_controller);
	p_tb->addModel(p_sdram);
	// Setup tracer
	p_tb->setTracing(1, "SDRAMControllerWB.vcd");
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
		p_tb->evalUntilClockEdge(p_wb_domain, 0);
	}
#endif
}
