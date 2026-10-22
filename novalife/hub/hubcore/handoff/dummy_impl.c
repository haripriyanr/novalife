/* A deliberately WRONG implementation: proves the harness fails when the C is wrong. */
#include <string.h>
#include "nl_api.h"
int nl_mark(const uint8_t *c, int h, int w, const uint8_t k[16], const uint8_t b[16], uint8_t *m, nl_mark_info *i) { (void)k; (void)b; memcpy(m, c, (size_t)h * w); i->copies_written = 1; return 0; }
int nl_recover(const uint8_t *im, int h, int w, int dh, int dw, const uint8_t k[16], nl_recover_result *o) { (void)im; (void)h; (void)w; (void)dh; (void)dw; (void)k; o->tag_ok = 1; memset(o->block, 0, 16); return 0; }
