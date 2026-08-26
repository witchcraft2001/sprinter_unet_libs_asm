# sprinter_unet_libs_asm

A single, submodule-friendly place to get UNET network support into a
Sprinter (Z80 / DSS) project. It bundles:

- prebuilt `UNETESP.DLL` (WiFi/ESP8266) and `UNETRTL.DLL` (ISA RTL8019A)
  backend DLLs, both implementing the same frozen
  [UNET ABI](docs/UNETAPI.md);
- [libman](https://github.com/witchcraft2001/sprinter-libman) as a nested
  git submodule, the DLL loader/dispatcher both backends are built for;
- `include/unetld.asm`, a small SjASMPlus include that reads the `NET`
  environment variable, loads the matching DLL, validates it, and gives you
  a thin call wrapper plus a NETINIT/NETDONE lifecycle - see
  [docs/UNETLD.md](docs/UNETLD.md);
- four runnable examples (`NETINFO`, `PING`, `HTTPGET`, `UDPECHO`).

Target toolchain: [sjasmplus](https://github.com/z00m128/sjasmplus). This
project is Z80 assembly only - a separate project covers C/Pascal bindings.

Every document here exists in both languages - Russian versions carry an
`RU` suffix: [READMERU.md](READMERU.md),
[docs/UNETLDRU.md](docs/UNETLDRU.md), [docs/UNETAPIRU.md](docs/UNETAPIRU.md).

## Using this as a submodule

```sh
git submodule add https://github.com/witchcraft2001/sprinter_unet_libs_asm.git extern/unet_libs_asm
```

Consumers must clone (or update) recursively so the nested `libman`
submodule comes along too:

```sh
git clone --recursive <your-repo>
# or, in an existing checkout:
git submodule update --init --recursive
```

## Build integration

Add two include paths to your `sjasmplus` invocation:

```sh
sjasmplus -I extern/unet_libs_asm/include -I extern/unet_libs_asm/extern/libman/libman ...
```

Then, in your source, define libman's options *before* including it, and
include `unetld.asm` outside your own `MODULE` (it opens its own
`MODULE UNETLD`):

```asm
        DEVICE  NOSLOT64K
        INCLUDE "dss.inc"
        INCLUDE "unet.inc"

        DEFINE  LIBMAN_MAX_LIBS 1
        DEFINE  LIBMAN_DIAGNOSTICS      ; optional but recommended: gives you
                                        ; LIBMAN.l_reason/l_dss_error/... on
                                        ; a failed load
        DEFINE  LIBMAN_NO_LEGACY_API

        MODULE  MYAPP
        ; ... your program, including calls to UNETLD.* ...
        ENDMODULE

        INCLUDE "unetld.asm"
        INCLUDE "libman.asm"
```

`unetld.asm` has two state-placement modes - see
[docs/UNETLD.md](docs/UNETLD.md#two-state-placement-modes) for the choice
and the exact contract. The short version: include it with no further setup
for the simplest integration (state rides in the EXE image, ~315 bytes),
or `DEFINE UNETLD_STATE_BASE <address>` first for a build that doesn't pay
that cost (and call `UNETLD.RESET` once before anything else). All four
examples in this repo are worked, buildable references for both modes -
`examples/netinfo` uses the simple one, the other three use the compact one.

Because your program includes `libman.asm` itself, the full
`LIBMAN.l_load`/`l_call`/`l_info`/`l_free` API stays available to your own
code for loading your own DLLs (fonts, graphics, ...) alongside the UNET
backend - just raise `LIBMAN_MAX_LIBS` to the number of DLLs you keep
loaded at once. See
[docs/UNETLD.md](docs/UNETLD.md#loading-your-own-dlls-alongside-unet).

Copy `dll/UNETESP.DLL` and `dll/UNETRTL.DLL` next to your built EXE (or into
your distribution's floppy image / zip) - libman resolves a plain DLL name
against the EXE's own directory first (via DSS `APPINFO`), then the current
directory. You do not need to ship both if you only target one backend, but
shipping both is what lets a single EXE run against either.

## Environment variables

`NET` selects the backend: its value (3-4 characters, `[A-Z0-9]`, case
insensitive) becomes the DLL name directly - `NET=RTL` loads
`UNETRTL.DLL`, `NET=WIZ` would load `UNETWIZ.DLL`, and so on. `WIFI` is the
one built-in exception, aliased to `UNETESP.DLL` for compatibility with
existing tooling. See [docs/UNETLD.md](docs/UNETLD.md#adding-a-backend) for
how a new backend fits into this scheme.

`NET` is *published by the backend's bring-up tool*, together with the rest
of that backend's configuration - it is not something users (or consumer
programs) set by hand. If it is missing, the right fix is always "run the
bring-up tool", never `SET NET=...`:

| Backend | Bring-up tool | Publishes |
| --- | --- | --- |
| WiFi (`UNETESP.DLL`) | `NETUP` | `NET=WIFI`, `NET_ESP_*`, `NET_IP`/`NET_MASK`/`NET_GW`/`NET_MAC`/... |
| RTL8019A (`UNETRTL.DLL`) | `NETCFG -i` then `IFUP` | `NET=RTL`, `NET_RTL_*`, `NET_IP`/`NET_MASK`/`NET_GW`/`NET_MAC`/... |

Get the bring-up tools from your backend's own distribution: `NETUP` comes
with the WiFi kit ([sprinter_net](https://github.com/witchcraft2001/sprinter_net)),
`NETCFG`/`IFUP` with the RTL kit
([sprinter-rtl8019a](https://github.com/witchcraft2001/sprinter-rtl8019a)).
`UNET_FN_STATUS` called with `A=0xFF` (what `UNETLD.NETSTART`
does before `NETINIT`) checks that this environment was published without
touching any hardware - useful for a friendly "run NETUP/IFUP first"
message. See [docs/UNETAPI.md](docs/UNETAPI.md) for the full variable list
and the UNET function reference.

## Memory-map rules

These come from the UNET ABI itself (see `include/unet.inc`) and from DSS:

- Load a DLL into window 1 (`0x4000`) or window 2 (`0x8000`) only - **never
  window 3** (`0xC000`); the ESP backend maps hardware there during every
  call.
- Every buffer you pass to a UNET function (host/port strings, send/recv
  payloads, `GETINFO` destinations) must live below `0xC000` and entirely
  outside the DLL's own window.
- Host strings are limited to 128 bytes, port strings to 15 bytes.
- Keep at least ~256 bytes of free stack across a UNET call.
- UNET is not reentrant - one call at a time.
- For any `RST 0x10`/`RST 0x08` (DSS/BIOS) call, `SP` must be inside
  `0x8000`-`0xBFFF`, and `HL'`/`DE'`/`BC'` are DSS/BIOS-reserved - never
  `EXX` around a DSS call.

## Building and running the examples

```sh
make            # build all four examples into build/
make netinfo    # or just one
make check      # verify the vendored DLLs against dll/manifest.json
make image      # build + write distr/unet_libs_asm.img (FAT12, for an emulator
                # or a real floppy)
make package    # build + write distr/unet_libs_asm.zip
```

Requires `sjasmplus` on `PATH` (all targets), and `mtools` + `iconv`
(`image` only). Try them in this order once a backend is configured - just
run its bring-up tool (`NETUP`, or `NETCFG -i` + `IFUP`); it publishes
`NET` itself, users never set that variable by hand:

```
NETINFO                      - prints backend, capabilities, ABI, IP/MAC/...
PING 8.8.8.8                 - four pings
HTTPGET info.cern.ch         - plain-HTTP GET, dumps the response
UDPECHO <host> 7777          - pair with `python3 tools/udp_echo.py`
```

Manual test matrix (no hardware needed for the first two rows):

(The `SET NET=...` rows below are deliberate fault injection for testing the
error paths - in normal use `NET` is only ever published by a bring-up tool.)

| Scenario | Expected |
| --- | --- |
| `NET` unset (no bring-up tool run) | "NET is not set" + a bring-up hint, exit code 4 |
| `SET NET=XX` by hand (2 chars) | "NET has an invalid value: XX", exit code 4 |
| `SET NET=FOO` by hand (valid shape, no such DLL) | "Could not load UNETFOO.DLL" + libman diagnostics, exit code 2 |
| after `NETUP` | NETINFO shows backend ESP, caps `0x031F` |
| after `NETCFG -i`/`IFUP` | NETINFO shows backend RTL, caps `0x001F` |
| Esc during a network wait | clean `NERR_CANCEL` exit; re-running works (UNLOAD is idempotent) |

## Maintaining the vendored DLLs

```sh
make update-dlls
```

Copies fresh `UNETESP.DLL`/`UNETRTL.DLL` from sibling backend-project
checkouts (override with the `UNETESP_SRC`/`UNETRTL_SRC` environment
variables), updates `dll/manifest.json`'s size/sha256 (bump the `version`
field by hand), re-runs verification, and warns if `include/unet.inc` has
drifted from the upstream copy it was vendored from.

The DLL's L1 name is checked only by prefix at load time (`UNET` + your
`NET` tag) - the version suffix is intentionally not pinned there. The
`sha256` in `dll/manifest.json` is the real build-time identity.

## License

BSD 3-Clause, see [LICENSE](LICENSE). The vendored DLLs remain subject to
their own upstream projects' licenses - see `dll/manifest.json` for
provenance.
