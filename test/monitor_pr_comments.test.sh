#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/monitor_pr_comments.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)

# Stage fixtures: one open PR
mkdir -p "$TMP/threads-r1" "$TMP/threads-r2" "$TMP/threads-r3"
cat > "$TMP/prs.json" <<'EOF'
[{"number": 4321, "headRefName": "task/app-1234-foo"}]
EOF

# Round 1: PR has no unresolved threads
echo '[]' > "$TMP/threads-r1/pr-4321.json"

# Round 2: PR has 2 unresolved threads (new comments)
echo '["thread-A","thread-B"]' > "$TMP/threads-r2/pr-4321.json"

# Round 3: PR still has the same 2 threads (no change)
echo '["thread-A","thread-B"]' > "$TMP/threads-r3/pr-4321.json"

run_once() {
  ( cd "$TMP" && \
    SMITH_MONITOR_ONESHOT=1 \
    SMITH_DRY_RUN_PRS_FIXTURE="$TMP/prs.json" \
    SMITH_DRY_RUN_PR_THREADS_DIR="$1" \
    bash "$SCRIPT" )
}

# Round 1: empty threads, no notification expected (and no prior state).
got=$(run_once "$TMP/threads-r1")
assert_eq "" "$got" "round-1-empty"

# Round 2: threads appear, expect a notification.
got=$(run_once "$TMP/threads-r2")
[[ "$got" == *'"smith.pr.new_comments"'* ]] || { echo "FAIL: expected notification, got: $got" >&2; exit 1; }
[[ "$got" == *'"pr":4321'* ]] || { echo "FAIL: missing pr key, got: $got" >&2; exit 1; }
[[ "$got" == *'"new_count":2'* ]] || { echo "FAIL: wrong new_count, got: $got" >&2; exit 1; }
[[ "$got" == *'"branch":"task/app-1234-foo"'* ]] || { echo "FAIL: missing branch, got: $got" >&2; exit 1; }

# Round 3: no change in threads, no notification.
got=$(run_once "$TMP/threads-r3")
assert_eq "" "$got" "round-3-no-change"

# State file landed
[[ -f "$TMP/.smith/state/pr-comments/pr-4321.json" ]] || { echo "FAIL: state file missing" >&2; exit 1; }

# Empty PR list -> no error, no output
echo '[]' > "$TMP/no-prs.json"
got=$( ( cd "$TMP" && \
  SMITH_MONITOR_ONESHOT=1 \
  SMITH_DRY_RUN_PRS_FIXTURE="$TMP/no-prs.json" \
  SMITH_DRY_RUN_PR_THREADS_DIR="$TMP/threads-r1" \
  bash "$SCRIPT" ) )
assert_eq "" "$got" "no-prs"

echo "PASS monitor_pr_comments.test.sh"
