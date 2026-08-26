Читать по-русски: [UNETLDRU.md](UNETLDRU.md).

# UNETLD reference

`include/unetld.asm` is a SjASMPlus code-include that reads the `NET`
environment variable, resolves it to a UNET backend DLL name, loads that
DLL through [libman](https://github.com/witchcraft2001/sprinter-libman),
validates its ABI/capabilities, and gives you a thin wrapper around
`LIBMAN.l_call` plus a `NETINIT`/`NETDONE` lifecycle.

See [docs/UNETAPI.md](UNETAPI.md) for the UNET function contract itself
(function numbers, register conventions, error codes, capability bits).
This document only covers the selector/loader layer.

## Backend selection

`NET` must be 3-4 characters from `[A-Z0-9]` (lower-case is accepted and
upper-cased automatically). The DLL name is built directly from that value:

| `NET` | DLL loaded    |
| ----- | ------------- |
| `RTL` | `UNETRTL.DLL` |
| `WIZ` | `UNETWIZ.DLL` |
| `3COM`| `UNET3COM.DLL`|

`WIFI` is the one exception, aliased to the `ESP` tag (`UNETESP.DLL`) for
backward compatibility with existing tooling (`NETUP` publishes `NET=WIFI`).
See `ALIAS_TABLE` near the end of `unetld.asm` if you need to add another
alias - a normal new backend that follows the `NET` = DLL-tag convention
needs no code changes at all, just vendor the matching `UNET<tag>.DLL`.

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
else is in registers or state.

### `UNETLD.RESET`
Zero the entire state block. Mandatory once, before anything else, when
`UNETLD_STATE_BASE` is used. Harmless in simple mode. Safe to call again
after `UNLOAD`. Out: CF=0.

### `UNETLD.SELECT`
Read `NET`, validate and upper-case it, resolve aliases, build the DLL
name.
In: -
Out: CF=0, `UNETLD.NET_TAG` and `UNETLD.DLL_NAME` set.
CF=1, A=`UNETLD_E_NOENV` (not set/empty) or `UNETLD_E_BADVALUE` (wrong
length/charset - the raw value is in `UNETLD.ENV_VALUE`).

### `UNETLD.LOAD`
Load the DLL selected by `SELECT` and validate it.
In: A = target window, 1 (`0x4000`) or 2 (`0x8000`). **Never 3.** Requires
a prior successful `SELECT`.
Out: CF=0, HL=handle, DE=caps, IX=ABI word (also stored in
`UNETLD.HANDLE`/`CAPS`/`ABI`).
CF=1, A=`UNETLD_E_LOAD` (libman `l_load` failed - see
`LIBMAN.l_reason`/`l_dss_error`/`l_load_stage`/`l_init_status`, active with
`LIBMAN_DIAGNOSTICS`), `E_INFO` (`l_info` failed), `E_NAME` (the DLL's L1
name does not start with `UNET` + your tag), `E_CALL` (dispatcher failure,
or a non-OK status, while calling `GETCAPS`), or `E_ABI` (the major byte of
`GETCAPS`'s ABI word does not match `HIGH(UNET_ABI_VERSION)`).
On any CF=1 here **except** `E_LOAD`, a DLL handle is open - call `UNLOAD`
before retrying or exiting.

### `UNETLD.CALL`
Dispatch one UNET function on the loaded DLL. This is the whole body:
`LD HL,(UNETLD.HANDLE) / JP LIBMAN.l_call`.
In: B = `UNET_FN_*`, arguments in A/DE/IX/IY per `unet.inc`.
Out: CF=1 only on a libman dispatcher/DSS failure; otherwise A holds the
UNET `NERR_*` status (test A, not CF) and results are in A/DE/IX/IY.
The handle is a plain libman handle - calling `LIBMAN.l_call`/`l_info`/
`l_free` with it directly instead of through this wrapper works fine any
time.

### `UNETLD.NETSTART`
Check the configuration, then initialise the backend. Note this does *not*
bring the network up - that is the backend kit's job (`NETUP`, or
`NETCFG`/`IFUP`), done beforehand, and it is what publishes the `NET_*`
environment. `NETSTART` only makes the DLL ready to use that network:
`STATUS(0xFF)` (intentionally non-hardware - it just confirms the
environment is there), accepting `NERR_OK` or `NERR_NONET`, then `NETINIT`,
which initialises the driver and its hardware (locating the UART / probing
the card, flow control, multi-connection mode).
In: - Requires a prior successful `LOAD`.
Out: CF=0, A=0, the NETINIT flag set.
CF=1, A=`UNETLD_E_CALL` (dispatcher failure), `E_STATUS` (`STATUS`
returned neither `NERR_OK` nor `NERR_NONET`), or `E_NETINIT` (`NETINIT`
returned a non-OK status). The `NERR_*` code is in `UNETLD.LAST_STATUS`.

### `UNETLD.REQUIRE`
Capability gate.
In: DE = required `UNET_CAP_*` mask (bits may be combined).
Out: CF=0 if every requested bit is set in `UNETLD.CAPS`; CF=1 otherwise.
Does not touch `UNETLD.ERROR` - report a missing capability yourself.

### `UNETLD.UNLOAD`
Idempotent teardown, safe to call on every error path and more than once:
`NETDONE` (if `NETINIT` had succeeded) then `l_free` (if a DLL is loaded), both
best-effort, then the whole state block is zeroed via `RESET`.
Out: CF=0 always.

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

1. Vendor `dll/UNET<TAG>.DLL` (built against the frozen `unet.inc` ABI) and
   add its entry to `dll/manifest.json`.
2. If its `NET` value should differ from its DLL tag (like `WIFI` -> `ESP`),
   add one row to `ALIAS_TABLE` in `unetld.asm`. Otherwise nothing else
   changes - once the new backend's bring-up tool publishes `NET=<TAG>`
   (the way `NETUP` publishes `NET=WIFI` and `NETCFG`/`IFUP` publish
   `NET=RTL` - users never set `NET` by hand), everything above just works.
