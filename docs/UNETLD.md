Читать по-русски: [UNETLDRU.md](UNETLDRU.md).

# UNETLD reference (asm)

`include/unetld.asm` is a SjASMPlus code-include implementing the UNETLD
loader/selector. This document covers the **asm-specific** parts: the two
state-placement modes, the exact `CALL UNETLD.<name>` register contracts,
and integration notes for this repo.

For the language-neutral *behavior* (the backend-selection algorithm, the
two independent failure planes, what each entry point does and why, the
`UNETLD_E_*`/`UNETLD_F_*` codes) see
[UNETLD-SPEC.md in sprinter_unet_libs_core](https://github.com/witchcraft2001/sprinter_unet_libs_core/blob/main/docs/UNETLD-SPEC.md) -
that document is the contract this asm implementation, the Pascal port and
the Solid C port all satisfy identically.

See [UNETAPI.md in core](https://github.com/witchcraft2001/sprinter_unet_libs_core/blob/main/docs/UNETAPI.md)
for the UNET function contract itself (function numbers, register
conventions, error codes, capability bits).

## Backend selection

`NET` must be 3-4 characters from `[A-Z0-9]` (lower-case is accepted and
upper-cased automatically); the DLL name is built directly from that value
(`RTL` -> `UNETRTL.DLL`, and so on), with one built-in alias: `WIFI` ->
`UNETESP.DLL`. See `ALIAS_TABLE` near the end of `unetld.asm` to add
another - a normal new backend needs no code changes at all, just vendor
the matching `UNET<tag>.DLL` into core. Full algorithm:
[UNETLD-SPEC.md#backend-selection-select](https://github.com/witchcraft2001/sprinter_unet_libs_core/blob/main/docs/UNETLD-SPEC.md#backend-selection-select).

## Two state-placement modes

Pick **one** before `INCLUDE "unetld.asm"`:

### Simple mode (default)

Just include the file. UNETLD's ~315 bytes of state (handle, capabilities,
ABI word, error/status bytes, the resolved tag and DLL name, the 32-byte
`l_info` buffer, and the 256-byte environment value buffer) are emitted as
zeroed storage right inside the EXE image. Nothing else is required - every
entry point is safe to call immediately. The cost is that the built EXE
file is about 315 bytes larger than it needs to be. `examples/netinfo`
uses this mode.

### Compact mode

```asm
        DEFINE  UNETLD_STATE_BASE <address>
        INCLUDE "unetld.asm"
```

No state bytes are emitted into the image at all - every `UNETLD.*` state
label becomes an `EQU` offset from `<address>` instead. That address must
be memory your program actually owns once running (not reused by anything
else, in a window that stays mapped, below `0xC000`), and it is **not**
zero-initialised by loading the EXE - you **must** call `UNETLD.RESET`
once, before any other entry point, to zero it yourself.

`examples/ping`, `examples/httpget` and `examples/udpecho` all use this
mode with a fixed work-area address (`WORK_BASE EQU 0B000h`) placed safely
above where their code can plausibly end, verified by an
`ASSERT CODE_END <= WORK_BASE` placed *after* `unetld.asm`/`libman.asm` are
included (their code is real, emitted bytes too - only UNETLD's *state* is
address-only in this mode). Do not compute the base address from the
in-progress `$` position before `unetld.asm` is included - `unetld.asm`
itself still emits real code after that point, and an address derived too
early will overlap it. Either pick a fixed constant like the examples do,
or place a label after every `INCLUDE` your program needs and use that.

Either way, `UNETLD.STATE_SIZE` is available if you want to compute layout
elsewhere, and `UNETLD.STATE_END` is the first address after UNETLD's state
- convenient as the base of your own buffers, as the three compact-mode
examples do.

## Entry points

All are called as `CALL UNETLD.<name>`. Register contracts follow the UNET
convention: arguments in A/DE/IX/IY, CF signals a hard failure, everything
else is in registers or state. Behavior: see UNETLD-SPEC.md, linked above.

| Entry point | In | Out |
| --- | --- | --- |
| `UNETLD.RESET` | - | CF=0 |
| `UNETLD.SELECT` | - | CF=0, `NET_TAG`/`DLL_NAME` set. CF=1, A=`UNETLD_E_NOENV`\|`E_BADVALUE` |
| `UNETLD.LOAD` | A=window (1 or 2, never 3) | CF=0, HL=handle, DE=caps, IX=ABI. CF=1, A=`E_LOAD`\|`E_INFO`\|`E_NAME`\|`E_CALL`\|`E_ABI` |
| `UNETLD.CALL` | B=`UNET_FN_*`, args in A/DE/IX/IY | CF=1 only on dispatcher failure; else A=`NERR_*`, results in A/DE/IX/IY |
| `UNETLD.NETSTART` | - | CF=0, A=0, NETINIT flag set. CF=1, A=`E_CALL`\|`E_STATUS`\|`E_NETINIT` |
| `UNETLD.REQUIRE` | DE=required `UNET_CAP_*` mask | CF=0 if all bits set in `CAPS`; else CF=1 |
| `UNETLD.UNLOAD` | - | CF=0 always |

On any `UNETLD.LOAD` failure **except** `E_LOAD`, a DLL handle is already
open - call `UNLOAD` before retrying or exiting (see UNETLD-SPEC.md).

`UNETLD.CALL`'s whole body is `LD HL,(UNETLD.HANDLE) / JP LIBMAN.l_call` -
the handle is a plain libman handle, so calling `LIBMAN.l_call`/`l_info`/
`l_free` with it directly, bypassing this wrapper, works fine any time.

## State (read-only, same label names in both placement modes)

| Label | Size | Meaning |
| --- | --- | --- |
| `UNETLD.HANDLE` | 2 | libman handle of the loaded DLL |
| `UNETLD.CAPS` | 2 | `GETCAPS` capability bitmask |
| `UNETLD.ABI` | 2 | `GETCAPS` ABI word (major\<\<8\|minor) |
| `UNETLD.ERROR` | 1 | last `UNETLD_E_*` code |
| `UNETLD.LAST_STATUS` | 1 | last `NERR_*` from `STATUS`/`NETINIT` |
| `UNETLD.FLAGS` | 1 | bit0 = DLL loaded, bit1 = `NETINIT` succeeded |
| `UNETLD.NET_TAG` | 5 | resolved tag, ASCIIZ, up to 4 chars |
| `UNETLD.DLL_NAME` | 13 | `"UNETxxxx.DLL",0` |
| `UNETLD.DLL_INFO` | 32 | libman `l_info` destination |
| `UNETLD.ENV_VALUE` | 256 | raw/upper-cased `NET` value |
| `UNETLD.STATE_SIZE` | - | total size of the block above |
| `UNETLD.STATE_END` | - | first free address after the block |

## Error codes (`UNETLD_E_*`, plain global constants - not module-qualified)

Defined in [abi/unet_abi.toml in core](https://github.com/witchcraft2001/sprinter_unet_libs_core/blob/main/abi/unet_abi.toml)
(group `unetld_e`), rendered here via `extern/core/bindings/asm/unet.inc`.

| Constant | Value | Set by |
| --- | --- | --- |
| `UNETLD_E_NOENV` | 1 | `SELECT` - `NET` not set or empty |
| `UNETLD_E_BADVALUE` | 2 | `SELECT` - `NET` not 3-4 chars of `[A-Z0-9]` |
| `UNETLD_E_LOAD` | 3 | `LOAD` - `l_load` failed |
| `UNETLD_E_INFO` | 4 | `LOAD` - `l_info` failed |
| `UNETLD_E_NAME` | 5 | `LOAD` - DLL name mismatch |
| `UNETLD_E_CALL` | 6 | `LOAD`/`NETSTART` - dispatcher failure or bad `GETCAPS` status |
| `UNETLD_E_ABI` | 7 | `LOAD` - unsupported major ABI version |
| `UNETLD_E_STATUS` | 8 | `NETSTART` - unexpected `STATUS(0xFF)` result |
| `UNETLD_E_NETINIT` | 9 | `NETSTART` - `NETINIT` failed |

## Loading your own DLLs alongside UNET

UNETLD does not wrap or hide libman - your program includes `libman.asm`
itself, so the full `LIBMAN.l_load` / `l_call` / `l_info` / `l_free` API is
available to your own code for your own libraries (fonts, graphics, ...),
side by side with the UNET backend. `UNETLD.LOAD`'s handle is a plain
libman handle in the same table as yours, and `UNETLD.UNLOAD` frees only
that one handle - it never touches libraries you loaded yourself.

Two things to keep in mind:

- **`LIBMAN_MAX_LIBS`** is your DEFINE, not UNETLD's. The examples set it
  to 1 because they load nothing but the UNET DLL; raise it to the number
  of DLLs you keep loaded at once (weather-forecast's graphics build uses
  3: UNET + GFX320 + AFNT320).
- **Windows:** libman maps the right DLL's page into its window on every
  `l_call`, so several DLLs may share window 1 the way weather-forecast's
  do. The UNET-specific rules still stand: never window 3 for the UNET
  DLL, and buffers passed to UNET functions must stay outside its window.

## A note on `dss.inc`

`include/dss.inc` is a small, deliberately incomplete set of DSS constants
- just what `unetld.asm` and the examples use. It is not a merge of the
`sprinter_wifi/network` and `sprinter-rtl8019a` copies of `dss.inc` (those
have diverged and collide on some names). `unetld.asm` itself only
references `DSS`, `DSS_ENVIRON` and `ENV_GET`, which exist in every variant
we know of, so it is safe to use `unetld.asm` alongside a backend's own,
more complete `dss.inc`. `examples/common/conutil.asm` uses a few more
names from this project's own `dss.inc` and is examples-only scaffolding,
not part of the consumer-facing API.

## Adding a backend

See [UNETLD-SPEC.md#adding-a-backend in core](https://github.com/witchcraft2001/sprinter_unet_libs_core/blob/main/docs/UNETLD-SPEC.md#adding-a-backend)
for the general steps (vendor the DLL into core, add an alias-table row
only if the tag differs from `NET`'s value). The asm-specific part is
adding that row to `ALIAS_TABLE` in `unetld.asm` - the Pascal and Solid C
ports each keep their own equivalent table, all three in sync.
