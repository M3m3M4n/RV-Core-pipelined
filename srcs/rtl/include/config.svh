`ifndef CONFIG_SVH
`define CONFIG_SVH

/* Data cache */
// Dcache is 2 ways 32 bit, disable when using bram as ram since its faster
`define DCACHE_EN 1
`ifdef DCACHE_EN
   // Capacity divisible by block size
   `define DCACHE_CAPACITY 8192
   // Block size divisible by 32
   `define DCACHE_BLOCK_SIZE 64
`endif

/* ROM */
`define ROM_SIZE 2048 // 0x2000
`define ROM_START_ADDR 32'h10000000

/* RAM */
// Generate PLL if changed, also change in config.h
`define BRAM_AS_RAM 1
`undef BRAM_AS_RAM
`define RAM_START_ADDR 32'h20000000
`ifdef BRAM_AS_RAM
   `define RAM_SIZE 8192 // 0x2000
`else
   `define RAM_SIZE 8388608 // 0x800000
   `define RAM_CLK_FREQ 90
   `define RAM_CAS_LATENCY 2
`endif

/* SEPERATE BRAM CONFIG */
`define BRAM_EN 1
`undef  BRAM_EN // undef
`ifdef BRAM_EN
   `define BRAM_SIZE 8192 // 0x2000
   `define BRAM_START_ADDR 32'h30000000
`endif

/* HDMI CONFIG */
`define HDMI_EN 1
`undef  HDMI_EN // Temporary disable current HDMI controller to get more bram from framebuffer
`ifdef HDMI_EN
   `define HDMI_SIZE 38408 // 480p frame + status reg 640*480/8 + 8, ALSO HARDCODED
   `define HDMI_START_ADDR 32'h40000000
`endif

/* GPIO CONFIG */
`define GPIO_EN 1
`ifdef GPIO_EN
   `define GPIO_SIZE 32
   `define GPIO_SIZE_BYTE (`GPIO_SIZE >> 3) // div 8 
   `define GPIO_START_ADDR 32'hfffffff8
`endif

`endif /* DEFCONFIGS_SVH */
