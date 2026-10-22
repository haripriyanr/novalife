/* Mailbox protocol between the PS (FreeRTOS gateway) and the PL enclave.
 *
 * Commands: BUILD_TAG, VERIFY_TAG, MARK_IMAGE, EXTRACT_TAG, STATUS.
 * ADMIN_* commands are restricted to a PL-wired console and are never
 * reachable over the network.
 *
 * The PL is memory-mapped at PL_BASE (defined below).  When no bitstream
 * is loaded (PL absent), every command returns MB_ERR_NO_PL and logs the
 * stub.  When the PL is present, the PS writes the command + arguments to
 * the mailbox registers, pulses the doorbell, and waits for the done flag.
 */
#ifndef MAILBOX_H
#define MAILBOX_H

#include <stdint.h>

typedef enum {
    MB_BUILD_TAG = 0,
    MB_VERIFY_TAG,
    MB_MARK_IMAGE,
    MB_EXTRACT_TAG,
    MB_STATUS,
    MB_ADMIN_LOAD_KEY,
    MB_ADMIN_ROTATE_KEY,
    MB_ADMIN_WIPE_KEY,
    MB_CMD_COUNT
} mb_cmd_t;

typedef enum {
    MB_OK = 0,
    MB_ERR_NO_PL,       /* no bitstream loaded */
    MB_ERR_TIMEOUT,     /* PL did not respond */
    MB_ERR_BAD_ARG,     /* invalid argument */
    MB_ERR_VERIFY_FAIL, /* tag verification failed */
    MB_ERR_CAPACITY,    /* cannot place 256 blocks per region */
} mb_status_t;

/* Shared memory region for image data (PS -> PL and PL -> PS).
 * The PL reads/writes this region via AXI.  Size must match the reserved
 * memory window in the device tree. */
#define MB_SHMEM_BASE   0x10000000UL
#define MB_SHMEM_SIZE   (4 * 1024 * 1024)  /* 4 MB */

/* PL mailbox register offsets (relative to PL_BASE). */
#define PL_BASE         0x40000000UL
#define PL_REG_CMD      0x00
#define PL_REG_ARG0     0x04
#define PL_REG_ARG1     0x08
#define PL_REG_STATUS   0x0C
#define PL_REG_DONE     0x10
#define PL_REG_RESULT   0x14

#define PL_STATUS_READY  0x01
#define PL_DONE_BIT      0x01

/* Extended registers (vivado/ip_repo/enclave_axi/enclave_axi.v). */
#define PL_REG_FIELDS    0x20   /* [15:12] version, [11:0] hub_id */
#define PL_REG_HANDLE_HI 0x24
#define PL_REG_HANDLE_LO 0x28
#define PL_REG_TAGIN_HI  0x2C   /* [15:0] */
#define PL_REG_TAGIN_LO  0x30
#define PL_REG_RTAG_HI   0x34   /* [15:0] */
#define PL_REG_RTAG_LO   0x38
#define PL_REG_CYCLES    0x3C   /* PL cycles of the last command */
#define PL_STATUS_MAGIC  0x4E4CU /* STATUS[31:16] */

/* RESULT register fields */
#define PL_RES_STATUS(r) ((r) & 0x3U)       /* 0 OK, 1 NO_KEY, 2 LIMITED, 3 BAD_OP */
#define PL_RES_OK(r)     (((r) >> 8) & 1U)  /* VERIFY accepted */
#define PL_RES_UNSUP(r)  (((r) >> 16) & 1U)

/* Zynq devcfg: a PL access with no configured fabric hangs the bus, so the probe checks
 * that the PL is configured before it reads the AXI window.  PCFG_DONE is bit 2 of
 * devcfg INT_STS (Zynq TRM, ug585); checked on the board in results/hw_enclave_*.md. */
#define DEVCFG_INT_STS   0xF800700CUL
#define DEVCFG_PCFG_DONE (1U << 2)

const char *mb_cmd_name(mb_cmd_t c);
int  mailbox_init(void);
int  mailbox_send(mb_cmd_t cmd, uint32_t arg0, uint32_t arg1);
mb_status_t mailbox_wait_done(uint32_t timeout_ms);
int  mailbox_pl_present(void);

/* Synchronous tag commands (serialised by a mutex; callable from any task).
 * Return MB_OK, MB_ERR_NO_PL, MB_ERR_TIMEOUT, MB_ERR_BAD_ARG (no key / rate limited / bad op;
 * *pl_status gets the raw PL status), or MB_ERR_VERIFY_FAIL for a rejected tag. */
mb_status_t mailbox_build_tag(uint8_t version, uint16_t hub_id, uint64_t handle,
                              uint64_t *tag48, uint32_t *pl_status);
mb_status_t mailbox_verify_tag(uint8_t version, uint16_t hub_id, uint64_t handle,
                               uint64_t tag48, uint32_t *pl_status);
mb_status_t mailbox_load_key(const uint8_t key[16]);

#endif
