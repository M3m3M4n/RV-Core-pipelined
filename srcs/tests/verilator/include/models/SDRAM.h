/* Model for testing simple SDRAM controller 
 * No interleaving supported, single acive bank at a time
 * simulation: https://github.com/ZipCPU/xulalx25soc/tree/master/bench/cpp
 * gg: verilator test sdram controller
 * https://www.reddit.com/r/FPGA/comments/a5e3ok/recommend_an_sdram_model_for_verilator/
 * https://github.com/ZipCPU/xulalx25soc/blob/master/bench/cpp/sdramsim.h
 */

#ifndef SDRAM_H
#define SDRAM_H

#include <cmath>
#include <cassert>
#include <cstdint>
#include <cstring>
#include <memory>

#include "model.h"
#include "../debug.h"

// ==================================================
template<uint32_t Max>
struct RequiredBits
{
    enum { value =
        Max <= 0xff       ?  8 :
        Max <= 0xffff     ? 16 :
        Max <= 0xffffffff ? 32 :
                            64
    };
};

template<uint32_t Width>
struct AlignBitWidth
{
    enum { value =
        Width <= 8        ?  8 :
        Width <= 16       ? 16 :
        Width <= 32       ? 32 :
        Width <= 64       ? 64 :
                            -1
    };
};

// https://stackoverflow.com/questions/7038797/automatically-pick-a-variable-type-big-enough-to-hold-a-specified-number
// https://stackoverflow.com/questions/38467025/template-specialization-with-empty-brackets-and-struct
template<int bits> struct SelectInteger_;
template<> struct SelectInteger_ <8> { typedef uint8_t  type; };
template<> struct SelectInteger_<16> { typedef uint16_t type; };
template<> struct SelectInteger_<32> { typedef uint32_t type; };
template<> struct SelectInteger_<64> { typedef uint64_t type; };

template<uint32_t Max>
struct SelectTypeMaxInt : SelectInteger_<RequiredBits<Max>::value> {};

template<uint32_t Max>
struct SelectTypeWidth : SelectInteger_<AlignBitWidth<Max>::value> {};

// ==================================================
/* Implementation of a SDRAM model based on simple controller for EM638325-6H (SDRAMController.sv)
 * Using the controller state-machine model, forcing certain constraints based on the datasheet
 */
