#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
build_dir="$repo_root/build"
target="${1:-all}"

if ! command -v sjasmplus >/dev/null 2>&1; then
  echo "Error: sjasmplus is not installed or not in PATH" >&2
  exit 1
fi

libman_asm="$repo_root/extern/libman/libman/libman.asm"
if [[ ! -f "$libman_asm" ]]; then
  echo "Error: $libman_asm not found." >&2
  echo "Run: git submodule update --init --recursive" >&2
  exit 1
fi

"$script_dir/check_dlls.py"

mkdir -p "$build_dir"

build_example() {
  local name="$1"
  local dir="$2"
  sjasmplus --nologo --fullpath \
    -I "$repo_root/include" -I "$repo_root/examples/common" -I "$repo_root/extern/libman/libman" \
    --lst="$build_dir/$name.lst" --sym="$build_dir/$name.sym" \
    --raw="$build_dir/$name.EXE" "$repo_root/examples/$dir/$dir.asm"
  "$script_dir/check_exe.py" "$build_dir/$name.EXE"
}

case "$target" in
  netinfo) build_example NETINFO netinfo ;;
  ping)    build_example PING ping ;;
  httpget) build_example HTTPGET httpget ;;
  udpecho) build_example UDPECHO udpecho ;;
  all)
    build_example NETINFO netinfo
    build_example PING ping
    build_example HTTPGET httpget
    build_example UDPECHO udpecho
    ;;
  *)
    echo "Usage: $0 [all|netinfo|ping|httpget|udpecho]" >&2
    exit 2
    ;;
esac

cp "$repo_root/dll/UNETESP.DLL" "$build_dir/UNETESP.DLL"
cp "$repo_root/dll/UNETRTL.DLL" "$build_dir/UNETRTL.DLL"
