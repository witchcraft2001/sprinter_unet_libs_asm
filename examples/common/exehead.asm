; ============================================================================
; DSS EXE v1 header emitter, shared by every example in this project.
;
; Include this once, right after ORG-independent EQUs, inside the example's
; own MODULE. It expects two EQUs and one label to already be defined:
;   EXE_LOAD_ADDRESS  load/entry address, 08100h for every example here
;   EXE_HEADER_SIZE   0200h (the fixed DSS v1 header size)
;   STACK_TOP         defined later in the file (forward reference is fine -
;                     sjasmplus resolves EQUs and labels in later passes)
; and defines a START label for the caller to place its first instruction
; right after the INCLUDE.
;
; Entry contract (see the Sprinter manual, 04_dss/05_dss_exe.md): on entry,
; IX points to the argument buffer at EXE_LOAD_ADDRESS-080h. [IX+0] is the
; argument text length, [IX+1..] is the ASCIIZ text itself.
; ============================================================================

        ORG     EXE_LOAD_ADDRESS - EXE_HEADER_SIZE
EXE_HEADER:
        DB      "EXE", 1
        DD      EXE_HEADER_SIZE
        DW      0                       ; no primary loader
        DS      6, 0                    ; reserved
        DW      START                   ; load address
        DW      START                   ; entry point
        DW      STACK_TOP               ; initial stack
        DB      0                       ; unused byte at offset 22
        DS      EXE_HEADER_SIZE - ($ - EXE_HEADER), 0

        ASSERT  $ = EXE_LOAD_ADDRESS
        ORG     EXE_LOAD_ADDRESS

START:
