/*
 * Runner minimo para ejecutar simulacion.bin con z80ex.
 *
 * Uso:
 *   ./z80_run [archivo.bin] [caracteres_a_capturar]
 *
 * Carga el binario en 0x0FFD (donde arranca segun el ".ORG 1000H - 3" del
 * fuente), arranca el PC en NBIOIO (primera instruccion real, "JP DEBMON")
 * y ejecuta paso a paso. Cada vez que el monitor hace OUT al CONSOLE_PORT
 * (0FFH) -- lo hace la rutina PRINTC -- el caracter se imprime en stdout,
 * asi se ve en vivo el orden real en que las tareas T1/T2/T3 corren.
 *
 * Simplificacion deliberada: en vez de emular el chip CTC (Z80 CTC real,
 * con su registro de vector de 5 bits + 3 bits de canal), la interrupcion
 * periodica del "reloj" se dispara cada TICK_EVERY instrucciones, y el
 * byte de vector devuelto en el ciclo de reconocimiento de interrupcion
 * (IM 2) se fija directamente al byte bajo de TARTIT (ver simulacion.sym),
 * que es adonde el monitor espera saltar. Esto basta para observar el
 * round-robin y el time-slicing sin tener que reproducir el hardware del
 * CTC bit a bit.
 */
#include <stdio.h>
#include <stdlib.h>
#include <z80ex/z80ex.h>

#define MEMSIZE       0x10000
#define ORG_START     0x0FFD   /* .ORG 1000H - 3 */
#define ENTRY_POINT   0x1001   /* NBIOIO: "JP DEBMON", ver simulacion.sym */
#define TARTIT_LOW    0x5D     /* byte bajo de TARTIT, ver simulacion.sym  */
#define CONSOLE_PORT  0xFF
#define CONSBUF_ADDR  0x195F   /* ver simulacion.sym */
#define CONSPTR_ADDR  0x1A27   /* ver simulacion.sym */
#define TICK_EVERY    200
#define MAX_INSTR     5000000L

static unsigned char mem[MEMSIZE];

static Z80EX_BYTE mem_read(Z80EX_CONTEXT *cpu, Z80EX_WORD addr, int m1_state, void *ud)
{
    (void)cpu; (void)m1_state; (void)ud;
    return mem[addr];
}

static void mem_write(Z80EX_CONTEXT *cpu, Z80EX_WORD addr, Z80EX_BYTE val, void *ud)
{
    (void)cpu; (void)ud;
    mem[addr] = val;
}

static Z80EX_BYTE port_read(Z80EX_CONTEXT *cpu, Z80EX_WORD port, void *ud)
{
    (void)cpu; (void)port; (void)ud;
    return 0xFF;
}

static void port_write(Z80EX_CONTEXT *cpu, Z80EX_WORD port, Z80EX_BYTE val, void *ud)
{
    (void)cpu; (void)ud;
    if ((port & 0xFF) == CONSOLE_PORT) {
        putchar(val);
        fflush(stdout);
    }
}

static Z80EX_BYTE int_read(Z80EX_CONTEXT *cpu, void *ud)
{
    (void)cpu; (void)ud;
    return TARTIT_LOW;
}

int main(int argc, char **argv)
{
    const char *binpath = argc > 1 ? argv[1] : "simulacion.bin";
    long want_chars = argc > 2 ? atol(argv[2]) : 200;

    FILE *f = fopen(binpath, "rb");
    if (!f) { perror(binpath); return 1; }
    size_t n = fread(mem + ORG_START, 1, MEMSIZE - ORG_START, f);
    fclose(f);
    fprintf(stderr, "[z80_run] cargados %zu bytes en 0x%04X\n", n, ORG_START);

    Z80EX_CONTEXT *cpu = z80ex_create(mem_read, NULL, mem_write, NULL,
                                       port_read, NULL, port_write, NULL,
                                       int_read, NULL);
    z80ex_reset(cpu);                  /* deja AF/BC/DE/HL/IX/IY/IM/IFF en el
                                           estado conocido de un reset real, en
                                           vez de la basura que deja el malloc
                                           interno de z80ex_create */
    z80ex_set_reg(cpu, regPC, ENTRY_POINT);

    fprintf(stderr, "[z80_run] ejecutando (Ctrl+C para detener antes)...\n\n");

    long instr = 0, since_tick = 0, printed = 0;
    while (instr < MAX_INSTR && printed < want_chars) {
        z80ex_step(cpu);
        instr++;

        if (++since_tick >= TICK_EVERY) {
            since_tick = 0;
            z80ex_int(cpu);
        }

        printed = (mem[CONSPTR_ADDR] | (mem[CONSPTR_ADDR + 1] << 8)) - CONSBUF_ADDR;
    }

    fprintf(stderr, "\n[z80_run] %ld instrucciones ejecutadas, %ld caracteres capturados\n",
            instr, printed);

    fprintf(stderr, "[z80_run] CONSBUF completo:\n");
    for (long i = 0; i < printed; i++) putchar(mem[CONSBUF_ADDR + i]);
    putchar('\n');

    z80ex_destroy(cpu);
    return 0;
}
