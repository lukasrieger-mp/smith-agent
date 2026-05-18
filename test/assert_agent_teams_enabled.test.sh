#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/bin/assert_agent_teams_enabled.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)

# Case 1: env var set → exit 0
out=$(CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 HOME="$TMP" bash "$SCRIPT" 2>&1)
ec=$?
assert_eq "0" "$ec" "env-set-passes"
assert_eq "" "$out" "no stderr when passing"

# Case 2: settings.json has the flag → exit 0
mkdir -p "$TMP/.claude"
echo '{"env":{"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS":"1"}}' > "$TMP/.claude/settings.json"
unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
HOME="$TMP" bash "$SCRIPT" > /dev/null 2>&1
ec=$?
assert_eq "0" "$ec" "settings-set-passes"

# Case 3: neither env nor settings → exit 1 with the fix hint
rm -f "$TMP/.claude/settings.json"
set +e
out=$(unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS; HOME="$TMP" bash "$SCRIPT" 2>&1)
ec=$?
set -e
assert_eq "1" "$ec" "missing-flag-fails"
[[ "$out" == *"agent-teams not enabled"* ]] \
  || { echo "FAIL: error message missing 'agent-teams not enabled' in: $out" >&2; exit 1; }
[[ "$out" == *"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"* ]] \
  || { echo "FAIL: error message missing flag name in: $out" >&2; exit 1; }

# Case 4: settings.json exists but flag is missing → exit 1
echo '{"env":{"SOMETHING_ELSE":"x"}}' > "$TMP/.claude/settings.json"
set +e
HOME="$TMP" bash "$SCRIPT" > /dev/null 2>&1
ec=$?
set -e
assert_eq "1" "$ec" "settings-without-flag-fails"

echo "PASS assert_agent_teams_enabled.test.sh"
