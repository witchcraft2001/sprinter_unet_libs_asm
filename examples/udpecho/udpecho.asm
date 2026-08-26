; ============================================================================
; UDPECHO.EXE - send one UDP datagram through the configured UNET backend
; and print whatever comes back.
;
; Usage: UDPECHO <host> <port> [text]     (text defaults to a fixed message)
; Pair with tools/udp_echo.py running on a host reachable from the Sprinter.
;
; Compact-mode example (see docs/UNETLD.md, or docs/UNETLDRU.md for the
; Russian version): UNETLD's state and this program's own buffers both
; live in a fixed work area above the code, never in the EXE image.
; ============================================================================

EXE_HEADER_SIZE          EQU 0200h
EXE_LOAD_ADDRESS         EQU 08100h

; See ping.asm for why this is a fixed constant rather than derived from
; the assembled code size.
WORK_BASE                EQU 0B000h

EXIT_OK                  EQU 0
EXIT_DLL                 EQU 2
EXIT_NETWORK              EQU 3
EXIT_CONFIG               EQU 4
EXIT_TRANSPORT            EQU 5

RECV_TIMEOUT_MS            EQU 3000

        DEVICE  NOSLOT64K

        INCLUDE "dss.inc"
        INCLUDE "unet.inc"

        DEFINE  LIBMAN_MAX_LIBS 1
        DEFINE  LIBMAN_DIAGNOSTICS
        DEFINE  LIBMAN_NO_LEGACY_API

        MODULE  UDPECHO

        INCLUDE "exehead.asm"

        LD      SP, STACK_TOP
        LD      (ARGS_PTR), IX          ; DSS passes the argument pointer in IX

        CALL    UNETLD.RESET            ; mandatory: WORK_BASE memory is not
                                        ; pre-zeroed like the image is

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
        JP      C, USAGE                ; host is mandatory

        LD      DE, PORT_BUF
        LD      B, PORT_BUF_SIZE - 1
        CALL    ARG_NEXT
        JP      C, USAGE                ; port is mandatory

        PUSH    HL                      ; HL is the scan cursor; TEXT_BUF's
                                        ; default fill below needs HL too
        LD      HL, LIT_DEFAULT_TEXT
        LD      DE, TEXT_BUF
        CALL    STRCPY
        POP     HL

        LD      DE, TEXT_BUF
        LD      B, TEXT_BUF_SIZE - 1
        CALL    ARG_NEXT                ; CF=1 here just means "use default text"

        LD      HL, TEXT_BUF
        CALL    STRLEN
        LD      (TEXT_LEN), HL

        CALL    UNETLD.SELECT
        JP      C, ERR_SELECT

        LD      A, 1                    ; load into window 1
        CALL    UNETLD.LOAD
        JP      C, ERR_LOAD

        LD      DE, UNET_CAP_UDP
        CALL    UNETLD.REQUIRE
        JP      C, ERR_NOCAP

        LD      A, UNET_OPT_CANCELKEYS
        LD      DE, 1
        LD      B, UNET_FN_SETOPT
        CALL    UNETLD.CALL

        CALL    UNETLD.NETSTART
        JP      C, ERR_NETSTART

        LD      HL, MSG_OPENING
        CALL    PUTS
        LD      HL, HOST_BUF
        CALL    PUTS
        LD      HL, MSG_COLON
        CALL    PUTS
        LD      HL, PORT_BUF
        CALL    PUTS_LN

        XOR     A                       ; channel 0
        LD      DE, HOST_BUF
        LD      IX, PORT_BUF
        LD      IY, 0                   ; any local port
        LD      B, UNET_FN_UDPOPEN
        CALL    UNETLD.CALL
        JP      C, ERR_CALL
        OR      A
        JP      NZ, ERR_UDPOPEN

        LD      HL, MSG_SENDING
        CALL    PUTS
        LD      HL, TEXT_BUF
        CALL    PUTS_LN

        XOR     A                       ; channel 0
        LD      DE, TEXT_BUF
        LD      IX, (TEXT_LEN)
        LD      B, UNET_FN_SEND
        CALL    UNETLD.CALL
        JP      C, ERR_CALL
        OR      A
        JP      NZ, ERR_SEND

        LD      HL, MSG_WAITING
        CALL    PUTS_LN

        XOR     A                       ; channel 0
        LD      DE, RECV_BUF
        LD      IX, RECV_BUF_SIZE - 1   ; leave room for the NUL we add below
        LD      IY, RECV_TIMEOUT_MS
        LD      B, UNET_FN_RECV
        CALL    UNETLD.CALL
        JP      C, ERR_CALL
        CP      NERR_CANCEL
        JR      Z, DONE
        OR      A
        JP      NZ, ERR_RECV

        LD      A, D
        OR      E
        JR      Z, TIMED_OUT

        LD      HL, RECV_BUF
        ADD     HL, DE
        LD      (HL), 0
        LD      HL, MSG_REPLY
        CALL    PUTS
        LD      HL, RECV_BUF
        CALL    PUTS_LN
        JR      DONE

TIMED_OUT:
        LD      HL, MSG_TIMEOUT
        CALL    PUTS_LN

