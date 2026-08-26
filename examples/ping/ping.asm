; ============================================================================
; PING.EXE - ping a host through the configured UNET backend.
;
; Usage: PING <host>
;
; This is a "compact mode" example: it defines UNETLD_STATE_BASE right
; after its own BSS, so neither its own scratch nor UNETLD's ~315 bytes of
; state add anything to the EXE file - both live in memory the program
; claims after loading, not in the image. See docs/UNETLD.md (or
; docs/UNETLDRU.md for the Russian version).
; ============================================================================

EXE_HEADER_SIZE          EQU 0200h
EXE_LOAD_ADDRESS         EQU 08100h

; Compact-mode data/stack area: a fixed address well above where this
; program's code (plus unetld.asm and libman.asm) can plausibly reach, and
; well below the 0xC000 boundary shared with every window-1/2 DLL. Nothing
; here is emitted into the EXE file - CODE_END is asserted against it below
; as a safety net in case that ever stops being true.
WORK_BASE                EQU 0B000h

EXIT_OK                  EQU 0
EXIT_DLL                 EQU 2
EXIT_NETWORK              EQU 3
EXIT_CONFIG               EQU 4

PING_COUNT                EQU 4
PING_TIMEOUT_MS            EQU 4000

        DEVICE  NOSLOT64K

        INCLUDE "dss.inc"
        INCLUDE "unet.inc"

        DEFINE  LIBMAN_MAX_LIBS 1
        DEFINE  LIBMAN_DIAGNOSTICS
        DEFINE  LIBMAN_NO_LEGACY_API

        MODULE  PING

        INCLUDE "exehead.asm"

        LD      SP, STACK_TOP
        LD      (ARGS_PTR), IX          ; DSS passes the argument buffer pointer
                                        ; in IX at entry - save it before any
                                        ; call that might not preserve IX

        CALL    UNETLD.RESET           ; mandatory: UNETLD_STATE_BASE memory
                                        ; is not pre-zeroed like the image is

        LD      HL, MSG_BANNER
        CALL    PUTS_LN

        LD      IX, (ARGS_PTR)
        LD      A, (IX+0)
        OR      A
        JP      Z, USAGE

        LD      HL, (ARGS_PTR)
        INC     HL                      ; HL -> argument text (ASCIIZ)
        LD      DE, HOST_BUF
        LD      B, HOST_BUF_SIZE - 1
        CALL    ARG_NEXT
        JP      C, USAGE

        CALL    UNETLD.SELECT
        JP      C, ERR_SELECT

        LD      A, 1                    ; load into window 1
        CALL    UNETLD.LOAD
        JP      C, ERR_LOAD

        LD      DE, UNET_CAP_PING
        CALL    UNETLD.REQUIRE
        JP      C, ERR_NOCAP

        LD      A, UNET_OPT_CANCELKEYS  ; best effort: lets Esc/Ctrl+Z break
        LD      DE, 1                   ; out of a stuck PING wait
        LD      B, UNET_FN_SETOPT
        CALL    UNETLD.CALL

        CALL    UNETLD.NETSTART
        JP      C, ERR_NETSTART

        LD      HL, MSG_PINGING
        CALL    PUTS
        LD      HL, HOST_BUF
        CALL    PUTS_LN

        LD      A, PING_COUNT
        LD      (PINGS_LEFT), A         ; a register loop counter would not
                                        ; survive UNETLD.CALL: libman's
                                        ; l_call repurposes both BC and HL
PING_LOOP:
        LD      DE, HOST_BUF
        LD      IY, PING_TIMEOUT_MS
        LD      B, UNET_FN_PING
        CALL    UNETLD.CALL
        JR      C, .DISPATCH_FAIL

        CP      NERR_OK
        JR      Z, .OK
        CP      NERR_CANCEL
        JP      Z, DONE
        CP      NERR_TIMEOUT
        JR      Z, .TIMEOUT
        CP      NERR_DNS
        JR      Z, .DNS

        LD      HL, MSG_PING_FAIL
        CALL    PUTS
        CALL    PUT_HEX8
        JR      CRLF_AND_NEXT
