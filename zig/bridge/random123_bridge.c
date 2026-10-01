/*
 * Random123 C bridge -- implementation.
 *
 * Copyright 2025 CoffeeImpliesCode contributors.
 * Upstream Random123 (c) 2010-2016 D. E. Shaw Research, BSD-3-Clause.
 * See NOTICE.md.  This file is a fork addition; it contains no upstream code.
 *
 * Every function below is a one-line forwarder into the genuine upstream
 * `static __inline__` implementation included from the vendored headers.  The
 * file exists purely to give those inline algorithms external linkage so that
 * a compiled `librandom123` can be linked and translated.
 */

#include "random123_bridge.h"

#include <Random123/features/compilerfeatures.h>
#include <Random123/philox.h>
#include <Random123/threefry.h>
#include <Random123/u01fixedpt.h>

#if R123_BRIDGE_HAS_AESNI
#include <string.h>

#include <Random123/aes.h>
#include <Random123/ars.h>
#endif

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
#define R123_BRIDGE_STATIC_ASSERT(cond, msg) _Static_assert(cond, msg)
#else
#define R123_BRIDGE_STATIC_ASSERT(cond, msg) R123_STATIC_ASSERT(cond, msg)
#endif

/*
 * The constants published in random123_bridge.h must match upstream exactly.
 * If a future Random123 release changes a default, this file stops compiling
 * and the Zig facade's documented round counts are corrected deliberately.
 */
R123_BRIDGE_STATIC_ASSERT(PHILOX2x32_DEFAULT_ROUNDS == R123_BRIDGE_PHILOX2x32_DEFAULT_ROUNDS,
                          "philox2x32 default round count drifted");
R123_BRIDGE_STATIC_ASSERT(PHILOX2x64_DEFAULT_ROUNDS == R123_BRIDGE_PHILOX2x64_DEFAULT_ROUNDS,
                          "philox2x64 default round count drifted");
R123_BRIDGE_STATIC_ASSERT(PHILOX4x32_DEFAULT_ROUNDS == R123_BRIDGE_PHILOX4x32_DEFAULT_ROUNDS,
                          "philox4x32 default round count drifted");
R123_BRIDGE_STATIC_ASSERT(PHILOX4x64_DEFAULT_ROUNDS == R123_BRIDGE_PHILOX4x64_DEFAULT_ROUNDS,
                          "philox4x64 default round count drifted");
R123_BRIDGE_STATIC_ASSERT(THREEFRY2x32_DEFAULT_ROUNDS == R123_BRIDGE_THREEFRY2x32_DEFAULT_ROUNDS,
                          "threefry2x32 default round count drifted");
R123_BRIDGE_STATIC_ASSERT(THREEFRY2x64_DEFAULT_ROUNDS == R123_BRIDGE_THREEFRY2x64_DEFAULT_ROUNDS,
                          "threefry2x64 default round count drifted");
R123_BRIDGE_STATIC_ASSERT(THREEFRY4x32_DEFAULT_ROUNDS == R123_BRIDGE_THREEFRY4x32_DEFAULT_ROUNDS,
                          "threefry4x32 default round count drifted");
R123_BRIDGE_STATIC_ASSERT(THREEFRY4x64_DEFAULT_ROUNDS == R123_BRIDGE_THREEFRY4x64_DEFAULT_ROUNDS,
                          "threefry4x64 default round count drifted");

R123_BRIDGE_STATIC_ASSERT(R123_USE_PHILOX_64BIT,
                          "build must supply a 64x64->128 multiply for Philox Nx64");

/*
 * The Zig facade represents a counter or key as a plain [N]Word array and
 * fills the `v` member of the upstream struct when calling in.  That is only
 * sound while the upstream struct is exactly one fixed-size array of exactly
 * that word type: assert it here rather than trusting the preprocessor.
 */
R123_BRIDGE_STATIC_ASSERT(sizeof(struct r123array1x32) == sizeof(uint32_t),
                          "r123array1x32 is not a bare 32-bit word");
R123_BRIDGE_STATIC_ASSERT(sizeof(struct r123array2x32) == 2 * sizeof(uint32_t),
                          "r123array2x32 is not two bare 32-bit words");
R123_BRIDGE_STATIC_ASSERT(sizeof(struct r123array4x32) == 4 * sizeof(uint32_t),
                          "r123array4x32 is not four bare 32-bit words");
