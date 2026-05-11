#!/usr/bin/env bash
# Increment the per-thread fix-cycle counter for a PR (spec Section
# 10.5, 5.5: max 5 cycles per thread before needs-human-attention).
#
# Usage: pr_fix_cycle_inc.sh <PR-NUMBER> <THREAD-ID>
#
# Reads/writes .smith/state/pr-<N>.json in the target repo. Prints the
# new cycle count for the named thread to stdout.
#
# State file schema (created on first call for a PR):
#   {
#     "pr": <int>,
#     "fix_cycles_per_thread": {"<thread-id>": <int>, ...},
#     "last_polled": "<ISO-8601 UTC>"
#   }
set -euo pipefail

PR="${1:?usage: pr_fix_cycle_inc.sh <PR-NUMBER> <THREAD-ID>}"
THREAD="${2:?usage: pr_fix_cycle_inc.sh <PR-NUMBER> <THREAD-ID>}"

target_root=$(git rev-parse --show-toplevel)
state_dir="$target_root/.smith/state"
state_file="$state_dir/pr-$PR.json"

mkdir -p "$state_dir"

# Initialize if missing
if [[ ! -f "$state_file" ]]; then
  jq -n --argjson pr "$PR" '{pr: $pr, fix_cycles_per_thread: {}, last_polled: ""}' > "$state_file"
fi

now=$(date -u +%FT%TZ)

# Atomically read+update+write. Race-free for the single-Smith-per-PR
# model; not safe under concurrent Smiths on the same PR (but the lead
# prevents that — Section 5.3 "if there's already a PR-fix Smith on
# this PR, ignore").
tmp_file=$(mktemp)
jq --arg thread "$THREAD" --arg now "$now" '
  .fix_cycles_per_thread[$thread] = ((.fix_cycles_per_thread[$thread] // 0) + 1)
  | .last_polled = $now
' "$state_file" > "$tmp_file"
mv "$tmp_file" "$state_file"

# Print the new count
jq -er --arg thread "$THREAD" '.fix_cycles_per_thread[$thread]' "$state_file"
