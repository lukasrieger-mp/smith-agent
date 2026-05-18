#!/usr/bin/env bash
# Exits 0 if the current worktree is clean (no staged, unstaged, or untracked
# changes), non-zero otherwise. Prints a one-line reason on failure.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "assert_clean_worktree: working tree is dirty" >&2
  git status --short >&2
  exit 1
fi
