#ifndef TESTBENCH_H
#define TESTBENCH_H

#include <climits>

#include <vector>
#include <iterator>
#include <verilated.h>
#include <verilated_vcd_c.h>

#include "module.h"
#include "models/model.h"
#include "debug.h"

class TestBench {
protected:
    // All the modules inside this testbench share the same sense of time (therefore sharing context)
    VerilatedContext* p_context;
    // Tracer
    unsigned char enable_trace;
	VerilatedVcdC *p_vcd_tracer;
    // Multiple clock domain share the same context. DOES NOT support phase shift
    std::vector<ClockDomain *> v_domains;
    std::vector<IModule *> v_modules;
    std::vector<IModel *> v_models;
    // Runtime, this is used to check in isDone
    unsigned long long runtime_limit;
    // Flags
    // Not allow adding clock signal after eval to ensure clock domain synchronicity
    unsigned char testbench_clock_lock;
    // Funcs
    void moduleEval(void);
    void modelEval(void);
public:
	TestBench(int argc, char **argv, unsigned long long runtime = 0);
	~TestBench(void);

    VerilatedContext *getContextPtr(void);
    VerilatedVcdC *getTracerPtr(void);   

    // All added clock module started with a posedge,
    // consider that time 0 is the point that all clock signal align
    // any deviation from this is used as phase shift
    void addClockDomain(ClockDomain *domain);
    void addModule(IModule *module);
    void addModel(IModel *model);

    void vcdTraceSet(const char* vcdfile);
    // Won't work without tracer set, so set them first
    void setTracing(unsigned char en, const char* vcdfile = nullptr);
    
    /* Iterate through clock domains to see which will tick next 
     * Currently using vector, might change to unordered_map, unique value
     * Module eval scheme:
     * - Given multiple clock domains, find the minimum amount of time to next clock edge, what edge does not mater
     *   and it also does not matter if multiple edge happend at the same time since we are going to eval all module anyway
     * - There MUST be an ack signal if we are to expect that a change in data is to be registered, since we cannot be sure
     *   we are evaling the clock that data just get set. If there are no mechanism for ack-ing then the change
     *   might not be registered at all before we change it again.
     */
    virtual void eval(void);
    // TODO: THREADING SUPPORT FOR EACH DOMAIN
    // Eval until the selected clock domain signal reach desired clock edge
    virtual void evalUntilClockEdge(ClockDomain *sampler, unsigned char desired_edge);
	virtual bool isDone(void);
};

#endif // TESTBENCH_H
