#!/usr/bin/env bash
# Resolve the **main target repo root** for the current git context.
#
# `git rev-parse --show-toplevel` returns the worktree path when the
# caller is inside a linked worktree (e.g., Smith-fixer running from
# <target>/.smith/worktrees/<key>/). That breaks any state file the
# watchdog and the worktree-side scripts need to share (the watchdog
# runs from the main target repo, so a relative-path read from there
# resolves differently than a `--show-toplevel` write from a worktree).
#
# `git rev-parse --git-common-dir` returns the main repo's `.git`
# regardless of where we're called from. dirname → the main repo.
#
# Usage: target_root=$(resolve_target_root.sh)

set -euo pipefail

common_dir=$(git rev-parse --git-common-dir)

# common_dir may be relative ('.git') or absolute. Canonicalise to an
# absolute path before dirname, so the result is stable regardless of
# the caller's cwd.
if [[ "$common_dir" = /* ]]; then
  abs_common=$common_dir
else
  abs_common="$(pwd -P)/$common_dir"
fi

cd "$(dirname "$abs_common")" && pwd -P
