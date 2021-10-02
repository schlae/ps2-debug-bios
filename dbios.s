;
; PS/2 Model 77 (Bermuda Planar) Hacky Diagnostics ROM
; Burn this into a 27C010 or 29F010 and swap it into the ROM socket on your
; machine. Use at your own risk.
; Copyright (C) 2021 Eric Schlaepfer
;
; This work is licensed under the Creative Commons Attribution-ShareAlike 4.0
; International License. To view a copy of this license, visit
; http://creativecommons.org/licenses/by-sa/4.0/ or send a letter to Creative
; Commons, PO Box 1866, Mountain View, CA 94042, USA.
;

; Build using
; $ nasm dbios.s -l dbios.lst

; Macro for calling functions with non-functional RAM.
; Good for when you haven't configured the RAM, set up the refresh, and set
; up the stack. Before calling, make sure SS = CS.
%macro   rcall 1
    mov sp, $+5                 ; Return stack points to dw statement
    jmp %1                      ; Jump to the function (no pushes, no calls)
    dw $+2                      ; Pointer to next executable code
%endmacro

    global _start               ; This is designed for a 27C010 ROM
    org 0xe0000                 ; BASIC would go here
    section .text start=0xf0000 ; ROM BIOS goes here
reset_vector:
    ; Init code copied from existing BIOS.
    cli
    cld
    in al,0x60                  ; Presumable clears something in the 8042
    in al,0x64                  ; Read keyboard status

    ; Does something to CMOS
    mov ax, 0xd58d              ; Sets NMI bit mask
    out 0x70,al                 ; Set RTC register to 0x0D

    ; BIOS normally tests CPU flags here. Skipping that.
    in al, 0x64

    ; BIOS normally checks power up status (warm/cold boot). Skipping.
    ; Set up data segment to BIOS data area
    mov ax,0x40
    mov ds,ax

    mov ax, cs
    mov ss, ax      ; We're doing the nasty stack trick

    mov ax,0xff7f   ; AH=FF - leave planar setup.
                    ; AL=7F - enter planar setup group #1
    out 0x94,al     ; Enter planar setup
    mov al,0x91     ; Bit 7: disable bidir mode.
                    ; Bit 5-6: Parallel port addr: 00: 3BC-3BFh)
                    ; Bit 4: Enable parallel port (1: enabled)
                    ; Bit 0: Enable system board functions (0: all disabled)
    mov dx,0x102    ; 102h = planar POS group #1, register 2
    out dx,al       ; Write config value
    mov al,ah       ; AL=FFh, leave planar setup
    out 0x94,al     ; Leave planar setup
    xor al,al       ; AL=0
    mov dx,0x681    ; 681h = secondary micro channel diag port
    out dx,al       ; First checkpoint, writes 0x00 to 0x681 debug port

    ; BIOS normally does a fancy flags/register test here. Skipping.

    ; This initializes the memory controller on Bermuda planars.
    ; I have no idea how this works.
    mov al,0xff
    out 0xe0,al
    mov al,0xff
    out 0xe8,al
    mov al,0xb
    out 0xe1,al
    mov al,0x77
    out 0xe2,al
    mov al,0x32
    out 0xe4,al

    ; Run the read/write test
    ; Comment out this line to run the POS card select test instead
    jmp mainloop

    ; This test changes the MCA POS card select line.
    ; This is controlled from the IO controller, U42, driving a 74F138 decoder
    ; that drives the CD_SETUP# wires.
mainloop2:
    mov al,0x00
    rcall do_port
    mov al,0x01
    rcall do_port
    mov al,0x02
    rcall do_port
    mov al,0x03
    rcall do_port
    mov al,0x04
    rcall do_port
    mov al,0x05
    rcall do_port
    mov al,0x06
    rcall do_port
    mov al,0x07
    rcall do_port
    jmp mainloop2

do_port:
    mov dx,0x100
    or al,0x08                      ; Drive CD_SETUP#
    out 0x96,al                     ; Select this particular slot
    mov cx,0x100                    ; Wait loop to make probing easier
do_port_loop:
    in al,dx
    loop do_port_loop
    ret

    ; Read/write test of adapter setup/enable register
mainloop:
    ; Write a junk value to the parallel port just for fun
    mov al,0x55
    mov dx,0x3bc
    out dx,al

    ; 94 - system control register (bit if zero means setup, one means run)
    ; bit 7: grp1: diskette controller, parallel port, memory in setup mode
    ; bit 6: grp2: serial controller, interrupt level
    ; bit 0-5: reserved. Some of these are read/write, others read back
    ; as '1' always

    ; 96 - Adapter enable/setup register
    ; bit 7: when set to 1, this is a channel reset signal
    ; bit 4-6: reserved, do not use
    ; bit 3: 1=setup adapters, 0=enable registers
    ; bit 2-0: channel select

    mov dx,0x94                 ; Port 94 is the system control register
    mov al, 0x00                ; Write 0x00
    out dx, al
    out 0x4f,al                 ; Dummy port, just for the delay
    in al,dx                    ; Read, hope it matches
    rcall bin2beep              ; Beep it out

    mov dx,0x94
    mov al, 0xff                ; Write 0xFF this time
    out dx, al
    out 0x4f,al
    in al,dx
    rcall bin2beep

    jmp mainloop
    ; Safety halt
    hlt

bin2beep:
; Beeps out the contents of AL.
; Trashes AX, BX, CX, DX
    mov ah, al                  ; Save off the input byte to AH
    xor cx,cx
    mov dh, 8
bitloop:
    ; Low pitch = 0, high pitch = 1
    mov dl, 0x64                ; Low pitch
    rol ah, 1                   ; Get the next bit (MSB first)
    jnc not_a_one
    mov dl, 0x32                ; High pitch
not_a_one:

    ; Do the actual beep now
beep:
    mov al,0x0
    mov bx, 0x300               ; Number of cycles
lp1:
    xor al,0x2                  ; Toggle speaker enable bit
    out 0x61,al                 ; Keyboard controller port
    mov cl,dl                   ; Delay/pitch
lp2:
    loop lp2
    sub bx, 1                   ; Next cycle
    jnz lp1

    ; Delay between beeps
    mov cx,0x6400
lp3:
    loop lp3

    sub dh, 1
    jnz bitloop         ; Do the next bit

    ; Add another delay so we can differentiate this from the next byte
    mov cx,0xfd00 ; 100
lpdelay:
    loop lpdelay

    ret


    section reset start=0xffff0
    ; This is just a long jump to 0xf000:0000. nasm doesn't seem to support
    ; long jumps with the binary output format which I need since this is
    ; going into a ROM.
    db 0xea, 0x00, 0x00, 0x00, 0xf0
    db "09/03/21", 0x00
    ; Checksum?
    db 0x00, 0x00
