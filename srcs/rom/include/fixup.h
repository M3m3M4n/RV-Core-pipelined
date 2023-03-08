#ifndef FIXUP_H
#define FIXUP_H

// Fixup SP to 2^pow
#define sp_fixup_2_power(pow) \
    __asm__ __volatile__ ("slti    sp,zero,1;"\
                          "slli    sp,sp,%0;"\
                           :: "I" (pow));

// FP to SP + arg, should only 10 bit long (+1 for signed?)
#define fp_fixup_plus_arg(arg) \
    __asm__ __volatile__ ("addi    s0,sp,%0;"\
                           :: "I" (arg));

#endif /* FIXUP_H */





