#ifndef RESET_H
#define RESET_H

// Check lib libopencm3 for examples of vector_table and reset_handler

/*
typedef void (*vector_table_entry_t)(void);

typedef struct {
} vector_table_t;

extern vector_table_t vector_table;
*/

extern unsigned _data_loadaddr, _data, _edata, _ebss, _stack;

extern void reset_handler(void);

// section .reset to put this into reset section (linker)
// naked to remove epilogue, prologue (might not work on some arch???)
extern void __attribute__ ((section(".reset"), naked)) _reset_handler(void);

#endif