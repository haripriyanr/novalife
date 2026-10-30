/* amp_shm.h -- CPU0 <-> CPU1 shared mailbox (AMP), included by both images.
 *
 * Memory map (512 MB DDR):
 *   0x0010_0000 .. 0x17FF_FFFF  CPU0: FreeRTOS, network, marking (ends ~0x0492_0000 today)
 *   0x1800_0000 .. 0x1DFF_FFFF  CPU1: bare-metal verify worker (code, data, 64 MB heap)
 *   0x1F00_0000 .. 0x1FFF_FFFF  shared window, mapped NON-CACHEABLE by both CPUs, so neither needs cache
 *                               maintenance (the AMP standalone BSP's flush routines skip the L2).
 *                               Its top 1 MB (0x1FF0_0000) holds the scheduling trace rings (trace.h).
 *
 * Protocol (one job at a time; CPU0 = producer, CPU1 = consumer):
 *   CPU0: wait until seq_done == seq_req, write the input bytes and op/in_len, dmb, seq_req++.
 *   CPU1: sees seq_req != seq_done, runs the job, writes the result fields, dmb, seq_done = seq_req.
 * CPU1 sets magic = AMP_MAGIC_READY once its MMU attributes are set, and bumps heartbeat while idle.
 */
#ifndef AMP_SHM_H
#define AMP_SHM_H

#include <stdint.h>

#define AMP_SHM_BASE        0x1F000000u
#define AMP_SHM_SIZE        0x01000000u          /* 16 MB = 16 x 1 MB MMU sections */
#define AMP_IN_OFFSET       0x00001000u
#define AMP_IN_MAX          (AMP_SHM_SIZE - AMP_IN_OFFSET - 0x00100000u)   /* below the trace area */
#define AMP_CPU1_ENTRY      0x18000000u          /* CPU1 image load/entry address (its linker script) */
#define AMP_CPU1_START_REG  0xFFFFFFF0u          /* the boot ROM parks CPU1 in WFE, then jumps here */

#define AMP_MAGIC_READY     0x434F5231u          /* "COR1" */
#define AMP_OP_VERIFY       1u

typedef struct {
    volatile uint32_t magic;
    volatile uint32_t heartbeat;
    volatile uint32_t seq_req;
    volatile uint32_t seq_done;
    volatile uint32_t op;
    volatile uint32_t in_len;
    /* results (valid once seq_done == seq_req) */
    volatile int32_t  rc;            /* 0 ok, <0 error (-1 decode failed, other: nl_recover rc) */
    volatile int32_t  tag_ok;
    volatile int32_t  version;
    volatile int32_t  hub_id;
    volatile int32_t  candidate;
    volatile uint32_t handle_hi;
    volatile uint32_t handle_lo;
    volatile uint32_t width;
    volatile uint32_t height;
    volatile uint32_t cpu_us;        /* CPU1 compute time, from the shared global timer */
    volatile uint32_t jobs;          /* jobs completed since CPU1 started */
} amp_mbox_t;

#define AMP_MBOX   ((amp_mbox_t *)AMP_SHM_BASE)
#define AMP_INBUF  ((uint8_t *)(AMP_SHM_BASE + AMP_IN_OFFSET))

static inline void amp_dmb(void) { __asm__ volatile("dmb" ::: "memory"); }

#endif /* AMP_SHM_H */
