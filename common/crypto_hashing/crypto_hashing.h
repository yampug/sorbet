#ifndef RUBY_TYPER_CRYPTO_HASHING_H
#define RUBY_TYPER_CRYPTO_HASHING_H

#include "common/common.h"
extern "C" {
#if defined(__i386__) || defined(__x86_64__) || defined(_M_X64) || defined(_M_IX86)
#include "blake2.h"
#elif defined(__aarch64__)
#include "neon/blake2.h"
#else
#include "ref/blake2.h"
#endif
};

namespace sorbet::crypto_hashing {
inline std::array<uint8_t, 64> hash64(std::string_view data) {
    static_assert(BLAKE2B_OUTBYTES == 64);
    std::array<uint8_t, 64> res;

#if defined(__i386__) || defined(__x86_64__) || defined(_M_X64) || defined(_M_IX86)
    int err = blake2b(&res[0], data.data(), nullptr, std::size(res), data.size(), 0);
#else
    // it has different order of arguments \facepalm
    int err = blake2b(&res[0], std::size(res), data.data(), data.size(), nullptr, 0);
#endif
    ENFORCE(err == 0);
    return res;
};
} // namespace sorbet::crypto_hashing
#endif // RUBY_TYPER_CRYPTO_HASHING_H