DONE:
        XOR     A                       ; channel 0
        LD      B, UNET_FN_CLOSE
        CALL    UNETLD.CALL             ; best effort

        CALL    UNETLD.UNLOAD
        LD      B, EXIT_OK
        JP      FINISH

; HL = ASCIIZ string. Out: HL = its length (excluding the NUL).
STRLEN:
        PUSH    HL
        XOR     A
.LOOP:
        CP      (HL)
        JR      Z, .DONE
        INC     HL
        JR      .LOOP
.DONE:
        POP     DE
        OR      A
        SBC     HL, DE
        RET

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
        LD      HL, MSG_NO_UDP_CAP
        CALL    PUTS_LN
        CALL    UNETLD.UNLOAD
        LD      B, EXIT_NETWORK
        JP      FINISH

ERR_NETSTART:
        CALL    PRINT_UNETLD_ERROR
        CALL    UNETLD.UNLOAD
        LD      B, EXIT_NETWORK
        JP      FINISH

ERR_CALL:
        LD      HL, MSG_DISPATCH_FAIL
        CALL    PUTS_LN
        CALL    UNETLD.UNLOAD
        LD      B, EXIT_DLL
        JP      FINISH

ERR_UDPOPEN:
        LD      HL, MSG_UDPOPEN_FAIL
        CALL    PUTS
        CALL    PUT_HEX8
        CALL    CRLF
        CALL    UNETLD.UNLOAD
        LD      B, EXIT_TRANSPORT
        JP      FINISH

ERR_SEND:
        LD      HL, MSG_SEND_FAIL
        CALL    PUTS
        CALL    PUT_HEX8
        CALL    CRLF
        XOR     A
        LD      B, UNET_FN_CLOSE
        CALL    UNETLD.CALL
        CALL    UNETLD.UNLOAD
        LD      B, EXIT_TRANSPORT
        JP      FINISH

ERR_RECV:
        LD      HL, MSG_RECV_FAIL
        CALL    PUTS
        CALL    PUT_HEX8
        CALL    CRLF
        XOR     A
        LD      B, UNET_FN_CLOSE
        CALL    UNETLD.CALL
        CALL    UNETLD.UNLOAD
        LD      B, EXIT_TRANSPORT
FINISH:
        LD      C, DSS_EXIT
        RST     DSS

        INCLUDE "conutil.asm"

MSG_BANNER:          DB      "UDPECHO - UNET UDP round-trip tool", 13, 10, 0
MSG_USAGE:            DB      "Usage: UDPECHO <host> <port> [text]", 0
MSG_OPENING:          DB      "Opening UDP to ", 0
MSG_COLON:            DB      ":", 0
MSG_SENDING:          DB      "Sending: ", 0
MSG_WAITING:          DB      "Waiting for a reply...", 0
MSG_REPLY:            DB      "Reply: ", 0
MSG_TIMEOUT:          DB      "No reply (timed out).", 0
MSG_UDPOPEN_FAIL:     DB      "UDPOPEN failed, status=0x", 0
MSG_SEND_FAIL:        DB      "SEND failed, status=0x", 0
MSG_RECV_FAIL:        DB      "RECV failed, status=0x", 0
MSG_DISPATCH_FAIL:    DB      "UNET dispatch failed (libman/DSS error).", 0
MSG_NO_UDP_CAP:       DB      "This backend does not support UDP.", 0

LIT_DEFAULT_TEXT:     DB      "PING FROM SPRINTER", 0

        ENDMODULE

        DEFINE  UNETLD_STATE_BASE WORK_BASE

        INCLUDE "unetld.asm"
        INCLUDE "libman.asm"

; See ping.asm for why this comes after unetld.asm/libman.asm.
CODE_END        EQU $

; ---------------------------------------------------------------------------
; Compact-mode data placement: address arithmetic only, nothing here is
; emitted into the EXE file.
; ---------------------------------------------------------------------------
        MODULE  UDPECHO

ARGS_PTR        EQU UNETLD.STATE_END    ; saved DSS argument pointer (2)
HOST_BUF        EQU ARGS_PTR + 2
HOST_BUF_SIZE   EQU 129                 ; UNET host strings limited to 128 bytes + NUL
PORT_BUF        EQU HOST_BUF + HOST_BUF_SIZE
PORT_BUF_SIZE   EQU 16                  ; UNET port strings limited to 15 bytes + NUL
TEXT_BUF        EQU PORT_BUF + PORT_BUF_SIZE
TEXT_BUF_SIZE   EQU 256
TEXT_LEN        EQU TEXT_BUF + TEXT_BUF_SIZE   ; (2)
RECV_BUF        EQU TEXT_LEN + 2
RECV_BUF_SIZE   EQU 513                 ; +1 spare byte for the printing NUL
BSS_END         EQU RECV_BUF + RECV_BUF_SIZE

STACK_SIZE      EQU 0400h
STACK_TOP       EQU BSS_END + STACK_SIZE

        ASSERT  CODE_END <= WORK_BASE
        ASSERT  STACK_TOP <= 0C000h
        ENDMODULE

        END     UDPECHO.START
