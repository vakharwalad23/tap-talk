#ifndef RING_ATOMICS_H
#define RING_ATOMICS_H

#include <stdint.h>

// Acquire/release access to the sample ring counters; Swift's Atomic type needs macOS 15.
static inline int64_t tt_load_acquire(const int64_t *p) { return __atomic_load_n(p, __ATOMIC_ACQUIRE); }
static inline void tt_store_release(int64_t *p, int64_t v) { __atomic_store_n(p, v, __ATOMIC_RELEASE); }
static inline void tt_add_relaxed(int64_t *p, int64_t v) { (void)__atomic_fetch_add(p, v, __ATOMIC_RELAXED); }

#endif
