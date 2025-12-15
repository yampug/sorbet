#ifndef SORBET_ENFORCENOTIMER_H
#define SORBET_ENFORCENOTIMER_H

#include "common/exception/Exception.h"
#include "common/os/os.h"
#include "sorbet_version/sorbet_version.h"

#define _MAYBE_ADD_COMMA(...) , ##__VA_ARGS__

// A faster version of ENFORCE that does not emit a timer. Useful for checks that happen extremely frequently and
// are O(1). Please avoid using unless ENFORCE shows up in profiles.
#include <type_traits>

namespace sorbet {
namespace detail {
template <typename T, typename... Args>
constexpr bool check_enforce_condition(const T& val, const Args&... args) {
    if constexpr (std::is_convertible_v<T, bool>) {
        return static_cast<bool>(val);
    } else {
        return true; // Skip check if not boolean (workaround for MSVC macro issues)
    }
}
} // namespace detail
} // namespace sorbet

#define ENFORCE_NO_TIMER(x, ...)                                                                            \
    do {                                                                                                    \
        if (::sorbet::debug_mode) {                                                                         \
            if (!::sorbet::detail::check_enforce_condition(x)) {                                            \
                ::sorbet::Exception::failInFuzzer();                                                        \
                if (stopInDebugger()) {                                                                     \
                    ((void)0);                                                                             \
                }                                                                                           \
                ::sorbet::Exception::enforce_handler(#x, __FILE__, __LINE__ _MAYBE_ADD_COMMA(__VA_ARGS__)); \
            }                                                                                               \
        }                                                                                                   \
    } while (false);

#endif // SORBET_ENFORCENOTIMER_H
