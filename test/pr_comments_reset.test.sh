#!/usr/bin/env bash
# Test that the kick file resets the monitor's backoff cadence.
# Scenario: monitor accumulates quiet cycles → kick file appears →
# on next cycle, quiet_cycles drops back to 0 and the kick file is
# consumed.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

MONITOR="${ROOT}/bin/monitor_pr_comments.sh"
RESET="${ROOT}/bin/pr_comments_reset.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)

mkdir -p "$TMP/threads" "$TMP/.smith/state"
echo full > "$TMP/.smith/state/watchdog-mode"
cat > "$TMP/prs.json" <<'EOF'
[{"number": 9999, "headRefName": "task/app-1234-quiet"}]
EOF
echo '[]' > "$TMP/threads/pr-9999.json"

# Part 1: pr_comments_reset.sh creates the kick file at the expected path.
( cd "$TMP" && bash "$RESET" )
[[ -f "$TMP/.smith/state/pr-comments/kick" ]] \
  || { echo "FAIL: reset script did not create kick file" >&2; exit 1; }

# Part 2: monitor consumes the kick file and resets quiet_cycles.
# Run 5 quiet cycles first, then create the kick, then run 1 more cycle.
# After the 6th cycle, quiet_cycles should be 0 (reset, then 1 more
# quiet cycle... actually wait: the reset happens BEFORE the
# emit_diff_for_each_pr call in that same cycle, so the cycle that
# observes the kick goes 0 → 1 in its own quiet-bump. Let's assert
# quiet_cycles == 1 after the kick cycle.)

# First: 5 quiet cycles, no kick.
( cd "$TMP" && \
  SMITH_PR_POLL_INTERVAL=0 \
  SMITH_PR_POLL_BACKOFF_INTERVAL=0 \
  SMITH_PR_POLL_QUIET_CYCLES=100 \
  SMITH_MONITOR_MAX_CYCLES=5 \
  SMITH_DRY_RUN_PRS_FIXTURE="$TMP/prs.json" \
  SMITH_DRY_RUN_PR_THREADS_DIR="$TMP/threads" \
  bash "$MONITOR" > /dev/null )

quiet_before=$(jq -r '.quiet_cycles' "$TMP/.smith/state/pr-comments/cadence.json")
assert_eq "5" "$quiet_before" "5 quiet cycles accumulated"

# Now drop a kick file and run one more cycle.
( cd "$TMP" && bash "$RESET" )

( cd "$TMP" && \
  SMITH_PR_POLL_INTERVAL=0 \
  SMITH_PR_POLL_BACKOFF_INTERVAL=0 \
  SMITH_PR_POLL_QUIET_CYCLES=100 \
  SMITH_MONITOR_MAX_CYCLES=1 \
  SMITH_DRY_RUN_PRS_FIXTURE="$TMP/prs.json" \
  SMITH_DRY_RUN_PR_THREADS_DIR="$TMP/threads" \
  bash "$MONITOR" > /dev/null )

quiet_after=$(jq -r '.quiet_cycles' "$TMP/.smith/state/pr-comments/cadence.json")
# Cycle goes: kick observed → quiet_cycles=0 → emit (no new) → quiet_cycles=1
assert_eq "1" "$quiet_after" "kick cycle reset to 0, then bumped to 1 by quiet check"

# Kick file should be consumed (removed) by the monitor.
[[ ! -f "$TMP/.smith/state/pr-comments/kick" ]] \
  || { echo "FAIL: kick file was not consumed" >&2; exit 1; }

echo "PASS pr_comments_reset.test.sh"