R123_BRIDGE_STATIC_ASSERT(sizeof(struct r123array1x64) == sizeof(uint64_t),
                          "r123array1x64 is not a bare 64-bit word");
R123_BRIDGE_STATIC_ASSERT(sizeof(struct r123array2x64) == 2 * sizeof(uint64_t),
                          "r123array2x64 is not two bare 64-bit words");
R123_BRIDGE_STATIC_ASSERT(sizeof(struct r123array4x64) == 4 * sizeof(uint64_t),
                          "r123array4x64 is not four bare 64-bit words");

/* ---------------------------------------------------------------- Philox */

struct r123array1x32 r123_bridge_philox2x32_keyinit(struct r123array1x32 ukey)
{
    return philox2x32keyinit(ukey);
}

struct r123array2x32 r123_bridge_philox2x32_R(unsigned int rounds,
                                             struct r123array2x32 ctr,
                                             struct r123array1x32 key)
{
    return philox2x32_R(rounds, ctr, key);
}

struct r123array2x32 r123_bridge_philox4x32_keyinit(struct r123array2x32 ukey)
{
    return philox4x32keyinit(ukey);
}

struct r123array4x32 r123_bridge_philox4x32_R(unsigned int rounds,
                                             struct r123array4x32 ctr,
                                             struct r123array2x32 key)
{
    return philox4x32_R(rounds, ctr, key);
}

struct r123array1x64 r123_bridge_philox2x64_keyinit(struct r123array1x64 ukey)
{
    return philox2x64keyinit(ukey);
}

struct r123array2x64 r123_bridge_philox2x64_R(unsigned int rounds,
                                             struct r123array2x64 ctr,
                                             struct r123array1x64 key)
{
    return philox2x64_R(rounds, ctr, key);
}

struct r123array2x64 r123_bridge_philox4x64_keyinit(struct r123array2x64 ukey)
{
    return philox4x64keyinit(ukey);
}

struct r123array4x64 r123_bridge_philox4x64_R(unsigned int rounds,
                                             struct r123array4x64 ctr,
                                             struct r123array2x64 key)
{
    return philox4x64_R(rounds, ctr, key);
}

/* -------------------------------------------------------------- Threefry */

struct r123array2x32 r123_bridge_threefry2x32_keyinit(struct r123array2x32 ukey)
{
    return threefry2x32keyinit(ukey);
}

struct r123array2x32 r123_bridge_threefry2x32_R(unsigned int rounds,
                                               struct r123array2x32 ctr,
                                               struct r123array2x32 key)
{
    return threefry2x32_R(rounds, ctr, key);
}

struct r123array4x32 r123_bridge_threefry4x32_keyinit(struct r123array4x32 ukey)
{
    return threefry4x32keyinit(ukey);
}

struct r123array4x32 r123_bridge_threefry4x32_R(unsigned int rounds,
                                               struct r123array4x32 ctr,
                                               struct r123array4x32 key)
{
    return threefry4x32_R(rounds, ctr, key);
}

struct r123array2x64 r123_bridge_threefry2x64_keyinit(struct r123array2x64 ukey)
{
    return threefry2x64keyinit(ukey);
}

struct r123array2x64 r123_bridge_threefry2x64_R(unsigned int rounds,
                                               struct r123array2x64 ctr,
                                               struct r123array2x64 key)
{
    return threefry2x64_R(rounds, ctr, key);
}

struct r123array4x64 r123_bridge_threefry4x64_keyinit(struct r123array4x64 ukey)
{
    return threefry4x64keyinit(ukey);
}

struct r123array4x64 r123_bridge_threefry4x64_R(unsigned int rounds,
                                               struct r123array4x64 ctr,
                                               struct r123array4x64 key)
{
    return threefry4x64_R(rounds, ctr, key);
}

/* ------------------------------------------ u01fixedpt: integer to real */

float r123_bridge_u01_closed_closed_32_float(uint32_t i)
{
    return u01fixedpt_closed_closed_32_float(i);
}

float r123_bridge_u01_closed_open_32_float(uint32_t i)
{
    return u01fixedpt_closed_open_32_float(i);
}

float r123_bridge_u01_open_closed_32_float(uint32_t i)
{
    return u01fixedpt_open_closed_32_float(i);
}

float r123_bridge_u01_open_open_32_float(uint32_t i)
{
    return u01fixedpt_open_open_32_float(i);
}

