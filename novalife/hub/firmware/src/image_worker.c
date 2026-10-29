/* image_worker.c -- FreeRTOS image marking and verification worker.
 *
 * Runs in ONE FreeRTOS worker task at lower priority than the network tasks,
 * guarded by a mutex so jobs run strictly one at a time.
 *
 * INTERIM deviation from D5: key held on PS in firmware and loaded into PL at boot.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"
#include "xil_printf.h"
#include "xil_io.h"

#include "image_worker.h"
#include "config_local.h"
#include "nl_api.h"
#include "hubcore/tag_block.h"
#include "handle_gen.h"

#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_THREAD_LOCALS
#define STBI_NO_STDIO
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#include "vendor/stb_image.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "vendor/stb_image_write.h"

static SemaphoreHandle_t s_job_mutex = NULL;
static QueueHandle_t s_job_queue = NULL;


static void do_embed(image_job_t *job)
{
    int w = 0, h = 0, comp = 0;
    stbi_uc *pixels = stbi_load_from_memory(job->in_data, job->in_len, &w, &h, &comp, 1);
    if (!pixels) {
        job->http_status = 400;
        job->out_ctype = "application/json";
        snprintf(job->json_verdict, sizeof(job->json_verdict),
                 "{\"error\":\"image decode failed (must be PNG/JPEG)\"}\n");
        return;
    }

    if (w < 16 || h < 16 || (w & 1) || (h & 1)) {
        stbi_image_free(pixels);
        job->http_status = 400;
        job->out_ctype = "application/json";
        snprintf(job->json_verdict, sizeof(job->json_verdict),
                 "{\"error\":\"image dimensions must be even and >= 16\"}\n");
        return;
    }

    uint8_t version = job->version ? job->version : 1;
    uint16_t hub_id = job->hub_id ? job->hub_id : 1;
    /* Global timer (0xF8F00200, CPU/2 = 333 MHz) as the free-running "now". */
    uint64_t handle = job->handle ? job->handle
                                  : hg_next_handle(HUB_AES_ASCON_KEY, job->handle_salt,
                                                   ((uint64_t)Xil_In32(0xF8F00204u) << 32) | Xil_In32(0xF8F00200u));
    job->handle = handle;

    uint8_t block16[16];
    if (hc_tag_build_bytes(HUB_AES_ASCON_KEY, version, hub_id, handle, block16) != 0) {
        stbi_image_free(pixels);
        job->http_status = 500;
        job->out_ctype = "application/json";
        snprintf(job->json_verdict, sizeof(job->json_verdict),
                 "{\"error\":\"tag block generation failed\"}\n");
        return;
    }

    uint8_t *marked = (uint8_t *)malloc((size_t)w * h);
    if (!marked) {
        stbi_image_free(pixels);
        job->http_status = 500;
        job->out_ctype = "application/json";
        snprintf(job->json_verdict, sizeof(job->json_verdict),
                 "{\"error\":\"out of memory for marked buffer\"}\n");
        return;
    }

    nl_mark_info minfo;
    memset(&minfo, 0, sizeof(minfo));
    int rc = nl_mark(pixels, h, w, HUB_AES_ASCON_KEY, block16, marked, &minfo);
    stbi_image_free(pixels);

    if (rc == 1) {
        free(marked);
        job->http_status = 422;
        job->out_ctype = "application/json";
        snprintf(job->json_verdict, sizeof(job->json_verdict),
                 "{\"error\":\"mark refused: insufficient capacity or clipped\",\"copies\":0}\n");
        return;
    } else if (rc < 0) {
        free(marked);
        job->http_status = 500;
        job->out_ctype = "application/json";
        snprintf(job->json_verdict, sizeof(job->json_verdict),
                 "{\"error\":\"nl_mark error\",\"rc\":%d}\n", rc);
        return;
    }

    int png_len = 0;
    unsigned char *png = stbi_write_png_to_mem(marked, w, w, h, 1, &png_len);
    free(marked);

    if (!png || png_len <= 0) {
        job->http_status = 500;
        job->out_ctype = "application/json";
        snprintf(job->json_verdict, sizeof(job->json_verdict),
                 "{\"error\":\"PNG encoding failed\"}\n");
        return;
    }

    job->out_data = (uint8_t *)png;
    job->out_len = png_len;
    job->out_ctype = "image/png";
    job->http_status = 200;
    snprintf(job->json_verdict, sizeof(job->json_verdict),
             "{\"ok\":true,\"handle\":\"0x%016llx\",\"copies\":%d}\n",
             (unsigned long long)handle, minfo.copies_written);
}

