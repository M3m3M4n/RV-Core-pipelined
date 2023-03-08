#ifndef DEBUG_H
#define DEBUG_H

#include <iostream>
#include <cstdio>

#ifndef ENDEBUG
#define ENDEBUG 1
#endif

#if ENDEBUG
#define DEBUG(...) {\
    char str[256];\
    snprintf(str, 256, __VA_ARGS__);\
    std::cout << "[" << __FILE__ << "][" << __FUNCTION__ << "][Line " << __LINE__ << "] " << str << std::endl;\
    }
#else
#define DEBUG(...)
#endif

#endif
