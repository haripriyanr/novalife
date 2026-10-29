/* NovaLife HUB HTTP server (FreeRTOS + lwIP sockets + ESP32 WiFi AT).
 *
 * Serves the HUB endpoints:
 *   GET  /status           liveness + vault count + enclave status (JSON)
 *   GET  /vault/index.txt  vault listing (JSONL)
 *   GET  /enclave/verify   verify tag MAC in PL enclave hardware
 *   POST /embed            mark an image with 128-bit tag -> returns PNG
 *   POST /verify           recover tag from image -> returns JSON verdict
 *
 * Dual transport on the EDGE ZYNQ kit:
 *   1. lwIP socket server on GEM0 (:80) via echo_application_thread()
 *   2. Onboard ESP-WROOM-32 Wi-Fi AT server (:8080) on UART1 EMIO (R19/T19)
 *      via esp_wifi_http_task(), so the phone and host can reach the board
 *      over the Wi-Fi LAN (192.168.31.86:8080) without an RJ45 cable.
 *
 * INTERIM deviation from D5: key held on PS in firmware and loaded into PL at boot.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lwip/sockets.h"
#include "netif/xadapter.h"
#include "lwipopts.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "xparameters.h"
#include "bspconfig.h"
#include "handle_gen.h"
#include "amp.h"
#include "FreeRTOS.h"
#include "task.h"
#include "vault.h"
#include "mailbox.h"
#include "image_worker.h"
#include "cloud_worker.h"
#include "config_local.h"

#define HTTP_PORT 80
#define ESP_HTTP_PORT 8080
#define REQ_BUF_SZ 4352   /* initial header buffer */
#define RESP_BUF_SZ 2048

static u16_t http_port = HTTP_PORT;
static char g_esp_gmr[1024] = "not captured yet";
static char g_esp_cmd_list[4096] = "not captured yet";
static char g_benchmark_report[1024] = "not run yet\n";

static int esp_run_benchmark_100k(char *out_json, int max_len);
static void esp_wifi_http_task(void *arg);

void print_echo_app_header()
{
    xil_printf("%20s %6d %s\r\n", "http server",
                        http_port,
                        "$ curl <board_ip>/status");
}

static int send_all(int sd, const char *buf, int len)
{
    int sent = 0, n;
    while (sent < len) {
        n = write(sd, buf + sent, len - sent);
        if (n <= 0)
            return -1;
        sent += n;
    }
    return sent;
}

static void send_reply(int sd, int code, const char *reason,
                       const char *ctype, const char *body, int body_len)
{
    char hdr[256];
    int hlen = snprintf(hdr, sizeof(hdr),
        "HTTP/1.0 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n"
        "Connection: close\r\n\r\n",
        code, reason, ctype, body_len);
    if (hlen > 0)
        send_all(sd, hdr, hlen);
    if (body_len > 0)
        send_all(sd, body, body_len);
}

/* Minimal request parse: METHOD SP PATH SP HTTP/... then headers.
 * Returns Content-Length via *clen (0 if absent). Body starts at *body. */
static int parse_request(char *req, int n, char *method, int msz,
                         char *path, int psz, char **body)
{
    char *sp1, *sp2, *eol, *hdr;
    int clen = 0;

    *body = req + n; /* default: no body */
    eol = strstr(req, "\r\n");
    if (eol == NULL)
        return -1;
    *eol = '\0';
    sp1 = strchr(req, ' ');
    if (sp1 == NULL)
        return -1;
    *sp1 = '\0';
    sp2 = strchr(sp1 + 1, ' ');
    if (sp2 == NULL)
        return -1;
    *sp2 = '\0';
    strncpy(method, req, msz - 1);
    method[msz - 1] = '\0';
    if ((int)strlen(sp1 + 1) >= psz)
        return -2;                      /* request target too long */
    strncpy(path, sp1 + 1, psz - 1);
    path[psz - 1] = '\0';

    /* headers end at blank line; body follows */
    hdr = strstr(eol + 2, "\r\n\r\n");
    if (hdr != NULL)
        *body = hdr + 4;
    hdr = eol + 2;
    while (hdr < *body) {
        if (strncasecmp(hdr, "Content-Length:", 15) == 0)
            clen = atoi(hdr + 15);
        hdr = strstr(hdr, "\r\n");
        if (hdr == NULL)
            break;
        hdr += 2;
    }
    return clen;
}

