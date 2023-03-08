#ifndef CONFIG_H
#define CONFIG_H

// SYNC THIS WITH RTL CONFIG FILE

/* RAM */
#define BRAM_AS_RAM 1
#undef  BRAM_AS_RAM
#ifndef BRAM_AS_RAM
    #define RAM_SIZE 8388608 // 0x800000
    #define RAM_CLK_FREQ 90
    #define RAM_CAS_LATENCY 2
#endif

#endif