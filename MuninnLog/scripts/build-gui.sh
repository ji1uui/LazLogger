#!/usr/bin/env bash
# Builds the UI prototype build/muninn-gui with lazbuild (Lazarus 4.4, ADR 0009).
# Usage: scripts/build-gui.sh   (run from any directory)
# LAZBUILD=<path> picks lazbuild (default: lazbuild on PATH);
# LAZARUS_DIR=<dir> passes --lazarusdir to it.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/common.sh

check_fpc_version

LAZBUILD="${LAZBUILD:-lazbuild}"
args=()
if [ -n "${LAZARUS_DIR:-}" ]; then
  args+=("--lazarusdir=$LAZARUS_DIR")
fi
# Apple's current linker (ld-prime) crashes on the resource object FPC 3.2.2
# writes ("no platform load command found", then a segfault on the macos-15
# runner); the classic linker accepts it.
if [ "$(uname -s)" = Darwin ]; then
  args+=("--opt=-k-ld_classic")
fi
# ${args[@]+...}: macOS bash 3.2 treats an empty array as unset under set -u.
"$LAZBUILD" ${args[@]+"${args[@]}"} app/gui/muninn-gui.lpi
