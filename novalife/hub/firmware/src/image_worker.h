/* image_worker.h -- FreeRTOS image marking and verification worker.
 *
 * Runs as a lower-priority task than network tasks, guarded by a mutex
 * so jobs run strictly one at a time.
 *
 * INTERIM deviation from D5: key held on PS in firmware and loaded into PL at boot.
 */
#ifndef IMAGE_WORKER_H
#define IMAGE_WORKER_H

#include <stdint.h>
#include <stddef.h>
#include "FreeRTOS.h"
#include "semphr.h"

typedef enum {
    JOB_OP_EMBED = 1,
    JOB_OP_VERIFY = 2
} job_op_t;

typedef struct {
    job_op_t op;
    const uint8_t *in_data;
    int in_len;

    /* Embed options */
    uint8_t version;
    uint16_t hub_id;
    uint64_t handle;

    /* Verify options */
    int decl_h;
    int decl_w;

    /* Results */
    int http_status;
    const char *out_ctype;
    uint8_t *out_data;   /* dynamically allocated, caller must free() */
    int out_len;
    char json_verdict[256];

    /* Sync */
    SemaphoreHandle_t done_sem;
} image_job_t;

/* Initialize worker task and synchronization primitives */
int image_worker_init(void);

/* Process a job synchronously: thread-safe, serialised by mutex */
int image_worker_process(image_job_t *job);

#endif /* IMAGE_WORKER_H */
