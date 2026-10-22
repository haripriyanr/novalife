/* nl_api.c -- Implementation of nl_api.h wrapping hubcore functions. */
#include <string.h>
#include "nl_api.h"
#include "hubcore/embed.h"
#include "hubcore/extract.h"

int nl_mark(const uint8_t *cover, int h, int w, const uint8_t key[16], const uint8_t block[16],
            uint8_t *marked, nl_mark_info *info)
{
    uint8_t bits[HC_EMB_BITS];
    hc_mark_info hinfo;
    int rc, i, b;

    if (!cover || !key || !block || !marked || h <= 0 || w <= 0)
        return -1;

    for (i = 0; i < 16; i++) {
        for (b = 0; b < 8; b++) {
            bits[i * 8 + b] = (uint8_t)((block[i] >> (7 - b)) & 1);
        }
    }

    rc = hc_mark(cover, h, w, NULL, key, bits, marked, &hinfo);

    if (info) {
        info->copies_written = hinfo.copies_written;
        for (i = 0; i < 4; i++) {
            info->capacity[i] = (int)hinfo.blocks_available_per_region[i];
        }
    }

    if (rc == HC_EMB_CAPACITY)
        return 1;
    if (rc < 0)
        return rc;

    return 0;
}

int nl_recover(const uint8_t *img, int h, int w, int decl_h, int decl_w, const uint8_t key[16],
               nl_recover_result *out)
{
    hc_recovery rec;
    int rc, i, bit;

    if (!img || !key || !out || h <= 0 || w <= 0 || decl_h <= 0 || decl_w <= 0)
        return -1;

    memset(out, 0, sizeof(*out));

    rc = hc_recover(img, h, w, decl_h, decl_w, key, &rec);
    if (rc != 0)
        return rc;

    out->tag_ok = rec.tag_ok;
    out->version = rec.fields.version;
    out->hub_id = rec.fields.hub_id;
    out->handle = rec.fields.handle;
    out->candidate = (rec.accepted.cls == HC_CAND_NONE) ? -1 : (int)rec.accepted.cls;

    for (i = 0; i < 16; i++) {
        uint8_t byte_val = 0;
        for (bit = 0; bit < 8; bit++) {
            byte_val = (uint8_t)((byte_val << 1) | (rec.bits[i * 8 + bit] & 1));
        }
        out->block[i] = byte_val;
    }

    return 0;
}
