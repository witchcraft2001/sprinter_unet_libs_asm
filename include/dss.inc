; ======================================================
; Minimal consumer-side DSS constants for unet_libs.
;
; This is deliberately NOT a merge of the sprinter_wifi/network and
; sprinter-rtl8019a copies of dss.inc: those two have diverged (e.g.
; DSS_KCLEAR vs DSS_K_CLEAR for the same function) and reconciling every
; name would create a much larger surface than unetld.asm and the examples
; actually need. This file defines only what this project uses. Consumers
; that already include a backend's own dss.inc may include this one too -
; the guard below is shared on purpose so whichever include lands first
; wins and the other becomes a no-op.
;
; Hard rules enforced by DSS itself (see the Sprinter manual, 04_dss/):
;   - SP must be inside 0x8000-0xBFFF for the duration of every RST #10.
;   - HL'/DE'/BC' are reserved by DSS/BIOS; never EXX around RST #10.
;   - ENV_GET takes no destination-capacity argument, so the value buffer
;     must always be a full 256 bytes.
; ======================================================

        IFNDEF  _DSS_INC
        DEFINE  _DSS_INC

DSS                     EQU 010h        ; RST entry point (C = function number)

DSS_WAITKEY             EQU 030h        ; blocking key read -> A
DSS_SCANKEY             EQU 031h        ; non-blocking key read -> A/CF
DSS_KCLEAR              EQU 035h        ; clear the keyboard buffer

DSS_EXIT                EQU 041h        ; B = exit code

DSS_ENVIRON             EQU 046h        ; environment variables, subfunction in B
ENV_GET                 EQU 001h        ;   HL="NAME",0  DE=256-byte value buf
                                        ;   A=0FFh found / A=0 not found, DE[0]=0
ENV_SET                 EQU 002h        ;   HL="NAME=VALUE",0 ("NAME=",0 deletes)

DSS_APPINFO             EQU 047h        ; application info, subfunction in B
APPINFO_PARAMS          EQU 000h        ;   HL=dest -> command-line text
APPINFO_EXE_HOMEDIR     EQU 001h        ;   HL=dest -> ASCIIZ dir of the running EXE

DSS_PUTCHAR             EQU 05Bh        ; A = character to print
DSS_PCHARS              EQU 05Ch        ; HL = ASCIIZ string to print

        ENDIF