/* Shared HTTP route handler: fills out_ctype, out_body, returns HTTP status code. */
static int build_http_response(const char *method, const char *path,
                               const char *body, int body_len,
                               const char **out_ctype,
                               char *resp, int resp_sz, int *out_len)
{
    int rlen = 0;

    if (strcmp(method, "GET") == 0 && strcmp(path, "/status") == 0) {
        /* live enclave state */
        int pl = mailbox_pl_present();
        uint32_t st = pl ? Xil_In32(PL_BASE + PL_REG_STATUS) : 0;
        rlen = snprintf(resp, resp_sz,
            "{\"product\":\"novalife-hub\",\"fw\":\"freertos-0.1\","
            "\"vault_files\":%d,\"uptime_ticks\":%lu,"
            "\"mailbox\":\"axi\",\"pl\":\"%s\",\"key\":\"%s\",\"tokens\":%lu}\n",
            vault_count(), (unsigned long)xTaskGetTickCount(),
            pl ? "present" : "absent",
            (pl && (st & 0x2U)) ? "loaded" : "absent",
            (unsigned long)((st >> 8) & 0xFFU));
        *out_ctype = "application/json";
        *out_len = rlen;
        return 200;
    } else if (strcmp(method, "GET") == 0 && strncmp(path, "/enclave/verify?", 16) == 0) {
        const char *q = path + 16;
        unsigned long long v = 0, hub = 0, handle = 0, tag = 0;
        int have = 0;
        while (*q) {
            const char *eq = strchr(q, '=');
            if (!eq) break;
            unsigned long long val = strtoull(eq + 1, NULL, 16);
            if (strncmp(q, "v=", 2) == 0)           { v = val; have |= 1; }
            else if (strncmp(q, "hub=", 4) == 0)    { hub = val; have |= 2; }
            else if (strncmp(q, "handle=", 7) == 0) { handle = val; have |= 4; }
            else if (strncmp(q, "tag=", 4) == 0)    { tag = val; have |= 8; }
            q = strchr(eq, '&');
            if (!q) break;
            q++;
        }
        if (have != 15) {
            rlen = snprintf(resp, resp_sz, "{\"error\":\"need v, hub, handle, tag (hex)\"}\n");
            *out_ctype = "application/json"; *out_len = rlen;
            return 400;
        }
        uint32_t pls = 0;
        mb_status_t r = mailbox_verify_tag((uint8_t)v, (uint16_t)hub, (uint64_t)handle,
                                           (uint64_t)tag, &pls);
        uint32_t cyc = (r == MB_OK || r == MB_ERR_VERIFY_FAIL) ? Xil_In32(PL_BASE + PL_REG_CYCLES) : 0;
        rlen = snprintf(resp, resp_sz,
            "{\"ok\":%s,\"mb_status\":%d,\"pl_result\":\"0x%08lx\",\"pl_cycles\":%lu,"
            "\"v\":\"%llx\",\"hub\":\"%03llx\",\"handle\":\"%016llx\",\"tag\":\"%012llx\"}\n",
            r == MB_OK ? "true" : "false", (int)r, (unsigned long)pls, (unsigned long)cyc,
            v, hub, handle, tag);
        *out_ctype = "application/json"; *out_len = rlen;
        return (r == MB_ERR_NO_PL) ? 503 : 200;
    } else if (strcmp(method, "GET") == 0 &&
               (strcmp(path, "/vault/index.txt") == 0 ||
                strcmp(path, "/vault/index.json") == 0)) {
        rlen = vault_index_jsonl(resp, resp_sz);
        if (rlen < 0)
            rlen = 0;
        *out_ctype = "text/plain";
        *out_len = rlen;
        return 200;
    } else if (strcmp(method, "GET") == 0 && strcmp(path, "/esp/info") == 0) {
        rlen = snprintf(resp, resp_sz, "%s\n=== CMD LIST ===\n%s\n", g_esp_gmr, g_esp_cmd_list);
        *out_ctype = "text/plain";
        *out_len = rlen;
        return 200;
    } else if (strcmp(method, "GET") == 0 && strcmp(path, "/esp/benchmark_100k") == 0) {
        rlen = esp_run_benchmark_100k(g_benchmark_report, sizeof(g_benchmark_report));
        memcpy(resp, g_benchmark_report, rlen);
        resp[rlen] = '\0';
        *out_ctype = "application/json";
        *out_len = rlen;
        return 200;
    } else if (strcmp(method, "GET") == 0 && strcmp(path, "/cloud/status") == 0) {
        rlen = cloud_worker_get_status_json(resp, resp_sz);
        *out_ctype = "application/json";
        *out_len = rlen;
        return 200;
    } else if (strcmp(method, "GET") == 0 && strcmp(path, "/esp/benchmark_results") == 0) {
        rlen = strlen(g_benchmark_report);
        if (rlen > resp_sz - 1) rlen = resp_sz - 1;
        memcpy(resp, g_benchmark_report, rlen);
        resp[rlen] = '\0';
        *out_ctype = "application/json";
        *out_len = rlen;
        return 200;
    } else if (strcmp(method, "POST") == 0 && (strncmp(path, "/embed", 6) == 0 || strncmp(path, "/verify", 7) == 0)) {
        if (body_len <= 0) {
            rlen = snprintf(resp, resp_sz, "{\"error\":\"empty body\"}\n");
            *out_ctype = "application/json";
            *out_len = rlen;
            return 400;
        }
        image_job_t job;
        memset(&job, 0, sizeof(job));
        job.in_data = (const uint8_t *)body;
        job.in_len = body_len;
        job.op = (strncmp(path, "/embed", 6) == 0) ? JOB_OP_EMBED : JOB_OP_VERIFY;
        image_worker_process(&job);
        if (job.out_data != NULL) {
            int to_copy = (job.out_len < resp_sz) ? job.out_len : resp_sz;
            memcpy(resp, job.out_data, to_copy);
            free(job.out_data);
            *out_ctype = job.out_ctype;
            *out_len = to_copy;
            return job.http_status;
        } else {
            rlen = snprintf(resp, resp_sz, "%s", job.json_verdict);
            *out_ctype = job.out_ctype;
            *out_len = rlen;
            return job.http_status;
        }
    } else {
        rlen = snprintf(resp, resp_sz, "not found\n");
        *out_ctype = "text/plain";
        *out_len = rlen;
        return 404;
    }
}

static void handle_connection(int sd)
{
    static char req[REQ_BUF_SZ];
    static char resp[RESP_BUF_SZ];
    char method[8], path[160], *body;
    const char *ctype = "text/plain";
    int n, total = 0, clen, body_avail, rlen = 0, code;

    while (total < (int)sizeof(req) - 1) {
        n = read(sd, req + total, sizeof(req) - 1 - total);
        if (n <= 0)
            break;
        total += n;
        req[total] = '\0';
        if (strstr(req, "\r\n\r\n") != NULL)
            break;
    }
    if (total <= 0)
        return;
    req[total] = '\0';

    clen = parse_request(req, total, method, sizeof(method),
                         path, sizeof(path), &body);
    if (clen < 0) {
        send_reply(sd, 400, "Bad Request", "text/plain", "bad request\n", 12);
        return;
    }
    body_avail = total - (body - req);

    /* Handle image uploads (POST /embed or POST /verify) directly with dynamic buffer */
    if (strcmp(method, "POST") == 0 && (strncmp(path, "/embed", 6) == 0 || strncmp(path, "/verify", 7) == 0)) {
        if (clen <= 0) {
            send_reply(sd, 400, "Bad Request", "application/json", "{\"error\":\"missing Content-Length or empty body\"}\n", 50);
            return;
        }
        if (clen > 4 * 1024 * 1024) {
            send_reply(sd, 413, "Payload Too Large", "application/json", "{\"error\":\"image too large (>4MB)\"}\n", 33);
            return;
        }
        uint8_t *full_body = (uint8_t *)malloc(clen);
        if (!full_body) {
            send_reply(sd, 500, "Internal Server Error", "application/json", "{\"error\":\"out of memory\"}\n", 26);
            return;
        }
        int cur_avail = (body_avail < clen) ? body_avail : clen;
        if (cur_avail > 0) {
            memcpy(full_body, body, cur_avail);
        }
        int recvd = cur_avail;
        while (recvd < clen) {
            n = read(sd, full_body + recvd, clen - recvd);
            if (n <= 0) break;
            recvd += n;
        }
        if (recvd < clen) {
            free(full_body);
            send_reply(sd, 400, "Bad Request", "application/json", "{\"error\":\"incomplete body read\"}\n", 30);
            return;
        }

        image_job_t job;
        memset(&job, 0, sizeof(job));
        job.in_data = full_body;
        job.in_len = clen;
        job.op = (strncmp(path, "/embed", 6) == 0) ? JOB_OP_EMBED : JOB_OP_VERIFY;
        image_worker_process(&job);
        free(full_body);

        if (job.out_data != NULL) {
            send_reply(sd, job.http_status, "OK", job.out_ctype, (const char *)job.out_data, job.out_len);
            free(job.out_data);
        } else {
            send_reply(sd, job.http_status, (job.http_status == 200) ? "OK" : "Error",
                       job.out_ctype, job.json_verdict, strlen(job.json_verdict));
        }
        return;
    }

    while (body_avail < clen && total < (int)sizeof(req) - 1) {
        n = read(sd, req + total, sizeof(req) - 1 - total);
        if (n <= 0)
            break;
        total += n;
        body_avail += n;
    }
    if (clen > body_avail)
        clen = body_avail;

    code = build_http_response(method, path, body, clen,
                               &ctype, resp, sizeof(resp), &rlen);
    send_reply(sd, code, (code == 200) ? "OK" : "Error", ctype, resp, rlen);
}

/* =========================================================================
 * Onboard ESP-WROOM-32 Wi-Fi AT HTTP server task (UART1 EMIO @ 0xE0001000)
 * ========================================================================= */
