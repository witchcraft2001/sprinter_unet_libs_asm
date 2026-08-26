; ============================================================================
; Console helpers shared by the examples: text output, decimal/hex printing,
; command-line argument splitting and a UNETLD error printer.
;
; Include this inside the example's own MODULE (like exehead.asm) - each
; example gets its own private copy, the same way weatherc.asm includes
; text_ui.asm. Requires "dss.inc" and "unetld.asm" to already be visible.
; ============================================================================

PUTS:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      C, DSS_PCHARS
        RST     DSS
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET

PUTS_LN:
        CALL    PUTS
CRLF:
        LD      HL, MSG_CRLF
        JR      PUTS

PUT_CHAR:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      C, DSS_PUTCHAR
        RST     DSS
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET

PUT_HEX16:
        LD      A, D
        CALL    PUT_HEX8
        LD      A, E
PUT_HEX8:
        PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    PUT_NIBBLE
        POP     AF
PUT_NIBBLE:
        AND     0Fh
        ADD     A, 090h
        DAA
        ADC     A, 040h
        DAA
        JP      PUT_CHAR

; Print DE as an unsigned decimal number, no leading zeros (0 itself prints
; as a single "0"). Used for ping RTT and byte counts.
PUT_DEC16:
        PUSH    DE
        POP     HL
        LD      B, 0                    ; B=0: still suppressing leading zeros
        LD      DE, 10000
        CALL    .DIGIT
        LD      DE, 1000
        CALL    .DIGIT
        LD      DE, 100
        CALL    .DIGIT
        LD      DE, 10
        CALL    .DIGIT
        LD      A, L
        ADD     A, '0'
        JP      PUT_CHAR
.DIGIT:
        LD      C, 0
.SUB_LOOP:
        OR      A
        SBC     HL, DE
        JR      C, .RESTORE
        INC     C
        JR      .SUB_LOOP
.RESTORE:
        ADD     HL, DE
        LD      A, C
        OR      A
        JR      NZ, .PRINT
        LD      A, B
        OR      A
        RET     Z                       ; leading zero, nothing printed yet
        LD      A, '0'
        JP      PUT_CHAR
.PRINT:
        LD      B, 1                    ; a non-zero digit has now been printed
        LD      A, C
        ADD     A, '0'
        JP      PUT_CHAR

; Split the next whitespace-separated token out of an ASCIIZ scan buffer.
; In:  HL = scan cursor (start it at the DSS argument text, IX+1)
;      DE = destination buffer
;      B  = destination capacity, excluding the terminating NUL
; Out: CF=0, HL advanced past the token and one trailing space, DE holds
;      the ASCIIZ token (truncated silently if longer than B).
;      CF=1, no token remained (HL was already at the terminating NUL).
; Clobbers AF/B/HL/DE(advanced).
ARG_NEXT:
.SKIP:
        LD      A, (HL)
        OR      A
        JR      Z, .EMPTY
        CP      ' '
        JR      NZ, .COPY
        INC     HL
        JR      .SKIP
.EMPTY:
        SCF
        RET
.COPY:
        LD      A, (HL)
        OR      A
        JR      Z, .DONE
        CP      ' '
        JR      Z, .SEP
        LD      A, B
        OR      A
        JR      Z, .SKIP_CHAR
        LD      A, (HL)
        LD      (DE), A
        INC     DE
        DEC     B
.SKIP_CHAR:
        INC     HL
        JR      .COPY
.SEP:
        INC     HL
.DONE:
        XOR     A
        LD      (DE), A
        OR      A
        RET

; Compare ASCIIZ HL and DE. Z when equal. (A private copy - UNETLD.STREQ is
; an internal implementation detail of the selector, not shared API.)
STREQ:
        LD      A, (DE)
        LD      C, A
        LD      A, (HL)
        CP      C
        RET     NZ
        AND     A
        RET     Z
        INC     HL
        INC     DE
        JR      STREQ

; Copy ASCIIZ HL to DE, including the terminating NUL. (A private copy -
; UNETLD.STRCPY is an internal implementation detail of the selector.)
STRCPY:
        LD      A, (HL)
        LD      (DE), A
        OR      A
        RET     Z
        INC     HL
        INC     DE
        JR      STRCPY

; Report the current UNETLD.ERROR in a human-readable line, with the extra
; libman/UNET diagnostic fields for the error codes that carry one.
PRINT_UNETLD_ERROR:
        LD      A, (UNETLD.ERROR)
        CP      UNETLD_E_NOENV
        JR      Z, .NOENV
        CP      UNETLD_E_BADVALUE
        JR      Z, .BADVALUE
        CP      UNETLD_E_LOAD
        JR      Z, .LOAD
        CP      UNETLD_E_INFO
        JR      Z, .INFO
        CP      UNETLD_E_NAME
        JR      Z, .NAME
        CP      UNETLD_E_CALL
        JR      Z, .CALL
        CP      UNETLD_E_ABI
        JR      Z, .ABI
        CP      UNETLD_E_STATUS
        JP      Z, .STATUS
        CP      UNETLD_E_NETINIT
        JP      Z, .NETINIT
        LD      HL, MSG_ERR_UNKNOWN
        JP      PUTS_LN

