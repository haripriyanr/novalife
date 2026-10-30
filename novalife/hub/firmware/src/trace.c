/* trace.c -- CPU0 writer of the scheduling trace (see trace.h). */
#include <string.h>

#include "xil_mmu.h"
#include "xil_cache.h"

#include "trace.h"

static int s_trace_on = 0;

void trace_init(void)
{
    /* Push anything cached for this section out first, then make it non-cacheable (amp_init maps the rest
     * of the window later; this section must be ready before the first context switch). */
    Xil_DCacheFlushRange(TRACE_BASE, TRACE_AREA_SIZE);
    Xil_SetTlbAttributes(TRACE_BASE, NORM_NONCACHE);

    trace_hdr_t *h = TRACE_HDR;
    h->magic = 0;
    h->version = TRACE_VERSION;
    h->gt_hz = TRACE_GT_HZ;
    h->cap0 = TRACE_CAP0;
    h->cap1 = TRACE_CAP1;
    h->ring1_off = TRACE_RING1_OFF;
    h->head0 = 0;                  /* head1 belongs to CPU1, which resets it when it starts */
    for (unsigned i = 0; i < TRACE_NAMES; i++) {
        h->names[i].num = 0xFFFFFFFFu;
        h->names[i].name[0] = '\0';
    }
    __asm__ volatile("dmb" ::: "memory");
    h->magic = TRACE_MAGIC;
    s_trace_on = 1;
}

static inline uint32_t irq_save(void)
{
    uint32_t cpsr;
    __asm__ volatile("mrs %0, cpsr\n\tcpsid i" : "=r"(cpsr) :: "memory");
    return cpsr;
}

static inline void irq_restore(uint32_t cpsr)
{
    __asm__ volatile("msr cpsr_c, %0" :: "r"(cpsr) : "memory");
}

void trace_emit(uint8_t type, uint8_t a, uint8_t b, uint8_t c, uint32_t arg)
{
    if (!s_trace_on)
        return;
    uint32_t s = irq_save();       /* the tick IRQ switches tasks and writes this ring too */
    trace_put(TRACE_RING0, TRACE_CAP0, &TRACE_HDR->head0, type, a, b, c, arg);
    irq_restore(s);
}

/* Runs inside vTaskSwitchContext with interrupts masked.  The kernel calls it on every yield, also when it
 * picks the same task again (measured 2026-10-29: 99.6% of calls were espw -> espw, ~16000/s, which
 * overflowed the ring between JTAG reads), so only a change of task is recorded. */
static uint32_t s_last_tcb = 0xFFFFFFFFu;

void trace_task_in(uint32_t tcb_num, const char *name)
{
    if (!s_trace_on || tcb_num == s_last_tcb)
        return;
    s_last_tcb = tcb_num;
    volatile trace_name_t *n = &TRACE_HDR->names[tcb_num % TRACE_NAMES];
    if (n->num != tcb_num) {
        unsigned i = 0;
        for (; i < sizeof(n->name) - 1 && name[i]; i++)
            n->name[i] = name[i];
        n->name[i] = '\0';
        __asm__ volatile("dmb" ::: "memory");
        n->num = tcb_num;
    }
    trace_put(TRACE_RING0, TRACE_CAP0, &TRACE_HDR->head0, TE_TASK, (uint8_t)tcb_num, 0, 0, tcb_num);
}
