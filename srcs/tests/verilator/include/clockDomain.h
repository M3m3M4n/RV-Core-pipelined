// IDEA: https://zipcpu.com/blog/2018/09/06/tbclock.html
//       in one context only eval where edge happens

#ifndef CLOCK_H
#define CLOCK_H

#include <vector>
#include <iterator>
#include <algorithm>
#include <tuple>

#include <cmath>
#include <cassert>

#include "debug.h"

class ClockDomain
{
private:
    // Derived from frequency, does not need to be in a particular unit like ms or ns or ps...
    // but will need uniformity between time unit in one verilator context.
    // So for the sake of clarity I will lock 1 time unit = 1 ps
    // => max 500MHz
    unsigned long long half_period_ps;
    unsigned long long period_ps;  // calculated using half_period_ps because it can be rounded up
    double freq_mhz;               // calculated using half_period_ps because it can be rounded up
    unsigned long long phase_delta_t_ps;
    double phase_shift_degree;     // Also rounded to fit with 1ps limit
    // Save the last time this get positive edge, again, does not need to be in a particular unit,
    // ps is only for clarity, allowing for upto 18446744073709551615ps (18446744s) simulation time
    // Should not stay behind or after current time more than 1 cycle
    // Support phase shifting by allowing last posedge to be after current time
    unsigned long long last_posedge_ps;
    // Stores clock line from modules, models in this clock domain
    std::vector<unsigned char *> v_module_clocks;
    // Models clocks point to this
    unsigned char saved_clock_value;

public:
    // NOTE ON MANAGING CLOCK SIGNALS:
    // Since verilated modules IOs are contained, and must be set explicitly.
    // Clock signal to them must be set via pointer, stored in this class
    // For custom simulation models, I want them to be connect-and-forget
    // so their IOs are public pointers, pointed to verilated models IOs,
    // for clock signal, will point to saved_clock_value.
    // All and all saved_clock_value is only for changing model clocks, not ideal
    // now we have multiple way of getting the same clock -> more to maintain

    // All functions below take current time from testbench as it owns the context
    
    // All clocks start with posedge position at time 0, assume the first point in time
    // is where ALL domain has posedge
    ClockDomain(double freq_mhz, double phase_shift = 0);
    double getFreqMhz();
    double getPhaseDeg();
    unsigned long long getLastPosedgePs();
    // Check if a posedge is at current time time that is not last posedge
    unsigned char isPosedgeAt(unsigned long long current_time_ps);
    // Check if a posedge is next according to current time
    // Can also be used to get current clock value (== !isPosedgeNext)
    unsigned char isPosedgeNext(unsigned long long current_time_ps);
    // return amount of time until next edge
    // testbench should call this to get the list of next clock domains to edge
    unsigned long long timeToNextEdge(unsigned long long current_time_ps);
    // get current clock value based on current time;
    unsigned char getClockSignalValue(unsigned long long current_time_ps);
    // return value of saved_clock_value;
    unsigned char getSavedClockSignalValue();
    // Setting signal according to current edge time
    // Update saved_clock_value. Also set last_posedge time
    // ONLY called once list of next clock domains to edge is created and time is already advanced (edge time = prev current + time to edge)
    void updateNewClockEdge(unsigned long long edge_time_ps);
    // For sorting clock domains, std::sort uses < and ==
    bool operator< (const ClockDomain& comp) const;
    bool operator== (const ClockDomain& comp) const;
    // Manage module clock signals in this domain
    void addModuleClock(unsigned char * const clk);
    void removeModuleClock(unsigned char * const clk);
    // Set the model clock signal to point to saved_clock_value
    void addModelClock(unsigned char ** clk);
};

#endif
