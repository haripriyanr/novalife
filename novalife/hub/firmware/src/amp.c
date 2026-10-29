/* amp.c -- CPU0 side of the CPU1 verify worker.  Owner decision 2026-10-29: verify jobs run on CPU1,
 * marking and the network on CPU0, so a doctor's verify never waits for a mark's compute. */
#include <string.h>

#include "FreeRTOS.h"
#include "task.h"
#include "xil_mmu.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"

#include "amp.h"
#include "amp_shm.h"

static uint32_t s_seq_expect = 0;
static int s_pending = 0;

int amp_alive(void)
{
    amp_mbox_t *m = AMP_MBOX;
    if (m->magic != AMP_MAGIC_READY)
        return 0;
    /* The magic survives a CPU-only reset in DDR; only a moving heartbeat proves CPU1 runs now. */
    uint32_t hb = m->heartbeat;
    for (int i = 0; i < 20; i++) {
        if (m->heartbeat != hb)
            return 1;
        vTaskDelay(1);
    }
    return 0;
}

void amp_init(void)
{
    for (uint32_t a = AMP_SHM_BASE; a < AMP_SHM_BASE + AMP_SHM_SIZE; a += 0x100000u)
        Xil_SetTlbAttributes(a, NORM_NONCACHE);

    if (amp_alive()) {
        xil_printf("AMP: CPU1 already running\r\n");
    } else {
        /* After a power-on or system reset the boot ROM parks CPU1 in WFE, reading its start address
         * from 0xFFFFFFF0 at every event.  The CPU1 image is already in DDR (FSBL from BOOT.BIN, or JTAG). */
        AMP_MBOX->magic = 0;
        Xil_Out32(AMP_CPU1_START_REG, AMP_CPU1_ENTRY);
        Xil_DCacheFlushRange(AMP_CPU1_START_REG, 16);
        __asm__ volatile("dsb\n\tsev" ::: "memory");
        for (int i = 0; i < 100 && AMP_MBOX->magic != AMP_MAGIC_READY; i++)
            vTaskDelay(pdMS_TO_TICKS(10));
        xil_printf("AMP: CPU1 %s\r\n", amp_alive() ? "started" : "NOT running (verify falls back to CPU0)");
    }
    s_seq_expect = AMP_MBOX->seq_req;
    s_pending = 0;
}

int amp_submit_verify(const uint8_t *data, int len)
{
    amp_mbox_t *m = AMP_MBOX;
    if (s_pending || len <= 0 || (uint32_t)len > AMP_IN_MAX)
        return -1;
    if (m->magic != AMP_MAGIC_READY || m->seq_req != m->seq_done)
        return -1;
    memcpy(AMP_INBUF, data, (size_t)len);
    m->op = AMP_OP_VERIFY;
    m->in_len = (uint32_t)len;
    amp_dmb();
    s_seq_expect = m->seq_req + 1u;
    m->seq_req = s_seq_expect;
    s_pending = 1;
    return 0;
}

int amp_poll(amp_result_t *r)
{
    amp_mbox_t *m = AMP_MBOX;
    if (!s_pending || m->seq_done != s_seq_expect)
        return 0;
    amp_dmb();
    r->rc = m->rc;
    r->tag_ok = m->tag_ok;
    r->version = m->version;
    r->hub_id = m->hub_id;
    r->candidate = m->candidate;
    r->handle = ((uint64_t)m->handle_hi << 32) | m->handle_lo;
    r->cpu_ms = m->cpu_us / 1000u;
    s_pending = 0;
    return 1;
}
