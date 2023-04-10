# RV-Processor

***Work-in-progress***

A simple FPGA based RISC-V processor built from scratch, with 5 stage pipelined architecture for learning purposes. For colorlight-i5 board.

## 1. Specs, features

- Piplined FETCH-DECODE-EXEC-MEMORY-WRITE, single core, 40MHz processor with RV32I ISA, without ecall, ebreak & fence
- Memory mapped peripherals through wishbone bus
    - SDRAM, with 8KB data cache
    - GPIO
    - HDMI (PoC)
- Clock correct verilator simulations

## 2. Features in progress

  - ~~Precise exception, and interrupt system~~
  - ~~Zicsr extension~~
  - ~~Formal verification~~
  - ~~Multiple functional units~~

***DUE TO MANY DRASTIC CHANGES TO THE CURRENT PIPELINE IMPLEMENTATION ARE NEEDED IN ORDER TO SUPPORT PLANNED IMPROVEMENTS. THIS PROJECT IS NOW SUSPENDED. I WILL BE WORKING ON A OUT-OF-ORDER CORE WITH THOSE FEATURES ADDED. TBA.***

## 3. Build instruction

### Requirements

- Yosys commit 7c5dba8b7 (later commit using libmap-pass somehow break BRAM inferal)
- nextpnr
- prjtrellis
- verliator
- openFPGALoader
- RV32I compiler (change in Makefile)

### Verilator build

- make test

### Synthesizable build

- ROM=\<ROMFILE.c\> make bit
