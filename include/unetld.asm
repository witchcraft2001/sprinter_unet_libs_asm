; ============================================================================
; UNETLD - UNET backend selector and loader for Sprinter DSS.
;
; Reads the NET environment variable, turns its value into a DLL name
; ("UNET" + value + ".DLL"), loads it through libman, validates its ABI and
; capabilities, and gives the caller a thin wrapper around libman.l_call plus
; a NETINIT/NETDONE lifecycle. See docs/UNETLD.md for the full reference
; (docs/UNETLDRU.md is the same document in Russian).
;
; Backend selection (UNETLD.SELECT):
;   NET is published by the backend's bring-up tool (NETUP publishes
;   NET=WIFI, NETCFG/IFUP publish NET=RTL) - users never set it by hand.
;   NET must be 3-4 characters from [A-Z0-9] (values are upper-cased first).
;   The DLL name is built directly from that value: RTL -> UNETRTL.DLL,
;   WIZ -> UNETWIZ.DLL, 3COM -> UNET3COM.DLL. Adding a backend that follows
;   this convention needs NO changes here - just vendor the matching DLL.
;   ESP is the one alias: NET=WIFI resolves to UNETESP.DLL (ALIAS_TABLE
;   below is where future exceptions like this one would go).
;
; Calling convention reminder (see unet.inc for the full contract): UNET
; functions take arguments only in A/DE/IX/IY and return their status in A,
; not CF. UNETLD.CALL's own CF denotes a libman dispatcher failure only.
;
; State placement - pick ONE before including this file:
;
;   Simple mode (default, easiest to use): just include this file. State
;   (~315 bytes) is emitted as zeroed DS/DW/DB storage inside the image
;   itself, so the EXE file is ~315 bytes larger, but nothing else is
;   required - it is safe to CALL any entry point right away.
;
;   Compact mode: DEFINE UNETLD_STATE_BASE to a free memory address before
;   including this file. No state bytes are emitted into the image at all;
;   every UNETLD label becomes an EQU offset from that address instead. The
;   address must point at memory the running program actually owns (e.g.
;   right after its own BSS, still below 0xC000, in a window that stays
;   mapped) - it is NOT zero-initialised by loading the EXE, so you MUST
;   call UNETLD.RESET once before using any other entry point.
; ============================================================================

        IFNDEF  _UNETLD_ASM
        DEFINE  _UNETLD_ASM

        INCLUDE "dss.inc"
        INCLUDE "unet.inc"

; ----------------------------------------------------------------------
; Error codes, stored in UNETLD.ERROR and returned in A on CF=1. Defined
; outside MODULE UNETLD so they read as plain UNETLD_E_* everywhere, the
; same way unet.inc's own UNET_FN_*/NERR_* constants do.
; ----------------------------------------------------------------------
UNETLD_E_NOENV          EQU 1   ; NET is not set or empty
UNETLD_E_BADVALUE       EQU 2   ; NET is not 3-4 chars of [A-Z0-9] (raw value in ENV_VALUE)
UNETLD_E_LOAD           EQU 3   ; l_load failed (see LIBMAN.l_reason/l_dss_error/...)
UNETLD_E_INFO           EQU 4   ; l_info failed
UNETLD_E_NAME           EQU 5   ; the loaded DLL's L1 name does not match NET
UNETLD_E_CALL           EQU 6   ; libman dispatcher (CF) failure, or GETCAPS returned
                                 ; a non-OK status during LOAD
UNETLD_E_ABI            EQU 7   ; GETCAPS major ABI byte != HIGH(UNET_ABI_VERSION)
UNETLD_E_STATUS         EQU 8   ; STATUS(0FFh) returned neither NERR_OK nor NERR_NONET
UNETLD_E_NETINIT        EQU 9   ; NETINIT returned a non-OK status (see LAST_STATUS)

UNETLD_F_LOADED         EQU 00000001b   ; bit0 of FLAGS: DLL handle is open
UNETLD_F_NETINIT        EQU 00000010b   ; bit1 of FLAGS: NETINIT succeeded

        MODULE  UNETLD

; ----------------------------------------------------------------------
; State. See the file header for the two placement modes.
; ----------------------------------------------------------------------
        IFDEF   UNETLD_STATE_BASE
