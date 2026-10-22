/* UART0 (MIO, USB-serial /dev/ttyUSB1) <-> UART1 (EMIO, ESP32) byte bridge, bare metal, polled.
 * Run after ps7_init + the enclave bitstream (UART1 EMIO pins R19/T19). 115200 8N1 both sides,
 * UART ref clock 100 MHz: BAUDGEN=124, BDIV=6. Purpose: flash the ESP32 with esptool through the board. */
#include <stdint.h>
#define U0 0xE0000000u
#define U1 0xE0001000u
#define R(b, o) (*(volatile uint32_t *)((b) + (o)))
#define CR 0x00
#define MR 0x04
#define BAUDGEN 0x18
#define SR 0x2C
#define FIFO 0x30
#define BDIV 0x34
static void init(uint32_t b) {
    R(b, CR) = 0x28; R(b, MR) = 0x20; R(b, BAUDGEN) = 124; R(b, BDIV) = 6;
    R(b, CR) = 0x03; R(b, CR) = 0x14;
}
int main(void) {
    init(U0); init(U1);
    for (;;) {
        if (!(R(U0, SR) & 2)) { uint32_t c = R(U0, FIFO) & 0xFF; while (R(U1, SR) & 0x10) {} R(U1, FIFO) = c; }
        if (!(R(U1, SR) & 2)) { uint32_t c = R(U1, FIFO) & 0xFF; while (R(U0, SR) & 0x10) {} R(U0, FIFO) = c; }
    }
}
