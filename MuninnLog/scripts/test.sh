#!/usr/bin/env bash
# Builds and runs the MuninnLog unit tests with FPCUnit.
# Usage: scripts/test.sh   (run from any directory; FPC can be overridden)
# Set MUNINN_TEST_XML=<path> to also write the results as FPCUnit XML.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/common.sh

check_fpc_version

TEST_DIR="$BUILD_DIR/tests"
UNIT_DIR="$TEST_DIR/units"
mkdir -p "$UNIT_DIR"

"$FPC" "${FPC_FLAGS[@]}" -Futests/unit \
  -FU"$UNIT_DIR" -FE"$TEST_DIR" \
  tests/unit/muninn-unit-tests.lpr

# The FPCUnit console runner exits with 1 when any test fails or errors.
"./$TEST_DIR/muninn-unit-tests" --all --format=plain

if [ -n "${MUNINN_TEST_XML:-}" ]; then
  mkdir -p "$(dirname "$MUNINN_TEST_XML")"
  "./$TEST_DIR/muninn-unit-tests" --all --format=xml --file="$MUNINN_TEST_XML" > /dev/null
fi
