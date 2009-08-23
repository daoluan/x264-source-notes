/*****************************************************************************
 * cpu-a.S: h264 encoder library
 *****************************************************************************
 * Copyright (C) 2009 x264 project
 *
 * Authors: David Conrad <lessen42@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02111, USA.
 *****************************************************************************/

#include "asm.S"

.fpu neon
.align

// done in gas because .fpu neon overrides the refusal to assemble
// instructions the selected -march/-mcpu doesn't support
function x264_cpu_neon_test, export=1
    vadd.i16    q0, q0, q0
    bx          lr
.endfunc

// return: 0 on success
//         1 if counters were already enabled
//         9 if lo-res counters were already enabled
function x264_cpu_enable_armv7_counter
    mrc         p15, 0, r2, c9, c12, 0      // read PMNC
    ands        r0, r2, #1
    andne       r0, r2, #9

    orr         r2, r2, #1                  // enable counters
    bic         r2, r2, #8                  // full resolution
    mcreq       p15, 0, r2, c9, c12, 0      // write PMNC
    mov         r2, #1 << 31                // enable cycle counter
    mcr         p15, 0, r2, c9, c12, 1      // write CNTENS
    bx          lr
.endfunc

function x264_cpu_disable_armv7_counter
    mrc         p15, 0, r0, c9, c12, 0      // read PMNC
    bic         r0, r0, #1                  // disable counters
    mcr         p15, 0, r0, c9, c12, 0      // write PMNC
    bx          lr
.endfunc


.macro READ_TIME r
    mrc         p15, 0, \r, c9, c13, 0
.endm

// return: 0 if transfers neon -> arm transfers take more than 10 cycles
//         nonzero otherwise
function x264_cpu_fast_neon_mrc_test, export=1
    // check for user access to performance counters
    mrc         p15, 0, r0, c9, c14, 0
    cmp         r0, #0
    bxeq        lr

    push        {r4-r6,lr}
    bl          x264_cpu_enable_armv7_counter
    ands        r1, r0, #8
    mov         r3, #0
    mov         ip, #4
    mov         r6, #4
    moveq       r5, #1
    movne       r5, #64

average_loop:
    mov         r4, r5
    READ_TIME   r1
1:  subs        r4, r4, #1
.rept 8
    vmov.u32    lr, d0[0]
    add         lr, lr, lr
.endr
    bgt         1b
    READ_TIME   r2

    subs        r6, r6, #1
    sub         r2, r2, r1
    cmpgt       r2, #30 << 3    // assume context switch if it took over 30 cycles
    addle       r3, r3, r2
    subles      ip, ip, #1
    bgt         average_loop

    // disable counters if we enabled them
    ands        r0, r0, #1
    bleq        x264_cpu_disable_armv7_counter

    lsr         r0, r3, #5
    cmp         r0, #10
    movgt       r0, #0
    pop         {r4-r6,pc}
.endfunc