# Repository guidelines

## Project scope

`sprinter_unet_libs_asm` is the SjASMPlus/Z80 assembly binding for the
Sprinter DSS UNET network interface. It provides `include/unetld.asm`, a
loader/selector which reads the `NET` environment variable, loads the matching
network DLL through libman, verifies its ABI, and exposes UNET call and
lifecycle helpers. The repository also contains runnable DSS EXE examples:
`NETINFO`, `PING`, `HTTPGET`, and `UDPECHO`.

This repository is a consumer binding, not the owner of the network ABI or
backend implementations. Preserve the frozen ABI and keep the loader generic:
a normal backend is selected as `NET=<TAG>` and loaded as `UNET<TAG>.DLL`;
`WIFI -> UNETESP.DLL` is the intentional compatibility alias. `NET` is
published by a backend bring-up tool, not set by consumer programs.

## Layout and ownership

- `include/unetld.asm` is the assembly-specific UNETLD implementation.
- `include/dss.inc` contains the deliberately small DSS surface needed by this
  binding and its examples; do not turn it into a merged copy of backend
  projects' diverged headers.
- `examples/` contains application sources; `examples/common/` contains shared
  EXE-header and console helpers.
- `docs/UNETLD.md` and `docs/UNETLDRU.md` are the assembly-specific loader
  reference; `README.md` / `READMERU.md` explain use and distribution.
- `extern/core` is a git submodule holding the ABI source, generated headers,
  API/behavior documentation, and vendored `UNETESP.DLL` / `UNETRTL.DLL`.
- `extern/libman` is a git submodule supplying the DLL loader and dispatcher
  included by applications.
- `tools/` builds EXEs, validates their header, and creates distribution
  artifacts. `build/` and `distr/` are generated and must not be committed.

## ABI, memory, and lifecycle rules

Treat `extern/core/abi/unet_abi.toml` as the source of truth for function
numbers, statuses, capability bits, and UNETLD error/flag values.
`extern/core/bindings/asm/unet.inc` is generated: edit the TOML in the core
repository and regenerate there; never hand-edit the generated include here.
The language-neutral behavior contract is `extern/core/docs/UNETLD-SPEC.md`,
while this repository documents only its assembly-specific interface.

UNET functions receive arguments in `A`/`DE`/`IX`/`IY` and return their status
in `A`; do not infer a function failure from carry. Carry from `UNETLD.CALL`
only reports a libman dispatcher failure. Load a backend only in window 1 or
2, never window 3. Caller buffers must be wholly below `0xC000` and outside
the loaded DLL window. Keep at least about 256 bytes of stack free over a
call.

For DSS/BIOS `RST #10` (and `RST #08`) calls, keep `SP` in `0x8000..0xBFFF`
and never use `EXX` around the call: `HL'`, `DE'`, and `BC'` are reserved by
DSS/BIOS. `ENV_GET` requires a 256-byte destination buffer.

`unetld.asm` has two state-placement modes. The default emits zeroed state
inside the EXE. With `UNETLD_STATE_BASE`, no state is emitted, so the caller
must own the area below `0xC000` and call `UNETLD.RESET` before every other
UNETLD entry point. In either mode, unload an opened DLL on every exit path;
after a `LOAD` failure other than `UNETLD_E_LOAD`, call `UNLOAD` before retry
or exit.

## Assembly style

Use SjASMPlus syntax and match the existing source style:

- Indent instructions and directives with spaces; use uppercase mnemonics,
  registers, directives, and symbolic constants.
- Use descriptive uppercase global labels and short dotted local labels. Keep
  labels and data aligned as in the surrounding source.
- Use `EQU` for named constants, hexadecimal values with the existing `0...h`
  convention, and symbolic DSS/UNET/libman constants rather than raw numbers.
- Keep `MODULE` boundaries intact. `unetld.asm` opens `MODULE UNETLD`, so
  include it outside an application's own module, as the examples do.