.NOENV:
        ; NET_TAG is empty at this point (SELECT failed before resolving it),
        ; so a per-backend hint is impossible - name both bring-up tools.
        LD      HL, MSG_ERR_NOENV
        JP      PUTS_LN
.BADVALUE:
        LD      HL, MSG_ERR_BADVALUE
        CALL    PUTS
        LD      HL, UNETLD.ENV_VALUE
        JP      PUTS_LN
.LOAD:
        LD      HL, MSG_ERR_LOAD
        CALL    PUTS
        LD      HL, UNETLD.DLL_NAME
        CALL    PUTS_LN
        LD      HL, MSG_REASON
        CALL    PUTS
        LD      A, (LIBMAN.l_reason)
        CALL    PUT_HEX8
        LD      HL, MSG_DSS_CODE
        CALL    PUTS
        LD      A, (LIBMAN.l_dss_error)
        CALL    PUT_HEX8
        LD      HL, MSG_LOAD_STAGE
        CALL    PUTS
        LD      A, (LIBMAN.l_load_stage)
        CALL    PUT_HEX8
        LD      HL, MSG_INIT_STATUS
        CALL    PUTS
        LD      A, (LIBMAN.l_init_status)
        CALL    PUT_HEX8
        JP      CRLF
.INFO:
        LD      HL, MSG_ERR_INFO
        JP      PUTS_LN
.NAME:
        LD      HL, MSG_ERR_NAME
        CALL    PUTS
        LD      HL, UNETLD.DLL_INFO + 16
        JP      PUTS_LN
.CALL:
        LD      HL, MSG_ERR_CALL
        JP      PUTS_LN
.ABI:
        LD      HL, MSG_ERR_ABI
        CALL    PUTS
        LD      A, (UNETLD.ABI + 1)
        CALL    PUT_HEX8
        JP      CRLF
.STATUS:
        LD      HL, MSG_ERR_STATUS
        CALL    PUTS
        LD      A, (UNETLD.LAST_STATUS)
        CALL    PUT_HEX8
        CALL    CRLF
        JP      PRINT_BRINGUP_HINT
.NETINIT:
        LD      HL, MSG_ERR_NETINIT
        CALL    PUTS
        LD      A, (UNETLD.LAST_STATUS)
        CALL    PUT_HEX8
        CALL    CRLF
        JP      PRINT_BRINGUP_HINT

; Per-backend bring-up hint, keyed off UNETLD.NET_TAG.
PRINT_BRINGUP_HINT:
        LD      HL, UNETLD.NET_TAG
        LD      DE, LIT_TAG_ESP
        CALL    STREQ
        JR      Z, .ESP
        LD      HL, UNETLD.NET_TAG
        LD      DE, LIT_TAG_RTL
        CALL    STREQ
        JR      Z, .RTL
        LD      HL, MSG_HINT_GENERIC
        JP      PUTS_LN
.ESP:
        LD      HL, MSG_HINT_ESP
        JP      PUTS_LN
.RTL:
        LD      HL, MSG_HINT_RTL
        JP      PUTS_LN

LIT_TAG_ESP:            DB      "ESP", 0
LIT_TAG_RTL:             DB      "RTL", 0

MSG_CRLF:                DB      13, 10, 0
MSG_ERR_UNKNOWN:         DB      "Unknown UNETLD error", 13, 10, 0
MSG_ERR_NOENV:           DB      "NET is not set. Run NETUP (WiFi) or "
                         DB      "NETCFG -i + IFUP (RTL) first.", 13, 10, 0
MSG_ERR_BADVALUE:        DB      "NET has an invalid value: ", 0
MSG_ERR_LOAD:            DB      "Could not load ", 0
MSG_ERR_INFO:            DB      "libman l_info failed.", 13, 10, 0
MSG_ERR_NAME:            DB      "DLL name mismatch, found: ", 0
MSG_ERR_CALL:            DB      "UNET dispatch failed (libman/DSS error).", 13, 10, 0
MSG_ERR_ABI:             DB      "Unsupported UNET ABI major version: ", 0
MSG_ERR_STATUS:          DB      "Unexpected network status: ", 0
MSG_ERR_NETINIT:         DB      "NETINIT failed, status: ", 0
MSG_REASON:               DB      " reason=", 0
MSG_DSS_CODE:             DB      " dss=", 0
MSG_LOAD_STAGE:           DB      " stage=", 0
MSG_INIT_STATUS:          DB      " init=", 0
MSG_HINT_ESP:             DB      "Run NETUP to bring the WiFi link up first.", 13, 10, 0
MSG_HINT_RTL:             DB      "Run NETCFG -i and IFUP to bring the RTL link up first.", 13, 10, 0
MSG_HINT_GENERIC:         DB      "Run this backend's bring-up tool before retrying.", 13, 10, 0
