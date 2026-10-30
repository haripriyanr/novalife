/* trace.h -- scheduling trace rings for the live Gantt viewer (hub/tools/trace_viewer), both CPUs.
 *
 * The top 1 MB of the AMP shared window (amp_shm.h) holds a header and one ring per CPU.  Both CPUs map
 * it non-cacheable, so a JTAG memory read (xsdb `mrd -force`, no halt) sees every entry as written.
 * Each CPU writes only its own ring and head, so no lock is shared between the cores.
 *
 *   0x1FF0_0000  trace_hdr_t (magic, timer rate, ring sizes, heads, CPU0 task-name table)
 *   0x1FF0_1000  ring 0, CPU0: TRACE_CAP0 x 16 B
 *   ring 1       CPU1, right after ring 0: TRACE_CAP1 x 16 B
 *
 * head0/head1 count entries written since start (they never wrap); entry i lives at ring[i % cap].
 * A reader that falls more than cap entries behind has lost the oldest ones and reports a gap.
 * Timestamps come from the Cortex-A9 global timer, shared by both CPUs, so the two rings line up.
 */
#ifndef TRACE_H
#define TRACE_H

#include <stdint.h>

#define TRACE_BASE      0x1FF00000u
#define TRACE_MAGIC     0x54524331u          /* "TRC1" */
#define TRACE_VERSION   1u
#define TRACE_GT_HZ     333333333u           /* global timer = CPU_3x2x clock */
#define TRACE_RING0_OFF 0x1000u
#define TRACE_CAP0      16384u               /* 256 KB */
#define TRACE_CAP1      4096u                /* 64 KB */
#define TRACE_NAMES     64u

/* event types (trace_ev_t.type) */
enum {
    TE_TASK    = 1,   /* CPU0 context switch: a = TCB number (name in hdr->names) */
    TE_LANE    = 2,   /* job lane state: a = lane (0 verify, 1 mark), b = state (LS_*), c = priority, arg = job */
    TE_LINK_B  = 3,   /* ESP32 link operation begins: a = op (TL_*), b = lane or 255, arg = job */
    TE_LINK_E  = 4,   /* link operation ends: a = op, b = 0 ok / 1 failed, arg = bytes or HTTP code */
    TE_CPU1_B  = 5,   /* CPU1 verify begins: arg = request sequence number */
    TE_CPU1_E  = 6,   /* CPU1 verify ends: b = tag_ok, c = rc (low byte), arg = compute us */
    TE_MARK    = 7,   /* free-form marker: a = id, arg = value */
};

/* link operations (TE_LINK_* a) */
enum { TL_PEEK = 1, TL_CLAIM = 2, TL_DOWNLOAD = 3, TL_UPLOAD = 4, TL_COMPLETE = 5, TL_TLS = 6 };

typedef struct {
    uint32_t ts_lo, ts_hi;                   /* global timer */
    uint8_t type, a, b, c;
    uint32_t arg;
} trace_ev_t;

typedef struct {
    uint32_t num;                            /* FreeRTOS uxTCBNumber */
    char name[12];
} trace_name_t;

typedef struct {
    volatile uint32_t magic, version, gt_hz, cap0, cap1;
    volatile uint32_t head0, head1;
    volatile uint32_t ring1_off;
    volatile trace_name_t names[TRACE_NAMES];   /* slot = TCB number % TRACE_NAMES */
} trace_hdr_t;

#define TRACE_HDR    ((trace_hdr_t *)TRACE_BASE)
#define TRACE_RING0  ((volatile trace_ev_t *)(TRACE_BASE + TRACE_RING0_OFF))
#define TRACE_RING1_OFF (TRACE_RING0_OFF + TRACE_CAP0 * 16u)
#define TRACE_RING1  ((volatile trace_ev_t *)(TRACE_BASE + TRACE_RING1_OFF))

/* the AMP input buffer must stop below the trace area */
#define TRACE_AREA_SIZE 0x00100000u

static inline uint64_t trace_gt_now(void)
{
    volatile uint32_t *hi = (volatile uint32_t *)0xF8F00204u, *lo = (volatile uint32_t *)0xF8F00200u;
    uint32_t h, l;
    do {
        h = *hi;
        l = *lo;
    } while (h != *hi);
    return ((uint64_t)h << 32) | l;
}

/* Fill one entry and publish it by bumping *head.  The caller makes it atomic on its own CPU. */
static inline void trace_put(volatile trace_ev_t *ring, uint32_t cap, volatile uint32_t *head,
                             uint8_t type, uint8_t a, uint8_t b, uint8_t c, uint32_t arg)
{
    uint32_t i = *head;
    volatile trace_ev_t *e = &ring[i % cap];
    uint64_t t = trace_gt_now();
    e->ts_lo = (uint32_t)t;
    e->ts_hi = (uint32_t)(t >> 32);
    e->type = type;
    e->a = a;
    e->b = b;
    e->c = c;
    e->arg = arg;
    __asm__ volatile("dmb" ::: "memory");
    *head = i + 1u;
}

/* First 8 hex digits of a job UUID, so the viewer can match a Supabase job row. */
static inline uint32_t trace_job32(const char *id)
{
    uint32_t v = 0;
    for (int i = 0; i < 8 && id && id[i]; i++) {
        char ch = id[i];
        uint32_t d = (ch >= '0' && ch <= '9') ? (uint32_t)(ch - '0')
                   : (ch >= 'a' && ch <= 'f') ? (uint32_t)(ch - 'a' + 10)
                   : (ch >= 'A' && ch <= 'F') ? (uint32_t)(ch - 'A' + 10) : 0u;
        v = (v << 4) | d;
    }
    return v;
}

/* CPU0 (trace.c) */
void trace_init(void);                                     /* call in main() before the scheduler starts */
void trace_emit(uint8_t type, uint8_t a, uint8_t b, uint8_t c, uint32_t arg);   /* from tasks */
void trace_task_in(uint32_t tcb_num, const char *name);    /* from the kernel's traceTASK_SWITCHED_IN */

#endif /* TRACE_H */
