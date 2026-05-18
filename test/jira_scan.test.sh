#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/bin/jira_scan.sh"
FIX="${SCRIPT_DIR}/fixtures"

# Stub mode returns the fixture content verbatim.
got=$(SMITH_DRY_RUN_FIXTURE="${FIX}/jira-candidates.json" bash "$SCRIPT")
expected=$(cat "${FIX}/jira-candidates.json")
assert_eq "$expected" "$got" "stub-mode-candidates"

# Empty fixture yields empty array.
got=$(SMITH_DRY_RUN_FIXTURE="${FIX}/jira-empty.json" bash "$SCRIPT")
assert_eq "[]" "$got" "stub-mode-empty"

# Output is always a JSON array (validated via jq).
echo "$got" | jq -e 'type == "array"' >/dev/null

# Missing fixture path -> non-zero exit.
if SMITH_DRY_RUN_FIXTURE=/no/such/file bash "$SCRIPT" 2>/dev/null; then
  echo "FAIL: should error on missing fixture" >&2; exit 1
fi

echo "PASS jira_scan.test.sh"
