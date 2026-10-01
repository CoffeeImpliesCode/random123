/*
 * Random123 C bridge -- public declarations for the Zig packaging.
 *
 * Copyright 2025 CoffeeImpliesCode contributors.
 * Upstream Random123 (c) 2010-2016 D. E. Shaw Research, BSD-3-Clause.
 * See NOTICE.md.  This file is a fork addition; it contains no upstream code.
 *
 * Random123 is a header-only C library: every algorithm is a
 * `R123_STATIC_INLINE` (that is, `static __inline__`) function and every
 * default-round entry point is a preprocessor macro.  Nothing in the upstream
 * tree produces a linkable symbol.  The translation unit
 * `random123_bridge.c` includes the upstream headers verbatim and defines the
 * plain, externally linked wrappers declared here, so that a compiled
 * `librandom123` carries the genuine upstream algorithms.
 *
 * Nothing in this header reimplements an algorithm.  Each wrapper is a single
 * call into the upstream inline function, using the upstream types.
 *
 * The `r123arrayNxW` counter and key types are the upstream types; they are
 * declared here by tag so that this header stays free of the SSE/AES-NI
 * intrinsics that `<Random123/array.h>` may pull in on x86.
 */

#ifndef R123_BRIDGE_H_
#define R123_BRIDGE_H_

#include <stdint.h>

#include <Random123/array.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Default round counts and the AES-NI expanded-key geometry are mirrored here
 * so that the translated Zig surface can see them.  Every numeric constant
 * below is static-asserted in random123_bridge.c against the upstream macro
 * of the same meaning, so none of them can drift from Random123 without
 * failing the build.
 *
 * Upstream: PHILOxNxW_DEFAULT_ROUNDS, THREEFRYNxW_DEFAULT_ROUNDS,
 * ARS1xm128i_DEFAULT_ROUNDS and aesni4x32_rounds in include/Random123, and
 * aesni1xm128i_key_t { __m128i k[11]; } in include/Random123/aes.h.  The AES
 * key word count has no macro; it is asserted by size, against
 * sizeof(aesni4x32_key_t).
 */
typedef enum r123_bridge_rounds {
    R123_BRIDGE_PHILOX2x32_DEFAULT_ROUNDS = 10,
    R123_BRIDGE_PHILOX2x64_DEFAULT_ROUNDS = 10,
    R123_BRIDGE_PHILOX4x32_DEFAULT_ROUNDS = 10,
    R123_BRIDGE_PHILOX4x64_DEFAULT_ROUNDS = 10,
    R123_BRIDGE_THREEFRY2x32_DEFAULT_ROUNDS = 20,
    R123_BRIDGE_THREEFRY2x64_DEFAULT_ROUNDS = 20,
    R123_BRIDGE_THREEFRY4x32_DEFAULT_ROUNDS = 20,
    R123_BRIDGE_THREEFRY4x64_DEFAULT_ROUNDS = 20,
    R123_BRIDGE_ARS4x32_DEFAULT_ROUNDS = 7,
    R123_BRIDGE_AESNI4x32_ROUNDS = 10,
    /* An expanded AES-NI key schedule is 11 round keys of 128 bits. */
    R123_BRIDGE_AESNI_KEY_WORDS = 44
} r123_bridge_rounds;

/*
 * Declares the AES-NI and ARS wrappers.  The build defines this to 1 only for
 * an x86 or x86_64 target that carries the `aes` CPU feature, and the build
 * adds that feature to the target rather than passing a -maes cflag, because
 * upstream's own gate is R123_USE_AES_NI and that comes from __AES__, which
 * describes the target CPU.  `random123_bridge.c` static-asserts that the two
 * agree, so the declarations below can never outlive their definitions.
 *
 * The assertion lives in the .c, not here, because this header is also the
 * translate-c input, where R123_USE_SSE is pinned to 0 and upstream's AES-NI
 * gate is deliberately off: here this macro is the only gate, and the
 * declarations below are plain word arrays with no __m128i in them.
 *
 * Never forced on a non-x86 target: see UPSTREAM.md, "AES-NI and ARS".
 */
#ifndef R123_BRIDGE_HAS_AESNI
#define R123_BRIDGE_HAS_AESNI 0
#endif

/* ---------------------------------------------------------------- Philox */

struct r123array1x32 r123_bridge_philox2x32_keyinit(struct r123array1x32 ukey);
struct r123array2x32 r123_bridge_philox2x32_R(unsigned int rounds,
                                             struct r123array2x32 ctr,
                                             struct r123array1x32 key);