STATE_BASE      EQU UNETLD_STATE_BASE
HANDLE          EQU STATE_BASE          ; libman handle of the loaded DLL (2)
CAPS            EQU HANDLE + 2          ; GETCAPS capability bitmask (2)
ABI             EQU CAPS + 2            ; GETCAPS ABI word, major<<8|minor (2)
ERROR           EQU ABI + 2             ; last UNETLD_E_* code (1)
LAST_STATUS     EQU ERROR + 1           ; last NERR_* from STATUS/NETINIT (1)
FLAGS           EQU LAST_STATUS + 1     ; UNETLD_F_* bits (1)
NET_TAG         EQU FLAGS + 1           ; resolved tag, ASCIIZ, up to 4 chars (5)
DLL_NAME        EQU NET_TAG + 5         ; "UNETxxxx.DLL",0 (13)
DLL_INFO        EQU DLL_NAME + 13       ; libman l_info destination (32)
ENV_VALUE       EQU DLL_INFO + 32       ; raw/upper-cased NET value (256)
STATE_END       EQU ENV_VALUE + 256
        ELSE
HANDLE:         DW 0
CAPS:           DW 0
ABI:            DW 0
ERROR:          DB 0
LAST_STATUS:    DB 0
FLAGS:          DB 0
NET_TAG:        DS 5, 0
DLL_NAME:       DS 13, 0
DLL_INFO:       DS 32, 0
ENV_VALUE:      DS 256, 0
STATE_END       EQU $
        ENDIF
STATE_SIZE      EQU STATE_END - HANDLE

        ASSERT  STATE_END <= 0C000h

; ----------------------------------------------------------------------
; UNETLD.RESET - zero the entire state block.
; Mandatory once, before any other call, when UNETLD_STATE_BASE is used
; (that memory is not pre-zeroed the way the EXE image is). Harmless to
; call in simple mode too, and safe to call again after UNLOAD.
; Out: CF=0.
; ----------------------------------------------------------------------
RESET:
        LD      HL, HANDLE
        LD      DE, HANDLE + 1
        LD      BC, STATE_SIZE - 1
        XOR     A
        LD      (HL), A
        LDIR
        RET

; ----------------------------------------------------------------------
; UNETLD.SELECT - read NET and resolve it to a DLL name.
; In:  -
; Out: CF=0, NET_TAG/DLL_NAME set, A=0.
;      CF=1, A=UNETLD_E_NOENV or UNETLD_E_BADVALUE (raw value in ENV_VALUE).
; Clobbers AF/BC/DE/HL.
; ----------------------------------------------------------------------
SELECT:
        XOR     A
        LD      (ENV_VALUE), A
        LD      HL, LIT_NET
        LD      DE, ENV_VALUE
        LD      B, ENV_GET
        LD      C, DSS_ENVIRON
        RST     DSS
        JP      C, .E_NOENV
        OR      A
        JP      Z, .E_NOENV

        LD      A, (ENV_VALUE)
        OR      A
        JP      Z, .E_NOENV

        ; Upper-case in place and measure the length in B.
        LD      HL, ENV_VALUE
        LD      B, 0
.UPPER_LOOP:
        LD      A, (HL)
        OR      A
        JR      Z, .UPPER_DONE
        CP      'a'
        JR      C, .NOT_LOWER
        CP      'z' + 1
        JR      NC, .NOT_LOWER
        SUB     32
        LD      (HL), A
.NOT_LOWER:
        INC     HL
        INC     B
        JR      .UPPER_LOOP
.UPPER_DONE:
        LD      A, B
        CP      3
        JP      C, .E_BADVALUE
        CP      5
        JP      NC, .E_BADVALUE

        ; Charset check: every character must be 0-9 or A-Z.
        LD      HL, ENV_VALUE
.CHARSET_LOOP:
        LD      A, (HL)
        OR      A
        JR      Z, .CHARSET_OK
        CP      '0'
        JR      C, .E_BADVALUE
        CP      '9' + 1
        JR      C, .CHARSET_NEXT
        CP      'A'
        JR      C, .E_BADVALUE
        CP      'Z' + 1
        JR      NC, .E_BADVALUE
.CHARSET_NEXT:
        INC     HL
        JR      .CHARSET_LOOP
.CHARSET_OK:

        ; Alias lookup: {value ptr, tag ptr} pairs, DW 0 terminator.
        ; No match -> the value itself (already validated) is the tag.
        LD      HL, ALIAS_TABLE
.ALIAS_LOOP:
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        INC     HL
        LD      A, D
        OR      E
        JR      Z, .NO_ALIAS
        PUSH    HL
        EX      DE, HL
        LD      DE, ENV_VALUE
        CALL    STREQ
        POP     HL
        JR      Z, .ALIAS_MATCH
        INC     HL
        INC     HL
        JR      .ALIAS_LOOP
.ALIAS_MATCH:
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        EX      DE, HL
        LD      DE, NET_TAG
        CALL    STRCPY
        JR      .TAG_READY
.NO_ALIAS:
        LD      HL, ENV_VALUE
        LD      DE, NET_TAG
        CALL    STRCPY
