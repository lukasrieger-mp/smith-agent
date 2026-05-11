#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/monitor_jira.sh"
FIX="${SCRIPT_DIR}/fixtures"

# Run the monitor in oneshot mode against a fake working directory.
# CLAUDE_PLUGIN_ROOT points back at the real plugin source so jira_scan.sh
# can be located. The fake target's cwd is where state files land.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)

run_once() {
  ( cd "$TMP" && \
    SMITH_MONITOR_ONESHOT=1 \
    SMITH_DRY_RUN_FIXTURE="$1" \
    CLAUDE_PLUGIN_ROOT="$ROOT" \
    bash "$SCRIPT" )
}

# First run with empty fixture: no prior state, no candidates, no output expected.
got=$(run_once "${FIX}/jira-empty.json")
assert_eq "" "$got" "first-empty-no-output"

# Second run with the candidates fixture: introduces TWO new keys (APP-5601, APP-5612).
got=$(run_once "${FIX}/jira-candidates.json")
[[ "$got" == *'"smith.jira.new_candidates"'* ]] || { echo "FAIL: expected notification, got: $got" >&2; exit 1; }
[[ "$got" == *'"APP-5601"'* ]] || { echo "FAIL: missing APP-5601 in notification" >&2; exit 1; }
[[ "$got" == *'"APP-5612"'* ]] || { echo "FAIL: missing APP-5612 in notification" >&2; exit 1; }

# Third run, same fixture: no change in keys -> no output (idempotent).
got=$(run_once "${FIX}/jira-candidates.json")
assert_eq "" "$got" "third-no-change-no-output"

# Fourth run: switch to empty fixture (all candidates removed).
# Since `current - last` of an empty set vs a populated set is empty,
# no notification should fire (we only emit on NEW keys, not removed ones).
got=$(run_once "${FIX}/jira-empty.json")
assert_eq "" "$got" "fourth-keys-removed-no-output"

# State file exists and is valid JSON
[[ -f "$TMP/.smith/state/last-jira-candidates.json" ]] || { echo "FAIL: state file missing" >&2; exit 1; }
jq -e 'type == "array"' < "$TMP/.smith/state/last-jira-candidates.json" >/dev/null || { echo "FAIL: state file not valid JSON array" >&2; exit 1; }

echo "PASS monitor_jira.test.sh"
