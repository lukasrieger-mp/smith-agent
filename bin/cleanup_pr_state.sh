#!/usr/bin/env bash
# Convergence cleanup. Posts the "Smith fix loop converged" summary
# comment to the PR, then removes the per-PR state files. Order
# matters: if the gh call fails, leave state in place so the lead can
# retry.
#
# Usage: cleanup_pr_state.sh <PR>

set -euo pipefail

PR="${1:?usage: cleanup_pr_state.sh <PR>}"

target_root=$(bash "$(dirname "$0")/resolve_target_root.sh")
rounds_file="$target_root/.smith/state/pr-fix-rounds/pr-$PR.json"
comments_file="$target_root/.smith/state/pr-comments/pr-$PR.json"

rounds=$( [[ -f "$rounds_file" ]] && jq -r .rounds "$rounds_file"        || echo 0)
fix_t=$(  [[ -f "$rounds_file" ]] && jq -r .fix_total "$rounds_file"     || echo 0)
dis_t=$(  [[ -f "$rounds_file" ]] && jq -r .dismiss_total "$rounds_file" || echo 0)

body="Smith fix loop converged.

- rounds: $rounds
- findings fixed: $fix_t
- findings dismissed with reasoning: $dis_t (see resolved review threads)

The current code reflects Smith's and Anderson's final position on
this PR. Ready for human review."

# 1. Post the summary. Fail-loud — caller propagates the error.
gh pr comment "$PR" --body "$body"

# 2. Remove per-PR state.
rm -f "$rounds_file" "$comments_file"
