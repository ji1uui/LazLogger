#!/usr/bin/env bash
# Builds the MuninnLog command-line tool with Free Pascal.
# Usage: scripts/build.sh   (run from any directory; FPC can be overridden)
set -euo pipefail

cd "$(dirname "$0")/.."

FPC="${FPC:-fpc}"
EXPECTED_FPC_VERSION="3.2.2"
BUILD_DIR="build"
UNIT_DIR="$BUILD_DIR/units"

actual_version="$("$FPC" -iV)"
if [ "$actual_version" != "$EXPECTED_FPC_VERSION" ]; then
  echo "Free Pascal $EXPECTED_FPC_VERSION is required, found $actual_version" >&2
  exit 1
fi

mkdir -p "$UNIT_DIR"

# -Sa: assertions, -Criot: range/IO/overflow/stack checks, -gl: line info.
"$FPC" -Mobjfpc -Sh -Sa -Criot -gl \
  -Fusrc/core \
  -FU"$UNIT_DIR" -FE"$BUILD_DIR" \
  app/cli/muninn-cli.lpr
