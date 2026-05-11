#!/usr/bin/env bash
# Create a worktree on an EXISTING remote branch (the PR's head ref) at
# .smith/worktrees/<key-lower>/. This is the PR-fix-mode counterpart of
# make_worktree.sh — make_worktree creates a NEW branch from
# origin/develop; this one checks out a branch that already exists on
# the remote (because Smith pushed it earlier in ticket mode).
#
# Usage: checkout_pr_worktree.sh <TICKET-KEY> <BRANCH>
#
# The branch must start with `task/`. The remote branch
# `origin/<BRANCH>` must exist (we fetch first to confirm).
#
# Idempotent: if the worktree already exists on the expected branch,
# exit 0. If on a different branch, abort.
set -euo pipefail

KEY="${1:?usage: checkout_pr_worktree.sh <TICKET-KEY> <BRANCH>}"
BRANCH="${2:?usage: checkout_pr_worktree.sh <TICKET-KEY> <BRANCH>}"

case "$BRANCH" in
  task/*) ;;
  *) echo "checkout_pr_worktree: branch must start with task/ (got '$BRANCH')" >&2; exit 1 ;;
esac

key_lower=$(printf '%s' "$KEY" | tr '[:upper:]' '[:lower:]')
target_root=$(git rev-parse --show-toplevel)
worktree_path="$target_root/.smith/worktrees/$key_lower"

if [[ -d "$worktree_path/.git" || -f "$worktree_path/.git" ]]; then
  current=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ "$current" == "$BRANCH" ]]; then
    exit 0
  fi
  echo "checkout_pr_worktree: worktree at $worktree_path is on '$current', expected '$BRANCH'" >&2
  exit 1
fi

git -C "$target_root" fetch --quiet origin "$BRANCH"

# Verify the remote branch exists after fetch
if ! git -C "$target_root" rev-parse --verify "refs/remotes/origin/$BRANCH" >/dev/null 2>&1; then
  echo "checkout_pr_worktree: remote branch origin/$BRANCH not found" >&2
  exit 1
fi

mkdir -p "$(dirname "$worktree_path")"
# Check out the existing remote branch into the worktree, tracking origin
git -C "$target_root" worktree add --track -b "$BRANCH" "$worktree_path" "origin/$BRANCH"
