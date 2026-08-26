; ============================================================================
; NETINFO.EXE - smoke-test the configured UNET backend.
;
; Selects and loads the DLL named by NET, prints its capabilities and ABI,
; then walks every UNET_FN_GETINFO field and prints the ones the backend
; has a value for. Takes no arguments.
;
; This is the "simple mode" example: it just includes unetld.asm with no
; DEFINE beforehand, so UNETLD's ~315 bytes of state ride along inside the
; EXE image. See docs/UNETLD.md (or docs/UNETLDRU.md for the Russian
; version) for the alternative (compact) mode used by the other examples.
; ============================================================================

EXE_HEADER_SIZE         EQU 0200h
EXE_LOAD_ADDRESS        EQU 08100h

EXIT_OK                 EQU 0
EXIT_DLL                EQU 2
EXIT_NETWORK             EQU 3
EXIT_CONFIG              EQU 4

        DEVICE  NOSLOT64K

        INCLUDE "dss.inc"
        INCLUDE "unet.inc"

        DEFINE  LIBMAN_MAX_LIBS 1
        DEFINE  LIBMAN_DIAGNOSTICS
        DEFINE  LIBMAN_NO_LEGACY_API

        MODULE  NETINFO

        INCLUDE "exehead.asm"

        LD      SP, STACK_TOP

        LD      HL, MSG_BANNER
        CALL    PUTS_LN

        CALL    UNETLD.SELECT
        JP      C, ERR_SELECT

        LD      HL, MSG_SELECTED
        CALL    PUTS
        LD      HL, UNETLD.DLL_NAME
        CALL    PUTS_LN

        LD      A, 1                    ; load into window 1
        CALL    UNETLD.LOAD
        JP      C, ERR_LOAD

        LD      HL, MSG_DLL
        CALL    PUTS
        LD      HL, UNETLD.DLL_INFO + 16
        CALL    PUTS_LN

        ; SETOPT CANCELKEYS is a nicety: best-effort, not fatal here.
        LD      A, UNET_OPT_CANCELKEYS
        LD      DE, 1
        LD      B, UNET_FN_SETOPT
        CALL    UNETLD.CALL

        CALL    UNETLD.NETSTART
        JP      C, ERR_NETSTART

        LD      HL, MSG_CAPS
        CALL    PUTS
        LD      DE, (UNETLD.CAPS)
        LD      A, D
        CALL    PUT_HEX8
        LD      A, E
        CALL    PUT_HEX8
        CALL    CRLF
        CALL    PRINT_CAPS_LIST

        LD      HL, MSG_ABI
        CALL    PUTS
        LD      DE, (UNETLD.ABI)
        LD      A, D
        CALL    PUT_HEX8
        LD      A, E
        CALL    PUT_HEX8
        CALL    CRLF

        LD      HL, INFO_FIELDS
        CALL    PRINT_INFO_FIELDS

        CALL    UNETLD.UNLOAD
        LD      B, EXIT_OK
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

ERR_NETSTART:
        CALL    PRINT_UNETLD_ERROR
        CALL    UNETLD.UNLOAD
        LD      B, EXIT_NETWORK
        JP      FINISH

FINISH:
        LD      C, DSS_EXIT
        RST     DSS

; ---------------------------------------------------------------------------
; Print every capability bit set in UNETLD.CAPS, space-separated.
; ---------------------------------------------------------------------------
PRINT_CAPS_LIST:
        LD      HL, CAPS_BITS
.LOOP:
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        INC     HL
        LD      A, D
        OR      E
        JR      Z, .DONE
        LD      C, (HL)
        INC     HL
        LD      B, (HL)
        INC     HL
        PUSH    HL
        PUSH    BC

        LD      HL, (UNETLD.CAPS)
        LD      A, H
        AND     D
        LD      H, A
        LD      A, L
        AND     E
        LD      L, A
        LD      A, H
        OR      L
        JR      Z, .SKIP

        POP     HL
        CALL    PUTS
        LD      HL, MSG_SPACE
        CALL    PUTS
        JR      .NEXT
.SKIP:
        POP     HL
.NEXT:
        POP     HL
        JR      .LOOP
.DONE:
        JP      CRLF

; ---------------------------------------------------------------------------
; Walk {field id, label ptr} pairs (0FFh terminates), print "label: value"
; for every field the backend returns a non-empty string for.
; ---------------------------------------------------------------------------
PRINT_INFO_FIELDS:
.LOOP:
        LD      A, (HL)
        CP      0FFh
        RET     Z
        LD      C, A
        INC     HL
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        INC     HL
        PUSH    HL
        LD      (CUR_LABEL), DE

        LD      A, C
        LD      DE, INFO_BUF
        LD      IX, INFO_BUF_SIZE
        LD      B, UNET_FN_GETINFO
        CALL    UNETLD.CALL
        JR      C, .NEXT
        OR      A
        JR      NZ, .NEXT
        LD      A, (INFO_BUF)
        OR      A
        JR      Z, .NEXT

        LD      HL, (CUR_LABEL)
        CALL    PUTS
        LD      HL, MSG_COLON
        CALL    PUTS
        LD      HL, INFO_BUF
        CALL    PUTS_LN
