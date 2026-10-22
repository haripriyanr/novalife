/* cloud_worker.c -- NovaLife cloud relay worker for Supabase job queue.
 *
 * Implements design D6: Outbound-only polling to Supabase RPC hub_device_claim,
 * execution via PL enclave (verify_tag) or PS image_worker (verify_image / mark_image),
 * and reporting via hub_device_complete.
 *
 * All outbound TLS connections use Option 1 (GlobalSign Root CA verified, CIPSSLCCONF=2).
 * Strictly halts if TLS verification fails (never falls back to unverified TLS).
 */

#include <stdarg.h>
#include "cloud_worker.h"
#include <ctype.h>

static int s_cloud_link4_connected = 0;
static int s_cloud_tls_verification_failed = 0;
static TickType_t s_cloud_last_claim_tick = 0;
static uint32_t s_cloud_poll_count = 0;
static int s_cloud_last_code = 0;
static uint32_t s_cloud_jobs_done = 0;
static char s_cloud_last_resp[256] = "none";
static char s_cloud_last_job_id[40] = "none";
static char s_cloud_last_err[64] = "none";
static char s_debug_recv_dump[256] = "none";
static char s_debug_poll_dump[256] = "none";
static char s_cloud_last_conn[80] = "none";      /* last CIPSTART output, for diagnosis */
static TickType_t s_cloud_next_connect_tick = 0;  /* back-off: no connect attempt before this tick */
static uint32_t s_cloud_connect_fail_total = 0;
static uint32_t s_cloud_esp_resets = 0;

/* Undelivered completion, re-sent before any new claim (see cloud_complete_job). */
static int s_pending_active = 0;
static char s_pending_job[40];
static int s_pending_ok;
static char s_pending_result[320];
static char s_pending_err[64];
static int s_pending_has_err;

/* Small in-memory event log (the console is not readable: its UART goes to the ESP32), shown in /cloud/status. */
#define EVLOG_N 10
static char s_evlog[EVLOG_N][44];
static unsigned s_evlog_n = 0;
static void evlog(const char *fmt, ...)
{
    char tmp[44];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(tmp, sizeof tmp, fmt, ap);
    va_end(ap);
    char line[44];
    snprintf(line, sizeof line, "%lu %s", (unsigned long)(xTaskGetTickCount() / configTICK_RATE_HZ), tmp);
    for (char *c = line; *c; c++) if (*c == '"' || *c == '\\' || *c < 32) *c = ' ';
    strncpy(s_evlog[s_evlog_n % EVLOG_N], line, sizeof s_evlog[0] - 1);
    s_evlog[s_evlog_n % EVLOG_N][sizeof s_evlog[0] - 1] = 0;
    s_evlog_n++;
}

int cloud_worker_is_halted(void)
{
    return s_cloud_tls_verification_failed;
}

void cloud_worker_init(void)
{
    s_cloud_link4_connected = 0;
    s_cloud_tls_verification_failed = 0;
    s_cloud_last_claim_tick = 0;
    s_cloud_poll_count = 0;
    s_cloud_last_code = 0;
    s_cloud_jobs_done = 0;
    s_cloud_esp_resets = 0;
    strncpy(s_cloud_last_resp, "none", sizeof(s_cloud_last_resp));
    strncpy(s_cloud_last_job_id, "none", sizeof(s_cloud_last_job_id));
    strncpy(s_cloud_last_err, "none", sizeof(s_cloud_last_err));
}

int cloud_worker_get_status_json(char *buf, int max_len)
{
    char evlog_json[EVLOG_N * 48 + 8];
    int ep = 0;
    evlog_json[0] = 0;
    unsigned first = (s_evlog_n > EVLOG_N) ? s_evlog_n - EVLOG_N : 0;
    for (unsigned i = first; i < s_evlog_n && ep < (int)sizeof(evlog_json) - 50; i++)
        ep += snprintf(evlog_json + ep, sizeof(evlog_json) - ep, "%s\"%s\"", i > first ? "," : "", s_evlog[i % EVLOG_N]);
    return snprintf(buf, max_len,
        "{\"halted\":%d,\"link4_connected\":%d,\"poll_count\":%lu,\"jobs_done\":%lu,"
        "\"last_code\":%d,\"last_claim_age_s\":%lu,\"job_id\":\"%s\",\"err\":\"%s\","
        "\"last_resp\":\"%s\",\"debug\":\"%s\",\"conn_fail\":%lu,\"conn\":\"%s\",\"esp_resets\":%lu,\"free_heap\":%u,\"pending\":%d,\"log\":[%s]}\n",
        s_cloud_tls_verification_failed, s_cloud_link4_connected,
        (unsigned long)s_cloud_poll_count, (unsigned long)s_cloud_jobs_done,
        s_cloud_last_code,
        s_cloud_last_claim_tick ? (unsigned long)((xTaskGetTickCount() - s_cloud_last_claim_tick) / configTICK_RATE_HZ) : 0,
        s_cloud_last_job_id, s_cloud_last_err, s_cloud_last_resp,
        s_debug_recv_dump, (unsigned long)s_cloud_connect_fail_total, s_cloud_last_conn,
        (unsigned long)s_cloud_esp_resets,
        (unsigned int)xPortGetFreeHeapSize(), s_pending_active, evlog_json);
}

