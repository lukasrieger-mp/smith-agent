#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/pr_fix_round_inc.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)

# Make TMP look like a git repo so the script can find its root.
( cd "$TMP" && git init -q && git commit --allow-empty -q -m init )

# First call: bumps rounds=1, initializes counters.
got=$( cd "$TMP" && bash "$SCRIPT" 891 )
assert_eq "1" "$got" "first-bump"

state="$TMP/.smith/state/pr-fix-rounds/pr-891.json"
[[ -f "$state" ]] || { echo "FAIL: state file not created" >&2; exit 1; }
assert_eq "1" "$(jq -r .rounds "$state")"        "rounds=1"
assert_eq "0" "$(jq -r .fix_total "$state")"     "fix_total=0"
assert_eq "0" "$(jq -r .dismiss_total "$state")" "dismiss_total=0"
[[ "$(jq -r .first_round_at "$state")" != "" ]] || { echo "FAIL: first_round_at empty" >&2; exit 1; }

# Second call: bumps rounds=2; first_round_at unchanged.
first_at=$(jq -r .first_round_at "$state")
got=$( cd "$TMP" && bash "$SCRIPT" 891 )
assert_eq "2" "$got" "second-bump"
assert_eq "$first_at" "$(jq -r .first_round_at "$state")" "first_round_at sticky"

# --fix and --dismiss accumulate.
( cd "$TMP" && bash "$SCRIPT" 891 --fix 3 --dismiss 2 ) > /dev/null
assert_eq "3" "$(jq -r .rounds "$state")"        "rounds=3 after --fix --dismiss call"
assert_eq "3" "$(jq -r .fix_total "$state")"     "fix_total accumulated"
assert_eq "2" "$(jq -r .dismiss_total "$state")" "dismiss_total accumulated"

# --trigger increments augment_trigger_count without bumping rounds.
( cd "$TMP" && bash "$SCRIPT" 891 --trigger ) > /dev/null
assert_eq "3" "$(jq -r .rounds "$state")" "rounds unchanged by --trigger"
assert_eq "1" "$(jq -r .augment_trigger_count "$state")" "trigger count"

# Missing PR number errors out.
if ( cd "$TMP" && bash "$SCRIPT" 2>/dev/null ); then
  echo "FAIL: missing arg should error" >&2; exit 1
fi

# --fix with non-numeric value errors out.
if ( cd "$TMP" && bash "$SCRIPT" 891 --fix abc 2>/dev/null ); then
  echo "FAIL: --fix abc should error" >&2; exit 1
fi

# --dismiss with non-numeric value errors out.
if ( cd "$TMP" && bash "$SCRIPT" 891 --dismiss xyz 2>/dev/null ); then
  echo "FAIL: --dismiss xyz should error" >&2; exit 1
fi

# --trigger combined with --fix is rejected.
if ( cd "$TMP" && bash "$SCRIPT" 891 --trigger --fix 1 2>/dev/null ); then
  echo "FAIL: --trigger --fix combo should error" >&2; exit 1
fi

# --trigger combined with --dismiss is rejected.
if ( cd "$TMP" && bash "$SCRIPT" 891 --trigger --dismiss 1 2>/dev/null ); then
  echo "FAIL: --trigger --dismiss combo should error" >&2; exit 1
fi

# Verify the script writes to the MAIN repo path even when called from a worktree.
worktree="$TMP/.smith/worktrees/app-7777"
( cd "$TMP" && git worktree add -q -b task/wt "$worktree" )
got=$( cd "$worktree" && bash "$SCRIPT" 7777 )
assert_eq "1" "$got" "first-bump-from-worktree"
# State must land in the MAIN repo's .smith/state/, not the worktree's.
[[ -f "$TMP/.smith/state/pr-fix-rounds/pr-7777.json" ]] \
  || { echo "FAIL: worktree call wrote to wrong path" >&2; exit 1; }
[[ ! -f "$worktree/.smith/state/pr-fix-rounds/pr-7777.json" ]] \
  || { echo "FAIL: worktree call wrote to worktree path" >&2; exit 1; }

echo "PASS pr_fix_round_inc.test.sh"
