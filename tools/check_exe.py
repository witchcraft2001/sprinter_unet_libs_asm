#!/usr/bin/env python3
"""Sanity-check a DSS EXE v1 file built by sjasmplus --raw.

Usage: check_exe.py FILE.EXE [FILE.EXE ...]
"""
import struct
import sys

HEADER_SIZE = 0x200
LOAD_ADDRESS = 0x8100


def check(path):
    with open(path, "rb") as f:
        data = f.read()

    if len(data) <= HEADER_SIZE:
        print(f"error: {path}: file too small ({len(data)} bytes)", file=sys.stderr)
        return False

    if data[0:3] != b"EXE" or data[3] != 1:
        print(f"error: {path}: bad signature {data[0:4]!r}", file=sys.stderr)
        return False

    (hdr_size,) = struct.unpack_from("<I", data, 4)
    if hdr_size != HEADER_SIZE:
        print(f"error: {path}: header size 0x{hdr_size:X}, expected 0x{HEADER_SIZE:X}", file=sys.stderr)
        return False

    load, entry, stack = struct.unpack_from("<HHH", data, 0x10)
    ok = True
    if load != LOAD_ADDRESS:
        print(f"error: {path}: load address 0x{load:04X}, expected 0x{LOAD_ADDRESS:04X}", file=sys.stderr)
        ok = False
    if entry != LOAD_ADDRESS:
        print(f"error: {path}: entry point 0x{entry:04X}, expected 0x{LOAD_ADDRESS:04X}", file=sys.stderr)
        ok = False
    if not (LOAD_ADDRESS < stack <= 0xC000):
        print(f"error: {path}: stack 0x{stack:04X} outside (0x{LOAD_ADDRESS:04X}, 0xC000]", file=sys.stderr)
        ok = False

    image_size = len(data) - HEADER_SIZE
    image_end = LOAD_ADDRESS + image_size
    if image_end > 0xC000:
        print(f"error: {path}: image end 0x{image_end:04X} exceeds 0xC000", file=sys.stderr)
        ok = False

    if ok:
        print(f"{path}: ok (load=entry=0x{load:04X} stack=0x{stack:04X} image_end=0x{image_end:04X})")
    return ok


def main():
    if len(sys.argv) < 2:
        print("usage: check_exe.py FILE.EXE [FILE.EXE ...]", file=sys.stderr)
        return 1
    ok = True
    for path in sys.argv[1:]:
        if not check(path):
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