/* Parse a string value from JSON: key: "value" */
static int json_get_str(const char *json, const char *key, char *out, int max_len)
{
    char search[64];
    snprintf(search, sizeof(search), "\"%s\"", key);
    const char *p = strstr(json, search);
    if (!p) return -1;
    p += strlen(search);
    while (*p && (*p == ' ' || *p == ':')) p++;
    if (*p != '"') return -1;
    p++; /* skip opening quote */
    int i = 0;
    while (*p && *p != '"' && i < max_len - 1) {
        if (*p == '\\' && *(p + 1)) p++;
        out[i++] = *p++;
    }
    out[i] = '\0';
    return i;
}

/* Parse an integer from JSON: key: 123 */
static int json_get_int(const char *json, const char *key, int *out)
{
    char search[64];
    snprintf(search, sizeof(search), "\"%s\"", key);
    const char *p = strstr(json, search);
    if (!p) return -1;
    p += strlen(search);
    while (*p && (*p == ' ' || *p == ':')) p++;
    if (*p == '"') p++; /* handle quoted int */
    *out = atoi(p);
    return 0;
}

/* Parse a 64-bit hex from JSON: key: "0x123..." or key: "123..." */
static int json_get_hex64(const char *json, const char *key, uint64_t *out)
{
    char val[64];
    if (json_get_str(json, key, val, sizeof(val)) < 0) return -1;
    const char *p = val;
    if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) p += 2;
    *out = strtoull(p, NULL, 16);
    return 0;
}

/* Helper to check and purge 4,CLOSED from ring */
static int esp_link4_check_closed(void)
{
    int off = esp_ring_find("4,CLOSED");
    if (off >= 0) {
        s_cloud_link4_connected = 0;
        char *nl = strstr((char *)&esp_ring[off], "\n");
        if (nl) esp_ring_drop((nl + 1) - (char *)esp_ring);
        else esp_ring_drop(off + 8);
        return 1;
    }
    return 0;
}

static void esp_link4_purge_all_closed(void)
{
    esp_ring_drain();
    while (esp_link4_check_closed()) {
        esp_ring_drain();
    }
}

/* Link 4 runs in ACTIVE receive mode: the ESP32 pushes each piece of the reply as
 * "+IPD,4,<len>:<bytes>".  Measured 2026-10-22 on the same job-claim reply: active mode delivered it
 * in 0.51 s, passive mode (AT+CIPRECVTYPE=4,1 + CIPRECVDATA) in 3.5-6.6 s, because the ESP32 sat on
 * the last TLS records.  Active data must be drained at once (the UART FIFO holds 64 bytes, ~5 ms at
 * 115200 baud), so the reader below busy-drains with taskYIELD and never sleeps for a tick.
 *
 * Moves every complete "+IPD,4," frame from the ring into *buf.  Returns bytes appended, -2 on OOM. */
static int esp_link4_take_frames(uint8_t **buf, int *n, int *cap)
{
    int taken = 0;
    for (;;) {
        int off = esp_ring_find("+IPD,4,");
        if (off < 0) return taken;
        unsigned int p = (unsigned int)off + 7;
        int len = 0;
        while (p < esp_ring_n && esp_ring[p] >= '0' && esp_ring[p] <= '9') len = len * 10 + (esp_ring[p++] - '0');
        if (p >= esp_ring_n) return taken;                  /* header not complete yet */
        if (esp_ring[p] != ':' || len <= 0) {               /* not a data frame: skip the marker */
            esp_ring_drop((unsigned int)off + 7);
            continue;
        }
        p++;
        if (esp_ring_n - p < (unsigned int)len) return taken; /* payload still arriving */
        if (*n + len > *cap) {
            int ncap = *cap;
            while (*n + len > ncap) ncap *= 2;
            uint8_t *nb = (uint8_t *)realloc(*buf, ncap + 1);
            if (!nb) return -2;
            *buf = nb;
            *cap = ncap;
        }
        memcpy(*buf + *n, &esp_ring[p], (size_t)len);
        *n += len;
        (*buf)[*n] = '\0';
        taken += len;
        esp_ring_drop(p + (unsigned int)len);
    }
}

