; ============================================================================
; HTTPGET.EXE - fetch a page over plain HTTP through the configured UNET
; backend and dump the response to the console.
;
; Usage: HTTPGET <host> [port]     (port defaults to 80, e.g. info.cern.ch)
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

RECV_TIMEOUT_MS            EQU 1000
RECV_TOTAL_CAP              EQU 8192

        DEVICE  NOSLOT64K

        INCLUDE "dss.inc"
        INCLUDE "unet.inc"

        DEFINE  LIBMAN_MAX_LIBS 1
        DEFINE  LIBMAN_DIAGNOSTICS
        DEFINE  LIBMAN_NO_LEGACY_API

        MODULE  HTTPGET

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

        PUSH    HL                      ; HL is the scan cursor ARG_NEXT
                                        ; threads across calls - STRCPY below
                                        ; needs HL too, so save/restore it
        LD      HL, LIT_DEFAULT_PORT
        LD      DE, PORT_BUF
        CALL    STRCPY                  ; pre-fill the default before the
                                        ; optional port argument may override it
        POP     HL

        LD      DE, PORT_BUF
        LD      B, PORT_BUF_SIZE - 1
        CALL    ARG_NEXT                ; CF=1 here just means "use default 80"

        CALL    BUILD_REQUEST

        CALL    UNETLD.SELECT
        JP      C, ERR_SELECT

        LD      A, 1                    ; load into window 1
        CALL    UNETLD.LOAD
        JP      C, ERR_LOAD

        LD      DE, UNET_CAP_TCP
        CALL    UNETLD.REQUIRE
        JP      C, ERR_NOCAP

        LD      A, UNET_OPT_CANCELKEYS
        LD      DE, 1
        LD      B, UNET_FN_SETOPT
        CALL    UNETLD.CALL

        CALL    UNETLD.NETSTART
        JP      C, ERR_NETSTART

        LD      HL, MSG_CONNECTING
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
        LD      B, UNET_FN_CONNECT
        CALL    UNETLD.CALL
        JP      C, ERR_CALL
        OR      A
        JP      NZ, ERR_CONNECT

        LD      HL, (REQUEST_LEN)
        LD      (SEND_REMAIN), HL
        LD      HL, REQUEST_BUF
        LD      (SEND_PTR), HL
SEND_LOOP:
        LD      HL, (SEND_REMAIN)
        LD      A, H
        OR      L
        JR      Z, SEND_DONE
        XOR     A                       ; channel 0
        LD      DE, (SEND_PTR)
        LD      IX, (SEND_REMAIN)
        LD      B, UNET_FN_SEND
        CALL    UNETLD.CALL
        JP      C, ERR_CALL
        OR      A
        JP      NZ, ERR_SEND

        LD      HL, (SEND_PTR)
        ADD     HL, DE
        LD      (SEND_PTR), HL
        LD      HL, (SEND_REMAIN)
        OR      A
        SBC     HL, DE
        LD      (SEND_REMAIN), HL
        JR      SEND_LOOP
SEND_DONE:

        LD      HL, 0
        LD      (TOTAL_RECV), HL
RECV_LOOP:
        XOR     A                       ; channel 0
        LD      DE, RECV_BUF
        LD      IX, RECV_BUF_SIZE - 1   ; leave room for the NUL we add below
        LD      IY, RECV_TIMEOUT_MS
        LD      B, UNET_FN_RECV
        CALL    UNETLD.CALL
        JP      C, ERR_CALL

        CP      NERR_CLOSED
        JR      Z, RECV_PRINT_AND_DONE
        CP      NERR_CANCEL
        JR      Z, RECV_DONE
        OR      A
        JP      NZ, ERR_RECV

        LD      A, D
        OR      E
        JR      Z, RECV_LOOP            ; idle this round, keep waiting

        CALL    PRINT_CHUNK_FLOW

        LD      HL, (TOTAL_RECV)
        ADD     HL, DE
        LD      (TOTAL_RECV), HL
        LD      BC, RECV_TOTAL_CAP
        OR      A
        SBC     HL, BC
        JR      NC, RECV_CAP_HIT
        JR      RECV_LOOP

RECV_PRINT_AND_DONE:
        LD      A, D
        OR      E
        JR      Z, RECV_DONE
        CALL    PRINT_RECV_CHUNK
        JR      RECV_DONE

RECV_CAP_HIT:
        LD      HL, MSG_TRUNCATED
        CALL    PUTS_LN

RECV_DONE:
        CALL    CRLF
        XOR     A                       ; channel 0
        LD      B, UNET_FN_CLOSE
        CALL    UNETLD.CALL             ; best effort

        CALL    UNETLD.UNLOAD
        LD      B, EXIT_OK
        JP      FINISH

; DE = byte count in RECV_BUF (0 < DE <= RECV_BUF_SIZE-1). NUL-terminates
; and prints via PUTS - safe because IX was capped one byte short above.
PRINT_RECV_CHUNK:
        PUSH    DE
        LD      HL, RECV_BUF
        ADD     HL, DE
        LD      (HL), 0
        LD      HL, RECV_BUF
        CALL    PUTS
        POP     DE
        RET