double r123_bridge_u01_closed_closed_32_double(uint32_t i)
{
    return u01fixedpt_closed_closed_32_double(i);
}

double r123_bridge_u01_closed_open_32_double(uint32_t i)
{
    return u01fixedpt_closed_open_32_double(i);
}

double r123_bridge_u01_open_closed_32_double(uint32_t i)
{
    return u01fixedpt_open_closed_32_double(i);
}

double r123_bridge_u01_open_open_32_double(uint32_t i)
{
    return u01fixedpt_open_open_32_double(i);
}

double r123_bridge_u01_closed_closed_64_double(uint64_t i)
{
    return u01fixedpt_closed_closed_64_double(i);
}

double r123_bridge_u01_closed_open_64_double(uint64_t i)
{
    return u01fixedpt_closed_open_64_double(i);
}

double r123_bridge_u01_open_closed_64_double(uint64_t i)
{
    return u01fixedpt_open_closed_64_double(i);
}

double r123_bridge_u01_open_open_64_double(uint64_t i)
{
    return u01fixedpt_open_open_64_double(i);
}

/* ----------------------------------------------------- AES-NI / ARS (x86) */

#if R123_BRIDGE_HAS_AESNI

/*
 * R123_BRIDGE_HAS_AESNI says the build wants the AES-NI and ARS wrappers;
 * R123_USE_AES_NI is upstream's own gate, derived from __AES__ in
 * features/gccfeatures.h:113-119, and it is what actually makes aes.h and
 * ars.h declare anything.  The two can disagree -- a -maes cflag alone does
 * not make a compiler define __AES__ -- and when they do, this header still
 * declares the wrappers while the library contains none of them, which is a
 * link error waiting for whoever links it.  Fail here instead.
 */
R123_BRIDGE_STATIC_ASSERT(R123_USE_AES_NI,
                          "R123_BRIDGE_HAS_AESNI is set but upstream R123_USE_AES_NI is 0: the aes CPU feature did not reach the C compiler");

R123_BRIDGE_STATIC_ASSERT(sizeof(aesni4x32_key_t) == 11 * sizeof(__m128i),
                          "aesni4x32 key schedule is not 11 round keys");
R123_BRIDGE_STATIC_ASSERT(sizeof(aesni4x32_key_t) == R123_BRIDGE_AESNI_KEY_WORDS * sizeof(uint32_t),
                          "R123_BRIDGE_AESNI_KEY_WORDS no longer matches aesni4x32_key_t");
R123_BRIDGE_STATIC_ASSERT(ARS1xm128i_DEFAULT_ROUNDS == R123_BRIDGE_ARS4x32_DEFAULT_ROUNDS,
                          "ars4x32 default round count drifted");
R123_BRIDGE_STATIC_ASSERT(ars1xm128i_rounds == R123_BRIDGE_ARS4x32_DEFAULT_ROUNDS,
                          "ars1xm128i_rounds and ars4x32_rounds disagree upstream");
R123_BRIDGE_STATIC_ASSERT(aesni4x32_rounds == R123_BRIDGE_AESNI4x32_ROUNDS,
                          "aesni4x32_rounds drifted");

/* Upstream CPUID probe: true when the running CPU has AES-NI. */
int r123_bridge_have_aesni(void)
{
    return haveAESNI();
}

void r123_bridge_aesni4x32_keyinit(uint32_t *key_schedule, struct r123array4x32 ukey)
{
    aesni4x32_key_t schedule = aesni4x32keyinit(ukey);
    memcpy(key_schedule, &schedule, sizeof schedule);
}

struct r123array4x32 r123_bridge_aesni4x32_R(unsigned int rounds,
                                             struct r123array4x32 ctr,
                                             const uint32_t *key_schedule)
{
    aesni4x32_key_t schedule;
    memcpy(&schedule, key_schedule, sizeof schedule);
    return aesni4x32_R(rounds, ctr, schedule);
}

struct r123array4x32 r123_bridge_ars4x32_keyinit(struct r123array4x32 ukey)
{
    return ars4x32keyinit(ukey);
}

struct r123array4x32 r123_bridge_ars4x32_R(unsigned int rounds,
                                           struct r123array4x32 ctr,
                                           struct r123array4x32 key)
{
    return ars4x32_R(rounds, ctr, key);
}

#endif /* R123_BRIDGE_HAS_AESNI */