/* Case-insensitive header lookup inside the first hdr_len bytes; returns a pointer after "name". */
static const char *http_find_header(const char *buf, int hdr_len, const char *name)
{
    int nl = (int)strlen(name);
    for (int i = 0; i + nl <= hdr_len; i++) {
        if ((i == 0 || buf[i - 1] == '\n') && strncasecmp(buf + i, name, nl) == 0) return buf + i + nl;
    }
    return NULL;
}

/* Decode an HTTP/1.1 chunked body.  Returns 1 when the terminating 0-size chunk has arrived (dst holds
 * the body, *dst_len its length), 0 when more bytes are needed, -1 on a malformed stream.  dst may be
 * NULL to only test for completeness. */
static int http_dechunk(const uint8_t *src, int len, uint8_t *dst, int *dst_len)
{
    int pos = 0, out = 0;
    for (;;) {
        int eol = -1;
        for (int i = pos; i + 1 < len; i++)
            if (src[i] == '\r' && src[i + 1] == '\n') { eol = i; break; }
        if (eol < 0) return 0;
        char *endp;
        long sz = strtol((const char *)src + pos, &endp, 16);
        if (endp == (const char *)src + pos || sz < 0) return -1;
        pos = eol + 2;
        if (sz == 0) {
            if (dst_len) *dst_len = out;
            return (pos + 2 <= len) ? 1 : 0;   /* the empty trailer line */
        }
        if (pos + sz + 2 > len) return 0;
        if (dst) memcpy(dst + out, src + pos, (size_t)sz);
        out += (int)sz;
        pos += (int)sz + 2;
    }
}

/* Read one HTTP response on link 4.  Returns the status code (e.g. 200) or <0 on error; *out_body is
 * a malloc'd, NUL-terminated body (the caller frees it).  Knows when the reply is complete from
 * Content-Length or the chunked terminator, so nothing of it is left for the next request. */
static int esp_link4_http_recv(uint8_t **out_body, int *out_body_len, int timeout_ms)
{
    TickType_t start = xTaskGetTickCount();
    int cap = 4096, n = 0, hdr_len = -1, content_len = -1, chunked = 0, status = -1, done = 0, closed = 0;
    uint8_t *buf = (uint8_t *)malloc(cap + 1);

    *out_body = NULL;
    *out_body_len = 0;
    if (!buf) return -2;
    buf[0] = '\0';

    while (!done && xTaskGetTickCount() - start <= pdMS_TO_TICKS(timeout_ms)) {
        esp_ring_drain();
        int got = esp_link4_take_frames(&buf, &n, &cap);
        if (got == -2) { free(buf); return -2; }
        if (got == 0) {
            if (esp_link4_check_closed()) { closed = 1; break; }
            taskYIELD();
            continue;
        }
        if (hdr_len < 0) {
            char *e = strstr((char *)buf, "\r\n\r\n");
            if (!e) continue;
            hdr_len = (int)(e + 4 - (char *)buf);
            char *sp = strchr((char *)buf, ' ');
            if (sp && sp < e) status = atoi(sp + 1);
            const char *v = http_find_header((char *)buf, hdr_len, "content-length:");
            if (v) content_len = atoi(v);
            v = http_find_header((char *)buf, hdr_len, "transfer-encoding:");
            if (v && strncasecmp(v + strspn(v, " "), "chunked", 7) == 0) chunked = 1;
            v = http_find_header((char *)buf, hdr_len, "connection:");
            if (v && strncasecmp(v + strspn(v, " "), "close", 5) == 0) s_cloud_link4_connected = 0;
        }
        if (status == 204 || status == 304 || content_len == 0) done = 1;
        else if (chunked) done = (http_dechunk(buf + hdr_len, n - hdr_len, NULL, NULL) != 0);
        else if (content_len > 0) done = (n - hdr_len >= content_len);
    }

    if (hdr_len < 0 || (!done && !(closed && !chunked && content_len < 0))) {
        evlog("recv fail: n=%d hdr=%d st=%d", n, hdr_len, status);
        free(buf);
        s_cloud_link4_connected = 0;
        return -1;
    }

    int body_len = n - hdr_len;
    uint8_t *body = (uint8_t *)malloc(body_len + 1);
    if (!body) { free(buf); return -2; }
    if (chunked) {
        if (http_dechunk(buf + hdr_len, n - hdr_len, body, &body_len) != 1) body_len = 0;
    } else {
        if (content_len >= 0 && content_len < body_len) body_len = content_len;
        memcpy(body, buf + hdr_len, body_len);
    }
    body[body_len] = '\0';
    free(buf);
    *out_body = body;
    *out_body_len = body_len;
    return status;
}

