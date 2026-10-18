#!/usr/bin/env bash
# Builds the MuninnLog command-line tool with Free Pascal.
# Usage: scripts/build.sh   (run from any directory; FPC can be overridden)
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/common.sh

check_fpc_version

UNIT_DIR="$BUILD_DIR/units"
mkdir -p "$UNIT_DIR"

"$FPC" "${FPC_FLAGS[@]}" -Fusrc/storage \
  -FU"$UNIT_DIR" -FE"$BUILD_DIR" \
  app/cli/muninn-cli.lpr
