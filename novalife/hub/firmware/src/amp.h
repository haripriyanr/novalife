/* amp.h -- CPU0 side of the CPU1 verify worker (see amp_shm.h for the map and protocol). */
#ifndef AMP_H
#define AMP_H

#include <stdint.h>

typedef struct {
    int rc;              /* 0 ok, -1 image decode failed, other: nl_recover error */
    int tag_ok;
    int version;
    int hub_id;
    int candidate;
    uint64_t handle;
    unsigned cpu_ms;     /* CPU1 compute time */
} amp_result_t;

/* Map the shared window non-cacheable and start CPU1 if it is not running.  Call once, from a task. */
void amp_init(void);

/* 1 when CPU1 answers (its heartbeat moves). */
int amp_alive(void);

/* Hand one image to CPU1.  0 ok; -1 CPU1 busy, not alive or image too big (caller verifies on CPU0). */
int amp_submit_verify(const uint8_t *data, int len);

/* 1 when the submitted job is done (*r filled), 0 while it runs. */
int amp_poll(amp_result_t *r);

#endif /* AMP_H */