static void do_verify(image_job_t *job)
{
    uint32_t csum = 0;
    for (int i = 0; i < job->in_len; i++) csum = (csum * 33) ^ job->in_data[i];
    xil_printf("IMG_IN: len=%d csum=0x%08lx bytes[0..7]=", job->in_len, (unsigned long)csum);
    for (int i = 0; i < 8 && i < job->in_len; i++) xil_printf("%02x ", job->in_data[i]);
    xil_printf("\r\n");

    int w = 0, h = 0, comp = 0;
    stbi_uc *pixels = stbi_load_from_memory(job->in_data, job->in_len, &w, &h, &comp, 1);
    if (!pixels) {
        job->http_status = 400;
        job->out_ctype = "application/json";
        snprintf(job->json_verdict, sizeof(job->json_verdict),
                 "{\"ok\":false,\"error\":\"image decode failed (must be PNG/JPEG)\"}\n");
        return;
    }

    int decl_h = job->decl_h > 0 ? job->decl_h : (h - (h & 1));
    int decl_w = job->decl_w > 0 ? job->decl_w : (w - (w & 1));

    xil_printf("IMG_WORKER: verify loaded %dx%d comp=%d in_len=%d, pix[0..3]=%d %d %d %d\r\n",
               w, h, comp, job->in_len, pixels[0], pixels[1], pixels[2], pixels[3]);

    nl_recover_result rres;
    memset(&rres, 0, sizeof(rres));
    int rc = nl_recover(pixels, h, w, decl_h, decl_w, HUB_AES_ASCON_KEY, &rres);
    xil_printf("IMG_WORKER: verify loaded %dx%d (in_len %d), rc=%d, tag_ok=%d, handle=0x%016llx\r\n",
               w, h, job->in_len, rc, rres.tag_ok, (unsigned long long)rres.handle);
    stbi_image_free(pixels);

    if (rc != 0) {
        job->http_status = 500;
        job->out_ctype = "application/json";
        snprintf(job->json_verdict, sizeof(job->json_verdict),
                 "{\"ok\":false,\"error\":\"nl_recover error\",\"rc\":%d}\n", rc);
        return;
    }

    job->http_status = 200;
    job->out_ctype = "application/json";
    snprintf(job->json_verdict, sizeof(job->json_verdict),
             "{\"ok\":%s,\"tag_ok\":%d,\"version\":%d,\"hub_id\":%d,"
             "\"handle\":\"%016llx\",\"candidate\":%d}\n",
             rres.tag_ok ? "true" : "false",
             rres.tag_ok,
             rres.version,
             rres.hub_id,
             (unsigned long long)rres.handle,
             rres.candidate);
}

static void image_worker_task(void *arg)
{
    image_job_t *job;
    (void)arg;

    xil_printf("IMG_WORKER: task up, waiting for jobs...\r\n");

    for (;;) {
        if (xQueueReceive(s_job_queue, &job, portMAX_DELAY) == pdTRUE) {
            if (!job) continue;

            if (job->op == JOB_OP_EMBED) {
                do_embed(job);
            } else if (job->op == JOB_OP_VERIFY) {
                do_verify(job);
            } else {
                job->http_status = 400;
                job->out_ctype = "application/json";
                snprintf(job->json_verdict, sizeof(job->json_verdict),
                         "{\"error\":\"unknown job op\"}\n");
            }

            if (job->done_sem) {
                xSemaphoreGive(job->done_sem);
            }
        }
    }
}

int image_worker_init(void)
{
    if (s_job_mutex == NULL) {
        s_job_mutex = xSemaphoreCreateMutex();
    }
    if (s_job_queue == NULL) {
        s_job_queue = xQueueCreate(2, sizeof(image_job_t *));
    }
    if (!s_job_mutex || !s_job_queue) {
        return -1;
    }

    /* Stack: 16384 words (64 KB) for image transformation, wavelet, & PNG encoding */
    if (xTaskCreate(image_worker_task, "img_work", 16384, NULL,
                    tskIDLE_PRIORITY + 1, NULL) != pdPASS) {
        return -1;
    }
    return 0;
}

/* Asynchronous use (the cloud worker): the network task must keep the ESP32 link moving while a mark is
 * computed, so it submits the job and polls for it instead of blocking.  The mutex is held from submit
 * until the poll that sees the job done, so jobs still run strictly one at a time. */
int image_worker_submit(image_job_t *job)
{
    if (!job || !s_job_mutex || !s_job_queue)
        return -1;
    if (xSemaphoreTake(s_job_mutex, 0) != pdTRUE)
        return -1;                                   /* busy */
    job->done_sem = xSemaphoreCreateBinary();
    if (!job->done_sem || xQueueSend(s_job_queue, &job, 0) != pdTRUE) {
        if (job->done_sem) vSemaphoreDelete(job->done_sem);
        job->done_sem = NULL;
        xSemaphoreGive(s_job_mutex);
        return -1;
    }
    return 0;
}

int image_worker_poll(image_job_t *job)
{
    if (!job || !job->done_sem)
        return -1;
    if (xSemaphoreTake(job->done_sem, 0) != pdTRUE)
        return 0;
    vSemaphoreDelete(job->done_sem);
    job->done_sem = NULL;
    xSemaphoreGive(s_job_mutex);
    return 1;
}

/* Synchronous use (local HTTP /embed, /verify).  Never waits for a running cloud job: that would stall
 * the task that owns the ESP32 link, so a busy worker answers 503. */
int image_worker_process(image_job_t *job)
{
    if (image_worker_submit(job) != 0) {
        if (job) {
            job->http_status = 503;
            job->out_ctype = "application/json";
            snprintf(job->json_verdict, sizeof(job->json_verdict), "{\"error\":\"image worker busy\"}\n");
        }
        return -1;
    }
    xSemaphoreTake(job->done_sem, portMAX_DELAY);
    xSemaphoreGive(job->done_sem);                   /* let image_worker_poll() see it and release */
    return image_worker_poll(job) == 1 ? 0 : -1;
}
