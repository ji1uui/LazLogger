# Shared settings for MuninnLog build scripts. Source this file; do not run it.
# The caller must already be in the MuninnLog directory.

FPC="${FPC:-fpc}"
EXPECTED_FPC_VERSION="3.2.2"
BUILD_DIR="build"

# -Sa: assertions, -Criot: range/IO/overflow/stack checks, -gl: line info.
FPC_FLAGS=(-Mobjfpc -Sh -Sa -Criot -gl -Fusrc/core)

check_fpc_version() {
  # Native Windows compilers print CRLF; drop the CR so the comparison is shell-independent.
  local actual_version
  actual_version="$("$FPC" -iV | tr -d '\r')"
  if [ "$actual_version" != "$EXPECTED_FPC_VERSION" ]; then
    echo "Free Pascal $EXPECTED_FPC_VERSION is required, found $actual_version" >&2
    exit 1
  fi
}
