.section .text.start
.global _start
_start:
    ldr sp, =0x00300000
    bl main
1:  b 1b