/* The ESP32 answers "busy p..." (ERR CODE 0x010b0000) to every command while it is still working on an
 * earlier one, e.g. an SSL handshake that takes ~5 s.  Measured 2026-10-22: the worker sent its next
 * AT+CIPSTART into that window, read the "busy" reply as a failure and retried at once, which kept the
 * ESP busy for good.  Wait until the module answers a plain AT with OK before touching the link. */
static int esp_wait_idle(int timeout_ms)
{
    TickType_t start = xTaskGetTickCount();
    while ((int)((xTaskGetTickCount() - start) * portTICK_PERIOD_MS) < timeout_ms) {
        if (esp_at_cmd("AT", "OK", 400) == 0) return 0;
        vTaskDelay(pdMS_TO_TICKS(300));
    }
    return -1;
}

/* Certificate verification needs the current date: after every ESP32 reset its clock starts at 1970 and
 * every certificate looks "not yet valid", so CIPSTART fails with a bare ERROR (measured 2026-10-22: the
 * worker could not connect after an AT+RST).  Configure SNTP and wait until the clock is real. */
static int s_cloud_time_ok = 0;

static int esp_ensure_time(void)
{
    if (s_cloud_time_ok) return 0;
    for (int attempt = 0; attempt < 15; attempt++) {
        char out[120] = {0};
        if (esp_at_cmd_capture("AT+CIPSNTPTIME?", "OK", 1500, out, sizeof(out)) == 0 &&
            strstr(out, "+CIPSNTPTIME:") != NULL && strstr(out, "1970") == NULL) {
            s_cloud_time_ok = 1;
            return 0;
        }
        if (attempt == 0 || attempt == 7)
            esp_at_cmd("AT+CIPSNTPCFG=1,0,\"time.google.com\",\"pool.ntp.org\"", "OK", 2000);
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
    return -1;
}

/* Reset ESP32 and restore basic AP/server configuration after stuck SSL state */
static int esp_reset_and_reinit(void)
{
    s_cloud_esp_resets++;
    evlog("esp reset #%lu", (unsigned long)s_cloud_esp_resets);
    xil_printf("CLOUD: resetting ESP32 (AT+RST)...\r\n");
    s_cloud_link4_connected = 0;
    s_cloud_time_ok = 0;

    esp_ring_n = 0;
    esp_ring[0] = '\0';
    esp_puts("AT+RST\r\n");

    TickType_t start = xTaskGetTickCount();
    int got_ip = 0;
    while ((int)((xTaskGetTickCount() - start) * portTICK_PERIOD_MS) < 10000) {
        esp_ring_drain();
        if (esp_ring_find("GOT IP") >= 0) {
            got_ip = 1;
            break;
        }
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    xil_printf("CLOUD: ESP32 reset, got_ip=%d\r\n", got_ip);
    vTaskDelay(pdMS_TO_TICKS(500));

    esp_wait_idle(3000);
    esp_at_cmd("ATE0", "OK", 500);
    esp_at_cmd("AT+CWMODE=1", "OK", 500);
    esp_at_cmd("AT+CIPMUX=1", "OK", 500);
    esp_at_cmd("AT+CIPSERVER=0", "OK", 500);
    vTaskDelay(pdMS_TO_TICKS(100));
    esp_at_cmd("AT+CIPSERVER=1,8080", "OK", 1000);
    esp_at_cmd("AT+CIPSTO=120", "OK", 500);

    return got_ip ? 0 : -1;
}

/* Ensure link 4 is open with verified TLS (Option 1) */
static int s_cloud_connect_retries = 0;

static int cloud_ensure_tls(void)
{
    if (s_cloud_tls_verification_failed) return -1;
    esp_link4_purge_all_closed();
    if (s_cloud_link4_connected) return 0;
    if (s_cloud_next_connect_tick && (int32_t)(xTaskGetTickCount() - s_cloud_next_connect_tick) < 0) return -1;

    xil_printf("CLOUD: opening verified TLS link 4 to %s:443...\r\n", SUPABASE_HOST);
    if (esp_wait_idle(15000) != 0) {
        s_cloud_connect_fail_total++;
        strncpy(s_cloud_last_conn, "esp busy (no OK to AT within 15 s)", sizeof(s_cloud_last_conn) - 1);
        s_cloud_next_connect_tick = xTaskGetTickCount() + pdMS_TO_TICKS(5000);
        return -1;
    }
    if (esp_ensure_time() != 0) {
        s_cloud_connect_fail_total++;
        strncpy(s_cloud_last_conn, "no network time (SNTP) yet", sizeof(s_cloud_last_conn) - 1);
        s_cloud_next_connect_tick = xTaskGetTickCount() + pdMS_TO_TICKS(10000);
        return -1;
    }
    esp_ring_n = 0;
    esp_ring[0] = '\0';
    esp_at_cmd("AT+CIPCLOSE=4", "OK", 1500);
    esp_wait_idle(5000);
    esp_at_cmd("AT+CIPSSLCCONF=4,2,0,0", "OK", 1500);
    esp_at_cmd("AT+CIPSSLCSNI=4,\"" SUPABASE_HOST "\"", "OK", 1500);

    char start_out[128] = {0};
    int rc = esp_at_cmd_capture("AT+CIPSTART=4,\"SSL\",\"" SUPABASE_HOST "\",443", "OK", 10000, start_out, sizeof(start_out));
    if (rc != 0 && strstr(start_out, "CONNECT") == NULL && strstr(start_out, "ALREADY CONNECTED") == NULL) {
        s_cloud_connect_retries++;
        s_cloud_connect_fail_total++;
        strncpy(s_cloud_last_conn, start_out[0] ? start_out : "(no output)", sizeof(s_cloud_last_conn) - 1);
        for (char *c = s_cloud_last_conn; *c; c++) if (*c == '\r' || *c == '\n' || *c == '"') *c = ' ';
        if (s_cloud_connect_retries % 3 == 0) {
            esp_reset_and_reinit();
        }
        /* A failed connect never falls back to an unverified link (CIPSSLCCONF=2 is re-set before every
         * attempt).  It is retried with exponential back-off (2 s, 4 s ... 60 s) instead of halting for
         * good: the earlier "halt after 3 errors" stopped the worker for transient errors, which are
         * indistinguishable from a rejected certificate in the AT output. */
        unsigned shift = (s_cloud_connect_retries > 4) ? 4 : (unsigned)s_cloud_connect_retries;
        uint32_t backoff_s = 4u << shift;
        if (backoff_s > 60) backoff_s = 60;
        s_cloud_next_connect_tick = xTaskGetTickCount() + pdMS_TO_TICKS(backoff_s * 1000u);
        xil_printf("CLOUD: link 4 connect attempt %d failed (output: %s); retry in %u s\r\n",
                   s_cloud_connect_retries, start_out, (unsigned)backoff_s);
        return -1;
    }

    s_cloud_connect_retries = 0;
    xil_printf("CLOUD: TLS verified link 4 connected\r\n");
    esp_at_cmd("AT+CIPRECVTYPE=4,0", "OK", 500);   /* active: see esp_link4_take_frames */
    s_cloud_link4_connected = 1;
    return 0;
}

/* A completion that could not be delivered is kept and re-sent before any new claim, so a claimed job
 * always ends (measured 2026-10-22: a job whose completion failed stayed "running" for good). */

static int cloud_complete_job_once(const char *job_id, int ok, const char *result_json, const char *error_str);

static int cloud_complete_job(const char *job_id, int ok, const char *result_json, const char *error_str)
{
    if (cloud_complete_job_once(job_id, ok, result_json, error_str) == 0) return 0;
    strncpy(s_pending_job, job_id, sizeof(s_pending_job) - 1);
    s_pending_job[sizeof(s_pending_job) - 1] = 0;
    s_pending_ok = ok;
    snprintf(s_pending_result, sizeof(s_pending_result), "%s", result_json ? result_json : "{}");
    s_pending_has_err = (error_str != NULL);
    snprintf(s_pending_err, sizeof(s_pending_err), "%s", error_str ? error_str : "");
    s_pending_active = 1;
    evlog("pending %.8s kept", job_id);
    return -1;
}

static int cloud_flush_pending(void)
{
    if (!s_pending_active) return 0;
    if (cloud_complete_job_once(s_pending_job, s_pending_ok, s_pending_result,
                                s_pending_has_err ? s_pending_err : NULL) != 0) return -1;
    evlog("pending %.8s delivered", s_pending_job);
    s_pending_active = 0;
    return 0;
}

/* Complete a job via hub_device_complete RPC */
static int cloud_complete_job_once(const char *job_id, int ok, const char *result_json, const char *error_str)
{
    esp_link4_purge_all_closed();
    if (cloud_ensure_tls() != 0) return -1;

    char body[1024];
    int blen;
    if (error_str) {
        blen = snprintf(body, sizeof(body),
            "{\"p_device\":\"" HUB_DEVICE_ID "\",\"p_secret\":\"" HUB_DEVICE_SECRET "\","
            "\"p_job\":\"%s\",\"p_ok\":%s,\"p_result\":%s,\"p_error\":\"%s\"}",
            job_id, ok ? "true" : "false", result_json ? result_json : "{}", error_str);
    } else {
        blen = snprintf(body, sizeof(body),
            "{\"p_device\":\"" HUB_DEVICE_ID "\",\"p_secret\":\"" HUB_DEVICE_SECRET "\","
            "\"p_job\":\"%s\",\"p_ok\":%s,\"p_result\":%s,\"p_error\":null}",
            job_id, ok ? "true" : "false", result_json ? result_json : "{}");
    }

    char full_req[1536];
    int rlen = snprintf(full_req, sizeof(full_req),
        "POST /rest/v1/rpc/hub_device_complete HTTP/1.1\r\n"
        "Host: " SUPABASE_HOST "\r\n"
        "apikey: " SUPABASE_ANON_KEY "\r\n"
        "Authorization: Bearer " SUPABASE_ANON_KEY "\r\n"
        "User-Agent: NovaLife-Hub/1.0\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: %d\r\n"
        "Connection: keep-alive\r\n\r\n"
        "%s", blen, body);

    /* Measured 2026-10-22: the "dead link" seen after back-to-back jobs was not a dead link -- the reply
     * had arrived and sat unread in the ESP32 because its notification was lost (see
     * esp_link4_pending).  The reader now polls the buffer, so a retry is only for a real failure:
     * drop the link, reconnect and send again. */
    int code = -1;
    for (int attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) {
            s_cloud_link4_connected = 0;
            s_cloud_next_connect_tick = 0;      /* a retry must not wait behind an earlier back-off */
            esp_at_cmd("AT+CIPCLOSE=4", "OK", 1500);
            if (cloud_ensure_tls() != 0) { evlog("complete a%d: reconnect failed", attempt); continue; }
        }
        TickType_t t0 = xTaskGetTickCount();
        if (esp_cipsend(4, full_req, rlen) != 0) {
            s_cloud_link4_connected = 0;
            evlog("complete a%d: cipsend failed", attempt);
            continue;
        }
        TickType_t t1 = xTaskGetTickCount();
        uint8_t *resp_body = NULL;
        int resp_len = 0;
        code = esp_link4_http_recv(&resp_body, &resp_len, 6000);
        evlog("done a%d %d send %lu recv %lu", attempt, code, (unsigned long)((t1 - t0) * portTICK_PERIOD_MS),
              (unsigned long)((xTaskGetTickCount() - t1) * portTICK_PERIOD_MS));
        /* "no such running job" means the job is no longer ours to finish: an earlier attempt was
         * executed, or the server re-queued it.  Re-sending cannot change that, so stop here. */
        int gone = (code == 400 && resp_body && strstr((char *)resp_body, "no such running job") != NULL);
        if (resp_body) free(resp_body);
        if (code == 200 || code == 204 || gone) { code = gone ? 200 : code; break; }
        s_cloud_link4_connected = 0;   /* no usable answer: the link is suspect */
    }

    snprintf(s_cloud_last_err, sizeof(s_cloud_last_err), "comp_code=%d", code);
    xil_printf("CLOUD: hub_device_complete status: %d\r\n", code);
    if (code == 200 || code == 204) {
        s_cloud_jobs_done++;
        vTaskDelay(pdMS_TO_TICKS(30));
        esp_link4_purge_all_closed();
        return 0;
    }
    return -1;
}

/* Download an image from private Supabase Storage bucket 'hub-jobs' */
static uint8_t *cloud_download_image(const char *image_path, int *out_len)
{
    if (cloud_ensure_tls() != 0) return NULL;

    char hdr[768];
    int hlen = snprintf(hdr, sizeof(hdr),
        "GET /storage/v1/object/hub-jobs/%s HTTP/1.1\r\n"
        "Host: " SUPABASE_HOST "\r\n"
        "apikey: " SUPABASE_ANON_KEY "\r\n"
        "Authorization: Bearer " SUPABASE_ANON_KEY "\r\n"
        "Connection: keep-alive\r\n\r\n", image_path);

    if (esp_cipsend(4, hdr, hlen) != 0) {
        s_cloud_link4_connected = 0;
        return NULL;
    }

    uint8_t *body = NULL;
    int body_len = 0;
    int code = esp_link4_http_recv(&body, &body_len, 25000);
    if (code != 200 || !body || body_len <= 0) {
        xil_printf("CLOUD: download failed, http code %d len %d\r\n", code, body_len);
        if (body) free(body);
        return NULL;
    }
    *out_len = body_len;
    return body;
}

/* Upload marked PNG to private Supabase Storage bucket 'hub-jobs' */
static int cloud_upload_marked_png(const char *auth_uid, const char *job_id, const uint8_t *png, int png_len)
{
    if (cloud_ensure_tls() != 0) return -1;

    char hdr[768];
    int hlen = snprintf(hdr, sizeof(hdr),
        "POST /storage/v1/object/hub-jobs/%s/results/%s.png HTTP/1.1\r\n"
        "Host: " SUPABASE_HOST "\r\n"
        "apikey: " SUPABASE_ANON_KEY "\r\n"
        "Authorization: Bearer " SUPABASE_ANON_KEY "\r\n"
        "Content-Type: image/png\r\n"
        "Content-Length: %d\r\n"
        "Connection: keep-alive\r\n\r\n", auth_uid, job_id, png_len);

    if (esp_cipsend(4, hdr, hlen) != 0) {
        s_cloud_link4_connected = 0;
        return -1;
    }

    int sent = 0;
    while (sent < png_len) {
        int chunk = png_len - sent;
        if (chunk > 2048) chunk = 2048;
        if (esp_cipsend(4, (const char *)png + sent, chunk) != 0) {
            s_cloud_link4_connected = 0;
            return -1;
        }
        sent += chunk;
    }

    uint8_t *resp_body = NULL;
    int resp_len = 0;
    int code = esp_link4_http_recv(&resp_body, &resp_len, 10000);
    if (resp_body) free(resp_body);

    xil_printf("CLOUD: upload marked PNG result status: %d\r\n", code);
    return (code == 200 || code == 201) ? 0 : -1;
}

/* Poll hub_device_claim and execute job */
int cloud_worker_poll(void)
{
    if (s_cloud_tls_verification_failed) return -1;
    esp_link4_purge_all_closed();
    if (cloud_ensure_tls() != 0) return -1;

    if (cloud_flush_pending() != 0) return -1;   /* never claim a new job while one is undelivered */
    s_cloud_poll_count++;

    /* Build claim request */
    static const char *claim_body =
        "{\"p_device\":\"" HUB_DEVICE_ID "\",\"p_secret\":\"" HUB_DEVICE_SECRET "\"}";
    int blen = strlen(claim_body);

    char full_req[1024];
    int rlen = snprintf(full_req, sizeof(full_req),
        "POST /rest/v1/rpc/hub_device_claim HTTP/1.1\r\n"
        "Host: " SUPABASE_HOST "\r\n"
        "apikey: " SUPABASE_ANON_KEY "\r\n"
        "Authorization: Bearer " SUPABASE_ANON_KEY "\r\n"
        "User-Agent: NovaLife-Hub/1.0\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: %d\r\n"
        "Connection: keep-alive\r\n\r\n"
        "%s", blen, claim_body);

    TickType_t t_send = xTaskGetTickCount();
    if (esp_cipsend(4, full_req, rlen) != 0) {
        s_cloud_link4_connected = 0;
        return -1;
    }
    TickType_t t_sent = xTaskGetTickCount();

    uint8_t *resp = NULL;
    int resp_len = 0;
    int code = esp_link4_http_recv(&resp, &resp_len, 8000);
    TickType_t t_recv = xTaskGetTickCount();
    s_cloud_last_code = code;
    snprintf(s_debug_recv_dump, sizeof(s_debug_recv_dump), "code=%d len=%d resp=%.150s",
             code, resp_len, resp ? (char *)resp : "null");

    if (code != 200 || !resp) {
        if (resp) free(resp);
        s_cloud_link4_connected = 0;
        return -1;
    }

    /* Check if queue was empty: returns "[]" */
    const char *first_obj = strstr((char *)resp, "{\"job_id\"");
    if (!first_obj) first_obj = strstr((char *)resp, "{\"");
    if (!first_obj) {
        snprintf(s_cloud_last_resp, sizeof(s_cloud_last_resp), "%s", (char *)resp);
        free(resp);
        return 0; /* Queue idle */
    }

    s_cloud_last_claim_tick = xTaskGetTickCount();
    snprintf(s_cloud_last_resp, sizeof(s_cloud_last_resp), "%s", (char *)resp);

    /* A job is claimed! Parse job fields */
    char job_id[40] = {0};
    char auth_uid[40] = {0};
    char kind[24] = {0};
    char image_path[128] = {0};

    json_get_str((char *)resp, "job_id", job_id, sizeof(job_id));
    json_get_str((char *)resp, "auth_uid", auth_uid, sizeof(auth_uid));
    json_get_str((char *)resp, "kind", kind, sizeof(kind));
    json_get_str((char *)resp, "image_path", image_path, sizeof(image_path));
    strncpy(s_cloud_last_job_id, job_id, sizeof(s_cloud_last_job_id));

    evlog("claim %.6s send %lu recv %lu ms", job_id, (unsigned long)((t_sent - t_send) * portTICK_PERIOD_MS), (unsigned long)((t_recv - t_sent) * portTICK_PERIOD_MS));
    xil_printf("\r\n=== CLOUD JOB CLAIMED ===\r\nID: %s\r\nKind: %s\r\nUser: %s\r\n", job_id, kind, auth_uid);

    if (strcmp(kind, "verify_tag") == 0) {
        int v = 1, hub = 1;
        uint64_t handle = 0, tag = 0;
        json_get_int((char *)resp, "v", &v);
        json_get_int((char *)resp, "hub", &hub);
        json_get_hex64((char *)resp, "handle", &handle);
        json_get_hex64((char *)resp, "tag", &tag);
        free(resp);

        xil_printf("CLOUD: verify_tag in PL enclave (v=%d, hub=%d, handle=0x%016llx, tag=0x%016llx)\r\n",
                   v, hub, (unsigned long long)handle, (unsigned long long)tag);

        uint32_t pls = 0;
        mb_status_t r = mailbox_verify_tag((uint8_t)v, (uint16_t)hub, handle, tag & 0xFFFFFFFFFFFFULL, &pls);
        uint32_t cyc = (r == MB_OK || r == MB_ERR_VERIFY_FAIL) ? Xil_In32(PL_BASE + PL_REG_CYCLES) : 0;
        int ok = (r == MB_OK);

        char res_json[128];
        snprintf(res_json, sizeof(res_json),
                 "{\"ok\":%s,\"mb_status\":%d,\"pl_result\":\"0x%08lx\",\"pl_cycles\":%lu}",
                 ok ? "true" : "false", (int)r, (unsigned long)pls, (unsigned long)cyc);

        xil_printf("CLOUD: PL verify finished (ok=%d, cyc=%lu). Completing...\r\n", ok, (unsigned long)cyc);
        cloud_complete_job(job_id, ok, res_json, NULL);
        return 1;

    } else if (strcmp(kind, "verify_image") == 0) {
        free(resp);
        xil_printf("CLOUD: downloading image '%s' for verification...\r\n", image_path);
        int img_len = 0;
        uint8_t *img_data = cloud_download_image(image_path, &img_len);
        if (!img_data) {
            cloud_complete_job(job_id, 0, "{}", "image download failed");
            return 1;
        }

        evlog("dl %d B verify", img_len);
        xil_printf("CLOUD: downloaded %d bytes. Running image verification...\r\n", img_len);
        image_job_t job;
        memset(&job, 0, sizeof(job));
        job.in_data = img_data;
        job.in_len = img_len;
        job.op = JOB_OP_VERIFY;
        image_worker_process(&job);
        free(img_data);

        int ok = (job.http_status == 200 && strstr(job.json_verdict, "\"tag_ok\":1") != NULL);
        evlog("v-res %s st=%d", ok ? "pass" : "fail", job.http_status);
        xil_printf("CLOUD: verify verdict: %s (ok=%d)\r\n", job.json_verdict, ok);

        char *nl = strchr(job.json_verdict, '\n');
        if (nl) *nl = '\0';

        cloud_complete_job(job_id, ok, job.json_verdict, ok ? NULL : "tag verification failed");
        return 1;

    } else if (strcmp(kind, "mark_image") == 0) {
        free(resp);
        xil_printf("CLOUD: downloading image '%s' for marking...\r\n", image_path);
        int img_len = 0;
        uint8_t *img_data = cloud_download_image(image_path, &img_len);
        if (!img_data) {
            cloud_complete_job(job_id, 0, "{}", "image download failed");
            return 1;
        }

        xil_printf("CLOUD: downloaded %d bytes. Embedding 128-bit watermark...\r\n", img_len);
        image_job_t job;
        memset(&job, 0, sizeof(job));
        job.in_data = img_data;
        job.in_len = img_len;
        job.op = JOB_OP_EMBED;
        image_worker_process(&job);
        free(img_data);

        if (job.http_status != 200 || !job.out_data) {
            xil_printf("CLOUD: embedding failed (%d): %s\r\n", job.http_status, job.json_verdict);
            cloud_complete_job(job_id, 0, "{}", "embedding failed or image unmarkable");
            return 1;
        }

        xil_printf("CLOUD: marked image encoded to %d PNG bytes. Uploading result...\r\n", job.out_len);
        int up_rc = cloud_upload_marked_png(auth_uid, job_id, job.out_data, job.out_len);
        free(job.out_data);

        if (up_rc != 0) {
            xil_printf("CLOUD: marked PNG upload failed!\r\n");
            cloud_complete_job(job_id, 0, "{}", "marked image storage upload failed");
            return 1;
        }

        char *nl = strchr(job.json_verdict, '\n');
        if (nl) *nl = '\0';

        xil_printf("CLOUD: marking & upload complete: %s\r\n", job.json_verdict);
        cloud_complete_job(job_id, 1, job.json_verdict, NULL);
        return 1;

    } else {
        free(resp);
        xil_printf("CLOUD: unknown job kind '%s'\r\n", kind);
        cloud_complete_job(job_id, 0, "{}", "unknown job kind");
        return 1;
    }
}