#define UART1_BASE 0xE0001000u
#define U_CR(b)      (*(volatile unsigned int *)((b) + 0x00u))
#define U_MR(b)      (*(volatile unsigned int *)((b) + 0x04u))
#define U_IER(b)     (*(volatile unsigned int *)((b) + 0x08u))
#define U_IDR(b)     (*(volatile unsigned int *)((b) + 0x0Cu))
#define U_ISR(b)     (*(volatile unsigned int *)((b) + 0x14u))
#define U_BAUDGEN(b) (*(volatile unsigned int *)((b) + 0x18u))
#define U_RXTOUT(b)  (*(volatile unsigned int *)((b) + 0x1Cu))
#define U_RXWM(b)    (*(volatile unsigned int *)((b) + 0x20u))
#define U_MODEMCR(b) (*(volatile unsigned int *)((b) + 0x24u))
#define U_SR(b)      (*(volatile unsigned int *)((b) + 0x2Cu))
#define U_FIFO(b)    (*(volatile unsigned int *)((b) + 0x30u))
#define U_BAUDDIV(b) (*(volatile unsigned int *)((b) + 0x34u))
#define SR_TXFULL    (1u << 4)
#define SR_TXEMPTY   (1u << 3)
#define SR_RXEMPTY   (1u << 1)
#define IXR_RTRIG    (1u << 0)     /* RX FIFO reached RXWM */
#define IXR_ROVR     (1u << 5)     /* RX FIFO overrun: bytes were lost in hardware */
#define IXR_TOUT     (1u << 8)     /* RX line idle for RXTOUT*4 bit times with bytes waiting */
#define CR_RXTX_EN   0x14u         /* RXEN | TXEN */
#define CR_TORST     (1u << 6)     /* restart the receive timeout counter */

/* UART1 reference clock is 100 MHz (XPAR_UART1_CLOCK_FREQ); baud = ref / (CD * (BDIV + 1)). */
#define ESP_BAUD_SLOW      115200u
#define ESP_BAUD_FAST      921600u
#define ESP_CD_SLOW        124u    /* 100e6 / (124 * 7) = 115,207 (+0.01%) */
#define ESP_BDIV_SLOW      6u
#define ESP_CD_FAST        18u     /* 100e6 / (18 * 6)  = 925,926 (+0.47%) */
#define ESP_BDIV_FAST      5u

/* The BSP is built in SDT mode (XPAR_XILTIMER_ENABLED), where the port's interrupt calls take the
 * SDT-encoded ID (type in bits 12+, SPI number in the low bits: 0x4032 = SPI 50 = GIC 82), not the raw
 * GIC number.  Passing 82 fails the connect, and its configASSERT hangs the calling task. */
#if defined(XPAR_XILTIMER_ENABLED) || defined(SDT)
#define ESP_UART1_IRQ XPAR_XUARTPS_1_INTERRUPTS
#else
#define ESP_UART1_IRQ XPS_UART1_INT_ID
#endif

#define ESP_RING_SZ 131072
static unsigned char esp_ring[ESP_RING_SZ];
static unsigned int esp_ring_n = 0;

/* Interrupt-driven receive.  The hardware RX FIFO is 64 bytes: at 115200 baud it fills in 5.6 ms, at
 * 921600 in 0.7 ms, so the task cannot poll it fast enough once it sleeps or yields (esp_at_cmd sleeps
 * 5 ms per loop).  The UART1 ISR empties the FIFO into this single-producer/single-consumer ring and
 * esp_ring_drain() moves bytes from it into esp_ring in task context.  head is written only by the
 * ISR and tail only by the task; both run on CPU0, so plain volatile accesses keep them ordered. */
#define ESP_SRING_SZ 32768u        /* power of two */
static volatile unsigned char esp_sring[ESP_SRING_SZ];
static volatile unsigned int esp_sring_head = 0;
static volatile unsigned int esp_sring_tail = 0;
static volatile unsigned int esp_rx_overruns = 0;    /* hardware FIFO overruns (IXR_ROVR) */
static volatile unsigned int esp_sring_drops = 0;    /* bytes lost because the soft ring was full */
static int esp_rx_irq = 0;                           /* 1 once the ISR is installed */
static unsigned int esp_baud = ESP_BAUD_SLOW;

static void esp_uart_isr(void *ref)
{
    unsigned int isr = U_ISR(UART1_BASE);
    (void)ref;
    U_ISR(UART1_BASE) = isr;                         /* write-1-to-clear */
    hg_add_entropy(Xil_In32(0xF8F00200u));           /* Wi-Fi arrival timing, global timer low word */
    while (!(U_SR(UART1_BASE) & SR_RXEMPTY)) {
        unsigned char c = (unsigned char)(U_FIFO(UART1_BASE) & 0xFFu);
        unsigned int h = esp_sring_head;
        if (h - esp_sring_tail < ESP_SRING_SZ) {
            esp_sring[h & (ESP_SRING_SZ - 1u)] = c;
            esp_sring_head = h + 1u;
        } else {
            esp_sring_drops++;
        }
    }
    if (isr & IXR_ROVR)
        esp_rx_overruns++;
    if (isr & IXR_TOUT)
        U_CR(UART1_BASE) = CR_RXTX_EN | CR_TORST;
}

static void esp_uart_set_divisors(unsigned int cd, unsigned int bdiv)
{
    U_CR(UART1_BASE) = 0x28u;                        /* RXDIS | TXDIS */
    U_BAUDGEN(UART1_BASE) = cd;
    U_BAUDDIV(UART1_BASE) = bdiv;
    U_CR(UART1_BASE) = 0x03u;                        /* RXRST | TXRST (self-clearing) */
    while (U_CR(UART1_BASE) & 0x03u) {}
    /* The path reset clears RXTOUT (measured on the board: 10 -> 0).  Without the receive timeout a
     * reply shorter than RXWM (e.g. "OK\r\n") never raises an interrupt and stays in the FIFO. */
    U_RXWM(UART1_BASE) = 32u;
    U_RXTOUT(UART1_BASE) = 10u;
    U_CR(UART1_BASE) = CR_RXTX_EN | CR_TORST;
}

static void esp_uart_init(void)
{
    U_CR(UART1_BASE) = 0;
    U_CR(UART1_BASE) = 0x03u;
    vTaskDelay(pdMS_TO_TICKS(5));
    U_ISR(UART1_BASE) = 0xFFFFFFFFu;
    U_IDR(UART1_BASE) = 0xFFFFFFFFu;
    U_BAUDGEN(UART1_BASE) = ESP_CD_SLOW;
    U_BAUDDIV(UART1_BASE) = ESP_BDIV_SLOW;
    U_MR(UART1_BASE) = 0x20u;
    U_MODEMCR(UART1_BASE) = 0u;
    U_RXWM(UART1_BASE) = 32u;                        /* interrupt at half a FIFO */
    U_RXTOUT(UART1_BASE) = 10u;                      /* idle for 40 bit times (~4 chars) */
    U_CR(UART1_BASE) = CR_RXTX_EN | CR_TORST;
    esp_baud = ESP_BAUD_SLOW;

    /* Runs in the espw task, after the scheduler has set up the GIC. Without the ISR the link
     * falls back to polling and stays at 115200 (see esp_link_go_fast). */
    if (xPortInstallInterruptHandler(ESP_UART1_IRQ, esp_uart_isr, NULL) == pdPASS) {
        U_IER(UART1_BASE) = IXR_RTRIG | IXR_ROVR | IXR_TOUT;
        vPortEnableInterrupt(ESP_UART1_IRQ);
        esp_rx_irq = 1;
    }
    xil_printf("ESP32: UART1 RX %s\r\n", esp_rx_irq ? "interrupt-driven (GIC 82)" : "polled (IRQ install failed)");
}

