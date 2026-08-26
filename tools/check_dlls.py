#!/usr/bin/env python3
"""Verify vendored UNET*.DLL binaries against dll/manifest.json.

Checks that every DLL listed in the manifest exists, matches the recorded
size and SHA-256, and passes `sprinter_mkdll verify` (from the libman
submodule). With --update, recomputes size/sha256 in place instead of
checking them (version/source/tag/caps are left untouched).
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DLL_DIR = REPO_ROOT / "dll"
MANIFEST_PATH = DLL_DIR / "manifest.json"
LIBMAN_SRC = REPO_ROOT / "extern" / "libman" / "src"


def sha256_of(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def run_mkdll_verify(dll_path):
    if not LIBMAN_SRC.is_dir():
        print(
            f"error: {LIBMAN_SRC} not found - run "
            "'git submodule update --init --recursive'",
            file=sys.stderr,
        )
        return False
    full_env = dict(os.environ)
    full_env["PYTHONPATH"] = str(LIBMAN_SRC)
    proc = subprocess.run(
        [sys.executable, "-m", "sprinter_mkdll.cli", "verify", str(dll_path), "--target", "1.3"],
        env=full_env,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        print(f"error: sprinter_mkdll verify failed for {dll_path.name}:", file=sys.stderr)
        print(proc.stdout, file=sys.stderr)
        print(proc.stderr, file=sys.stderr)
        return False
    print(proc.stdout.strip())
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--update", action="store_true", help="recompute size/sha256 in the manifest instead of checking them"
    )
    args = parser.parse_args()

    if not MANIFEST_PATH.is_file():
        print(f"error: manifest not found at {MANIFEST_PATH}", file=sys.stderr)
        return 1

    manifest = json.loads(MANIFEST_PATH.read_text())
    ok = True

    for name, entry in manifest.items():
        dll_path = DLL_DIR / name
        if not dll_path.is_file():
            print(f"error: {name} missing at {dll_path}", file=sys.stderr)
            ok = False
            continue

        size = dll_path.stat().st_size
        digest = sha256_of(dll_path)

        if args.update:
            entry["size"] = size
            entry["sha256"] = digest
            print(f"{name}: updated size={size} sha256={digest}")
            continue

        if size != entry["size"]:
            print(
                f"error: {name} size mismatch: manifest={entry['size']} actual={size}",
                file=sys.stderr,
            )
            ok = False
        if digest != entry["sha256"]:
            print(
                f"error: {name} sha256 mismatch:\n  manifest={entry['sha256']}\n  actual  ={digest}",
                file=sys.stderr,
            )
            ok = False
        if size == entry["size"] and digest == entry["sha256"]:
            print(f"{name}: size and sha256 match manifest")

        if not run_mkdll_verify(dll_path):
            ok = False

    if args.update:
        MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"manifest updated: {MANIFEST_PATH}")

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
