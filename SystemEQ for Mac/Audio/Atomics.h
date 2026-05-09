//
//  Atomics.h
//  SystemEQ for Mac
//
//  C11 atomic primitives for lock-free audio-thread data sharing.
//  Swift's Int/pointer stores are not formally guaranteed atomic;
//  these helpers give us explicit acquire/release semantics for
//  SPSC ring-buffer indices and the published filter pointer.
//

#ifndef SystemEQ_Atomics_h
#define SystemEQ_Atomics_h

#include <stdatomic.h>
#include <stdint.h>

typedef struct { _Atomic(int32_t) value; } SEQAtomicInt32;
typedef struct { _Atomic(int_fast64_t) value; } SEQAtomicInt64;
typedef struct { _Atomic(void *) value; } SEQAtomicPtr;
typedef struct { atomic_flag value; } SEQAtomicFlag;

static inline SEQAtomicInt32 seq_atomic_int32_make(int32_t v) {
    SEQAtomicInt32 a;
    atomic_store_explicit(&a.value, v, memory_order_relaxed);
    return a;
}
static inline void seq_atomic_int32_init(SEQAtomicInt32 *a, int32_t v) {
    atomic_store_explicit(&a->value, v, memory_order_relaxed);
}
static inline int32_t seq_atomic_int32_load(const SEQAtomicInt32 *a) {
    return atomic_load_explicit(&a->value, memory_order_acquire);
}
static inline int32_t seq_atomic_int32_fetch_add(SEQAtomicInt32 *a, int32_t delta) {
    return atomic_fetch_add_explicit(&a->value, delta, memory_order_acq_rel);
}

static inline void seq_atomic_int64_init(SEQAtomicInt64 *a, int_fast64_t v) {
    atomic_store_explicit(&a->value, v, memory_order_relaxed);
}

static inline int_fast64_t seq_atomic_int64_load_acquire(const SEQAtomicInt64 *a) {
    return atomic_load_explicit(&a->value, memory_order_acquire);
}

static inline int_fast64_t seq_atomic_int64_load_relaxed(const SEQAtomicInt64 *a) {
    return atomic_load_explicit(&a->value, memory_order_relaxed);
}

static inline void seq_atomic_int64_store_release(SEQAtomicInt64 *a, int_fast64_t v) {
    atomic_store_explicit(&a->value, v, memory_order_release);
}

static inline void seq_atomic_int64_store_relaxed(SEQAtomicInt64 *a, int_fast64_t v) {
    atomic_store_explicit(&a->value, v, memory_order_relaxed);
}

static inline void seq_atomic_ptr_init(SEQAtomicPtr *a, void *p) {
    atomic_store_explicit(&a->value, p, memory_order_relaxed);
}

static inline void *seq_atomic_ptr_load_acquire(const SEQAtomicPtr *a) {
    return atomic_load_explicit(&a->value, memory_order_acquire);
}

static inline void seq_atomic_ptr_store_release(SEQAtomicPtr *a, void *p) {
    atomic_store_explicit(&a->value, p, memory_order_release);
}

static inline void seq_atomic_flag_clear(SEQAtomicFlag *a) {
    atomic_flag_clear_explicit(&a->value, memory_order_release);
}

// Returns true if the flag was previously clear (i.e., this call set it).
static inline _Bool seq_atomic_flag_test_and_set(SEQAtomicFlag *a) {
    return !atomic_flag_test_and_set_explicit(&a->value, memory_order_acq_rel);
}

#endif /* SystemEQ_Atomics_h */
