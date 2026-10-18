#!/usr/bin/env bash
# Builds and runs the MuninnLog tests with FPCUnit: unit tests, then
# integration tests (these need the SQLite library; see ADR 0003).
# Usage: scripts/test.sh   (run from any directory; FPC can be overridden)
# Set MUNINN_TEST_RESULTS_DIR=<dir> to also write the results as FPCUnit XML
# (unit.xml and integration.xml).
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

# The CLI tests run build/muninn-cli.
scripts/build.sh

"$FPC" "${FPC_FLAGS[@]}" -Fusrc/storage -Futests/integration \
  -FU"$UNIT_DIR" -FE"$TEST_DIR" \
  tests/integration/muninn-crash-helper.lpr

"$FPC" "${FPC_FLAGS[@]}" -Fusrc/storage -Futests/integration \
  -FU"$UNIT_DIR" -FE"$TEST_DIR" \
  tests/integration/muninn-integration-tests.lpr

# The FPCUnit console runner exits with 1 when any test fails or errors.
# Run every suite and keep the first failing status, but still write the XML
# results: they matter most on failure.
status=0
run_suite() {
  local name="$1"
  "./$TEST_DIR/muninn-$name-tests" --all --format=plain || {
    local code=$?
    if [ "$status" -eq 0 ]; then status=$code; fi
  }
  if [ -n "${MUNINN_TEST_RESULTS_DIR:-}" ]; then
    mkdir -p "$MUNINN_TEST_RESULTS_DIR"
    "./$TEST_DIR/muninn-$name-tests" --all --format=xml \
      --file="$MUNINN_TEST_RESULTS_DIR/$name.xml" > /dev/null || true
  fi
}

run_suite unit
run_suite integration

exit "$status"