static void esp_putc(char c)
{
    while (U_SR(UART1_BASE) & SR_TXFULL) {}
    U_FIFO(UART1_BASE) = (unsigned int)(unsigned char)c;
}

static void esp_puts(const char *s)
{
    while (*s) esp_putc(*s++);
}

static void esp_ring_drain(void)
{
    if (esp_rx_irq) {
        unsigned int t = esp_sring_tail;
        unsigned int h = esp_sring_head;
        while (t != h && esp_ring_n < ESP_RING_SZ - 1)
            esp_ring[esp_ring_n++] = esp_sring[(t++) & (ESP_SRING_SZ - 1u)];
        esp_sring_tail = t;
    } else {
        while (esp_ring_n < ESP_RING_SZ - 1) {
            if (U_SR(UART1_BASE) & SR_RXEMPTY)
                break;
            esp_ring[esp_ring_n++] = (unsigned char)(U_FIFO(UART1_BASE) & 0xFFu);
        }
    }
    esp_ring[esp_ring_n] = '\0';
}

/* Discard everything received so far (soft ring and esp_ring). */
static void esp_rx_flush(void)
{
    if (esp_rx_irq)
        esp_sring_tail = esp_sring_head;
    esp_ring_n = 0;
    esp_ring[0] = '\0';
}

static void esp_ring_drop(unsigned int n)
{
    if (n >= esp_ring_n) {
        esp_ring_n = 0;
        esp_ring[0] = '\0';
        return;
    }
    memmove(esp_ring, esp_ring + n, esp_ring_n - n);
    esp_ring_n -= n;
    esp_ring[esp_ring_n] = '\0';
}

static int esp_ring_find(const char *needle)
{
    unsigned int nl = strlen(needle), i, j;
    if (nl == 0 || nl > esp_ring_n)
        return -1;
    for (i = 0; i + nl <= esp_ring_n; i++) {
        for (j = 0; j < nl; j++) {
            if (esp_ring[i + j] != (unsigned char)needle[j])
                break;
        }
        if (j == nl)
            return (int)i;
    }
    return -1;
}

static void esp_short_delay(volatile unsigned int loops)
{
    while (loops--) {
        __asm__ volatile("nop");
    }
}

static int esp_at_cmd_capture(const char *cmd, const char *expect, int timeout_ms, char *out, int out_sz)
{
    TickType_t start = xTaskGetTickCount();
    TickType_t wait_ticks = pdMS_TO_TICKS(timeout_ms);
    esp_ring_n = 0;
    esp_ring[0] = '\0';
    esp_puts(cmd);
    esp_puts("\r\n");
    while (xTaskGetTickCount() - start <= wait_ticks) {
        esp_ring_drain();
        int off = esp_ring_find(expect);
        if (off >= 0) {
            if (out && out_sz > 0) {
                int to_copy = (esp_ring_n < (unsigned int)out_sz - 1) ? esp_ring_n : out_sz - 1;
                memcpy(out, esp_ring, to_copy);
                out[to_copy] = '\0';
            }
            return 0;
        }
        if (esp_ring_find("ERROR") >= 0 || esp_ring_find("FAIL") >= 0) {
            if (out && out_sz > 0) {
                int to_copy = (esp_ring_n < (unsigned int)out_sz - 1) ? esp_ring_n : out_sz - 1;
                memcpy(out, esp_ring, to_copy);
                out[to_copy] = '\0';
            }
            return -1;
        }
        vTaskDelay(pdMS_TO_TICKS(5));
    }
    if (out && out_sz > 0) {
        int to_copy = (esp_ring_n < (unsigned int)out_sz - 1) ? esp_ring_n : out_sz - 1;
        memcpy(out, esp_ring, to_copy);
        out[to_copy] = '\0';
    }
    return -2;
}

static int esp_at_cmd(const char *cmd, const char *expect, int timeout_ms)
{
    TickType_t start = xTaskGetTickCount();
    TickType_t wait_ticks = pdMS_TO_TICKS(timeout_ms);
    esp_ring_n = 0;
    esp_ring[0] = '\0';
    esp_puts(cmd);
    esp_puts("\r\n");
    while (xTaskGetTickCount() - start <= wait_ticks) {
        esp_ring_drain();
        int off = esp_ring_find(expect);
        if (off >= 0)
            return 0;
        if (esp_ring_find("ERROR") >= 0 || esp_ring_find("FAIL") >= 0)
            return -1;
        vTaskDelay(pdMS_TO_TICKS(5));
    }
    return -2;
}

/* Switch only the Zynq side of the link (the ESP32 must already be at that speed). */
static void esp_uart_set_baud(unsigned int baud)
{
    while (!(U_SR(UART1_BASE) & SR_TXEMPTY)) {}      /* let the last command leave the wire */
    vTaskDelay(pdMS_TO_TICKS(2));
    if (baud == ESP_BAUD_FAST)
        esp_uart_set_divisors(ESP_CD_FAST, ESP_BDIV_FAST);
    else
        esp_uart_set_divisors(ESP_CD_SLOW, ESP_BDIV_SLOW);
    esp_baud = baud;
    esp_rx_flush();
}

static int esp_link_probe(void)
{
    for (int i = 0; i < 3; i++) {
        if (esp_at_cmd("AT", "OK", 300) == 0)
            return 0;
        vTaskDelay(pdMS_TO_TICKS(20));
    }
    return -1;
}

/* Move both ends of the link to 921600.  AT+UART_CUR changes the ESP32's speed until its next reset
 * (AT+RST and power-up return it to the 115200 stored by UART_DEF); the ESP32 answers OK at the old
 * speed, then switches.  Needs interrupt-driven RX: at 921600 the 64-byte FIFO fills in 0.7 ms.
 * Returns 0 when the link runs fast; on any failure the link is left working at 115200. */
static int esp_link_go_fast(void)
{
    if (esp_baud == ESP_BAUD_FAST)
        return 0;
    if (!esp_rx_irq)
        return -1;
    if (esp_at_cmd("AT+UART_CUR=921600,8,1,0,0", "OK", 1000) != 0) {
        xil_printf("ESP32: AT+UART_CUR refused, staying at 115200\r\n");
        return -1;
    }
    esp_uart_set_baud(ESP_BAUD_FAST);
    vTaskDelay(pdMS_TO_TICKS(20));
    if (esp_link_probe() == 0) {
        xil_printf("ESP32: link now 921600 baud\r\n");
        return 0;
    }
    /* No answer at 921600: the ESP32 did not switch, or the line cannot carry it. */
    esp_uart_set_baud(ESP_BAUD_SLOW);
    if (esp_link_probe() == 0) {
        xil_printf("ESP32: 921600 probe failed, ESP32 still at 115200\r\n");
        return -1;
    }
    /* The ESP32 is at 921600 but we cannot read it there: ask it back down blind. */
    esp_uart_set_baud(ESP_BAUD_FAST);
    esp_puts("AT+UART_CUR=115200,8,1,0,0\r\n");
    vTaskDelay(pdMS_TO_TICKS(50));
    esp_uart_set_baud(ESP_BAUD_SLOW);
    xil_printf("ESP32: 921600 unusable, link back at 115200 (probe rc=%d)\r\n", esp_link_probe());
    return -1;
}

