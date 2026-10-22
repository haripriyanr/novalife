#include <stdio.h>
#include <string.h>
#include "FreeRTOS.h"
#include "semphr.h"
#include "vault.h"

static char   slot_data[VAULT_SLOTS][VAULT_SLOT_SZ];
static int    slot_len[VAULT_SLOTS];
static int    next_slot = 0;
static SemaphoreHandle_t vault_mutex = NULL;

int vault_init(void)
{
    if (vault_mutex != NULL)
        return 0;
    vault_mutex = xSemaphoreCreateMutex();
    if (vault_mutex == NULL)
        return -1;
    memset(slot_data, 0, sizeof(slot_data));
    memset(slot_len, 0, sizeof(slot_len));
    next_slot = 0;
    return 0;
}

int vault_store(const char *data, int len, int *slot)
{
    int s;

    if (data == NULL || len <= 0 || slot == NULL)
        return -1;
    if (len > VAULT_SLOT_SZ)
        len = VAULT_SLOT_SZ; /* truncate, never overflow */

    if (xSemaphoreTake(vault_mutex, portMAX_DELAY) != pdTRUE)
        return -1;
    s = next_slot;
    memcpy(slot_data[s], data, len);
    slot_len[s] = len;
    next_slot = (next_slot + 1) % VAULT_SLOTS;
    xSemaphoreGive(vault_mutex);
    *slot = s;
    return len;
}

int vault_count(void)
{
    int i, n = 0;

    if (xSemaphoreTake(vault_mutex, portMAX_DELAY) != pdTRUE)
        return -1;
    for (i = 0; i < VAULT_SLOTS; i++)
        if (slot_len[i] > 0)
            n++;
    xSemaphoreGive(vault_mutex);
    return n;
}

/* One JSON object per line: {"slot":i,"size":n}. Same JSONL shape
 * the old bare-metal vault served at GET /vault/index.txt. */
int vault_index_jsonl(char *out, int out_sz)
{
    int i, pos = 0, w;

    if (out == NULL || out_sz <= 0)
        return -1;
    if (xSemaphoreTake(vault_mutex, portMAX_DELAY) != pdTRUE)
        return -1;
    for (i = 0; i < VAULT_SLOTS; i++) {
        if (slot_len[i] <= 0)
            continue;
        w = snprintf(&out[pos], out_sz - pos,
                     "{\"slot\":%d,\"size\":%d}\n", i, slot_len[i]);
        if (w < 0 || w >= out_sz - pos)
            break;
        pos += w;
    }
    xSemaphoreGive(vault_mutex);
    return pos;
}
