# CPU1 bare-metal verify worker (AMP).  Builds firmware/vitis_ws_core1/build/novalife_core1.elf.
#
#   vitis -s core1/create_core1_ws.py   # once: standalone BSP for ps7_cortexa9_1 (USE_AMP=1, no stdout)
#   make -C core1
#
# The algorithm sources are the same files CPU0 builds (src/), compiled with -O2.

XILINX ?= /home/user/develop/Xilinx/2026.1
CC     := $(XILINX)/gnu/aarch32/lin/gcc-arm-none-eabi/bin/arm-none-eabi-gcc
SIZE   := $(XILINX)/gnu/aarch32/lin/gcc-arm-none-eabi/bin/arm-none-eabi-size
BSP    := ../vitis_ws_core1/core1_platform/export/core1_platform/sw/standalone_a9_1
OUT    := ../vitis_ws_core1/build
SRC    := ../src

ALGO   := nl_api extract embed_block embed_mark embed_place embed_roi iwt polar ascon tag_block
OBJS   := $(OUT)/main.o $(addprefix $(OUT)/,$(addsuffix .o,$(ALGO)))

CFLAGS := -DSDT -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard -O2 -g -Wall -Wextra \
          -specs=$(BSP)/Xilinx.spec -I$(BSP)/include -I$(SRC) -MMD -MP
LDLIBS := -Wl,-T,lscript.ld -L$(BSP)/lib \
          -Wl,--start-group,-lxilstandalone,-lxiltimer,-lxil,-lm,-lgcc,-lc,--end-group

$(OUT)/novalife_core1.elf: $(OBJS) lscript.ld
	$(CC) $(CFLAGS) -o $@ $(OBJS) $(LDLIBS)
	$(SIZE) $@

$(OUT)/main.o: main.c | $(OUT)
	$(CC) $(CFLAGS) -c -o $@ $<

$(OUT)/%.o: $(SRC)/%.c | $(OUT)
	$(CC) $(CFLAGS) -c -o $@ $<

$(OUT):
	mkdir -p $@

clean:
	rm -rf $(OUT)

-include $(OBJS:.o=.d)
.PHONY: clean