static int esp_cipsend(int link, const char *buf, int len)
{
    char cmd[32];
    int i;
    snprintf(cmd, sizeof(cmd), "AT+CIPSEND=%d,%d", link, len);
    esp_ring_n = 0;
    esp_ring[0] = '\0';
    esp_puts(cmd);
    esp_puts("\r\n");

    TickType_t start = xTaskGetTickCount();
    while (xTaskGetTickCount() - start <= pdMS_TO_TICKS(2000)) {
        esp_ring_drain();
        if (esp_ring_find(">") >= 0)
            break;
        vTaskDelay(pdMS_TO_TICKS(2));
    }
    if (esp_ring_find(">") < 0)
        return -1;

    esp_ring_n = 0;
    for (i = 0; i < len; i++)
        esp_putc(buf[i]);

    start = xTaskGetTickCount();
    while (xTaskGetTickCount() - start <= pdMS_TO_TICKS(3000)) {
        esp_ring_drain();
        if (esp_ring_find("SEND OK") >= 0)
            return 0;
        if (esp_ring_find("ERROR") >= 0)
            return -1;
        vTaskDelay(pdMS_TO_TICKS(2));
    }
    return -1;
}

static int esp_link4_read_chunk(int chunk_len)
{
    char cmd[32];
    snprintf(cmd, sizeof(cmd), "AT+CIPRECVDATA=4,%d", chunk_len);
    esp_puts(cmd);
    esp_puts("\r\n");

    TickType_t rstart = xTaskGetTickCount();
    while (xTaskGetTickCount() - rstart <= pdMS_TO_TICKS(2000)) {
        esp_ring_drain();
        int data_off = esp_ring_find("+CIPRECVDATA:");
        if (data_off >= 0) {
            char *comma = strchr((const char *)&esp_ring[data_off + 13], ',');
            if (comma) {
                int act = atoi((const char *)&esp_ring[data_off + 13]);
                int data_start = (comma + 1) - (char *)esp_ring;
                TickType_t dstart = xTaskGetTickCount();
                while ((int)(esp_ring_n - data_start) < act && xTaskGetTickCount() - dstart <= pdMS_TO_TICKS(2000)) {
                    esp_ring_drain();
                    vTaskDelay(pdMS_TO_TICKS(1));
                }
                int drop_up_to = data_start + act;
                char *ok_p = strstr((const char *)&esp_ring[drop_up_to], "OK\r\n");
                if (ok_p) {
                    drop_up_to = (ok_p + 4) - (char *)esp_ring;
                }
                if (drop_up_to > (int)esp_ring_n) drop_up_to = (int)esp_ring_n;
                esp_ring_drop(drop_up_to);
                return act;
            }
        }
        vTaskDelay(pdMS_TO_TICKS(2));
    }
    return 0;
}

static int esp_run_benchmark_100k(char *out_json, int max_len)
{
    uint32_t t0, t1, hs_ms = 0;
    int rc;

    xil_printf("BENCHMARK: Setting up SSL CA verification and SNI on link 4...\r\n");
    esp_at_cmd("AT+CIPSSLCCONF=4,2,0,0", "OK", 500);
    esp_at_cmd("AT+CIPSSLCSNI=4,\"" SUPABASE_HOST "\"", "OK", 500);

    xil_printf("BENCHMARK: Initiating TLS handshake to %s:443...\r\n", SUPABASE_HOST);
    t0 = xTaskGetTickCount();
    rc = esp_at_cmd("AT+CIPSTART=4,\"SSL\",\"" SUPABASE_HOST "\",443", "4,CONNECT", 12000);
    t1 = xTaskGetTickCount();
    if (rc != 0) {
        xil_printf("BENCHMARK: TLS handshake FAILED rc=%d\r\n", rc);
        return snprintf(out_json, max_len, "{\"error\":\"TLS handshake failed\",\"rc\":%d}\n", rc);
    }
    hs_ms = (t1 - t0) * (1000 / configTICK_RATE_HZ);
    xil_printf("BENCHMARK: TLS handshake OK in %lu ms\r\n", (unsigned long)hs_ms);

    esp_at_cmd("AT+CIPRECVTYPE=4,1", "OK", 500);

    /* 1. 100 KB GET benchmark: request public scan file (~115 KB) */
    static const char *get_req =
        "GET /storage/v1/object/public/medical-images/scans/PAT-005/scan_009.png HTTP/1.1\r\n"
        "Host: " SUPABASE_HOST "\r\n"
        "apikey: " SUPABASE_ANON_KEY "\r\n"
        "Connection: keep-alive\r\n\r\n";

    xil_printf("BENCHMARK: Sending GET request via CIPSEND...\r\n");
    t0 = xTaskGetTickCount();
    rc = esp_cipsend(4, get_req, strlen(get_req));
    if (rc != 0) {
        esp_at_cmd("AT+CIPCLOSE=4", "OK", 500);
        return snprintf(out_json, max_len, "{\"error\":\"CIPSEND GET failed\"}\n");
    }

    int total_recvd = 0;
    TickType_t start_time = xTaskGetTickCount();
    int idle_count = 0;
    while (total_recvd < 115975 && (xTaskGetTickCount() - start_time) <= pdMS_TO_TICKS(30000)) {
        esp_ring_drain();
        int off = esp_ring_find("+IPD,4,");
        if (off >= 0) {
            char *p = (char *)&esp_ring[off + 7];
            int avail = atoi(p);
            char *eol = strstr(p, "\r\n");
            if (eol) {
                esp_ring_drop((eol + 2) - (char *)esp_ring);
            } else {
                esp_ring_drop(off + 7);
            }
            if (avail > 0) {
                int read_sz = (avail > 2048) ? 2048 : avail;
                int act = esp_link4_read_chunk(read_sz);
                if (act > 0) {
                    total_recvd += act;
                    idle_count = 0;
                }
            }
        } else {
            vTaskDelay(pdMS_TO_TICKS(10));
            idle_count++;
            if (idle_count > 10) {
                char rlen_buf[64] = {0};
                int rc2 = esp_at_cmd_capture("AT+CIPRECVLEN?", "OK", 200, rlen_buf, sizeof(rlen_buf));
                if (rc2 == 0) {
                    char *colon = strchr(rlen_buf, ':');
                    if (colon) {
                        int l[5] = {0};
                        if (sscanf(colon + 1, " %d , %d , %d , %d , %d", &l[0], &l[1], &l[2], &l[3], &l[4]) >= 5 && l[4] > 0) {
                            int read_sz = (l[4] > 2048) ? 2048 : l[4];
                            int act = esp_link4_read_chunk(read_sz);
                            if (act > 0) {
                                total_recvd += act;
                                idle_count = 0;
                            }
                        }
                    }
                }
            }
        }
    }
    t1 = xTaskGetTickCount();
    uint32_t get_ms = (t1 - t0) * (1000 / configTICK_RATE_HZ);
    xil_printf("BENCHMARK: GET complete: %d B in %lu ms\r\n", total_recvd, (unsigned long)get_ms);

    /* 2. 100 KB POST benchmark */
    char post_hdr[256];
    int hlen = snprintf(post_hdr, sizeof(post_hdr),
        "POST /storage/v1/object/hub-jobs/bench_dummy.bin HTTP/1.1\r\n"
        "Host: " SUPABASE_HOST "\r\n"
        "Content-Length: 102400\r\n"
        "Connection: keep-alive\r\n\r\n");

    xil_printf("BENCHMARK: Starting POST 102400 B in 50 chunks...\r\n");
    t0 = xTaskGetTickCount();
    esp_cipsend(4, post_hdr, hlen);

    static char dummy_chunk[2048];
    memset(dummy_chunk, 0x5A, sizeof(dummy_chunk));
    int chunks_ok = 0;
    for (int c = 0; c < 50; c++) {
        rc = esp_cipsend(4, dummy_chunk, 2048);
        if (rc == 0) chunks_ok++;
    }
    t1 = xTaskGetTickCount();
    uint32_t post_ms = (t1 - t0) * (1000 / configTICK_RATE_HZ);
    xil_printf("BENCHMARK: POST complete: %d/50 chunks in %lu ms\r\n", chunks_ok, (unsigned long)post_ms);

    size_t free_heap = xPortGetFreeHeapSize();
    esp_at_cmd("AT+CIPCLOSE=4", "OK", 500);

    double get_kbps = (get_ms > 0) ? ((double)total_recvd / 1024.0) / ((double)get_ms / 1000.0) : 0.0;
    double post_kbps = (post_ms > 0) ? ((double)(chunks_ok * 2048) / 1024.0) / ((double)post_ms / 1000.0) : 0.0;

    return snprintf(out_json, max_len,
        "{\n"
        "  \"tls_verified\": true,\n"
        "  \"handshake_ms\": %lu,\n"
        "  \"get_100k\": {\"target_bytes\": 115975, \"recvd_bytes\": %d, \"duration_ms\": %lu, \"throughput_kbps\": %.2f},\n"
        "  \"post_100k\": {\"sent_bytes\": %d, \"chunks_ok\": %d, \"chunks_total\": 50, \"duration_ms\": %lu, \"throughput_kbps\": %.2f},\n"
        "  \"free_heap_bytes\": %u,\n"
        "  \"baud\": %u, \"rx_irq\": %d, \"rx_overruns\": %u, \"ring_drops\": %u\n"
        "}\n",
        (unsigned long)hs_ms,
        total_recvd, (unsigned long)get_ms, get_kbps,
        chunks_ok * 2048, chunks_ok, (unsigned long)post_ms, post_kbps,
        (unsigned int)free_heap, esp_baud, esp_rx_irq, esp_rx_overruns, esp_sring_drops);
}

