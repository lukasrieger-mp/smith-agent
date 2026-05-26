#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/bin/smith_labels.sh"

# 1. Each known key prints its expected literal.
assert_eq "smith-authored"        "$(bash "$SCRIPT" PR_AUTHORED)"        "PR_AUTHORED"
assert_eq "needs-human-attention" "$(bash "$SCRIPT" PR_NEEDS_ATTENTION)" "PR_NEEDS_ATTENTION"
assert_eq "smith-implementing"    "$(bash "$SCRIPT" JIRA_IMPLEMENTING)" "JIRA_IMPLEMENTING"
assert_eq "no-auto-impl"          "$(bash "$SCRIPT" JIRA_NO_AUTO)"      "JIRA_NO_AUTO"
assert_eq "auto-impl-failed"      "$(bash "$SCRIPT" JIRA_FAILED)"       "JIRA_FAILED"

# 2. Unknown key exits non-zero with a clear message.
set +e
err=$(bash "$SCRIPT" BOGUS 2>&1 >/dev/null)
code=$?
set -e
assert_exit_code 1 "$code" "unknown key exit code"
assert_contains "$err" "unknown key: BOGUS" "unknown key error message"

# 3. No argument is a usage error.
set +e
bash "$SCRIPT" 2>/dev/null
code=$?
set -e
[[ "$code" -ne 0 ]] || { echo "FAIL: missing arg should fail" >&2; exit 1; }

# 4. Sourcing exports the SMITH_LABEL_* variables for in-process use.
(
  # shellcheck source=../bin/smith_labels.sh
  source "$SCRIPT"
  assert_eq "smith-authored"        "$SMITH_LABEL_PR_AUTHORED"        "sourced PR_AUTHORED"
  assert_eq "needs-human-attention" "$SMITH_LABEL_PR_NEEDS_ATTENTION" "sourced PR_NEEDS_ATTENTION"
  assert_eq "smith-implementing"    "$SMITH_LABEL_JIRA_IMPLEMENTING"  "sourced JIRA_IMPLEMENTING"
  assert_eq "no-auto-impl"          "$SMITH_LABEL_JIRA_NO_AUTO"       "sourced JIRA_NO_AUTO"
  assert_eq "auto-impl-failed"      "$SMITH_LABEL_JIRA_FAILED"        "sourced JIRA_FAILED"
)

echo "PASS smith_labels.test.sh"
