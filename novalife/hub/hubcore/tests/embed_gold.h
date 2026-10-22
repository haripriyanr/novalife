/* Reader for tests/golden/embed_*.bin (written by gen_embed.py): little-endian int64 words and
 * raw byte runs.  Any short read aborts the test. */
#ifndef EMBED_GOLD_H
#define EMBED_GOLD_H
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    FILE *f;
    const char *name;
} gold_t;

static void gold_open(gold_t *g, const char *path)
{
    g->f = fopen(path, "rb");
    g->name = path;
    if (!g->f) {
        fprintf(stderr, "cannot open golden file %s (run tests/gen_embed.py)\n", path);
        exit(2);
    }
}
static void gold_bytes(gold_t *g, void *p, size_t n)
{
    if (n && fread(p, 1, n, g->f) != n) {
        fprintf(stderr, "short read in %s\n", g->name);
        exit(2);
    }
}
static int64_t gold_i(gold_t *g)
{
    int64_t v;
    gold_bytes(g, &v, 8);
    return v;
}
static double gold_d(gold_t *g)
{
    double v;
    gold_bytes(g, &v, 8);
    return v;
}
static void gold_magic(gold_t *g, int64_t m)
{
    int64_t v = gold_i(g);
    if (v != m) {
        fprintf(stderr, "golden desync in %s: expected magic 0x%llx got 0x%llx\n", g->name,
                (long long)m, (long long)v);
        exit(2);
    }
}
static void *gold_alloc(size_t n)
{
    void *p = malloc(n ? n : 1);
    if (!p) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }
    return p;
}
#endif
