#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
BUILD=$(mktemp -d /tmp/dx-bridge-tests.XXXXXX)
trap 'rm -rf "$BUILD"' EXIT HUP INT TERM
cc -std=c11 -Wall -Wextra -Werror -pedantic -O2 \
  -I"$ROOT/Sources/System" "$ROOT/Sources/System/DXABIEncoding.c" \
  "$ROOT/Sources/System/DXLeasePolicy.c" "$ROOT/Tests/Bridge/test_policy.c" -o "$BUILD/test-policy"
"$BUILD/test-policy"
python3 "$ROOT/Tests/Bridge/check_evidence.py" "$@"