.NEXT:
        POP     HL
        JR      .LOOP

        INCLUDE "conutil.asm"

MSG_BANNER:      DB      "NETINFO - UNET backend smoke test", 13, 10, 0
MSG_SELECTED:     DB      "NET selected: ", 0
MSG_DLL:          DB      "DLL loaded: ", 0
MSG_CAPS:         DB      "Capabilities: 0x", 0
MSG_ABI:          DB      "ABI version: 0x", 0
MSG_SPACE:        DB      " ", 0
MSG_COLON:        DB      ": ", 0

LIT_CAP_TCP:          DB      "TCP", 0
LIT_CAP_UDP:          DB      "UDP", 0
LIT_CAP_RESOLVE:      DB      "RESOLVE", 0
LIT_CAP_PING:         DB      "PING", 0
LIT_CAP_MULTICHAN:    DB      "MULTICHAN", 0
LIT_CAP_LISTEN:       DB      "LISTEN", 0
LIT_CAP_RAWETH:       DB      "RAWETH", 0
LIT_CAP_TRANSPARENT:  DB      "TRANSPARENT", 0
LIT_CAP_RXFLOW:       DB      "RXFLOW", 0
LIT_CAP_ASYNCSEND:    DB      "ASYNCSEND", 0

CAPS_BITS:
        DW      UNET_CAP_TCP,         LIT_CAP_TCP
        DW      UNET_CAP_UDP,         LIT_CAP_UDP
        DW      UNET_CAP_RESOLVE,     LIT_CAP_RESOLVE
        DW      UNET_CAP_PING,        LIT_CAP_PING
        DW      UNET_CAP_MULTICHAN,   LIT_CAP_MULTICHAN
        DW      UNET_CAP_LISTEN,      LIT_CAP_LISTEN
        DW      UNET_CAP_RAWETH,      LIT_CAP_RAWETH
        DW      UNET_CAP_TRANSPARENT, LIT_CAP_TRANSPARENT
        DW      UNET_CAP_RXFLOW,      LIT_CAP_RXFLOW
        DW      UNET_CAP_ASYNCSEND,   LIT_CAP_ASYNCSEND
        DW      0

LIT_FLD_BACKEND:  DB      "Backend", 0
LIT_FLD_IP:       DB      "IP", 0
LIT_FLD_MASK:     DB      "Netmask", 0
LIT_FLD_GW:       DB      "Gateway", 0
LIT_FLD_MAC:      DB      "MAC", 0
LIT_FLD_DNS1:     DB      "DNS1", 0
LIT_FLD_DNS2:     DB      "DNS2", 0
LIT_FLD_IPSRC:    DB      "IP source", 0
LIT_FLD_SSID:     DB      "SSID", 0
LIT_FLD_BAUD:     DB      "Baud", 0
LIT_FLD_NTP:      DB      "NTP", 0
LIT_FLD_TZ:       DB      "TZ", 0
LIT_FLD_HW:       DB      "Hardware", 0

INFO_FIELDS:
        DB      UNET_IF_BACKEND
        DW      LIT_FLD_BACKEND
        DB      UNET_IF_IP
        DW      LIT_FLD_IP
        DB      UNET_IF_MASK
        DW      LIT_FLD_MASK
        DB      UNET_IF_GW
        DW      LIT_FLD_GW
        DB      UNET_IF_MAC
        DW      LIT_FLD_MAC
        DB      UNET_IF_DNS1
        DW      LIT_FLD_DNS1
        DB      UNET_IF_DNS2
        DW      LIT_FLD_DNS2
        DB      UNET_IF_IPSRC
        DW      LIT_FLD_IPSRC
        DB      UNET_IF_SSID
        DW      LIT_FLD_SSID
        DB      UNET_IF_BAUD
        DW      LIT_FLD_BAUD
        DB      UNET_IF_NTP
        DW      LIT_FLD_NTP
        DB      UNET_IF_TZ
        DW      LIT_FLD_TZ
        DB      UNET_IF_HW
        DW      LIT_FLD_HW
        DB      0FFh

        ENDMODULE

; UNETLD's ~315 bytes of state are emitted here, inside the image (simple
; mode - no UNETLD_STATE_BASE defined above).
        INCLUDE "unetld.asm"
        INCLUDE "libman.asm"

        MODULE  NETINFO

BSS_BASE        EQU $
CUR_LABEL       EQU BSS_BASE
INFO_BUF        EQU CUR_LABEL + 2
INFO_BUF_SIZE   EQU 40
BSS_END         EQU INFO_BUF + INFO_BUF_SIZE

        DS      BSS_END - BSS_BASE, 0

STACK_SIZE      EQU 0400h
STACK_BOTTOM    EQU $
STACK_TOP       EQU STACK_BOTTOM + STACK_SIZE

        DS      STACK_SIZE, 0
IMAGE_END       EQU $

        ASSERT  BSS_BASE >= 08100h
        ASSERT  IMAGE_END < 0C000h
        ASSERT  STACK_TOP <= 0C000h

        ENDMODULE

        END     NETINFO.START
