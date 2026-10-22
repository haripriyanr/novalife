/* Shared helpers for module-A tests (host only; uses stdio). */
#ifndef HCA_UTIL_H
#define HCA_UTIL_H
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static __attribute__((unused)) int hcA_hexval(int c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}
/* parse hex token ("-" or "" = empty) into buf; returns byte length or -1 */
static __attribute__((unused)) long hcA_hex(const char *s, uint8_t *buf, size_t cap) {
    size_t n = 0;
    if (s[0] == '-' && (s[1] == 0 || s[1] == ' ' || s[1] == '\n')) return 0;
    while (hcA_hexval(s[0]) >= 0 && hcA_hexval(s[1]) >= 0) {
        if (n >= cap) return -1;
        buf[n++] = (uint8_t)(hcA_hexval(s[0]) * 16 + hcA_hexval(s[1]));
        s += 2;
    }
    return (long)n;
}
static __attribute__((unused)) const char *hcA_next_tok(const char *s) { /* skip current token and spaces */
    while (*s && *s != ' ' && *s != '\n') s++;
    while (*s == ' ') s++;
    return s;
}
static __attribute__((unused)) uint8_t *hcA_readfile(const char *path, size_t *len) {
    FILE *f = fopen(path, "rb");
    uint8_t *b;
    long n;
    if (!f) { fprintf(stderr, "cannot open %s\n", path); return NULL; }
    fseek(f, 0, SEEK_END); n = ftell(f); fseek(f, 0, SEEK_SET);
    b = (uint8_t *)malloc((size_t)n + 1);
    if (!b || fread(b, 1, (size_t)n, f) != (size_t)n) { fclose(f); free(b); return NULL; }
    b[n] = 0; fclose(f); *len = (size_t)n;
    return b;
}
#define HCA_CHECK(cond, ...) do { if (!(cond)) { fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); return 1; } } while (0)
#endif
