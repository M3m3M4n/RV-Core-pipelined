# RV-Processor

***Work-in-progress***

A simple FPGA based RISC-V processor built from scratch, with 5 stage pipelined architecture for learning purposes. For colorlight-i5 board.

## 1. Specs, features

- Piplined, single core, 40MHz processor with RV32I ISA, without ecall, ebreak & fence
- Memory mapped peripherals through wishbone bus
    - SDRAM, with 8KB data cache
    - GPIO
    - HDMI (PoC)
- Clock correct verilator simulations

## 2. Features in progress

  - Interrupt, exception, trap
  - zicsr extension
  - Formal verification

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
