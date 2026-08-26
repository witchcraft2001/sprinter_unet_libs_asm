# sprinter_unet_libs_asm

Z80/SjASMPlus bindings and examples for UNET network support on a Sprinter
(Z80 / DSS) project. The backend DLLs, the frozen ABI and the API reference
live in [sprinter_unet_libs_core](https://github.com/witchcraft2001/sprinter_unet_libs_core)
(pulled in as `extern/core`); this repo adds:

- [libman](https://github.com/witchcraft2001/sprinter-libman) as a nested
  git submodule, the DLL loader/dispatcher both backends are built for;
- `include/unetld.asm`, a small SjASMPlus include that reads the `NET`
  environment variable, loads the matching DLL, validates it, and gives you
  a thin call wrapper plus a NETINIT/NETDONE lifecycle - see
  [docs/UNETLD.md](docs/UNETLD.md) (asm-specific reference) and
  [core's UNETLD-SPEC.md](https://github.com/witchcraft2001/sprinter_unet_libs_core/blob/main/docs/UNETLD-SPEC.md)
  (language-neutral behavior spec);
- four runnable examples (`NETINFO`, `PING`, `HTTPGET`, `UDPECHO`).

Target toolchain: [sjasmplus](https://github.com/z00m128/sjasmplus). Pascal
and Solid C bindings live in their own sibling repos,
[sprinter_unet_libs_pascal](https://github.com/witchcraft2001/sprinter_unet_libs_pascal)
and [sprinter_unet_libs_c](https://github.com/witchcraft2001/sprinter_unet_libs_c).

Every document here exists in both languages - Russian versions carry an
`RU` suffix: [READMERU.md](READMERU.md),
[docs/UNETLDRU.md](docs/UNETLDRU.md).

## Using this as a submodule

```sh
git submodule add https://github.com/witchcraft2001/sprinter_unet_libs_asm.git extern/unet_libs_asm
```

Consumers must clone (or update) recursively so the nested `libman` and
`core` submodules come along too:

```sh
git clone --recursive <your-repo>
# or, in an existing checkout:
git submodule update --init --recursive
```

## Build integration

Add three include paths to your `sjasmplus` invocation:

```sh
sjasmplus -I extern/unet_libs_asm/include -I extern/unet_libs_asm/extern/core/bindings/asm -I extern/unet_libs_asm/extern/libman/libman ...
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

Copy `extern/core/dll/UNETESP.DLL` and `extern/core/dll/UNETRTL.DLL` next
to your built EXE (or into your distribution's floppy image / zip) - libman
resolves a plain DLL name against the EXE's own directory first (via DSS
`APPINFO`), then the current directory. You do not need to ship both if you
only target one backend, but shipping both is what lets a single EXE run
against either.

## Environment variables and memory-map rules

Both are properties of the UNET ABI itself, not this repo - see
[core's README](https://github.com/witchcraft2001/sprinter_unet_libs_core#environment-variables)
for the `NET` selection rules and bring-up tools, and
[core's memory-map rules](https://github.com/witchcraft2001/sprinter_unet_libs_core#memory-map-rules)
for the window/buffer constraints. One asm-specific addition on top of
those: for any `RST 0x10`/`RST 0x08` (DSS/BIOS) call, `SP` must be inside
`0x8000`-`0xBFFF`, and `HL'`/`DE'`/`BC'` are DSS/BIOS-reserved - never `EXX`
around a DSS call.

## Building and running the examples

```sh
make            # build all four examples into build/
make netinfo    # or just one
make check      # verify the vendored DLLs against extern/core/dll/manifest.json
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
UDPECHO <host> 7777          - pair with `python3 extern/core/tools/udp_echo.py`
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

## Maintaining the vendored DLLs and the ABI

Both now live in `sprinter_unet_libs_core` - see
[core's README](https://github.com/witchcraft2001/sprinter_unet_libs_core#maintaining-the-vendored-dlls)
for `update_dlls.sh` and the ABI source-of-truth workflow
(`abi/unet_abi.toml` + `gen_bindings.py`). Bump the `extern/core` submodule
pointer here after a core update.

## License

BSD 3-Clause, see [LICENSE](LICENSE). The vendored DLLs remain subject to
their own upstream projects' licenses - see `extern/core/dll/manifest.json`
for provenance.
