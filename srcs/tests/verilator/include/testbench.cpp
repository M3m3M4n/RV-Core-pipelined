#include "testbench.h"

TestBench::TestBench(int argc, char **argv, unsigned long long runtime)
{
    p_context = new VerilatedContext();
    p_context->commandArgs(argc, argv);
    p_context->traceEverOn(true);

    enable_trace = 0;
    p_vcd_tracer = nullptr;

    // Hard limit @ ULLONG_MAX
    this->runtime_limit = (runtime == 0) ? ULLONG_MAX : runtime;

    testbench_clock_lock = 0;
}

TestBench::~TestBench(void)
{
    std::vector<ClockDomain *>::iterator i_domain;
    std::vector<IModule *>::iterator i_module;
    std::vector<IModel *>::iterator i_model;

    // delete models first since they have pointer to clock domain and nothing else
    for (i_model = this->v_models.begin(); i_model < this->v_models.end(); i_model++) {
        delete(*i_model);
        this->v_models.erase(i_model);
    }
    // next are domains because they hold ptr to models clk
    for (i_domain = this->v_domains.begin(); i_domain < this->v_domains.end(); i_domain++) {
        delete(*i_domain);
        this->v_domains.erase(i_domain);
    }
    // module last
    for (i_module = this->v_modules.begin(); i_module < this->v_modules.end(); i_module++) {
        delete(*i_module);
        this->v_modules.erase(i_module);
    }
    
    if(p_vcd_tracer) delete p_vcd_tracer;
    if(p_context) delete p_context;
}

VerilatedContext *TestBench::getContextPtr(void)
{
    return this->p_context;
}

VerilatedVcdC *TestBench::getTracerPtr(void)
{
    return this->p_vcd_tracer;
}

void TestBench::addClockDomain(ClockDomain *domain)
{
    assert(!testbench_clock_lock);
    assert(domain);
    this->v_domains.push_back(domain);
    // sort, check compare value not pointer
    std::sort(this->v_domains.begin(), this->v_domains.end());
    this->v_domains.erase(unique(this->v_domains.begin(), this->v_domains.end()), this->v_domains.end());
}

void TestBench::addModule(IModule *module)
{
    assert(module);
    this->v_modules.push_back(module);
    // sort
    std::sort(this->v_modules.begin(), this->v_modules.end());
    this->v_modules.erase(unique(this->v_modules.begin(), this->v_modules.end()), this->v_modules.end());
    // register tracer if exist
    if (this->p_vcd_tracer) {
        // Verilator does not allow calling trace after calling trace file open
        // so this behavior is not allowed
        // module->trace(this->p_vcd_tracer, 0, 0);
        DEBUG("THIS MODULE WILL NOT BE TRACED AFTER \'VerilatedVcdC::open()\'. Aborting.");
        abort();
    }
}

void TestBench::addModel(IModel *model)
{
    assert(model);
    this->v_models.push_back(model);
    // sort
    std::sort(this->v_models.begin(), this->v_models.end());
    this->v_models.erase(unique(this->v_models.begin(), this->v_models.end()), this->v_models.end());
}

void TestBench::vcdTraceSet(const char* vcdfile)
{
    // traceEverOn must be enabled
    if (!vcdfile) return;
    DEBUG("Set tracefile to: %s", vcdfile);
    if (!this->p_vcd_tracer) {
        this->p_vcd_tracer = new VerilatedVcdC();
        // Register to existing modules
        std::vector<IModule *>::iterator i_module;
        for (i_module = this->v_modules.begin(); i_module < this->v_modules.end(); i_module++) {
            IModule *module = *i_module;
            module->trace(this->p_vcd_tracer, 0, 0);
        }
        this->p_vcd_tracer->open(vcdfile);
    }
}

void TestBench::setTracing(unsigned char en, const char* vcdfile)
{
    if (!this->p_vcd_tracer) {
        DEBUG("Tracer not initialized");
        if (vcdfile == nullptr) return;
        else
            this->vcdTraceSet(vcdfile);
    }
    this->enable_trace = en;
}

void TestBench::moduleEval(void)
{
    std::vector<IModule *>::iterator i_module;
    for (i_module = this->v_modules.begin(); i_module < this->v_modules.end(); i_module++) {
        IModule *module = *i_module;
        module->evalStep();
    }
    for (i_module = v_modules.begin(); i_module < v_modules.end(); i_module++) {
        IModule *module = *i_module;
        module->evalEndStep();
    }
}

void TestBench::modelEval(void)
{
    std::vector<IModel *>::iterator i_model;
    for (i_model = this->v_models.begin(); i_model < this->v_models.end(); i_model++) {
        IModel *model = *i_model;
        model->eval();
    }
}

void TestBench::eval(void)
{
    // Set the lock if this is the first call to eval
    // No more clock signal after this
    if (!testbench_clock_lock) {
        testbench_clock_lock = 1;
    }

    // First call evals to evaluate first clock position at time 0
    // Module eval first incase models need output
    this->moduleEval();
    // 
    this->modelEval();
    // Call again to settle any logic by models
    this->moduleEval();
    // this->modelEval(); // This is not needed, probably
    // Dump - Officialy dump traces at this moment 
    if (p_vcd_tracer && enable_trace) {
        p_vcd_tracer->dump(this->p_context->time());
        p_vcd_tracer->flush();
    }

    unsigned long long ttne = 0;
    std::vector<ClockDomain *> v_next_domains;
    std::vector<ClockDomain *>::iterator i_domain;

    // Slow, PoC only
    for (i_domain = this->v_domains.begin(); i_domain < this->v_domains.end(); i_domain++) {
        unsigned long long ttne_tmp = (*i_domain)->timeToNextEdge(this->p_context->time());
        // ttne cannot be 0 given a single eval;
        if ((ttne == 0) || (ttne_tmp < ttne))
            ttne = ttne_tmp;
    }

    for (i_domain = this->v_domains.begin(); i_domain < this->v_domains.end(); i_domain++) {
        unsigned long long ttne_tmp = (*i_domain)->timeToNextEdge(this->p_context->time());
        if (ttne_tmp == ttne) 
            v_next_domains.push_back(*i_domain);
    }

    /* While it may look like the last step and the first step are identical since they both leave the clock at zero, they are not the same.
     * Between these two steps, co-simulation logic might change inputs to the design. 
     * Unless you call eval() following any co-simulation updates to design inputs,
     * combinational logic depending upon these inputs may not settle.
     */

    // Update time
    this->p_context->timeInc(ttne);
    // Set output value for clk signals from chosen domains, the rest stays
    // Next call to eval will evaluate at this time value
    for (i_domain = v_next_domains.begin(); i_domain < v_next_domains.end(); i_domain++)
        (*i_domain)->updateNewClockEdge(this->p_context->time());
}

void TestBench::evalUntilClockEdge(ClockDomain *sampler, unsigned char desired_edge)
{
    // Eval until current clock signal change
    unsigned char current_val = sampler->getClockSignalValue(this->p_context->time());
    do {
        this->eval();
    }
    while (sampler->getClockSignalValue(this->p_context->time()) == current_val);
    // Then eval until it is == desired_edge
    while (sampler->getClockSignalValue(this->p_context->time()) != desired_edge)
        this->eval();
}

bool TestBench::isDone(void)
{
    return ((this->p_context->time() >= this->runtime_limit) || (this->p_context)->gotFinish());
}
