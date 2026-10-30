/* rtos_trace_tasks.c -- the BSP's FreeRTOS tasks.c, rebuilt with a context-switch hook for the trace.
 *
 * The kernel is compiled into libfreertos.a without trace macros, and regenerating the BSP to add one is
 * not scriptable here.  This file compiles the same tasks.c (same FreeRTOSConfig.h) with
 * traceTASK_SWITCHED_IN defined.  It defines every symbol the archive's tasks.o does, so the linker never
 * pulls that member.  The path is relative to the Vitis app source folder (vitis_ws/novalife_hub_fw/src)
 * or to this folder (src/).
 */
#include "trace.h"

#define traceTASK_SWITCHED_IN() trace_task_in((uint32_t)pxCurrentTCB->uxTCBNumber, pxCurrentTCB->pcTaskName)

#if __has_include("../../novalife_ps_platform/ps7_cortexa9_0/freertos_a9/bsp/libsrc/freertos10_xilinx/src/Source/tasks.c")
#include "../../novalife_ps_platform/ps7_cortexa9_0/freertos_a9/bsp/libsrc/freertos10_xilinx/src/Source/tasks.c"
#elif __has_include("../vitis_ws/novalife_ps_platform/ps7_cortexa9_0/freertos_a9/bsp/libsrc/freertos10_xilinx/src/Source/tasks.c")
#include "../vitis_ws/novalife_ps_platform/ps7_cortexa9_0/freertos_a9/bsp/libsrc/freertos10_xilinx/src/Source/tasks.c"
#else
#error "FreeRTOS tasks.c not found: build the Vitis platform (firmware/vitis_ws/novalife_ps_platform) first"
#endif
