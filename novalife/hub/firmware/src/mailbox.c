#include "FreeRTOS.h"
#include "queue.h"
#include "semphr.h"
#include "task.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "mailbox.h"

#define MB_QUEUE_LEN 8

typedef struct {
    mb_cmd_t cmd;
    uint32_t arg0;
    uint32_t arg1;
} mb_msg_t;

static QueueHandle_t mb_queue = NULL;
/* One register file, many callers (the mbox task, the HTTP handlers): a FreeRTOS mutex
 * (priority inheritance, unlike a binary semaphore) makes each command atomic. */
static SemaphoreHandle_t mb_hw_mutex = NULL;

const char *mb_cmd_name(mb_cmd_t c)
{
    switch (c) {
    case MB_BUILD_TAG:       return "BUILD_TAG";
    case MB_VERIFY_TAG:      return "VERIFY_TAG";
    case MB_MARK_IMAGE:      return "MARK_IMAGE";
    case MB_EXTRACT_TAG:     return "EXTRACT_TAG";
    case MB_STATUS:          return "STATUS";
    case MB_ADMIN_LOAD_KEY:  return "ADMIN_LOAD_KEY";
    case MB_ADMIN_ROTATE_KEY: return "ADMIN_ROTATE_KEY";
    case MB_ADMIN_WIPE_KEY:  return "ADMIN_WIPE_KEY";
    default:                 return "UNKNOWN";
    }
}

/* Check whether a PL bitstream is loaded by reading the status register. */
int mailbox_pl_present(void)
{
    /* Never touch the AXI window unless the fabric is configured (the access would hang). */
    if (!(Xil_In32(DEVCFG_INT_STS) & DEVCFG_PCFG_DONE))
        return 0;
    uint32_t status = Xil_In32(PL_BASE + PL_REG_STATUS);
    return ((status >> 16) == PL_STATUS_MAGIC && (status & PL_STATUS_READY)) ? 1 : 0;
}

/* Wait for the PL to assert the done flag. */
mb_status_t mailbox_wait_done(uint32_t timeout_ms)
{
    uint32_t ticks = pdMS_TO_TICKS(timeout_ms);
    uint32_t start = xTaskGetTickCount();
    while (!(Xil_In32(PL_BASE + PL_REG_DONE) & PL_DONE_BIT)) {
        if ((xTaskGetTickCount() - start) >= ticks)
            return MB_ERR_TIMEOUT;
        vTaskDelay(pdMS_TO_TICKS(1));
    }
    /* DONE clears itself on the next CMD write (enclave_axi). */
    return MB_OK;
}

static void mailbox_task(void *arg)
{
    mb_msg_t msg;
    (void)arg;

    xil_printf("MB: task up, queue ready\r\n");
    if (mailbox_pl_present())
        xil_printf("MB: PL detected (bitstream loaded)\r\n");
    else
        xil_printf("MB: PL absent (no bitstream) -- stub mode\r\n");

    for (;;) {
        if (xQueueReceive(mb_queue, &msg, pdMS_TO_TICKS(10000)) == pdTRUE) {
            if (!mailbox_pl_present()) {
                /* Stub mode: log and return MB_ERR_NO_PL. */
                xil_printf("MB: %s -> STUB (no PL enclave)\r\n",
                           mb_cmd_name(msg.cmd));
                continue;
            }
            /* Arguments first: the CMD write is the doorbell. */
            xSemaphoreTake(mb_hw_mutex, portMAX_DELAY);
            Xil_Out32(PL_BASE + PL_REG_ARG0, msg.arg0);
            Xil_Out32(PL_BASE + PL_REG_ARG1, msg.arg1);
            Xil_Out32(PL_BASE + PL_REG_CMD,  (uint32_t)msg.cmd);

            mb_status_t st = mailbox_wait_done(5000);
            if (st == MB_OK) {
                uint32_t result = Xil_In32(PL_BASE + PL_REG_RESULT);
                xil_printf("MB: %s -> done, result=0x%08lx\r\n",
                           mb_cmd_name(msg.cmd), (unsigned long)result);
            } else {
                xil_printf("MB: %s -> TIMEOUT\r\n", mb_cmd_name(msg.cmd));
            }
            xSemaphoreGive(mb_hw_mutex);
        } else {
            xil_printf("MB: heartbeat, queue idle\r\n");
        }
    }
}

int mailbox_init(void)
{
    mb_queue = xQueueCreate(MB_QUEUE_LEN, sizeof(mb_msg_t));
    mb_hw_mutex = xSemaphoreCreateMutex();
    if (mb_queue == NULL || mb_hw_mutex == NULL)
        return -1;
    if (xTaskCreate(mailbox_task, "mbox", 2048, NULL,
                    tskIDLE_PRIORITY + 1, NULL) != pdPASS)
        return -1;
    return 0;
}

