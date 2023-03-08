/* > ram AT > rom semantic
 * 
 */

MEMORY
{
	rom       (rx)  : ORIGIN = 0x10000000, LENGTH = 2K
	ram_bram  (rwx) : ORIGIN = 0x20000000, LENGTH = 8K
}

ENTRY(_reset_handler)

STACK_SIZE = 0x800; /* 2 kB */

SECTIONS
{
    .text :
    {
        /* *(.vectors)	 Vector table */
        *(.reset)       /* Reset */
        *(.text*)	  /* Program code */
        _etext = .;
        . = ALIGN(4);
        _srdata = .;
		*(.rodata* .srodata*)	/* Read-only data */
        _erdata = .;
        . = ALIGN(4);
    } > rom

    .data :
    {
        _data = .;
        *(.data* .sdata*)	  /* Read-write initialized data */
        . = ALIGN(4);
        _edata = .;
        . = ALIGN(4);
    } > ram_bram AT > rom
    _data_loadaddr = LOADADDR(.data);

    .bss :
    {
        _bss = .;
        *(.bss* .bss.* .sbss*)	  /* Read-write zero initialized data */
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > ram_bram

    .stack (NOLOAD) :
    {
        . = ALIGN(8);
        . = . + STACK_SIZE;
        . = ALIGN(8);
    } > ram_bram
    _stack = .;
    _end = . ;
}

PROVIDE(_stack = ORIGIN(ram_bram) + LENGTH(ram_bram));