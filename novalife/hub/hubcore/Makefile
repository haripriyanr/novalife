CC ?= gcc
CFLAGS ?= -std=c99 -O2 -Wall -Wextra -Werror -Iinclude -D_POSIX_C_SOURCE=200809L
SRC := $(wildcard src/*.c)
TESTS := $(patsubst tests/%.c,build/%,$(wildcard tests/test_*.c))
all: $(TESTS)
build/%: tests/%.c $(SRC) $(wildcard include/hubcore/*.h)
	@mkdir -p build
	$(CC) $(CFLAGS) $< $(SRC) -lm -o $@
test: $(TESTS)
	@set -e; for t in $(TESTS); do echo "== $$t"; ./$$t; done
clean:
	rm -rf build
.PHONY: all test clean
