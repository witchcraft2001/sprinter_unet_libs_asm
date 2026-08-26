#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

source "$script_dir/artifacts.sh"

for tool in mformat mcopy mdir iconv; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: $tool is not installed or not in PATH" >&2
    exit 1
  fi
done

image="$repo_root/distr/$DIST_NAME.img"
stage="$repo_root/build/image"

rm -rf "$stage"
mkdir -p "$stage" "$repo_root/distr"

cp "$repo_root/build/NETINFO.EXE" "$stage/NETINFO.EXE"
cp "$repo_root/build/PING.EXE" "$stage/PING.EXE"
cp "$repo_root/build/HTTPGET.EXE" "$stage/HTTPGET.EXE"
cp "$repo_root/build/UDPECHO.EXE" "$stage/UDPECHO.EXE"
cp "$repo_root/build/UNETESP.DLL" "$stage/UNETESP.DLL"
cp "$repo_root/build/UNETRTL.DLL" "$stage/UNETRTL.DLL"
sed 's/$/'$'\r''/' "$repo_root/docs/README.ru.txt" |
  iconv -f UTF-8 -t CP866 > "$stage/README.TXT"
sed 's/$/'$'\r''/' "$repo_root/docs/README.en.txt" > "$stage/READMEEN.TXT"

rm -f "$image"
mformat -C -f 1440 -v UNETLIBS -i "$image" ::
for artifact in "${DIST_FILES[@]}"; do
  mcopy -o -i "$image" "$stage/$artifact" "::$artifact"
done

listing="$(mdir -b -i "$image" ::)"
for artifact in "${DIST_FILES[@]}"; do
  if ! grep -q "/$artifact$" <<< "$listing"; then
    echo "Error: $artifact is missing from FAT12 image" >&2
    exit 1
  fi
done

echo "Created FAT12 image: $image"
