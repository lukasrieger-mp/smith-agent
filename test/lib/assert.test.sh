#!/usr/bin/env bash
# Self-test of assert.sh helpers.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert.sh
source "${SCRIPT_DIR}/assert.sh"

# assert_eq passes on equal values
assert_eq "hello" "hello" "eq-positive"

# assert_eq fails on unequal values (run in subshell)
if ( set -e; assert_eq "a" "b" "eq-negative" ) 2>/dev/null; then
  echo "FAIL: assert_eq should have failed on a!=b" >&2
  exit 1
fi

# assert_exit_code passes on equal codes
assert_exit_code 0 0 "code-positive"

# assert_contains passes
assert_contains "the quick brown fox" "brown" "contains-positive"

# assert_contains fails when substring missing
if ( set -e; assert_contains "abc" "xyz" "contains-negative" ) 2>/dev/null; then
  echo "FAIL: assert_contains should have failed" >&2
  exit 1
fi

echo "PASS assert.test.sh"