struct r123array2x32 r123_bridge_philox4x32_keyinit(struct r123array2x32 ukey);
struct r123array4x32 r123_bridge_philox4x32_R(unsigned int rounds,
                                             struct r123array4x32 ctr,
                                             struct r123array2x32 key);

struct r123array1x64 r123_bridge_philox2x64_keyinit(struct r123array1x64 ukey);
struct r123array2x64 r123_bridge_philox2x64_R(unsigned int rounds,
                                             struct r123array2x64 ctr,
                                             struct r123array1x64 key);

struct r123array2x64 r123_bridge_philox4x64_keyinit(struct r123array2x64 ukey);
struct r123array4x64 r123_bridge_philox4x64_R(unsigned int rounds,
                                             struct r123array4x64 ctr,
                                             struct r123array2x64 key);

/* -------------------------------------------------------------- Threefry */

struct r123array2x32 r123_bridge_threefry2x32_keyinit(struct r123array2x32 ukey);
struct r123array2x32 r123_bridge_threefry2x32_R(unsigned int rounds,
                                               struct r123array2x32 ctr,
                                               struct r123array2x32 key);

struct r123array4x32 r123_bridge_threefry4x32_keyinit(struct r123array4x32 ukey);
struct r123array4x32 r123_bridge_threefry4x32_R(unsigned int rounds,
                                               struct r123array4x32 ctr,
                                               struct r123array4x32 key);

struct r123array2x64 r123_bridge_threefry2x64_keyinit(struct r123array2x64 ukey);
struct r123array2x64 r123_bridge_threefry2x64_R(unsigned int rounds,
                                               struct r123array2x64 ctr,
                                               struct r123array2x64 key);

struct r123array4x64 r123_bridge_threefry4x64_keyinit(struct r123array4x64 ukey);
struct r123array4x64 r123_bridge_threefry4x64_R(unsigned int rounds,
                                               struct r123array4x64 ctr,
                                               struct r123array4x64 key);

/* ------------------------------------------ u01fixedpt: integer to real */

/*
 * Converting random words to uniformly distributed floating point values.
 * Names map one-to-one onto the u01fixedpt_* functions upstream; the naming
 * is <range>_<word input>, matching the upstream C names.
 */

float r123_bridge_u01_closed_closed_32_float(uint32_t i);
float r123_bridge_u01_closed_open_32_float(uint32_t i);
float r123_bridge_u01_open_closed_32_float(uint32_t i);
float r123_bridge_u01_open_open_32_float(uint32_t i);

double r123_bridge_u01_closed_closed_32_double(uint32_t i);
double r123_bridge_u01_closed_open_32_double(uint32_t i);
double r123_bridge_u01_open_closed_32_double(uint32_t i);
double r123_bridge_u01_open_open_32_double(uint32_t i);

double r123_bridge_u01_closed_closed_64_double(uint64_t i);
double r123_bridge_u01_closed_open_64_double(uint64_t i);
double r123_bridge_u01_open_closed_64_double(uint64_t i);
double r123_bridge_u01_open_open_64_double(uint64_t i);

/* ----------------------------------------------------- AES-NI / ARS (x86) */

#if R123_BRIDGE_HAS_AESNI

/* Upstream CPUID probe (features/sse.h): nonzero when the running CPU has AES-NI. */
int r123_bridge_have_aesni(void);

/*
 * The 4x32 AES-NI and ARS CBRNGs take and return plain r123array4x32 words,
 * so no __m128i ever crosses the bridge boundary.  The AES-NI key is opaque:
 * it is an 11-round schedule handed back and forth as
 * R123_BRIDGE_AESNI_KEY_WORDS 32-bit words, which is byte-for-byte
 * aesni1xm128i_key_t.
 */
void r123_bridge_aesni4x32_keyinit(uint32_t *key_schedule, struct r123array4x32 ukey);
struct r123array4x32 r123_bridge_aesni4x32_R(unsigned int rounds,
                                             struct r123array4x32 ctr,
                                             const uint32_t *key_schedule);

struct r123array4x32 r123_bridge_ars4x32_keyinit(struct r123array4x32 ukey);
struct r123array4x32 r123_bridge_ars4x32_R(unsigned int rounds,
                                           struct r123array4x32 ctr,
                                           struct r123array4x32 key);

#endif /* R123_BRIDGE_HAS_AESNI */

#ifdef __cplusplus
}
#endif

#endif /* R123_BRIDGE_H_ */
