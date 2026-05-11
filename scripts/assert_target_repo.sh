#!/usr/bin/env bash
# Working-directory guard from spec Section 7.4.
#
# Verifies the current location is inside a git repo that's eligible to be
# Smith's target. Lazily bootstraps `.smith/config.json` (via smith_config.sh)
# on first call — that's part of the lazy-setup contract; no separate install
# step exists in the `--plugin-dir` design.
#
# Works from the main checkout or from any `.smith/worktrees/*` worktree
# inside the target.
#
# Optional override: if SMITH_TARGET_REPO is set, the resolved main repo
# must additionally match that path. (Useful as a belt-and-braces guard when
# the operator wants Smith pinned to one specific target.)
set -euo pipefail

git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || {
  echo "assert_target_repo: not inside a git repo" >&2; exit 1
}
# Main repo = parent of the shared .git/ dir (works from main worktree and
# from secondary worktrees alike).
main_repo=$(cd "$(dirname "$git_common_dir")" && pwd -P)

# Lazy-bootstrap config if it doesn't exist yet. smith_config.sh handles
# both .smith/config.json creation AND the .gitignore Smith block.
# Call from the main repo (not the current worktree, which might be a
# secondary worktree under .smith/worktrees/).
if [[ ! -f "$main_repo/.smith/config.json" ]]; then
  plugin_scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  ( cd "$main_repo" && bash "$plugin_scripts/smith_config.sh" target_repo >/dev/null )
fi

# Optional pinned-target check
if [[ -n "${SMITH_TARGET_REPO:-}" ]]; then
  expected_real=$(cd "$SMITH_TARGET_REPO" 2>/dev/null && pwd -P || echo "$SMITH_TARGET_REPO")
  if [[ "$expected_real" != "$main_repo" ]]; then
    echo "assert_target_repo: refusing to run outside SMITH_TARGET_REPO" >&2
    echo "  expected: $expected_real" >&2
    echo "  actual:   $main_repo" >&2
    exit 1
  fi
fi
