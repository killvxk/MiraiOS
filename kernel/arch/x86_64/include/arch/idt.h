#ifndef IRQ_IDT_H
#define IRQ_IDT_H

#include <stdint.h>
#include <irq.h>

void initIDT(void);

void mapIdtEntry(void (*ISR)(void), interrupt_t interrupt, uint8_t flags);

void unmapIdtEntry(interrupt_t interrupt);

void idtSetIST(interrupt_t interrupt, int ist);

void idtSetDPL(interrupt_t interrupt, bool user);

#endif