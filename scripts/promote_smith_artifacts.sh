#!/usr/bin/env bash
# Promote Smith's local-only artefacts into committed files for the
# WIP-stuck PR path (spec Section 10.2). Idempotent.
#
# Run this inside a Smith teammate's worktree right before opening a
# WIP-stuck PR. It does two things:
#
#   1. If `.smith/briefs/<key>-brief.md` exists, copy it to
#      `docs/superpowers/specs/<key>-brief.md` and `git add` it.
#      (Spec and plan files are already committed per-gate by
#      smith:pipeline, so no promotion needed for those.)
#
#   2. If the worktree has any uncommitted changes (whether from step 1
#      or from Smith abandoning mid-edit), commit them all with a
#      "wip(smith): partial work at point of stuck — <key>" message.
#      This preserves any partial impl that didn't make it into a
#      per-gate commit.
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

# Step 2: if there's anything uncommitted (staged or unstaged or
# untracked), include it in a single wip commit.
if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git commit -q -m "wip(smith): partial work at point of stuck — $KEY"
fi
