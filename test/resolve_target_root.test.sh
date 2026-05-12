#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/resolve_target_root.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)

# Set up a main repo with an initial commit (worktrees require a commit).
( cd "$TMP" && git init -q && git commit --allow-empty -q -m init )

# 1. From the main repo: returns the main repo path.
got=$( cd "$TMP" && bash "$SCRIPT" )
assert_eq "$TMP" "$got" "main-repo"

# 2. From a linked worktree: returns the main repo path, NOT the worktree.
worktree="$TMP/.smith/worktrees/app-1234"
( cd "$TMP" && git worktree add -q -b task/test "$worktree" )
worktree_resolved=$(cd "$worktree" && pwd -P)

got=$( cd "$worktree" && bash "$SCRIPT" )
assert_eq "$TMP" "$got" "from-worktree-returns-main"

# Defensive: the worktree path itself should NOT be what we return.
[[ "$got" != "$worktree_resolved" ]] || { echo "FAIL: returned worktree path" >&2; exit 1; }

# 3. From a subdirectory of the main repo: still returns the main repo.
mkdir -p "$TMP/sub/dir"
got=$( cd "$TMP/sub/dir" && bash "$SCRIPT" )
assert_eq "$TMP" "$got" "from-subdir"

# 4. From a subdirectory of a worktree: returns the main repo, not the worktree.
mkdir -p "$worktree/nested"
got=$( cd "$worktree/nested" && bash "$SCRIPT" )
assert_eq "$TMP" "$got" "from-worktree-subdir"

echo "PASS resolve_target_root.test.sh"
