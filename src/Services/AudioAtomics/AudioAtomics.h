#ifndef AUDIO_ATOMICS_H
#define AUDIO_ATOMICS_H

#include <stdatomic.h>
#include <stdlib.h>

_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "Audio callbacks require lock-free atomics");

typedef struct AudioAtomic AudioAtomic;
struct AudioAtomic {
    atomic_ullong value;
};

static inline AudioAtomic *audio_atomic_create(void) {
    AudioAtomic *atomic = malloc(sizeof(*atomic));
    if (atomic) atomic_init(&atomic->value, 0);
    return atomic;
}

static inline void audio_atomic_destroy(AudioAtomic *atomic) {
    free(atomic);
}

static inline unsigned long long audio_atomic_load(const AudioAtomic *atomic) {
    return atomic_load_explicit(&atomic->value, memory_order_relaxed);
}

static inline void audio_atomic_store(AudioAtomic *atomic, unsigned long long value) {
    atomic_store_explicit(&atomic->value, value, memory_order_relaxed);
}

static inline void audio_atomic_clear_if_equal(AudioAtomic *atomic, unsigned long long expected) {
    atomic_compare_exchange_strong_explicit(&atomic->value, &expected, 0,
                                            memory_order_relaxed, memory_order_relaxed);
}

#endif
