#include "SDRAM.h"

void SDRAM::init(void)
{
    // Allocate memory
    p_v_backing_mem = new uint8_t [s_size_byte]();
    // State machine init
    v_state = INIT_STARTUP_DELAY;
    // State machine flags
    v_init_done      = 0;
    v_init_refreshed = 0;
    v_init_MRSed     = 0;
    // Timer
    v_wait_timer     = s_c_init_wait;
    v_refresh_timer  = s_c_max_refresh_interval;
    // IOs - all to null, user must set them all before eval else crash lol
    i_clk = nullptr;
    i_cke = nullptr;
    i_cs_n = nullptr;
    i_ras_n = nullptr;
    i_cas_n = nullptr;
    i_we_n = nullptr;
    i_ba = nullptr;
    i_addr = nullptr;
    i_data = nullptr;
    i_dqm = nullptr;
    i_dq = nullptr;
    o_data = nullptr;
    // Flags
    last_clk = 0;
    signal_asserted = 0;
}

SDRAM::SDRAM(void)
{
    // Unparameterized constructor, see default values in h file
    init();
}

SDRAM::SDRAM(
    double  freq_mhz,
    uint8_t cas_latency,
    uint8_t burst_length,
    double  t_desl,
    double  t_mrd,
    double  t_rc,
    double  t_rcd,
    double  t_rp,
    double  t_wr,
    double  t_refi,
    double  t_max_refi
)
{
    // Set new values
    this->s_freq_mhz     = freq_mhz;
    this->v_cas_latency  = cas_latency;
    this->v_burst_length = burst_length;
    this->s_t_desl       = t_desl;
    this->s_t_mrd        = t_mrd;
    this->s_t_rc         = t_rc;
    this->s_t_rcd        = t_rcd;
    this->s_t_rp         = t_rp;
    this->s_t_wr         = t_wr;
    this->s_t_refi       = t_refi;
    this->s_t_max_refi   = t_max_refi;
    // Recalculate
    this->s_t_clk_period           = (1000.0 / s_freq_mhz);
    this->s_c_init_wait            = ceil(s_t_desl / s_t_clk_period);
    this->s_c_load_mode_wait       = ceil(s_t_mrd / s_t_clk_period);
    this->s_c_active_wait          = ceil(s_t_rcd / s_t_clk_period);
    this->s_c_refresh_wait         = ceil(s_t_rc / s_t_clk_period);
    this->s_c_precharge_wait       = ceil(s_t_rp / s_t_clk_period);
    this->s_c_refresh_interval     = floor(s_t_refi / s_t_clk_period);
    this->s_c_max_refresh_interval = floor(s_t_max_refi / s_t_clk_period);
    this->v_read_wait              = v_cas_latency + v_burst_length;
    this->v_write_wait             = ceil((s_t_wr + s_t_rp) / s_t_clk_period) + v_burst_length;
    //
    init();
}

SDRAM::~SDRAM(void)
{
    delete p_v_backing_mem;
}

void SDRAM::signalAssertCheck(void)
{
    assert(i_clk   != nullptr);
    assert(i_cke   != nullptr);
    assert(i_cs_n  != nullptr);
    assert(i_ras_n != nullptr);
    assert(i_cas_n != nullptr);
    assert(i_we_n  != nullptr);
    assert(i_ba    != nullptr);
    assert(i_addr  != nullptr);
    assert(i_data  != nullptr);
    assert(o_data  != nullptr);
    this->signal_asserted = 1;
}

uint8_t SDRAM::get_burst_length(void)
{
    return this->v_burst_length;
}

void SDRAM::eval(void)
{
    if (!this->signal_asserted)
        this->signalAssertCheck();
    // posedge
    if (this->last_clk == 0 && *this->i_clk == 1) {
        this->cycle();
    }
    this->last_clk = *this->i_clk;
}

bool SDRAM::operator< (const IModel& comp) const
{
    return (this < &comp);
}

bool SDRAM::operator== (const IModel& comp) const
{
    return (this == &comp);
}

