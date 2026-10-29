/* core1/main.c -- CPU1 bare-metal verify worker (AMP).
 *
 * CPU0 (FreeRTOS) owns the network and marking; this core only verifies images, so a doctor's verify
 * never waits for a lab tech's mark to finish computing.  It touches no peripheral and no interrupt:
 * it spins on the shared mailbox (src/amp_shm.h), decodes the image, runs nl_recover with the hub key
 * and writes the verdict back.  The verdict is checked again by the server (handle exists, not revoked).
 *
 * INTERIM deviation from D5 (as on CPU0): the key is held on the PS.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "xil_mmu.h"
#include "xil_io.h"

#include "amp_shm.h"
#include "nl_api.h"
#include "config_local.h"

#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_THREAD_LOCALS   /* same as CPU0: no TLS in a bare-metal image */
#define STBI_NO_STDIO
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#include "vendor/stb_image.h"

#define GT_LO 0xF8F00200u          /* Cortex-A9 global timer, CPU_3x2x = 333.33 MHz, shared with CPU0 */
#define GT_HI 0xF8F00204u
#define GT_PER_US 333u

static uint64_t gt_now(void)
{
    uint32_t hi, lo;
    do {
        hi = Xil_In32(GT_HI);
        lo = Xil_In32(GT_LO);
    } while (hi != Xil_In32(GT_HI));
    return ((uint64_t)hi << 32) | lo;
}

static void run_verify(amp_mbox_t *m)
{
    uint64_t t0 = gt_now();
    int w = 0, h = 0, comp = 0;
    uint32_t len = m->in_len;
    if (len > AMP_IN_MAX) len = AMP_IN_MAX;

    m->tag_ok = 0;
    m->version = m->hub_id = m->candidate = 0;
    m->handle_hi = m->handle_lo = 0;

    stbi_uc *pixels = stbi_load_from_memory(AMP_INBUF, (int)len, &w, &h, &comp, 1);
    if (!pixels) {
        m->rc = -1;
    } else {
        int decl_h = h - (h & 1);
        int decl_w = w - (w & 1);
        nl_recover_result r;
        memset(&r, 0, sizeof(r));
        int rc = nl_recover(pixels, h, w, decl_h, decl_w, HUB_AES_ASCON_KEY, &r);
        stbi_image_free(pixels);
        m->rc = rc;
        if (rc == 0) {
            m->tag_ok = r.tag_ok;
            m->version = r.version;
            m->hub_id = r.hub_id;
            m->candidate = r.candidate;
            m->handle_hi = (uint32_t)(r.handle >> 32);
            m->handle_lo = (uint32_t)r.handle;
        }
    }
    m->width = (uint32_t)w;
    m->height = (uint32_t)h;
    m->cpu_us = (uint32_t)((gt_now() - t0) / GT_PER_US);
}

int main(void)
{
    /* Both CPUs map the shared window non-cacheable (see amp_shm.h). */
    for (uint32_t a = AMP_SHM_BASE; a < AMP_SHM_BASE + AMP_SHM_SIZE; a += 0x100000u)
        Xil_SetTlbAttributes(a, NORM_NONCACHE);

    amp_mbox_t *m = AMP_MBOX;
    m->seq_done = m->seq_req;      /* never run a request left over from before this start */
    m->jobs = 0;
    amp_dmb();
    m->magic = AMP_MAGIC_READY;

    for (;;) {
        uint32_t seq = m->seq_req;
        if (seq == m->seq_done) {
            m->heartbeat = m->heartbeat + 1u;
            continue;
        }
        amp_dmb();                 /* read the request fields after seeing seq_req */
        if (m->op == AMP_OP_VERIFY)
            run_verify(m);
        else
            m->rc = -2;
        amp_dmb();                 /* publish the results before seq_done */
        m->jobs = m->jobs + 1u;
        m->seq_done = seq;
    }
}
