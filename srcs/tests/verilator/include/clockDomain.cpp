#include "clockDomain.h"

ClockDomain::ClockDomain(double freq_mhz, double phase_shift_degree)
{
    assert((freq_mhz > 0) && (freq_mhz <= 500)); // support upto 500mhz atm
    assert((phase_shift_degree >= 0) && (phase_shift_degree <= 360)); // no point having it shift 0 or 360
    // Lock to picosec: half_period_ps = 1000000 / (2 * freq_mhz)
    // Smallest is 1ps, so must divisible: assert((fmod(500000.0, freq_mhz) == 0.0));
    // Or could round UP the half period value, thus SLOW DOWN the frequency
    // to get an integer half_period_ps value.
    this->half_period_ps = (unsigned long long) ceil(500000 / freq_mhz);
    this->period_ps      = 2 * this->half_period_ps;
    this->freq_mhz       = 1000000 / this->period_ps;

    // Shift deg = 360 * freq (hz) * delta t (sec)
    this->phase_delta_t_ps = (unsigned long long)(phase_shift_degree * 1000000 / ( 360 * freq_mhz)); // Rounded down
    this->phase_shift_degree = (this->phase_delta_t_ps * 360 * this->freq_mhz) / 1000000;

    // Values at time 0 calc-ed based on phase shift
    if (phase_shift_degree == 0 || phase_shift_degree == 360){
        this->last_posedge_ps = 0;
        this->saved_clock_value = 1;
    }
    else {
        if (this->phase_shift_degree <= 180)
            this->saved_clock_value = 0;
        else
            this->saved_clock_value = 1;
        this->last_posedge_ps = this->phase_delta_t_ps;
    }
    
    // ==================================================
    // Info dump
    DEBUG("########################################");
    DEBUG("INIT CLOCK DOMAIN %.2f MHZ, SHIFT %.2f DEG.", freq_mhz, phase_shift_degree);
    DEBUG("    Normalized frequency: %.2f", this->freq_mhz);
    DEBUG("    Period: %llu ps", this->period_ps);
    DEBUG("    Normalized phase: %.2f", this->phase_shift_degree);
    DEBUG("    Time until first posedge (phase delay): %llu ps", this->last_posedge_ps);
    DEBUG("    Initial clock: %d", this->saved_clock_value);
    DEBUG("########################################");
}

double ClockDomain::getFreqMhz()
{
    return this->freq_mhz;
}

double ClockDomain::getPhaseDeg()
{
    return this->phase_shift_degree;
}

unsigned long long ClockDomain::getLastPosedgePs()
{
    return this->last_posedge_ps;
}

unsigned char ClockDomain::isPosedgeAt(unsigned long long current_time_ps)
{
    if (current_time_ps > this->last_posedge_ps) {
        // assure current time does not skip cycle & on edge at current time
        if (current_time_ps == this->last_posedge_ps + this->period_ps)
            return 1;
        else if (current_time_ps == this->last_posedge_ps + this->half_period_ps)
            return 0;
        else
            // if neither edge assert false
            assert(0);
    }
    else if (current_time_ps < this->last_posedge_ps) {
        if ((long long)current_time_ps == (long long)(this->last_posedge_ps - this->period_ps))
            return 1;
        else if ((long long)current_time_ps == (long long)(this->last_posedge_ps - this->half_period_ps))
            return 0;
        else
            // if neither edge assert false
            assert(0);
    }
    else // ==
        return 1;
}

unsigned char ClockDomain::isPosedgeNext(unsigned long long current_time_ps)
{
    if (current_time_ps >= this->last_posedge_ps) {
        // < neg edge
        if (current_time_ps < this->last_posedge_ps + this->half_period_ps)
            return 0;
        // >= neg edge < next posedge
        else if (current_time_ps < this->last_posedge_ps + this->period_ps)
            return 1;
        else
            assert(0); // out of 1 cycle range
    } else {
        // During last negedge
        if ((long long)current_time_ps >= (long long)(this->last_posedge_ps - this->half_period_ps))
            return 1;
        // During last posedge
        else if ((long long)current_time_ps >= (long long)(this->last_posedge_ps - this->period_ps))
            return 0;
        else
            assert(0); // out of 1 cycle range
    }
}

unsigned long long ClockDomain::timeToNextEdge(unsigned long long current_time_ps)
{
    // Inside isPosedgeNext assert current time should not be more / less than last posedge +/- 1 cycle
    // So checking wont be needed here
    bool next_edge = this->isPosedgeNext(current_time_ps);
    if (current_time_ps >= this->last_posedge_ps) {
        if (next_edge)
            // Next edge is a positive edge
            return this->last_posedge_ps + this->period_ps - current_time_ps;
        else
            // Next edge is a negative edge
            return this->last_posedge_ps + this->half_period_ps - current_time_ps;
    }
    else {
        if (next_edge)
            return this->last_posedge_ps - current_time_ps;
        else
            return this->last_posedge_ps - this->half_period_ps - current_time_ps;
    }
}

unsigned char ClockDomain::getClockSignalValue(unsigned long long current_time_ps)
{
    return !(this->isPosedgeNext(current_time_ps));
}

unsigned char ClockDomain::getSavedClockSignalValue()
{
    return this->saved_clock_value;
}

void ClockDomain::updateNewClockEdge(unsigned long long edge_time_ps)
{
    // Assert inside isPosedgeAt if not edge at current time
    // Update clock value for models
    
    this->saved_clock_value = isPosedgeAt(edge_time_ps);
    // The only time where current time < last posedge is when initialized
    // with phase shift, so there will be case where last posedge is already equals
    // current time when called, sill, phase shifting should be less than 1 full cycle
    // so there no need for a check here
    if (this->saved_clock_value) {
        this->last_posedge_ps = edge_time_ps;
    }
    // update clock for modules
    std::vector<unsigned char *>::iterator i_clk;
    for (i_clk = this->v_module_clocks.begin(); i_clk < this->v_module_clocks.end(); i_clk++)
        *(*i_clk) = this->saved_clock_value;
}

bool ClockDomain::operator< (const ClockDomain& comp) const
{
    return std::make_tuple(this->freq_mhz, this->phase_shift_degree) < 
            std::make_tuple(comp.freq_mhz, comp.phase_shift_degree);
}

bool ClockDomain::operator== (const ClockDomain& comp) const
{
    return std::make_tuple(this->freq_mhz, this->phase_shift_degree) == 
            std::make_tuple(comp.freq_mhz, comp.phase_shift_degree);
}

void ClockDomain::addModuleClock(unsigned char * const clk)
{
    this->v_module_clocks.push_back(clk);
    std::sort(this->v_module_clocks.begin(), this->v_module_clocks.end());
    this->v_module_clocks.erase(unique(this->v_module_clocks.begin(), this->v_module_clocks.end()), this->v_module_clocks.end());
    // Set the clock value right away so we don't have to call updateNewClockEdge before first eval
    *clk = this->saved_clock_value;
}

void ClockDomain::removeModuleClock(unsigned char * const clk)
{
    this->v_module_clocks.erase(std::remove(this->v_module_clocks.begin(), this->v_module_clocks.end(), clk), this->v_module_clocks.end());
}

void ClockDomain::addModelClock(unsigned char ** clk)
{
    *clk = &this->saved_clock_value;
}
