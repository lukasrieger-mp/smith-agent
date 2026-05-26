#!/usr/bin/env bash
# Idempotently create the GitHub labels Smith relies on. Safe to call
# every time before `gh pr create`. Each `gh label create` exits 0 if
# the label is created, non-zero if it already exists; we swallow the
# "already exists" failure mode.
#
# Usage: bash gh_ensure_labels.sh
#
# Test override: SMITH_DRY_RUN_GH_ENSURE_LABELS=1 — print the gh commands
# instead of running them. Used by the test suite to avoid network calls.

set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/smith_labels.sh"

ensure_label() {
  local name="$1" desc="$2" color="$3"
  if [[ "${SMITH_DRY_RUN_GH_ENSURE_LABELS:-0}" == "1" ]]; then
    echo "gh label create $name --description \"$desc\" --color $color"
    return 0
  fi
  # `gh label create` returns 0 on success, non-zero if the label exists.
  # We don't care about the latter — silent idempotency.
  gh label create "$name" --description "$desc" --color "$color" \
    >/dev/null 2>&1 || true
}

ensure_label "$SMITH_LABEL_PR_AUTHORED" \
  "PR opened by Smith autonomous agent" \
  8B7AB6

ensure_label "$SMITH_LABEL_PR_NEEDS_ATTENTION" \
  "Smith got stuck; requires human review" \
  D93F0B