class SDRAM : public IModel
{
public:
    // SDRAM specs, check datasheet. EM638325-6H as example
    // Size, data & addr bit width
    // Due to bit width values being needed at compile time, these values must be either static or defined, not object constant
    // This lead to limited configurability of SDRAM model, but I guess I can just create another class
    // ==================================================
    // SDRAM size in bit
    static const uint32_t s_size_bit        = 67108864;
    static const uint32_t s_size_byte       = s_size_bit / 8; // s_size_bit / 8
    // Number of data line, E.G: DQ0-DQ31 -> 32
    static const uint8_t  s_data_bit_width  = 32;
    // Number of "block" in this SDRAM
    // Each "block" consists of s_data_bit_width bits (or s_data_block_size bytes)
    static const uint32_t s_n_blocks        = s_size_bit / s_data_bit_width; // s_size_bit / s_data_bit_width
    static const uint8_t  s_data_block_size = s_data_bit_width / 8; // s_data_bit_width / 8
    static const uint8_t  s_block_bit_width = 21; // ceil(log2(s_n_blocks))
    // Number of banks
    static const uint8_t  s_n_banks         = 4;
    // Number of bank addr line, E.G: BA0-BA1 -> 2, or from n banks
    static const uint8_t  s_bank_bit_width  = 2;  // ceil(log2(s_n_banks))
    // Number of data addr line, E.G: A0-A10 -> 11
    static const uint8_t  s_addr_bit_width  = 11;
    // Number of data addr line needed for row, E.G: A0-A10 in BankActive
    static const uint8_t  s_row_bit_width   = s_addr_bit_width;
    // Number of data addr line needed for column, E.G: A0-A7 in Read / Write
    static const uint8_t  s_column_bit_width= 8;// ceil(log2(s_size_bit / s_data_bit_width)) - s_bank_bit_width - s_row_bit_width
    // Used when read / write entire page, currently not implemented
    static const uint16_t s_page_size       = 256;
    // Currently not implemented
    static const uint8_t  s_dqm_bit_width   = 4;
private:
    // Variables
    // ==================================================
    // T == timing (ns), C == clock timing
    // Timings in nanoseconds, default preset converted from tck @ 143MHz
    double s_freq_mhz   = 143;
    // -- startup delay, power on sequence
    double s_t_desl     = 200000.0;
    // -- mode register set cycle time
    double s_t_mrd      = 14.0;
    // -- row cycle time
    double s_t_rc       = 63.0;
    // -- RAS to CAS delay
    double s_t_rcd      = 21.0;
    // -- precharge to activate delay
    double s_t_rp       = 21.0;
    // -- write recovery time
    double s_t_wr       = 14.0;
    // -- average refresh interval
    double s_t_refi     = 15600.0;
    // -- max refresh interval
    // Need to refresh 4096 times in 64ms => need 1 refresh cmd every 15625ns
    double s_t_max_refi = 15625.0;
    // ==================================================
    // Clock based timings
    double   s_t_clk_period           = (1000.0 / s_freq_mhz); // ns
    uint32_t s_c_init_wait            = ceil(s_t_desl / s_t_clk_period);
    uint32_t s_c_load_mode_wait       = ceil(s_t_mrd / s_t_clk_period);
    uint32_t s_c_active_wait          = ceil(s_t_rcd / s_t_clk_period);
    uint32_t s_c_refresh_wait         = ceil(s_t_rc / s_t_clk_period);
    uint32_t s_c_precharge_wait       = ceil(s_t_rp / s_t_clk_period);
    uint32_t s_c_refresh_interval     = floor(s_t_refi / s_t_clk_period);
    uint32_t s_c_max_refresh_interval = floor(s_t_max_refi / s_t_clk_period);
    // ==================================================
    // Modifiable by using MRS command, these ONLY SERVE AS DEFAULT VALUE
    // CAS latency, use value from others 2=below 133MHz, 3=above 133MHz
    // t[CAC] (min) ≤ CAS Latency * t[CK]
    // t[CAC] is not mentioned anywhere else in the datasheet except this formula
    uint8_t v_cas_latency  = 3;
    uint8_t v_burst_length = 1; // full page when >8
    uint8_t v_read_wait    = v_cas_latency + v_burst_length;
    uint8_t v_write_wait   = ceil((s_t_wr + s_t_rp) / s_t_clk_period) + v_burst_length;
    // ==================================================
    // Backing memory for simulated SDRAM, byte addressible
    uint8_t *p_v_backing_mem;
    // ==================================================
    // State machine
    enum state_t {INIT_STARTUP_DELAY, INIT_PRECHARGE, INIT_REFRESH1, INIT_REFRESH2, INIT_MRS, 
                    WORK_IDLE, WORK_ACTIVE, WORK_READ, WORK_WRITE, WORK_REFRESH};
    uint8_t v_init_refreshed, v_init_MRSed, v_init_done; // flags used during init
    state_t v_state; // Main state machine
    uint32_t v_wait_timer, v_refresh_timer; // Shared between all banks, no interleaving, counting down
    // ==================================================
    // Saved addrs
    SelectTypeWidth<s_bank_bit_width>::type  v_bank_addr_active, v_bank_addr_rw; // Bank addr
    SelectTypeWidth<s_addr_bit_width>::type  v_row_addr, v_col_addr;
    SelectTypeWidth<s_block_bit_width>::type v_full_addr;
    // For checking edge
    uint8_t last_clk;
    // for checking used signal is not null
    uint8_t signal_asserted;
    // Funcs
    // ==================================================
    void init(void);
    void signalAssertCheck(void);
    void modeRegisterSet(void);
    void cycle(void);

public:
    // Give user access to set the IOs
    uint8_t                                 *i_clk;
    uint8_t                                 *i_cke;
    uint8_t                                 *i_cs_n;
    uint8_t                                 *i_ras_n;
    uint8_t                                 *i_cas_n;
    uint8_t                                 *i_we_n;
	SelectTypeWidth<s_bank_bit_width>::type *i_ba;
    SelectTypeWidth<s_addr_bit_width>::type *i_addr;
    SelectTypeWidth<s_data_bit_width>::type *i_data;
    SelectTypeWidth<s_dqm_bit_width>::type  *i_dqm;
    SelectTypeWidth<s_data_bit_width>::type *i_dq;
    SelectTypeWidth<s_data_bit_width>::type *o_data;

    SDRAM(void);
    SDRAM(
        double  freq_mhz,
        uint8_t cas_latency,
        uint8_t burst_length = 1,
        double  t_desl       = 200000.0,
        double  t_mrd        = 14.0,
        double  t_rc         = 63.0,
        double  t_rcd        = 21.0,
        double  t_rp         = 21.0,
        double  t_wr         = 14.0,
        double  t_refi       = 15600.0,
        double  t_max_refi   = 15625.0
    );
    ~SDRAM(void);
    uint8_t get_burst_length(void);
    void eval(void) override;
    bool operator< (const IModel& comp) const override;
    bool operator== (const IModel& comp) const override;
};

#endif
