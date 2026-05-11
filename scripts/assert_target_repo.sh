#!/usr/bin/env bash
# Working-directory guard from spec Section 7.4.
# Verifies the current location is inside a Smith-installed target repo —
# i.e. a git repo that has a .smith/config.json (proof that install.sh has
# been run against it).
#
# Works from the main checkout or from any .smith/worktrees/* worktree
# inside the target.
#
# Optional override: if SMITH_TARGET_REPO is set, the resolved main repo
# must additionally match that path.
set -euo pipefail

git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || {
  echo "assert_target_repo: not inside a git repo" >&2; exit 1
}
# Main repo = parent of the shared .git/ dir (works from main worktree and
# from secondary worktrees alike).
main_repo=$(cd "$(dirname "$git_common_dir")" && pwd -P)

if [[ ! -f "$main_repo/.smith/config.json" ]]; then
  echo "assert_target_repo: $main_repo has no .smith/config.json" >&2
  echo "  hint: run smith-agent/install.sh against this repo first" >&2
  exit 1
fi

if [[ -n "${SMITH_TARGET_REPO:-}" ]]; then
  expected_real=$(cd "$SMITH_TARGET_REPO" 2>/dev/null && pwd -P || echo "$SMITH_TARGET_REPO")
  if [[ "$expected_real" != "$main_repo" ]]; then
    echo "assert_target_repo: refusing to run outside SMITH_TARGET_REPO" >&2
    echo "  expected: $expected_real" >&2
    echo "  actual:   $main_repo" >&2
    exit 1
  fi
fi
