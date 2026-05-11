#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/pr_fix_cycle_inc.sh"

# Stage a target directory (no git init needed — script operates relative
# to the directory it's run in by reading SMITH_PR_STATE_DIR or computing
# it from git toplevel).
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
git -C "$TMP" init -q
git -C "$TMP" commit --allow-empty -m initial -q
cd "$TMP"

# First call: counter starts at 1
got=$(bash "$SCRIPT" 4321 PRRT_thread1)
assert_eq "1" "$got" "first-inc"

# State file created at .smith/state/pr-4321.json
state_file=".smith/state/pr-4321.json"
[[ -f "$state_file" ]] || { echo "FAIL: state file not created" >&2; exit 1; }
jq -e '.fix_cycles_per_thread.PRRT_thread1 == 1' "$state_file" >/dev/null \
  || { echo "FAIL: state file content wrong" >&2; cat "$state_file" >&2; exit 1; }

# Second call: counter is now 2
got=$(bash "$SCRIPT" 4321 PRRT_thread1)
assert_eq "2" "$got" "second-inc"
got=$(bash "$SCRIPT" 4321 PRRT_thread1)
assert_eq "3" "$got" "third-inc"

# Different thread on same PR: independent counter
got=$(bash "$SCRIPT" 4321 PRRT_thread2)
assert_eq "1" "$got" "thread2-independent"
got=$(bash "$SCRIPT" 4321 PRRT_thread1)
assert_eq "4" "$got" "thread1-continues"

# Different PR: own state file
got=$(bash "$SCRIPT" 5555 PRRT_thread1)
assert_eq "1" "$got" "different-pr"
[[ -f ".smith/state/pr-5555.json" ]] || { echo "FAIL: pr-5555 state file missing" >&2; exit 1; }

# State file is valid JSON
jq -e '.' "$state_file" >/dev/null || { echo "FAIL: state file not valid JSON" >&2; exit 1; }

# The PR key field is set
jq -e '.pr == 4321' "$state_file" >/dev/null \
  || { echo "FAIL: pr field missing or wrong" >&2; cat "$state_file" >&2; exit 1; }

# last_polled is updated
jq -e '.last_polled | type == "string"' "$state_file" >/dev/null \
  || { echo "FAIL: last_polled missing" >&2; exit 1; }

# Missing args
if bash "$SCRIPT" 2>/dev/null; then echo "FAIL: no args" >&2; exit 1; fi
if bash "$SCRIPT" 4321 2>/dev/null; then echo "FAIL: missing thread id" >&2; exit 1; fi

echo "PASS pr_fix_cycle_inc.test.sh"