int mailbox_send(mb_cmd_t cmd, uint32_t arg0, uint32_t arg1)
{
    mb_msg_t msg = { .cmd = cmd, .arg0 = arg0, .arg1 = arg1 };
    if (mb_queue == NULL)
        return -1;
    return (xQueueSend(mb_queue, &msg, 0) == pdTRUE) ? 0 : -1;
}

/* ---- synchronous tag commands --------------------------------------------------------- */

static mb_status_t tag_cmd(mb_cmd_t cmd, uint8_t version, uint16_t hub_id, uint64_t handle,
                           uint64_t tag_in, uint64_t *tag_out, uint32_t *pl_status)
{
    if (version > 0xF || hub_id > 0xFFF || tag_in >> 48)
        return MB_ERR_BAD_ARG;
    if (!mailbox_pl_present())
        return MB_ERR_NO_PL;
    xSemaphoreTake(mb_hw_mutex, portMAX_DELAY);
    Xil_Out32(PL_BASE + PL_REG_FIELDS, ((uint32_t)version << 12) | hub_id);
    Xil_Out32(PL_BASE + PL_REG_HANDLE_HI, (uint32_t)(handle >> 32));
    Xil_Out32(PL_BASE + PL_REG_HANDLE_LO, (uint32_t)handle);
    Xil_Out32(PL_BASE + PL_REG_TAGIN_HI, (uint32_t)(tag_in >> 32));
    Xil_Out32(PL_BASE + PL_REG_TAGIN_LO, (uint32_t)tag_in);
    Xil_Out32(PL_BASE + PL_REG_CMD, (uint32_t)cmd);          /* doorbell last */
    mb_status_t st = mailbox_wait_done(100);
    uint32_t res = Xil_In32(PL_BASE + PL_REG_RESULT);
    if (tag_out)
        *tag_out = ((uint64_t)(Xil_In32(PL_BASE + PL_REG_RTAG_HI) & 0xFFFF) << 32) |
                   Xil_In32(PL_BASE + PL_REG_RTAG_LO);
    xSemaphoreGive(mb_hw_mutex);
    if (pl_status)
        *pl_status = res;
    if (st != MB_OK)
        return st;
    if (PL_RES_UNSUP(res) || PL_RES_STATUS(res) != 0)
        return MB_ERR_BAD_ARG;
    if (cmd == MB_VERIFY_TAG && !PL_RES_OK(res))
        return MB_ERR_VERIFY_FAIL;
    return MB_OK;
}

mb_status_t mailbox_build_tag(uint8_t version, uint16_t hub_id, uint64_t handle,
                              uint64_t *tag48, uint32_t *pl_status)
{
    return tag_cmd(MB_BUILD_TAG, version, hub_id, handle, 0, tag48, pl_status);
}

mb_status_t mailbox_verify_tag(uint8_t version, uint16_t hub_id, uint64_t handle,
                               uint64_t tag48, uint32_t *pl_status)
{
    return tag_cmd(MB_VERIFY_TAG, version, hub_id, handle, tag48, NULL, pl_status);
}

mb_status_t mailbox_load_key(const uint8_t key[16])
{
    if (!mailbox_pl_present())
        return MB_ERR_NO_PL;
    xSemaphoreTake(mb_hw_mutex, portMAX_DELAY);
    uint32_t k0 = ((uint32_t)key[0] << 24) | ((uint32_t)key[1] << 16) | ((uint32_t)key[2] << 8) | key[3];
    uint32_t k1 = ((uint32_t)key[4] << 24) | ((uint32_t)key[5] << 16) | ((uint32_t)key[6] << 8) | key[7];
    uint32_t k2 = ((uint32_t)key[8] << 24) | ((uint32_t)key[9] << 16) | ((uint32_t)key[10] << 8) | key[11];
    uint32_t k3 = ((uint32_t)key[12] << 24) | ((uint32_t)key[13] << 16) | ((uint32_t)key[14] << 8) | key[15];
    Xil_Out32(PL_BASE + 0x40, k0);
    Xil_Out32(PL_BASE + 0x44, k1);
    Xil_Out32(PL_BASE + 0x48, k2);
    Xil_Out32(PL_BASE + 0x4C, k3);
    Xil_Out32(PL_BASE + PL_REG_CMD, (uint32_t)MB_ADMIN_LOAD_KEY);
    mb_status_t st = mailbox_wait_done(100);
    xSemaphoreGive(mb_hw_mutex);
    return st;
}
