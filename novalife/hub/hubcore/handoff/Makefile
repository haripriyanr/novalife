# make test IMPL="path/a.c path/b.c ..." [INC="-Ipath"]   -- builds your C with the harness and runs it
CC ?= gcc
IMPL ?=
INC ?=
build/run_golden: run_golden.c nl_api.h $(IMPL)
	@mkdir -p build
	$(CC) -std=c99 -O2 -Wall -Wextra -I. $(INC) run_golden.c $(IMPL) -lm -o $@
test: build/run_golden
	./build/run_golden golden
clean:
	rm -rf build
.PHONY: test clean
