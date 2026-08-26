#!/usr/bin/env bash
# Maintainer tool: refresh vendored UNET*.DLL binaries from sibling backend
# checkouts, update dll/manifest.json, and re-run verification.
#
# Usage: tools/update_dlls.sh
# Env overrides:
#   UNETESP_SRC  path to UNETESP.DLL              (default: sibling sprinter_wifi/network checkout)
#   UNETRTL_SRC  path to UNETRTL.DLL               (default: sibling sprinter-rtl8019a checkout)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

UNETESP_SRC="${UNETESP_SRC:-$repo_root/../../sprinter_wifi/network/UNETESP.DLL}"
UNETRTL_SRC="${UNETRTL_SRC:-$repo_root/../sprinter-rtl8019a/UNETRTL.DLL}"

esp_version_file="$(dirname "$UNETESP_SRC")/UNETESP_VERSION"
rtl_version_inc="$(dirname "$UNETRTL_SRC")/src/include/version.inc"

if [[ ! -f "$UNETESP_SRC" ]]; then
    echo "error: UNETESP.DLL source not found at $UNETESP_SRC (set UNETESP_SRC)" >&2
    exit 1
fi
if [[ ! -f "$UNETRTL_SRC" ]]; then
    echo "error: UNETRTL.DLL source not found at $UNETRTL_SRC (set UNETRTL_SRC)" >&2
    exit 1
fi

cp "$UNETESP_SRC" "$repo_root/dll/UNETESP.DLL"
cp "$UNETRTL_SRC" "$repo_root/dll/UNETRTL.DLL"

esp_version="unknown"
if [[ -f "$esp_version_file" ]]; then
    esp_version="$(cat "$esp_version_file")"
fi
rtl_version="unknown"
if [[ -f "$rtl_version_inc" ]]; then
    rtl_version="$(grep -oE 'PACKAGE_VERSION "[^"]+"' "$rtl_version_inc" | sed -E 's/.*"([^"]+)"/\1/')"
fi

echo "UNETESP.DLL source version: $esp_version"
echo "UNETRTL.DLL source version: $rtl_version"
echo "Update dll/manifest.json \"version\" fields by hand if they changed."

python3 "$repo_root/tools/check_dlls.py" --update

echo
echo "Re-verifying updated DLLs..."
python3 "$repo_root/tools/check_dlls.py"

# Freeze tripwire: warn if the frozen ABI header drifted upstream.
esp_unet_inc="$(dirname "$UNETESP_SRC")/src/include/unet.inc"
local_unet_inc="$repo_root/include/unet.inc"
if [[ -f "$esp_unet_inc" && -f "$local_unet_inc" ]]; then
    if ! cmp -s "$esp_unet_inc" "$local_unet_inc"; then
        echo
        echo "WARNING: include/unet.inc differs from $esp_unet_inc" >&2
        echo "The frozen UNET ABI may have changed upstream - review before re-vendoring." >&2
    fi
fi
