#!/usr/bin/env bash

# Single source of truth for all runtime artifacts, shared by image.sh and
# package.sh.
DIST_NAME="${DIST_NAME:-unet_libs}"
DIST_FILES=(
  "NETINFO.EXE"
  "PING.EXE"
  "HTTPGET.EXE"
  "UDPECHO.EXE"
  "UNETESP.DLL"
  "UNETRTL.DLL"
  "README.TXT"
  "READMEEN.TXT"
)
