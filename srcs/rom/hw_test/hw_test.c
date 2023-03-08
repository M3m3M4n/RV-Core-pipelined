
// Basic test
// No CSR or SYSTEM related instrs

#include <stdint.h>
#include "addr.h"
#include "reset.h"

char badidea()
{
    uint32_t a = 0xffffffff;
    uint32_t b = a, c = a;
    int16_t  d;
    int8_t   e;
    // adding, shifting
    for (e = 0; e < 4; e++) {
    b <<= 8;
    c >>= 8;
    }
    b += 0xaca6;
    // sub
    c -= 1;
    if (b == c) {
    a = 0xff;
    }
    else {
    a = 0xff00;
    }
    b ^= 0xff;
    c |= 0xff;
    a *= b;
    d  = (uint16_t)(a / 0x17195);
    d &= 0xffff;
    a += (uint32_t)d;
    if (a == 0xabad1dea)
        return 1;
    else
        return 0;
}

int main()
{
    if (badidea()) {
        while(1)
            *addr_gpio_out = *addr_gpio_in;
    }
    else {
        while(1);
    }
}