.TIMEOUT:
        LD      HL, MSG_PING_TIMEOUT
        CALL    PUTS
        JR      CRLF_AND_NEXT
.DNS:
        LD      HL, MSG_PING_DNS
        CALL    PUTS
        JR      CRLF_AND_NEXT
.OK:
        LD      HL, MSG_PING_TIME
        CALL    PUTS
        CALL    PUT_DEC16
        LD      HL, MSG_MS
        CALL    PUTS
        JR      CRLF_AND_NEXT
.DISPATCH_FAIL:
        LD      HL, MSG_PING_DISPATCH
        CALL    PUTS
CRLF_AND_NEXT:
        CALL    CRLF
        LD      A, (PINGS_LEFT)
        DEC     A
        LD      (PINGS_LEFT), A
        JR      NZ, PING_LOOP

        JP      DONE

USAGE:
        LD      HL, MSG_USAGE
        CALL    PUTS_LN
        LD      B, EXIT_CONFIG
        JP      FINISH

ERR_SELECT:
        CALL    PRINT_UNETLD_ERROR
        CALL    UNETLD.UNLOAD
        LD      B, EXIT_CONFIG
        JP      FINISH

ERR_LOAD:
        CALL    PRINT_UNETLD_ERROR
        CALL    UNETLD.UNLOAD
        LD      B, EXIT_DLL
        JP      FINISH

ERR_NOCAP:
        LD      HL, MSG_NO_PING_CAP
        CALL    PUTS_LN
        CALL    UNETLD.UNLOAD
        LD      B, EXIT_NETWORK
        JP      FINISH

ERR_NETSTART:
        CALL    PRINT_UNETLD_ERROR
        CALL    UNETLD.UNLOAD
        LD      B, EXIT_NETWORK
        JP      FINISH

DONE:
        CALL    UNETLD.UNLOAD
        LD      B, EXIT_OK
FINISH:
        LD      C, DSS_EXIT
        RST     DSS

        INCLUDE "conutil.asm"

MSG_BANNER:         DB      "PING - UNET ping tool", 13, 10, 0
MSG_USAGE:           DB      "Usage: PING <host>", 0
MSG_PINGING:         DB      "Pinging ", 0
MSG_PING_TIME:       DB      "  time=", 0
MSG_MS:              DB      " ms", 0
MSG_PING_FAIL:       DB      "  failed, status=0x", 0
MSG_PING_TIMEOUT:    DB      "  timeout", 0
MSG_PING_DNS:        DB      "  host name could not be resolved", 0
MSG_PING_DISPATCH:   DB      "  dispatch error (libman/DSS)", 0
MSG_NO_PING_CAP:     DB      "This backend does not support PING.", 0

        ENDMODULE

        DEFINE  UNETLD_STATE_BASE WORK_BASE

        INCLUDE "unetld.asm"
        INCLUDE "libman.asm"

; CODE_END must come after unetld.asm/libman.asm: their code is real,
; emitted bytes too (only UNETLD's *state* is address-only in this mode),
; so this is the true end of everything actually written to the image.
CODE_END        EQU $

; ---------------------------------------------------------------------------
; Compact-mode data placement: everything below is address arithmetic only,
; nothing here is emitted into the EXE file. HOST_BUF sits right after
; UNETLD's own state; the stack sits right after that.
; ---------------------------------------------------------------------------
        MODULE  PING

ARGS_PTR        EQU UNETLD.STATE_END    ; saved copy of the DSS argument pointer (2)
HOST_BUF        EQU ARGS_PTR + 2
HOST_BUF_SIZE   EQU 129                 ; UNET host strings are limited to 128 bytes + NUL
PINGS_LEFT      EQU HOST_BUF + HOST_BUF_SIZE   ; (1)
BSS_END         EQU PINGS_LEFT + 1

STACK_SIZE      EQU 0400h
STACK_TOP       EQU BSS_END + STACK_SIZE

        ASSERT  CODE_END <= WORK_BASE
        ASSERT  STACK_TOP <= 0C000h
        ENDMODULE

        END     PING.START
