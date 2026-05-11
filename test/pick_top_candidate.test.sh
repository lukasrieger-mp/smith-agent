#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/pick_top_candidate.sh"

# We need a working dir with an active-smiths state file to test the
# "skip already-active subjects" branch.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
git -C "$TMP" init -q
git -C "$TMP" commit --allow-empty -m initial -q
cd "$TMP"

# Two candidates from a fresh JIRA scan (already sorted per the JQL).
candidates='[
  {"key":"APP-5601","summary":"Hide skeleton loader","components":["Android"],"priority":"Medium","story_points":1,"sprint":"SPRINT 150"},
  {"key":"APP-5612","summary":"Localize snackbar","components":["Shared/KMP"],"priority":"High","story_points":2,"sprint":"SPRINT 150"}
]'

# Case 1: no active subjects → pick the first
got=$(echo "$candidates" | bash "$SCRIPT")
assert_eq "APP-5601" "$got" "case1-pick-first"

# Case 2: top candidate already active → pick next
bash "${ROOT}/scripts/active_smiths.sh" add smith-APP-5601 anderson-APP-5601 ticket APP-5601
got=$(echo "$candidates" | bash "$SCRIPT")
assert_eq "APP-5612" "$got" "case2-skip-active"

# Case 3: all candidates already active → exit 1 (no candidate, signal to caller)
bash "${ROOT}/scripts/active_smiths.sh" add smith-APP-5612 anderson-APP-5612 ticket APP-5612
if echo "$candidates" | bash "$SCRIPT" 2>/dev/null; then
  echo "FAIL: should exit non-zero when no eligible candidate" >&2; exit 1
fi

# Case 4: empty input → exit 1
bash "${ROOT}/scripts/active_smiths.sh" remove smith-APP-5601
bash "${ROOT}/scripts/active_smiths.sh" remove smith-APP-5612
if echo "[]" | bash "$SCRIPT" 2>/dev/null; then
  echo "FAIL: empty input should exit non-zero" >&2; exit 1
fi

# Case 5: malformed JSON → exit 1
if echo "not json" | bash "$SCRIPT" 2>/dev/null; then
  echo "FAIL: bad json should exit non-zero" >&2; exit 1
fi

echo "PASS pick_top_candidate.test.sh"
