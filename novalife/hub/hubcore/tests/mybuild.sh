#!/bin/sh
# Module A private build (does not depend on other modules' sources): ./tests/mybuild.sh ascon tag_block polar iwt
cd "$(dirname "$0")/.." || exit 1
mkdir -p build
CF="-std=c99 -O2 -Wall -Wextra -Werror -Iinclude -Isrc -D_POSIX_C_SOURCE=200809L ${CFLAGS_EXTRA}"
SRCS="src/ascon.c src/tag_block.c src/polar.c src/iwt.c"
for t in "$@"; do ${CC:-gcc} $CF tests/test_$t.c $SRCS -lm -o build/test_$t || exit 1; done
