#ifndef MODULE_H
#define MODULE_H

#include <memory>
#include <verilated.h>
#include <verilated_vcd_c.h>

#include "debug.h"
#include "clockDomain.h"

// Verilator access submodule signal
// https://www.embecosm.com/appnotes/ean6/html/ch06s02.html

class IModule {
public:
    // Return pointer to verilator UUT
	virtual void *getUUTPtr(void) = 0;
    virtual void trace(VerilatedVcdC* tfp, int levels, int options = 0) = 0;
    // eval_step & eval_end_step, refer to Verilator's doc for multiple design in a single context
    // https://verilator.org/guide/latest/connecting.html#wrappers-and-model-evaluation-loop
    virtual void evalStep(void) = 0;
    virtual void evalEndStep(void) = 0;
    virtual bool operator< (const IModule& comp) const = 0;
    virtual bool operator== (const IModule& comp) const = 0;
};

template<class UUT>
class Module : public IModule {
protected:
	UUT *p_uut;

public:
	Module(VerilatedContext *p_context, const char *p_name);
	~Module(void);

	void *getUUTPtr(void) override;

    void trace(VerilatedVcdC* tfp, int levels, int options = 0) override;
    
    virtual void evalStep(void) override;
    virtual void evalEndStep(void) override;

    bool operator< (const IModule& comp) const override;
    bool operator== (const IModule& comp) const override;
};

// g++ template function not in object file
// https://stackoverflow.com/questions/64544744/g-skipping-a-function-when-compiling-to-object-file
// Just keep implementation here for now

template <class UUT>
Module<UUT>::Module(VerilatedContext *p_context, const char *p_name)
{
    this->p_uut = new UUT(p_context, p_name);
}

template <class UUT>
Module<UUT>::~Module(void)
{
    this->p_uut->final();
    delete this->p_uut;
    this->p_uut = nullptr;
}

template <class UUT>
void *Module<UUT>::getUUTPtr(void)
{
    return (void *)this->p_uut;
}

template <class UUT>
void Module<UUT>::trace(VerilatedVcdC *tfp, int levels, int options)
{
    this->p_uut->trace(tfp, levels, options);
}

template <class UUT>
void Module<UUT>::evalStep(void)
{
    this->p_uut->eval_step();
}

template <class UUT>
void Module<UUT>::evalEndStep(void)
{
    this->p_uut->eval_end_step();
}

template <class UUT>
bool Module<UUT>::operator< (const IModule& comp) const
{
    return (this < &comp);
}

template <class UUT>
bool Module<UUT>::operator== (const IModule& comp) const
{
    return (this == &comp);
}

#endif // MODULE_H
