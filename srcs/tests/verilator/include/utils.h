#ifndef UTILS_H
#define UTILS_H

// ==================================================================================================

/* https://stackoverflow.com/questions/36797770/get-function-parameters-count
 * template <typename R, typename ... Types> 
 * constexpr std::integral_constant<unsigned, sizeof ...(Types)> getArgumentCount( R(*f)(Types ...))
 * {
 *    return std::integral_constant<unsigned, sizeof ...(Types)>{};
 * }
 * With this, you can get the number of argument by using:
 * // Guaranteed to be evaluated at compile time
 * size_t count = decltype(getArgumentCount(foo))::value;
 * or
 * // Most likely evaluated at compile time
 * size_t count = getArgumentCount(foo).value;
 */ 

#include <type_traits>

template <typename R, typename ... Types> 
constexpr std::integral_constant<unsigned, sizeof ...(Types)> getArgumentCount( R(*f)(Types ...))
{
   return std::integral_constant<unsigned, sizeof ...(Types)>{};
}

// ==================================================================================================

// Get source file name
#define __FILENAME__ (__builtin_strrchr(__FILE__, '/') ? __builtin_strrchr(__FILE__, '/') + 1 : __FILE__)

// ==================================================================================================

#endif