#include <csignal>
#include <cstdlib>

#include "include/config.h"

#include "include/utils.h"
#include "include/testbench.h"

// For symbols from top modules 
#include "VCPU.h"
#include "VCPU___024root.h"

// For DPI functions
#include "VCPU__Dpi.h"

// Available by tagging signals with /* verilator public */
#include "VCPU_CPU.h"
#include "VCPU_DataPipeline.h"

#ifndef BRAM_AS_RAM
#include "include/models/SDRAM.h"
#endif /* BRAM_AS_RAM */

// ========================================================
// Globals

TestBench    *p_tb;
ClockDomain  *p_domain_cpu;
Module<VCPU> *p_module_cpu;

#ifndef BRAM_AS_RAM
ClockDomain  *p_domain_ram;
SDRAM *p_sdram;
#endif

#define CPUPtr ((VCPU*)(p_module_cpu->getUUTPtr()))

// ========================================================
// Support functions

// ==============================
// Export to DPI-C

const char* fetchenv(const char* env_var)
{
	const char* data = getenv(env_var);
	if (!data) {
		DEBUG("Could not fetch env %s, exiting!", env_var);
		exit(EXIT_FAILURE);
	}
	return data;
}

// ==============================

void cleanup()
{
	// All models, modules, domains are managed by testbench instance,
	// once tb is deleted all other ptrs are invalid
	if (p_tb){
		delete p_tb;
		p_tb = nullptr;
	}
}

void cleanup_exit()
{
	cleanup();
	exit(EXIT_SUCCESS);
}

// ==============================

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

// ==============================

// SDRAM does not have rst line
void resetCPU()
{
	CPUPtr->i_rst = 0;
	p_tb->evalUntilClockEdge(p_domain_cpu, 0);
	CPUPtr->i_rst = 1;
	p_tb->evalUntilClockEdge(p_domain_cpu, 0);
}

// ==============================

void cycleUntilROMAddr(const unsigned int& curr, unsigned int target)
{
	unsigned long long current_time = p_tb->getContextPtr()->time();
	DEBUG("Begin cycling until instr addr 0x%08X, currently at 0x%08X, time %llu ps",target, curr, current_time);
	while(target != curr) {
		p_tb->evalUntilClockEdge(p_domain_cpu, 0);
		current_time = p_tb->getContextPtr()->time();
		// stalling set the ptr to 0
		if (curr)
			DEBUG("Reached instr: 0x%08X @ %llu ps", curr, current_time);
	}
}

// ========================================================

int main(int argc, char **argv)
{
	// ==============================
	// 0. Setup

	install_signal_handlers();

	// ==============================
	// 1. Create testbench

	p_tb = new TestBench(argc, argv);

	// ==============================
	// 2. Create Clock domains

	p_domain_cpu = new ClockDomain(20);

#ifndef BRAM_AS_RAM
	// Clock follow RTL file since SDRAMController is not standalone module anymore
	p_domain_ram = new ClockDomain(RAM_CLK_FREQ);
#endif

	// ==============================
	// 3. Create modules, add clock lines to clock domains

	p_module_cpu = new Module<VCPU>(p_tb->getContextPtr(), "CPU");
	p_domain_cpu->addModuleClock(&(CPUPtr->i_clk));

#ifndef BRAM_AS_RAM
	p_domain_ram->addModuleClock(&(CPUPtr->i_ram_clk));
#endif

	// ==============================
	// 4. Create models, add clock lines to clock domains

#ifndef BRAM_AS_RAM
	// Follow RTL file since SDRAMController is not standalone module anymore
    p_sdram = new SDRAM(RAM_CLK_FREQ, RAM_CAS_LATENCY);
	p_domain_ram->addModelClock(&(p_sdram->i_clk));
#endif

	// ==============================
	// 5. Connect models to modules, models IOs should be pointers

#ifndef BRAM_AS_RAM
	unsigned char one = 1;
	unsigned char zero = 0;
    p_sdram->i_cke   = &one;
    p_sdram->i_cs_n  = &zero;
    p_sdram->i_ras_n = &(CPUPtr->o_ram_ras);
    p_sdram->i_cas_n = &(CPUPtr->o_ram_cas);
    p_sdram->i_we_n  = &(CPUPtr->o_ram_we);
    p_sdram->i_ba    = &(CPUPtr->o_ram_ba);
    p_sdram->i_addr  = &(CPUPtr->o_ram_addr);
    p_sdram->i_data  = &(CPUPtr->o_ram_dq);
    p_sdram->o_data  = &(CPUPtr->i_ram_dq);
#endif

	// ==============================
	// 6. Add all into testbench

	p_tb->addClockDomain(p_domain_cpu);
	p_tb->addModule(p_module_cpu);

#ifndef BRAM_AS_RAM
	p_tb->addClockDomain(p_domain_ram);
	p_tb->addModel(p_sdram);
#endif

	// ==============================
	// 7. Setup tracer
	p_tb->setTracing(1, "CPU.vcd");

	// ==============================
	// 8. Simulate

	resetCPU();
	
	// Run
	// while(!p_tb->isDone()) {
	// 	p_tb->evalUntilClockEdge(p_domain_cpu, 0);
	// }

	// Instr test
	// cycleUntilROMAddr(CPUPtr->rootp->CPU->dataPipeline->e_pc, 0x1e4);

	// HW test
	int counter = 0; 
	while(!p_tb->isDone()) {
		counter++;
		if (counter >= 9) {
			counter = 0;
			// flip GPIO
			if (!CPUPtr->i_gpio)
				CPUPtr->i_gpio = 0xff000000;
			else
				CPUPtr->i_gpio = 0x00000000;
		}
	 	p_tb->evalUntilClockEdge(p_domain_cpu, 0);
	}
}
