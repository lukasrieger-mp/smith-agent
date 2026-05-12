#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/active_smiths.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
git -C "$TMP" init -q
git -C "$TMP" commit --allow-empty -m initial -q
cd "$TMP"

# Initially: count is 0, list is []
got=$(bash "$SCRIPT" count)
assert_eq "0" "$got" "initial-count-zero"
got=$(bash "$SCRIPT" list)
assert_eq "[]" "$got" "initial-list-empty"

# Add an impl-mode pair
bash "$SCRIPT" add smith-APP-1234 anderson-APP-1234 impl APP-1234
got=$(bash "$SCRIPT" count)
assert_eq "1" "$got" "count-after-one-add"

# Verify schema of the entry
got=$(bash "$SCRIPT" list)
echo "$got" | jq -e 'length == 1
  and .[0].smith_name == "smith-APP-1234"
  and .[0].anderson_name == "anderson-APP-1234"
  and .[0].mode == "impl"
  and .[0].subject == "APP-1234"
  and (.[0].spawned_at | type == "string")
' >/dev/null || { echo "FAIL: schema check failed: $got" >&2; exit 1; }

# Per-role count subcommand.
got=$( cd "$TMP" && bash "$SCRIPT" count impl )
assert_eq "1" "$got" "count impl after one impl add"

got=$( cd "$TMP" && bash "$SCRIPT" count fixer )
assert_eq "0" "$got" "count fixer when no fixer added"

# Add a fixer entry, then re-check.
( cd "$TMP" && bash "$SCRIPT" add smith-fixer-891 anderson-fixer-891 fixer 891 )
got=$( cd "$TMP" && bash "$SCRIPT" count fixer )
assert_eq "1" "$got" "count fixer after fixer add"
got=$( cd "$TMP" && bash "$SCRIPT" count impl )
assert_eq "1" "$got" "count impl unchanged"
got=$( cd "$TMP" && bash "$SCRIPT" count )
assert_eq "2" "$got" "total count = 2"

# Remove the fixer pair to keep the rest of the test consistent with
# the original flow (which expected 2 active pairs at this point).
bash "$SCRIPT" remove smith-fixer-891

# Add a fixer pair (the PR-fix subject)
bash "$SCRIPT" add smith-pr-4321 anderson-pr-4321 fixer 4321
got=$(bash "$SCRIPT" count)
assert_eq "2" "$got" "count-after-two-adds"

# Adding a duplicate smith_name should fail (deterministic names imply
# at most one active pair per subject)
if bash "$SCRIPT" add smith-APP-1234 anderson-x impl APP-1234 2>/dev/null; then
  echo "FAIL: should reject duplicate smith_name" >&2; exit 1
fi

# Remove the ticket pair
bash "$SCRIPT" remove smith-APP-1234
got=$(bash "$SCRIPT" count)
assert_eq "1" "$got" "count-after-remove"
echo "$(bash "$SCRIPT" list)" | jq -e 'all(.smith_name != "smith-APP-1234")' >/dev/null \
  || { echo "FAIL: removed entry still present" >&2; exit 1; }

# Remove a non-existent name: no-op, exit 0
bash "$SCRIPT" remove smith-not-real
got=$(bash "$SCRIPT" count)
assert_eq "1" "$got" "count-unchanged-after-noop-remove"

# `has-subject` subcommand — returns 0 if subject is active, 1 otherwise
bash "$SCRIPT" has-subject 4321
assert_exit_code 0 $? "has-subject-true"
if bash "$SCRIPT" has-subject APP-1234 2>/dev/null; then
  echo "FAIL: APP-1234 should not be active anymore" >&2; exit 1
fi

# State file location is .smith/state/active-smiths.json
[[ -f ".smith/state/active-smiths.json" ]] || { echo "FAIL: state file not in expected location" >&2; exit 1; }

# Missing/invalid subcommand -> non-zero
if bash "$SCRIPT" bogus 2>/dev/null; then echo "FAIL: bogus subcommand" >&2; exit 1; fi
if bash "$SCRIPT" 2>/dev/null; then echo "FAIL: no subcommand" >&2; exit 1; fi

echo "PASS active_smiths.test.sh"
