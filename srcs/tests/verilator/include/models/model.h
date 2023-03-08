#ifndef MODEL_H
#define MODEL_H

class IModel
{
public:
    // NOTE: eval can be called multiple time per clock edge, so its best to 
    // create a function called cycle and using eval only to detect clock edge,
    // then only on clock edge cycle is called
    virtual void eval() = 0;
    virtual bool operator< (const IModel& comp) const = 0;
    virtual bool operator== (const IModel& comp) const = 0;
    // REQUIREMENT FOR IOs: MUST be pointers
};

#endif