; PRINT_RECV_CHUNK wrapped in RXPAUSE/RXRESUME when the backend asks for it
; (CAP_RXFLOW): DSS console output is slow enough for the ESP UART to overrun
; while we print, unless RTS is dropped around the printing. This is the
; documented flow-control pattern for streaming consumers. Preserves DE.
PRINT_CHUNK_FLOW:
        CALL    RXFLOW_PAUSE
        CALL    PRINT_RECV_CHUNK
        ; fall through into resume, then return
RXFLOW_RESUME:
        LD      A, (UNETLD.CAPS + 1)
        AND     HIGH UNET_CAP_RXFLOW
        RET     Z
        PUSH    DE
        LD      B, UNET_FN_RXRESUME
        CALL    UNETLD.CALL             ; best effort
        POP     DE
        RET

RXFLOW_PAUSE:
        LD      A, (UNETLD.CAPS + 1)
        AND     HIGH UNET_CAP_RXFLOW
        RET     Z
        PUSH    DE
        LD      B, UNET_FN_RXPAUSE
        CALL    UNETLD.CALL             ; best effort
        POP     DE
        RET

; Build "GET / HTTP/1.0\r\nHost: <host>\r\nConnection: close\r\n\r\n" into
; REQUEST_BUF and record its length in REQUEST_LEN (not NUL-delimited: SEND
; needs an exact byte count, and this request can legitimately be long).
BUILD_REQUEST:
        LD      DE, REQUEST_BUF
        LD      HL, LIT_REQ_HEAD
        CALL    APPEND
        LD      HL, HOST_BUF
        CALL    APPEND
        LD      HL, LIT_REQ_TAIL
        CALL    APPEND
        LD      H, D
        LD      L, E
        LD      DE, REQUEST_BUF
        OR      A
        SBC     HL, DE
        LD      (REQUEST_LEN), HL
        RET

; Copy ASCIIZ HL onto the cursor in DE (advanced past the copied text, NUL
; excluded so further APPEND calls can continue the same buffer).
APPEND:
        LD      A, (HL)
        OR      A
        RET     Z
        LD      (DE), A
        INC     HL
        INC     DE
        JR      APPEND

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
        LD      HL, MSG_NO_TCP_CAP
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

ERR_CONNECT:
        LD      HL, MSG_CONNECT_FAIL
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

MSG_BANNER:          DB      "HTTPGET - UNET HTTP/1.0 fetch tool", 13, 10, 0
MSG_USAGE:            DB      "Usage: HTTPGET <host> [port]   (try: HTTPGET info.cern.ch)", 0
MSG_CONNECTING:       DB      "Connecting to ", 0
MSG_COLON:            DB      ":", 0
MSG_CONNECT_FAIL:     DB      "CONNECT failed, status=0x", 0
MSG_SEND_FAIL:        DB      "SEND failed, status=0x", 0
MSG_RECV_FAIL:        DB      "RECV failed, status=0x", 0
MSG_DISPATCH_FAIL:    DB      "UNET dispatch failed (libman/DSS error).", 0
MSG_NO_TCP_CAP:       DB      "This backend does not support TCP.", 0
MSG_TRUNCATED:        DB      "[truncated]", 0

LIT_REQ_HEAD:         DB      "GET / HTTP/1.0", 13, 10, "Host: ", 0
LIT_REQ_TAIL:         DB      13, 10, "Connection: close", 13, 10, 13, 10, 0
LIT_DEFAULT_PORT:     DB      "80", 0

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
        MODULE  HTTPGET

ARGS_PTR        EQU UNETLD.STATE_END    ; saved DSS argument pointer (2)
HOST_BUF        EQU ARGS_PTR + 2
HOST_BUF_SIZE   EQU 129                 ; UNET host strings limited to 128 bytes + NUL
PORT_BUF        EQU HOST_BUF + HOST_BUF_SIZE
PORT_BUF_SIZE   EQU 16                  ; UNET port strings limited to 15 bytes + NUL
REQUEST_BUF     EQU PORT_BUF + PORT_BUF_SIZE
REQUEST_BUF_SIZE EQU 200                ; LIT_REQ_HEAD + host(128) + LIT_REQ_TAIL, rounded up
REQUEST_LEN     EQU REQUEST_BUF + REQUEST_BUF_SIZE     ; (2)
SEND_PTR        EQU REQUEST_LEN + 2     ; (2)
SEND_REMAIN     EQU SEND_PTR + 2        ; (2)
RECV_BUF        EQU SEND_REMAIN + 2
RECV_BUF_SIZE   EQU 513                 ; +1 spare byte for the printing NUL
TOTAL_RECV      EQU RECV_BUF + RECV_BUF_SIZE   ; (2)
BSS_END         EQU TOTAL_RECV + 2

STACK_SIZE      EQU 0400h
STACK_TOP       EQU BSS_END + STACK_SIZE

        ASSERT  CODE_END <= WORK_BASE
        ASSERT  STACK_TOP <= 0C000h
        ENDMODULE

        END     HTTPGET.START
