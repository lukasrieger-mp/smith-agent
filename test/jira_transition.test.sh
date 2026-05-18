#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/bin/jira_transition.sh"

# Stage a temp dir with a fake-acli on PATH so we never touch real JIRA.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
mkdir -p "$TMP/bin"
cp "${SCRIPT_DIR}/lib/fake_acli.sh" "$TMP/bin/acli"
chmod +x "$TMP/bin/acli"

export PATH="$TMP/bin:$PATH"
export SMITH_FAKE_ACLI_LOG="$TMP/acli.log"

# Case 1: happy path without pre-check — fake acli just logs the transition call
> "$TMP/acli.log"
unset SMITH_EXPECTED_FROM_STATUS || true
bash "$SCRIPT" APP-1234 "In Progress"
got=$(cat "$TMP/acli.log")
assert_contains "$got" "jira workitem transition --key APP-1234 --status In Progress --yes" "happy-path"

# Case 2: pre-check passes (current status matches expected)
echo '{"fields":{"status":{"name":"Ready for Development"}}}' > "$TMP/view.json"
export SMITH_FAKE_ACLI_VIEW_FIXTURE="$TMP/view.json"
> "$TMP/acli.log"
SMITH_EXPECTED_FROM_STATUS="Ready for Development" bash "$SCRIPT" APP-1234 "In Progress"
got=$(cat "$TMP/acli.log")
assert_contains "$got" "transition" "pre-check-match-transitions"
# The view call was made first
assert_contains "$got" "view APP-1234" "pre-check-viewed-first"

# Case 3: pre-check rejects (current status does NOT match expected)
echo '{"fields":{"status":{"name":"Done"}}}' > "$TMP/view.json"
> "$TMP/acli.log"
if SMITH_EXPECTED_FROM_STATUS="Ready for Development" bash "$SCRIPT" APP-1234 "In Progress" 2>/dev/null; then
  echo "FAIL: should reject on status mismatch" >&2; exit 1
fi
# Transition should NOT have been called
grep -q "transition" "$TMP/acli.log" && { echo "FAIL: transition was called despite mismatch" >&2; exit 1; }
# View was called (the check happened)
assert_contains "$(cat "$TMP/acli.log")" "view APP-1234" "pre-check-still-viewed"

# Case 4: missing required args -> non-zero
if bash "$SCRIPT" 2>/dev/null; then
  echo "FAIL: should error on missing args" >&2; exit 1
fi
if bash "$SCRIPT" APP-1234 2>/dev/null; then
  echo "FAIL: should error on missing status" >&2; exit 1
fi

echo "PASS jira_transition.test.sh"
