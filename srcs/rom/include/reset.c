#include "reset.h"

int main(void); // declare main

void reset_handler(void)
{
    // copy over data from rom
    volatile unsigned *src, *dest;
    for (src = &_data_loadaddr, dest = &_data;
		dest < &_edata;
		src++, dest++) {
		*dest = *src;
	}

	while (dest < &_ebss) {
		*dest++ = 0;
	}

    // call main
    (void)main();
}

/* Normally like in ARM, upon reset, reset_handler from vector table and stack pointer value will be loaded to their
 * respective targets. However, current hardware is not designed with that in mind, upon reset PC and SP will just 
 * both be 0. So the handler at 0 will have to setup SP, to avoid compiler inserting prologue, use naked attribute
 */

/* Define an ISR stub that makes a call to a C function 
 * CAN'T PUT THIS FUNCTION INTO SECTION WITH __ATTRIBUTE__
 */
/*
__asm__ 	(".global _reset_handler;"\
			"_reset_handler:"\
			"slti  sp,zero,1;"\
			"slli  sp,sp,29;"\
			"call  reset_handler;"\
			"hang:"
			"jal zero, hang;"
			);
*/

// ADDI ILLEGAL INSTR: https://stackoverflow.com/questions/70986412/why-risc-v-addi-instruction-dont-take-12-bits-value-in-hex
// STUPID

void _reset_handler(void)
{
	// HARD CODED
	// NOTE: need to un-hardcode the sp addr. currennt 1 << 29 + 0x1ffc
	__asm__ __volatile__ (
							"lui sp,0x20002;"\
							"addi sp,sp,0xfffffffc;"\
							"call  reset_handler;"\
							"hang:"\
							"jal zero, hang;"\
						);
}