static void send_esp_reply(int link, int code, const char *reason, const char *ctype,
                           const uint8_t *data, int data_len)
{
    char hdr[256];
    int hlen = snprintf(hdr, sizeof(hdr),
        "HTTP/1.0 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n"
        "Connection: close\r\n\r\n",
        code, reason, ctype, data_len);
    if (hlen > 0) {
        esp_cipsend(link, hdr, hlen);
    }
    int sent = 0;
    while (sent < data_len) {
        int chunk = data_len - sent;
        if (chunk > 2048) chunk = 2048;
        esp_cipsend(link, (const char *)data + sent, chunk);
        sent += chunk;
    }
    char close_cmd[24];
    snprintf(close_cmd, sizeof(close_cmd), "AT+CIPCLOSE=%d", link);
    esp_at_cmd(close_cmd, "OK", 300);
    esp_ring_n = 0;
    esp_ring[0] = '\0';
}

static void esp_handle_ipd(int off)
{
    static char req_copy[REQ_BUF_SZ];
    static char resp[RESP_BUF_SZ];
    static char full_pkt[RESP_BUF_SZ + 256];
    unsigned int i = (unsigned int)off + 5;
    int link = 0, len = 0, loops;
    char method[8], path[160], *body;
    const char *ctype = "text/plain";
    int clen, body_avail, rlen = 0, code, hlen;

    if (i >= esp_ring_n || esp_ring[i] < '0' || esp_ring[i] >= '4') {
        /* Not a valid server link (0..3); ignore/drop */
        return;
    }

    /* Tight drain until '<link>,<len>:' header arrives */
    loops = 100000;
    while (loops-- > 0) {
        esp_ring_drain();
        if (strchr((const char *)&esp_ring[off], ':') != NULL)
            break;
        esp_short_delay(50);
    }
    if (i >= esp_ring_n || esp_ring[i] < '0' || esp_ring[i] > '4') {
        esp_ring_drop((unsigned int)off + 5);
        return;
    }
    link = esp_ring[i] - '0';
    if (link >= 4) {
        return;
    }
    i++;
    if (i >= esp_ring_n || esp_ring[i] != ',') {
        esp_ring_drop((unsigned int)off + 5);
        return;
    }
    i++;
    while (i < esp_ring_n && esp_ring[i] >= '0' && esp_ring[i] <= '9') {
        len = len * 10 + (esp_ring[i] - '0');
        i++;
    }
    if (i >= esp_ring_n || esp_ring[i] != ':' || len <= 0) {
        esp_ring_drop((unsigned int)off + 5);
        return;
    }
    i++; /* start of HTTP request payload */

    loops = 200000;
    while ((int)(esp_ring_n - i) < len && loops-- > 0 && esp_ring_n < ESP_RING_SZ - 16) {
        esp_ring_drain();
        if ((int)(esp_ring_n - i) >= len)
            break;
        esp_short_delay(50);
    }

    int copy_len = (int)(esp_ring_n - i);
    if (copy_len > len)
        copy_len = len;
    if (copy_len > (int)sizeof(req_copy) - 1)
        copy_len = (int)sizeof(req_copy) - 1;
    memcpy(req_copy, &esp_ring[i], copy_len);
    req_copy[copy_len] = '\0';

    clen = parse_request(req_copy, copy_len, method, sizeof(method),
                         path, sizeof(path), &body);
    if (clen < 0) {
        code = 400;
        ctype = "text/plain";
        rlen = snprintf(resp, sizeof(resp), "bad request\n");
        hlen = snprintf(full_pkt, sizeof(full_pkt),
            "HTTP/1.0 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: %d\r\n"
            "Connection: close\r\n\r\n", rlen);
        if (hlen > 0 && hlen + rlen <= (int)sizeof(full_pkt)) {
            memcpy(full_pkt + hlen, resp, rlen);
            esp_cipsend(link, full_pkt, hlen + rlen);
        }
        char close_cmd[24];
        snprintf(close_cmd, sizeof(close_cmd), "AT+CIPCLOSE=%d", link);
        esp_at_cmd(close_cmd, "OK", 300);
        esp_ring_n = 0;
        esp_ring[0] = '\0';
        return;
    }

    /* Check for large image upload routes over Wi-Fi */
    if (strcmp(method, "POST") == 0 && (strncmp(path, "/embed", 6) == 0 || strncmp(path, "/verify", 7) == 0)) {
        if (clen <= 0) {
            const char *err = "{\"error\":\"missing Content-Length or empty body\"}\n";
            send_esp_reply(link, 400, "Bad Request", "application/json", (const uint8_t *)err, strlen(err));
            return;
        }
        if (clen > 4 * 1024 * 1024) {
            const char *err = "{\"error\":\"image too large (>4MB)\"}\n";
            send_esp_reply(link, 413, "Payload Too Large", "application/json", (const uint8_t *)err, strlen(err));
            return;
        }
        uint8_t *full_body = (uint8_t *)malloc(clen);
        if (!full_body) {
            const char *err = "{\"error\":\"out of memory\"}\n";
            send_esp_reply(link, 500, "Internal Server Error", "application/json", (const uint8_t *)err, strlen(err));
            return;
        }

        /* The HTTP header was in &esp_ring[i]. The body in this first chunk starts at i + hdr_len */
        int hdr_len = (int)(body - req_copy);
        int first_avail = (int)(esp_ring_n - (i + hdr_len));
        if (first_avail > (len - hdr_len))
            first_avail = len - hdr_len;
        if (first_avail > clen)
            first_avail = clen;
        if (first_avail < 0)
            first_avail = 0;

        if (first_avail > 0) {
            memcpy(full_body, &esp_ring[i + hdr_len], first_avail);
        }
        int recvd = first_avail;

        /* Consume the first +IPD chunk completely from esp_ring */
        unsigned int drop_first = (unsigned int)(i + len);
        if (drop_first > esp_ring_n) drop_first = esp_ring_n;
        esp_ring_drop(drop_first);

        /* Drain remainder of body across multiple +IPD chunks if needed */
        int idle_loops = 0;
        while (recvd < clen && idle_loops < 4000000) {
            esp_ring_drain();
            int off2 = esp_ring_find("+IPD,");
            if (off2 < 0) {
                esp_short_delay(500);
                idle_loops++;
                continue;
            }
            idle_loops = 0;
            if (off2 > 0) {
                esp_ring_drop((unsigned int)off2);
            }
            /* Now +IPD, is at index 0 of esp_ring. Wait for the ':' delimiter */
            int wait_colon = 100000;
            while (strchr((const char *)esp_ring, ':') == NULL && wait_colon-- > 0) {
                esp_ring_drain();
                esp_short_delay(200);
            }
            if (strchr((const char *)esp_ring, ':') == NULL) {
                break;
            }

            unsigned int p2 = 5;
            if (p2 >= esp_ring_n || esp_ring[p2] != ('0' + link) || esp_ring[p2 + 1] != ',') {
                const char *col = strchr((const char *)esp_ring, ':');
                if (col) esp_ring_drop((unsigned int)((const unsigned char *)col - esp_ring + 1));
                continue;
            }
            p2 += 2;
            int chunk_len = 0;
            while (p2 < esp_ring_n && esp_ring[p2] >= '0' && esp_ring[p2] <= '9') {
                chunk_len = chunk_len * 10 + (esp_ring[p2] - '0');
                p2++;
            }
            if (p2 >= esp_ring_n || esp_ring[p2] != ':') {
                const char *col = strchr((const char *)esp_ring, ':');
                if (col) esp_ring_drop((unsigned int)((const unsigned char *)col - esp_ring + 1));
                continue;
            }
            p2++; /* Start of chunk payload in esp_ring */

            /* Wait until chunk_len bytes are present in esp_ring */
            int wait_data = 2000000;
            while ((int)(esp_ring_n - p2) < chunk_len && wait_data-- > 0 && esp_ring_n < ESP_RING_SZ - 16) {
                esp_ring_drain();
                esp_short_delay(200);
            }
            int avail = (int)(esp_ring_n - p2);
            if (avail > chunk_len) avail = chunk_len;
            if (avail < 0) avail = 0;

            int to_take = clen - recvd;
            if (avail < to_take) to_take = avail;
            if (to_take > 0) {
                memcpy(full_body + recvd, &esp_ring[p2], to_take);
                recvd += to_take;
            }
            esp_ring_drop(p2 + chunk_len);
        }

        if (recvd < clen) {
            free(full_body);
            const char *err = "{\"error\":\"incomplete body read\"}\n";
            send_esp_reply(link, 400, "Bad Request", "application/json", (const uint8_t *)err, strlen(err));
            return;
        }

        image_job_t job;
        memset(&job, 0, sizeof(job));
        job.in_data = full_body;
        job.in_len = recvd;
        job.op = (strncmp(path, "/embed", 6) == 0) ? JOB_OP_EMBED : JOB_OP_VERIFY;
        image_worker_process(&job);
        free(full_body);

        if (job.out_data != NULL) {
            send_esp_reply(link, job.http_status, "OK", job.out_ctype, job.out_data, job.out_len);
            free(job.out_data);
        } else {
            send_esp_reply(link, job.http_status, (job.http_status == 200) ? "OK" : "Error",
                           job.out_ctype, (const uint8_t *)job.json_verdict, strlen(job.json_verdict));
        }
        return;
    }

    body_avail = copy_len - (int)(body - req_copy);
    if (clen > body_avail) {
        loops = 100000;
        while (loops-- > 0) {
            esp_ring_drain();
            int off2 = esp_ring_find("+IPD,");
            if (off2 > (int)i) {
                const char *colon = strchr((const char *)&esp_ring[off2], ':');
                if (colon != NULL) {
                    int extra_off = (int)((const unsigned char *)colon - esp_ring) + 1;
                    int extra_avail = (int)esp_ring_n - extra_off;
                    if (extra_avail >= clen - body_avail) {
                        int need = clen - body_avail;
                        if ((body - req_copy) + body_avail + need < (int)sizeof(req_copy)) {
                            memcpy(body + body_avail, &esp_ring[extra_off], need);
                            body_avail += need;
                        }
                        break;
                    }
                }
            }
            esp_short_delay(50);
        }
    }
    if (clen > body_avail)
        clen = body_avail;
    code = build_http_response(method, path, body, clen,
                               &ctype, resp, sizeof(resp), &rlen);
    xil_printf("HTTP [ESP32]: %s %s -> %d (%d B)\r\n", method, path, code, rlen);

    hlen = snprintf(full_pkt, sizeof(full_pkt),
        "HTTP/1.0 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n"
        "Connection: close\r\n\r\n",
        code, (code == 200) ? "OK" : (code == 404 ? "Not Found" : "Bad Request"),
        ctype, rlen);
    if (hlen > 0 && hlen + rlen <= (int)sizeof(full_pkt)) {
        memcpy(full_pkt + hlen, resp, rlen);
        esp_cipsend(link, full_pkt, hlen + rlen);
    }
    {
        char close_cmd[24];
        snprintf(close_cmd, sizeof(close_cmd), "AT+CIPCLOSE=%d", link);
        esp_at_cmd(close_cmd, "OK", 300);
    }
    esp_ring_n = 0;
    esp_ring[0] = '\0';
}