.TAG_READY:

        ; DLL_NAME = "UNET" + NET_TAG + ".DLL",0
        LD      HL, DLL_NAME
        LD      (HL), 'U'
        INC     HL
        LD      (HL), 'N'
        INC     HL
        LD      (HL), 'E'
        INC     HL
        LD      (HL), 'T'
        INC     HL
        LD      DE, NET_TAG
.APPEND_TAG:
        LD      A, (DE)
        OR      A
        JR      Z, .APPEND_DONE
        LD      (HL), A
        INC     HL
        INC     DE
        JR      .APPEND_TAG
.APPEND_DONE:
        LD      (HL), '.'
        INC     HL
        LD      (HL), 'D'
        INC     HL
        LD      (HL), 'L'
        INC     HL
        LD      (HL), 'L'
        INC     HL
        LD      (HL), 0

        XOR     A
        LD      (ERROR), A
        RET

.E_NOENV:
        LD      A, UNETLD_E_NOENV
        JR      FAIL
.E_BADVALUE:
        LD      A, UNETLD_E_BADVALUE
        JR      FAIL

; Shared error exit: record the UNETLD_E_* code from A and return CF=1.
; Placed between SELECT and LOAD so both reach it with a two-byte JR;
; NETSTART sits too far away and uses JP.
FAIL:
        LD      (ERROR), A
        SCF
        RET

; ----------------------------------------------------------------------
; UNETLD.LOAD - load the DLL selected by SELECT and validate it.
; In:  A = target window, 1 (0x4000) or 2 (0x8000). NEVER 3. Requires a
;      prior successful SELECT.
; Out: CF=0, HL=handle, DE=caps, IX=ABI word (also stored in state).
;      CF=1, A=UNETLD_E_LOAD/E_INFO/E_NAME/E_CALL/E_ABI.
; On any CF=1 here except E_LOAD, the DLL handle is open - call UNLOAD
; before retrying or exiting.
; Clobbers all registers.
; ----------------------------------------------------------------------
LOAD:
        LD      HL, DLL_NAME
        CALL    LIBMAN.l_load
        JR      C, .E_LOAD

        LD      (HANDLE), HL
        LD      A, (FLAGS)
        OR      UNETLD_F_LOADED
        LD      (FLAGS), A

        LD      HL, (HANDLE)
        LD      DE, DLL_INFO
        CALL    LIBMAN.l_info
        JR      C, .E_INFO

        CALL    VALIDATE_NAME
        JR      C, .E_NAME

        LD      B, UNET_FN_GETCAPS
        CALL    CALL
        JR      C, .E_CALL
        LD      (LAST_STATUS), A        ; keep the NERR code for diagnostics
        OR      A
        JR      NZ, .E_CALL
        LD      (CAPS), DE
        LD      (ABI), IX

        LD      A, (ABI + 1)
        CP      HIGH UNET_ABI_VERSION
        JR      NZ, .E_ABI

        XOR     A
        LD      (ERROR), A
        LD      HL, (HANDLE)
        LD      DE, (CAPS)
        LD      IX, (ABI)
        RET

.E_LOAD:
        LD      A, UNETLD_E_LOAD
        JR      FAIL
.E_INFO:
        LD      A, UNETLD_E_INFO
        JR      FAIL
.E_NAME:
        LD      A, UNETLD_E_NAME
        JR      FAIL
.E_CALL:
        LD      A, UNETLD_E_CALL
        JR      FAIL
.E_ABI:
        LD      A, UNETLD_E_ABI
        JR      FAIL

; Confirm the loaded DLL's L1 name is "UNET" + NET_TAG. The version suffix
; is intentionally not checked here: the pinned file hash (see
; dll/manifest.json) is the build-time identity, while this runtime check
; only guards against loading the wrong backend's DLL by mistake.
VALIDATE_NAME:
        LD      HL, DLL_INFO + 16
        LD      DE, LIT_UNET
        LD      B, 4
.CMP_UNET:
        LD      A, (DE)
        CP      (HL)
        JR      NZ, .FAIL
        INC     HL
        INC     DE
        DJNZ    .CMP_UNET

        LD      DE, NET_TAG
.CMP_TAG:
        LD      A, (DE)
        OR      A
        JR      Z, .OK
        CP      (HL)
        JR      NZ, .FAIL
        INC     HL
        INC     DE
        JR      .CMP_TAG
.OK:
        OR      A
        RET
.FAIL:
        SCF
        RET

; ----------------------------------------------------------------------
; UNETLD.CALL - dispatch one UNET function on the loaded DLL.
; In:  B = UNET_FN_*, arguments in A/DE/IX/IY per unet.inc.
; Out: CF=1 only on a libman dispatcher/DSS failure; otherwise A holds the
;      UNET NERR_* status (test A, not CF) and results are in A/DE/IX/IY.
; The returned handle is a plain libman handle: calling LIBMAN.l_call,
; l_info or l_free with it directly instead of through this wrapper is
; fine any time.
; ----------------------------------------------------------------------
CALL:
        LD      HL, (HANDLE)
        JP      LIBMAN.l_call

