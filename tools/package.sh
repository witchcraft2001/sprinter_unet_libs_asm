#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

source "$script_dir/artifacts.sh"

if ! command -v zip >/dev/null 2>&1; then
  echo "Error: zip is not installed or not in PATH" >&2
  exit 1
fi
if ! command -v iconv >/dev/null 2>&1; then
  echo "Error: iconv is not installed or not in PATH" >&2
  exit 1
fi

package_root="$repo_root/build/package"
archive="$repo_root/distr/$DIST_NAME.zip"

rm -rf "$package_root"
mkdir -p "$package_root" "$repo_root/distr"

cp "$repo_root/build/NETINFO.EXE" "$package_root/NETINFO.EXE"
cp "$repo_root/build/PING.EXE" "$package_root/PING.EXE"
cp "$repo_root/build/HTTPGET.EXE" "$package_root/HTTPGET.EXE"
cp "$repo_root/build/UDPECHO.EXE" "$package_root/UDPECHO.EXE"
cp "$repo_root/build/UNETESP.DLL" "$package_root/UNETESP.DLL"
cp "$repo_root/build/UNETRTL.DLL" "$package_root/UNETRTL.DLL"
sed 's/$/'$'\r''/' "$repo_root/docs/README.ru.txt" |
  iconv -f UTF-8 -t CP866 > "$package_root/README.TXT"
sed 's/$/'$'\r''/' "$repo_root/docs/README.en.txt" > "$package_root/READMEEN.TXT"

rm -f "$archive"
(
  cd "$package_root"
  zip -q "$archive" "${DIST_FILES[@]}"
)

echo "Created $archive"
