/* NovaLife HUB RAM vault (phase 1 stub).
 * No SD card is present in this bring-up, so the vault lives in DDR.
 * 4 slots x 1024 bytes mirrors the old bare-metal vault's shape
 * (vault_files = 4, 1024 B stego body). All access is mutex-guarded
 * because the HTTP task is the only writer/reader today, but the
 * mailbox task will join once the PL exists.
 */
#ifndef VAULT_H
#define VAULT_H

#include <stddef.h>

#define VAULT_SLOTS  4
#define VAULT_SLOT_SZ 1024
#define VAULT_NAME_SZ 32

int  vault_init(void);                                   /* creates the mutex, empties slots */
int  vault_store(const char *data, int len, int *slot); /* round-robin store, returns slot id */
int  vault_count(void);                                  /* non-empty slots */
int  vault_index_jsonl(char *out, int out_sz);           /* JSONL listing, returns bytes */

#endif