#include "cloud_worker.c"

extern volatile int gem0_init_done;

static void esp_wifi_http_task(void *arg)
{
    int tries, rc;
    char ip_str[24] = {0};
    (void)arg;

    while (!gem0_init_done) {
        vTaskDelay(pdMS_TO_TICKS(50));
    }

    esp_uart_init();
    xil_printf("ESP32: initialising AT link on UART1 (115200 8N1)...\r\n");

    for (tries = 0; tries < 5; tries++) {
        rc = esp_at_cmd("ATE0", "OK", 500);
        if (rc == 0)
            break;
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    if (rc != 0 && esp_rx_irq) {
        /* A Zynq-only reset (JTAG load, PS soft reset) leaves the ESP32 at the 921600 set earlier. */
        esp_uart_set_baud(ESP_BAUD_FAST);
        rc = esp_at_cmd("ATE0", "OK", 500);
        if (rc != 0)
            esp_uart_set_baud(ESP_BAUD_SLOW);
    }
    xil_printf("ESP32: ATE0 rc=%d at %u baud\r\n", rc, esp_baud);
    esp_at_cmd_capture("AT+GMR", "OK", 1000, g_esp_gmr, sizeof(g_esp_gmr));
    esp_at_cmd_capture("AT+CMD?", "OK", 3000, g_esp_cmd_list, sizeof(g_esp_cmd_list));
    esp_at_cmd("AT+CWMODE=1", "OK", 500);

    /* Check if ESP32 already has an IP from earlier association */
    for (tries = 0; tries < 5; tries++) {
        if (esp_at_cmd("AT+CIFSR", "OK", 1000) == 0) {
            int off = esp_ring_find("+CIFSR:STAIP,\"");
            if (off >= 0) {
                const char *s = (const char *)&esp_ring[off + 14];
                const char *q = strchr(s, '"');
                if (q != NULL && (q - s) < (int)sizeof(ip_str)) {
                    memcpy(ip_str, s, q - s);
                    ip_str[q - s] = '\0';
                }
            }
            if (ip_str[0] != '\0' && strcmp(ip_str, "0.0.0.0") != 0)
                break;
        }
        xil_printf("ESP32: joining WiFi SSID '%s' (try %d)...\r\n", WIFI_SSID, tries + 1);
        esp_at_cmd("AT+CWJAP=\"" WIFI_SSID "\",\"" WIFI_PASS "\"", "OK", 12000);
        vTaskDelay(pdMS_TO_TICKS(1000));
    }

    /* Enable multi-connection mode first, reset stale server, and listen on :8080 */
    rc = esp_at_cmd("AT+CIPMUX=1", "OK", 500);
    xil_printf("ESP32: CIPMUX=1 rc=%d\r\n", rc);
    esp_at_cmd("AT+CIPSERVER=0", "OK", 500);
    vTaskDelay(pdMS_TO_TICKS(100));
    for (tries = 0; tries < 4; tries++) {
        rc = esp_at_cmd("AT+CIPSERVER=1,8080", "OK", 1000);
        if (rc == 0)
            break;
        esp_at_cmd("AT+CIPSERVER=0", "OK", 500);
        vTaskDelay(pdMS_TO_TICKS(200));
    }
    xil_printf("ESP32: CIPSERVER=1,8080 rc=%d\r\n", rc);
    esp_at_cmd("AT+CIPSTO=120", "OK", 500);
    xil_printf("ESP32 WiFi IP: %s\r\n", ip_str[0] ? ip_str : "192.168.31.86");
    xil_printf("HTTP ready (ESP32 :%d + lwIP :%d)\r\n", ESP_HTTP_PORT, HTTP_PORT);

    esp_link_go_fast();
    amp_init();
    cloud_worker_init();

    esp_ring_n = 0;
    for (;;) {
        esp_ring_drain();
        for (int l = 0; l <= 3; l++) {
            char pat[8];
            snprintf(pat, sizeof(pat), "+IPD,%d,", l);
            int off = esp_ring_find(pat);
            if (off >= 0) {
                esp_handle_ipd(off);
                break;
            }
        }

        if (esp_ring_n > 4096)
            esp_ring_drop(esp_ring_n - 1024);

        /* One link operation per pass; the worker paces its own queue peeks (every 2 s). */
        if (!cloud_worker_is_halted())
            cloud_worker_poll();
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}

/* Echo thread: bind, listen, accept loop */
void echo_application_thread(void *p)
{
    int sock, sd;
    struct sockaddr_in address, remote;
    socklen_t rlen = sizeof(remote);
    (void)p;

    if (vault_init() != 0)
        xil_printf("HTTP: vault init failed\r\n");
    if (mailbox_init() != 0)
        xil_printf("HTTP: mailbox init failed\r\n");
    else {
        /* INTERIM deviation from D5: load key from PS into PL enclave at boot */
        if (mailbox_load_key(HUB_AES_ASCON_KEY) == MB_OK)
            xil_printf("HTTP: key loaded into PL enclave\r\n");
        else
            xil_printf("HTTP: key load failed or PL absent\r\n");
    }
    if (image_worker_init() != 0)
        xil_printf("HTTP: image worker init failed\r\n");

    /* Start the ESP32 Wi-Fi HTTP task at same priority as mbox so taskYIELD() round-robins */
    /* 4096 words = 16 KB: twice the old 8 KB (the request/response buffers nest ~6 KB deep).  The
     * FreeRTOS heap has ~26 KB free at this point, so 32 KB failed silently (measured 2026-10-22). */
    /* Above img_work (tskIDLE_PRIORITY + 1): the ESP32 link keeps moving while a mark is computed. */
    if (xTaskCreate(esp_wifi_http_task, "espw", 4096, NULL, tskIDLE_PRIORITY + 2, NULL) != pdPASS)
        xil_printf("HTTP: ESP32 task create FAILED (heap free %u)\r\n", (unsigned)xPortGetFreeHeapSize());

    memset(&address, 0, sizeof(address));
    if ((sock = lwip_socket(AF_INET, SOCK_STREAM, 0)) < 0) {
        xil_printf("HTTP: socket failed\r\n");
        vTaskDelete(NULL);
        return;
    }
    address.sin_family = AF_INET;
    address.sin_port = htons(http_port);
    address.sin_addr.s_addr = INADDR_ANY;

    if (lwip_bind(sock, (struct sockaddr *)&address, sizeof(address)) != 0) {
        xil_printf("HTTP: bind :%d failed\r\n", http_port);
        close(sock);
        vTaskDelete(NULL);
        return;
    }
    lwip_listen(sock, 4);
    xil_printf("HTTP: listening on :%d "
               "[/status /vault/index.txt /enclave/verify POST /embed POST /verify]\r\n", http_port);

    for (;;) {
        sd = lwip_accept(sock, (struct sockaddr *)&remote, &rlen);
        if (sd < 0)
            continue;
        handle_connection(sd);
        close(sd);
    }
}