- Write concise `;` comments for non-obvious contracts, register clobbers,
  state ownership, and hardware/DSS constraints. Keep English and Russian
  documentation counterparts consistent when changing user-visible behavior.
- Preserve guards on includes and public labels/register contracts. Prefer a
  focused helper near its caller over an unrelated general-purpose include.

## Build and verification

Initialize both submodules before building:

```sh
git submodule update --init --recursive
```

```sh
make              # build all four EXE examples into build/
make netinfo      # build one example (also: ping, httpget, udpecho)
make check        # validate vendored DLL hashes and libman structure
make package      # build and create distr/unet_libs_asm.zip
make image        # build and create distr/unet_libs_asm.img
```

`sjasmplus` must be on `PATH`; `make image` additionally requires `mtools`
and `iconv`. Run the focused build after assembly changes, `make check` when
touching the core/DLL relationship, and `make package` plus `make image` for
changes that affect shipped examples, DLLs, documentation, or packaging. Do
not hand-edit artifacts produced under `build/` or `distr/`.

## Relationships to sibling projects

- [`unet_libs_core`](https://github.com/witchcraft2001/unet_libs_core)
  (`extern/core`) is shared by the assembly, Pascal, and Solid C bindings.
  Update its submodule pointer deliberately after a core change; it owns the
  vendored DLL manifest and ABI generation.
- `sprinter-rtl8019a` implements the RTL8019AS/DP8390 backend and publishes
  `NET=RTL` through `NETCFG -i` plus `IFUP`; its `UNETRTL.DLL` is vendored by
  core. Use it to understand or diagnose the Ethernet backend, not as a source
  for copying ABI constants.
- The Wi-Fi/ESP backend produces `UNETESP.DLL` and publishes `NET=WIFI`
  through `NETUP`; consumers should remain backend-neutral.
- `extern/libman` is the common libman L1 loader/dispatcher. An application
  includes `libman.asm` itself, chooses `LIBMAN_MAX_LIBS`, and can load its
  own DLLs alongside UNETLD.
- `Estex-DSS` is the DSS/boot/shell implementation; `sprinter_bios` is the
  BIOS/ROM implementation. They are platform references, not dependencies to
  vendor or modify from this repository.
- `gifview` and `sprinter-unzip` are practical SjASMPlus DSS EXE references,
  especially for EXE layout, cache/window discipline, packaging, and testing.

## Documentation and open-source reference sources

Use these paths as read-only sources for platform facts and implementation
ideas. This repository and its submodules remain authoritative for changes
made here.

- `/Users/dmitry/dev/zx/sprinter/sprinter_ai_doc/manual` — primary local Z80
  programmer manual. Start with `01_architecture/03_memory_map.md`,
  `04_dss/02_dss_api.md`, `04_dss/04_dss_memory.md`, and
  `04_dss/05_dss_exe.md`; consult other sections for BIOS, ports, ISA,
  interrupts, and hardware behavior.
- `/Users/dmitry/dev/zx/sprinter/sprinter-rtl8019a` — open RTL8019A backend,
  network utilities, UNETRTL DLL source, and `docs/UNETRTL.md` / network
  testing documentation.
- `/Users/dmitry/dev/zx/sprinter/gifview` — open SjASMPlus DSS application
  demonstrating EXE construction, cache/Win0 code, and FAT12 packaging.
- `/Users/dmitry/dev/zx/sprinter/Estex-DSS` — open DSS, bootloader, and shell
  source; consult it for OS API behavior, filesystem, and executable details.
- `/Users/dmitry/dev/zx/sprinter/sprinter_bios` — open BIOS/ROM source and
  memory-map material; consult it for BIOS calls and low-level hardware facts.
- `/Users/dmitry/dev/zx/sprinter/sources/sprinter-unzip` — open DSS utility
  using SjASMPlus, DeZog, EXE headers, SRAM cache, and disk-image workflow.

## Commit rule

Never add a `Co-Authored-By: Claude ...` (or similar AI-attribution) trailer
to commit messages in this repository. Commit messages must end with the last
line of actual content.