; ----------------------------------------------------------------------
; UNETLD.NETSTART - check the configuration, then initialise the backend.
; The network itself is brought up beforehand by the backend's own kit
; (NETUP, or NETCFG/IFUP), which is what publishes the NET_* environment.
; This only gets the DLL ready to use it: STATUS(0xFF) is intentionally
; non-hardware and just confirms that environment is present, then NETINIT
; initialises the driver and its hardware (locating the UART / probing the
; card, flow control, multi-connection mode).
; In:  -   Requires a prior successful LOAD.
; Out: CF=0, A=0, FLAGS NETINIT bit set.
;      CF=1, A=UNETLD_E_CALL/E_STATUS/E_NETINIT, NERR_* code in LAST_STATUS.
; ----------------------------------------------------------------------
NETSTART:
        LD      A, 0FFh
        LD      B, UNET_FN_STATUS
        CALL    CALL
        JR      C, .E_CALL
        LD      (LAST_STATUS), A
        CP      NERR_OK
        JR      Z, .PROCEED
        CP      NERR_NONET
        JR      NZ, .E_STATUS

.PROCEED:
        LD      B, UNET_FN_NETINIT
        CALL    CALL
        JR      C, .E_CALL
        LD      (LAST_STATUS), A
        OR      A
        JR      NZ, .E_NETINIT

        LD      A, (FLAGS)
        OR      UNETLD_F_NETINIT
        LD      (FLAGS), A
        XOR     A
        LD      (ERROR), A
        RET

.E_CALL:
        LD      A, UNETLD_E_CALL
        JP      FAIL                    ; out of JR range from here
.E_STATUS:
        LD      A, UNETLD_E_STATUS
        JP      FAIL
.E_NETINIT:
        LD      A, UNETLD_E_NETINIT
        JP      FAIL

; ----------------------------------------------------------------------
; UNETLD.REQUIRE - capability gate.
; In:  DE = required UNET_CAP_* mask (may combine several bits).
; Out: CF=0 if every requested bit is set in CAPS; CF=1 otherwise. Does
;      not touch ERROR - callers report a missing capability themselves.
; ----------------------------------------------------------------------
REQUIRE:
        LD      HL, (CAPS)
        LD      A, H
        AND     D
        LD      H, A
        LD      A, L
        AND     E
        LD      L, A
        LD      A, H
        CP      D
        JR      NZ, .MISSING
        LD      A, L
        CP      E
        JR      NZ, .MISSING
        OR      A
        RET
.MISSING:
        SCF
        RET

; ----------------------------------------------------------------------
; UNETLD.UNLOAD - idempotent teardown, safe on every error path.
; NETDONE (if the link was up) then l_free (if a DLL is loaded), both
; best-effort, then the whole state block is zeroed via RESET.
; Out: CF=0 always.
; ----------------------------------------------------------------------
UNLOAD:
        LD      A, (FLAGS)
        AND     UNETLD_F_NETINIT
        JR      Z, .SKIP_NETDONE
        LD      B, UNET_FN_NETDONE
        CALL    CALL
.SKIP_NETDONE:
        LD      A, (FLAGS)
        AND     UNETLD_F_LOADED
        JR      Z, .SKIP_FREE
        LD      HL, (HANDLE)
        CALL    LIBMAN.l_free
.SKIP_FREE:
        CALL    RESET
        OR      A
        RET

; Compare ASCIIZ HL and DE. Z when equal.
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

; Copy ASCIIZ HL to DE, including the terminating NUL.
STRCPY:
        LD      A, (HL)
        LD      (DE), A
        OR      A
        RET     Z
        INC     HL
        INC     DE
        JR      STRCPY

LIT_NET:        DB      "NET", 0
LIT_UNET:       DB      "UNET"          ; 4 bytes, compared without a NUL check

; Exceptions to the direct NET-value -> "UNET<value>.DLL" mapping.
; A tag string here MUST be at most 4 characters: NET_TAG holds 4 + NUL and
; DLL_NAME has room for exactly "UNET" + 4 + ".DLL" + NUL (13 bytes). The
; env value itself is length-checked in SELECT; alias tags are not.
ALIAS_TABLE:
        DW      LIT_WIFI, LIT_ESP       ; NET=WIFI -> UNETESP.DLL
        DW      0
LIT_WIFI:       DB      "WIFI", 0
LIT_ESP:        DB      "ESP", 0

        ENDMODULE
        ENDIF
