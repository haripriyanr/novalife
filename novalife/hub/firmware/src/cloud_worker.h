/* cloud_worker.h -- NovaLife cloud relay worker for Supabase job queue.
 *
 * Polls `hub_device_claim` over verified TLS (Option 1: GlobalSign CA, CIPSSLCCONF=2),
 * executes claims (verify_tag in PL enclave, verify_image/mark_image via image_worker),
 * uploads results to Supabase Storage, and calls `hub_device_complete`.
 */
#ifndef CLOUD_WORKER_H
#define CLOUD_WORKER_H

#include <stdint.h>
#include <stddef.h>

/* Initialise cloud worker state */
void cloud_worker_init(void);

/* Poll for a job and execute if claimed. Returns:
 *   1 if a job was executed,
 *   0 if queue was empty / idle,
 *  <0 on error or if TLS verification failed (worker halted).
 */
int cloud_worker_poll(void);

/* Check if TLS verification has failed (fatal stop) */
int cloud_worker_is_halted(void);

/* Format worker status as JSON */
int cloud_worker_get_status_json(char *buf, int max_len);

#endif /* CLOUD_WORKER_H */