// Mode register set
// BA0-1: Reserved
// A10: Reserved
// A9: Write burst length 0: burst, 1: single bit
// A8-7: Test mode : 00: normal
// A6-4: CAS latency: 010: 2, 011: 3
// A3: BT: 0: sequential, 1: interleave
// A2-0: Burst length: 32bits multiple
//       000: 1
//       001: 2
//       010: 4
//       011: 8
//       111: Full Page (Sequential)
void SDRAM::modeRegisterSet(void)
{
    v_cas_latency = (*this->i_addr & 0x70) >> 4;
    v_burst_length = (*this->i_addr & 0x3);
    v_read_wait = v_cas_latency + v_burst_length;
    v_write_wait = ceil((s_t_wr + s_t_rp) / s_t_clk_period) + v_burst_length;
    DEBUG("SDRAM MODE REGISTER SET:"
            "\n\tValue: 0x%08X"
            "\n\tCas latency : %d"
            "\n\tBurst length: %d",
            *this->i_addr, v_cas_latency, v_burst_length
        );
}

// Call every tick, after main verilator eval
void SDRAM::cycle(void)
{
    assert(*this->i_cke);
    if (v_wait_timer > 0) v_wait_timer--;
    // Watch refresh counter after init done, abort if not getting refreshed
    assert((!v_init_done) || 
        ((v_init_done) && (((v_refresh_timer > 0) && (v_state != WORK_REFRESH)) || (v_state == WORK_REFRESH))));
    if (v_init_done) v_refresh_timer--;
    if (!*this->i_cs_n) {
        switch (v_state) {
            case INIT_STARTUP_DELAY: {
                if (!v_wait_timer) {
                    if ((!*this->i_ras_n) && (*this->i_cas_n) && (!*this->i_we_n) && (*this->i_addr & 0x400)) {  // Precharge all
                        v_state = INIT_PRECHARGE;
                        v_wait_timer = s_c_precharge_wait;
                    }
                    else {
                        assert((*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)); // NOP
                    }
                }
                break;
            }
            case INIT_PRECHARGE: {
                if (!v_wait_timer) {
                    // Either refresh or mode register set
                    if ((!*this->i_ras_n) && (!*this->i_cas_n) && (*this->i_we_n)) { // Auto refresh
                        v_state = INIT_REFRESH1;
                        v_wait_timer = s_c_refresh_wait;
                    }
                    else if ((!*this->i_ras_n) && (!*this->i_cas_n) && (!*this->i_we_n)) { // MRS
                        modeRegisterSet();
                        v_state = INIT_MRS;
                        v_wait_timer = s_c_load_mode_wait;
                    }
                    else {
                       assert((*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)); // NOP
                    }
                }
                else {
                    assert((*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)); // NOP
                }
                break;
            }
            case INIT_REFRESH1: {
                if (!v_wait_timer && ((!*this->i_ras_n) && (!*this->i_cas_n) && (*this->i_we_n))) {
                    v_state = INIT_REFRESH2;
                    v_wait_timer = s_c_refresh_wait;
                }
                else {
                    assert((*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)); // NOP
                }
                break;
            }
            case INIT_REFRESH2: {
                if (!v_wait_timer) {
                    v_init_refreshed = 1;
                    if (v_init_MRSed) {
                        // Change to new work state
                        v_state = WORK_IDLE;
                        v_refresh_timer = s_c_max_refresh_interval; // also set in constructor
                        v_init_done = 1;
                        DEBUG("SDRAM STARTUP COMPLETE!");
                    }
                    else if ((!*this->i_ras_n) && (!*this->i_cas_n) && (!*this->i_we_n)) { //MRS
                        modeRegisterSet();
                        v_state = INIT_MRS;
                        v_wait_timer = s_c_load_mode_wait;
                    }
                    else {
                        assert((*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)); // NOP
                    }
                }
                else {
                    assert((*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)); // NOP
                }
                break;
            }
            case INIT_MRS: {
                if (!v_wait_timer) {
                    v_init_MRSed = 1;
                    if (v_init_refreshed) {
                        // Change to new work state
                        v_state = WORK_IDLE;
                        // Set here because refresh timer should be full after init done
                        v_refresh_timer = s_c_max_refresh_interval; // also set in constructor
                        v_init_done = 1;
                        DEBUG("SDRAM STARTUP COMPLETE!");
                    }
                    else if ((!*this->i_ras_n) && (!*this->i_cas_n) && (*this->i_we_n)) { // Auto refresh
                        v_state = INIT_REFRESH1;
                        v_wait_timer = s_c_refresh_wait;
                    }
                    else {
                        assert((*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)); // NOP
                    }
                }
                else {
                    assert((*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)); // NOP
                }
                break;
            }
            // Should this ever support interleaving, working state should monitor each bank's state individualy
            // and evaluate upon receiving commands
            // For the purpose of testing my simple controller, forcing it to comply to a state machine model
            // should be enough
            case WORK_IDLE: {
                // Available commands in this state only, else use nops
                if ((!*this->i_ras_n) && (!*this->i_cas_n) && (*this->i_we_n)) { // Receive AutoRefresh
                    v_state = WORK_REFRESH;
                    v_wait_timer = s_c_refresh_wait;
                    DEBUG("SDRAM STATE CHANGE: IDLE to REFRESH");
                }
                else if ((!*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)) { // BankActive
                    v_state = WORK_ACTIVE;
                    v_wait_timer = s_c_active_wait;
                    v_row_addr = *this->i_addr; // save row addr
                    v_bank_addr_active = *this->i_ba; // save bank addr
                    DEBUG("SDRAM STATE CHANGE: IDLE to ACTIVE");
                }
                else {
                    assert((*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)); // NOP
                }
                break;
            }
            case WORK_ACTIVE: {
                if (v_wait_timer == 0) { // Should wait for READ or WRITE
                    // save anyway
                    SelectTypeWidth<s_addr_bit_width>::type tmp = 0;
                    for (int i = 0; i < s_column_bit_width; i++) {
                        tmp += (1 << i);
                    }
                    v_col_addr = *this->i_addr & tmp; // save column addr 
                    v_bank_addr_rw = *this->i_ba; // save bank addr
                    // validate
                    assert(v_bank_addr_active == v_bank_addr_rw);
                    // Full address check = [bank][row][column]
                    // This addr is block addr
                    v_full_addr = (v_bank_addr_rw << (s_row_bit_width + s_column_bit_width)) +
                                (v_row_addr << (s_column_bit_width)) + v_col_addr;
                    // Size check
                    assert((v_full_addr + v_burst_length) < s_n_blocks);
                    if ((*this->i_ras_n) && (!*this->i_cas_n) && (*this->i_we_n)) { // READ
                        assert(*this->i_addr & 0x400); // a10 == high, precharge
                        v_state = WORK_READ;
                        v_wait_timer = v_read_wait;
                        DEBUG("SDRAM STATE CHANGE: ACTIVE to READ");
                    }
                    else if ((*this->i_ras_n) && (!*this->i_cas_n) && (!*this->i_we_n)) { // WRITE
                        assert(*this->i_addr & 0x400); // a10 == high, precharge
                        v_state = WORK_WRITE;
                        v_wait_timer = v_write_wait;
                        // first block
                        DEBUG("SDRAM WRITE: Writing block #%d with \"%s\", size %ld bytes",
                            v_full_addr, (char*)&*this->i_data, sizeof(*this->i_data));
                        ((SelectTypeWidth<s_data_bit_width>::type *)p_v_backing_mem)[v_full_addr] = *this->i_data;
                        DEBUG("SDRAM STATE CHANGE: ACTIVE to WRITE");
                    }
                    else {
                        assert((*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)); // NOP
                    }
                }
                else {
                    assert((*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)); // NOP
                }
                break;
            }
            // Allow only read / write burst with auto precharge, cannot be interrupted by read / write or precharge before the end of the burst
            // Burst stop cmd unavailable
            // Full page burst unavailable
            case WORK_READ: {
                // If (statisfy cas latency)
                if ((v_wait_timer <= (v_burst_length)) && (v_wait_timer > 0)) {
                    // Return data
                    *this->o_data = ((SelectTypeWidth<s_data_bit_width>::type *)p_v_backing_mem)[v_full_addr + (v_burst_length - v_wait_timer)];
                    DEBUG("SDRAM READ: Reading block #%d results \"%.4s\", size %ld bytes",
                        v_full_addr + (v_burst_length - v_wait_timer), (char*)this->o_data, sizeof(*this->o_data));
                }
                if (v_wait_timer == 0) {
                    // ...then we can allow another command
                    if ((!*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)) { // BankActive
                        v_state = WORK_ACTIVE;
                        v_wait_timer = s_c_active_wait;
                        v_row_addr = *this->i_addr; // save row addr
                        v_bank_addr_active = *this->i_ba; // save bank addr
                        DEBUG("SDRAM STATE CHANGE: READ to ACTIVE");
                    }
                    else if ((!*this->i_ras_n) && (!*this->i_cas_n) && (*this->i_we_n)) { // AutoRefresh
                        v_state = WORK_REFRESH;
                        v_wait_timer = s_c_refresh_wait;
                        DEBUG("SDRAM STATE CHANGE: READ to REFRESH");
                    }
                    else {
                        // idle
                        assert((*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)); // NOP
                        v_state = WORK_IDLE;
                        DEBUG("SDRAM STATE CHANGE: READ to IDLE");
                    }
                }
                else {
                    assert((*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)); // NOP
                }
                break;
            }
            case WORK_WRITE: {
                // Write data, from block index addr + 1
                if (v_wait_timer > (v_write_wait - v_burst_length)) { // not >= because already writen 1 block
                    DEBUG("SDRAM WRITE: Writing block #%d with \"%s\", size %ld bytes",
                        v_full_addr + (v_write_wait - v_wait_timer), (char*)&*this->i_data, sizeof(*this->i_data));
                    ((SelectTypeWidth<s_data_bit_width>::type *)p_v_backing_mem)[v_full_addr + (v_write_wait - v_wait_timer)] = *this->i_data;
                }
                if (v_wait_timer == 0) {
                    // ...then we can allow another command
                    if ((!*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)) { // BankActive
                        v_state = WORK_ACTIVE;
                        v_wait_timer = s_c_active_wait;
                        v_row_addr = *this->i_addr; // save row addr
                        v_bank_addr_active = *this->i_ba; // save bank addr
                        DEBUG("SDRAM STATE CHANGE: WRITE to ACTIVE");
                    }
                    else if ((!*this->i_ras_n) && (!*this->i_cas_n) && (*this->i_we_n)) { // AutoRefresh
                        v_state = WORK_REFRESH;
                        v_wait_timer = s_c_refresh_wait;
                        DEBUG("SDRAM STATE CHANGE: WRITE to REFRESH");
                    }
                    else {
                        // idle
                        assert((*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)); // NOP
                        v_state = WORK_IDLE;
                        DEBUG("SDRAM STATE CHANGE: WRITE to IDLE");
                    }
                }
                else {
                    assert((*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)); // NOP
                }
                break;
            }
            case WORK_REFRESH: {
                if (v_wait_timer == 0) {
                    // Refresh done
                    v_refresh_timer = s_c_max_refresh_interval;
                    // if receive active / idle
                    if ((!*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)) { // BankActive
                        v_state = WORK_ACTIVE;
                        v_wait_timer = s_c_active_wait;
                        v_row_addr = *this->i_addr; // save row addr
                        v_bank_addr_active = *this->i_ba; // save bank addr
                        DEBUG("SDRAM STATE CHANGE: REFRESH to ACTIVE");
                    }
                    else {
                        // idle
                        assert((*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)); // NOP
                        v_state = WORK_IDLE;
                        DEBUG("SDRAM STATE CHANGE: REFRESH to IDLE");
                    }
                }
                else {
                    assert((*this->i_ras_n) && (*this->i_cas_n) && (*this->i_we_n)); // NOP
                }
                break;
            }
            default: {
                abort();
            }
        }
    }
}
