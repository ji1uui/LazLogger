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
# ${args[@]+...}: macOS bash 3.2 treats an empty array as unset under set -u.
"$LAZBUILD" ${args[@]+"${args[@]}"} app/gui/muninn-gui.lpi
