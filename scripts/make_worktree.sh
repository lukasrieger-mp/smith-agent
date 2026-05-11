#!/usr/bin/env bash
# Create a per-ticket git worktree under .smith/worktrees/<key-lower>/.
#
# Usage: make_worktree.sh <TICKET-KEY> <BRANCH>
#
# The branch must start with `task/` (Smith convention; spec Section 7.1).
# If the worktree already exists at the expected path on the expected
# branch, exit 0 (idempotent). If the branch is checked out elsewhere or
# the path exists with different state, abort with a clear error.
set -euo pipefail

KEY="${1:?usage: make_worktree.sh <TICKET-KEY> <BRANCH>}"
BRANCH="${2:?usage: make_worktree.sh <TICKET-KEY> <BRANCH>}"

# Branch-name guard
case "$BRANCH" in
  task/*) ;;
  *) echo "make_worktree: branch must start with task/ (got '$BRANCH')" >&2; exit 1 ;;
esac

# Resolve target paths
key_lower=$(printf '%s' "$KEY" | tr '[:upper:]' '[:lower:]')
target_root=$(git rev-parse --show-toplevel)
worktree_path="$target_root/.smith/worktrees/$key_lower"

# Already exists and on the expected branch?
if [[ -d "$worktree_path/.git" || -f "$worktree_path/.git" ]]; then
  current=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ "$current" == "$BRANCH" ]]; then
    exit 0   # idempotent
  fi
  echo "make_worktree: worktree exists at $worktree_path on different branch ($current); refusing" >&2
  exit 1
fi

# Ensure we have origin/develop fresh
git -C "$target_root" fetch --quiet origin develop 2>/dev/null || true

# If the branch already exists locally, refuse — would suggest collision
if git -C "$target_root" rev-parse --verify "refs/heads/$BRANCH" >/dev/null 2>&1; then
  echo "make_worktree: branch $BRANCH already exists locally; cannot create worktree on a new branch with that name" >&2
  exit 1
fi

mkdir -p "$(dirname "$worktree_path")"
git -C "$target_root" worktree add -b "$BRANCH" "$worktree_path" origin/develop
