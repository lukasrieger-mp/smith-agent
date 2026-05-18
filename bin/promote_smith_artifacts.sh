#!/usr/bin/env bash
# Promote Smith's local-only artefacts into committed files for the
# WIP-stuck PR path (spec Section 10.2). Idempotent.
#
# Run this inside a Smith teammate's worktree right before opening a
# WIP-stuck PR. It does three things:
#
#   1. If `.smith/briefs/<key>-brief.md` exists, copy it to
#      `docs/superpowers/specs/<key>-brief.md` and `git add` it.
#
#   2. Promote spec and plan markdown from `.smith/specs/` and
#      `.smith/plans/` (gitignored agent-internal locations) into
#      `docs/superpowers/specs/` and `docs/superpowers/plans/` (tracked).
#      Spec and plan files are NEVER committed during the pipeline —
#      they're only landed here, on the WIP-stuck path, so the human
#      reviewer picking up Smith's work can see what was attempted.
#      Multiple files per directory are supported (pipeline retries can
#      produce multiple dated drafts); we promote everything matching.
#
#   3. If the worktree has any uncommitted changes (whether from steps
#      1+2 or from Smith abandoning mid-edit), commit them all with a
#      "wip(smith): partial work at point of stuck — <key>" message.
#
# Usage: promote_smith_artifacts.sh <TICKET-KEY>
set -euo pipefail

KEY="${1:?usage: promote_smith_artifacts.sh <TICKET-KEY>}"

# Must be inside a git worktree
worktree=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "promote_smith_artifacts: not inside a git repo" >&2
  exit 1
}
cd "$worktree"

# Step 1: promote brief if present
brief_src=".smith/briefs/$KEY-brief.md"
brief_dst="docs/superpowers/specs/$KEY-brief.md"
if [[ -f "$brief_src" ]]; then
  mkdir -p "$(dirname "$brief_dst")"
  cp "$brief_src" "$brief_dst"
  git add "$brief_dst"
fi

# Step 2: promote spec and plan files (gitignored → tracked locations).
# We walk `.smith/specs/` and `.smith/plans/` and copy each markdown
# file into the corresponding tracked dir. Idempotent (cp overwrites).
promote_dir() {
  local src_dir=$1 dst_dir=$2
  [[ -d "$src_dir" ]] || return 0
  mkdir -p "$dst_dir"
  local f
  for f in "$src_dir"/*.md; do
    [[ -f "$f" ]] || continue
    local base
    base=$(basename "$f")
    cp "$f" "$dst_dir/$base"
    git add "$dst_dir/$base"
  done
}
promote_dir ".smith/specs" "docs/superpowers/specs"
promote_dir ".smith/plans" "docs/superpowers/plans"

# Step 3: if there's anything uncommitted (staged or unstaged or
# untracked), include it in a single wip commit.
if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git commit -q -m "wip(smith): partial work at point of stuck — $KEY"
fi
