#!/bin/sh
# Module C private build (does not need embed_mark.c): ./tests/buildC.sh extract
cd "$(dirname "$0")/.." || exit 1
mkdir -p build
CF="-std=c99 -O2 -ffp-contract=off -Wall -Wextra -Werror -Iinclude -Isrc -D_POSIX_C_SOURCE=200809L ${CFLAGS_EXTRA}"
SRCS="src/ascon.c src/tag_block.c src/polar.c src/iwt.c src/embed_block.c src/embed_place.c src/embed_roi.c src/extract.c"
for t in "$@"; do ${CC:-gcc} $CF tests/test_$t.c $SRCS -lm -o build/test_$t || exit 1; done
