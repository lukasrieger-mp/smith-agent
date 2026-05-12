#!/usr/bin/env bash
# Per-PR fix-round counter. Replaces the old per-thread cycle counter.
# State file schema (per spec):
#   {
#     "pr": <int>,
#     "rounds": <int>,
#     "fix_total": <int>,
#     "dismiss_total": <int>,
#     "augment_trigger_count": <int>,
#     "first_round_at": "<ISO-8601 UTC>",
#     "last_round_at":  "<ISO-8601 UTC>"
#   }
#
# Usage:
#   pr_fix_round_inc.sh <PR>
#       Bump rounds. Print the new round count.
#   pr_fix_round_inc.sh <PR> --fix N --dismiss N
#       Bump rounds AND accumulate fix_total / dismiss_total by N each.
#   pr_fix_round_inc.sh <PR> --trigger
#       Increment augment_trigger_count only. Does NOT bump rounds.
set -euo pipefail

PR="${1:?usage: pr_fix_round_inc.sh <PR> [--fix N] [--dismiss N] [--trigger]}"
shift

fix_delta=0
dismiss_delta=0
trigger=0
while (($# > 0)); do
  case "$1" in
    --fix)     fix_delta="${2:?--fix needs a number}"; shift 2 ;;
    --dismiss) dismiss_delta="${2:?--dismiss needs a number}"; shift 2 ;;
    --trigger) trigger=1; shift ;;
    *) echo "pr_fix_round_inc: unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ "$fix_delta" =~ ^[0-9]+$ ]] || { echo "pr_fix_round_inc: --fix needs a non-negative integer (got '$fix_delta')" >&2; exit 1; }
[[ "$dismiss_delta" =~ ^[0-9]+$ ]] || { echo "pr_fix_round_inc: --dismiss needs a non-negative integer (got '$dismiss_delta')" >&2; exit 1; }

if (( trigger == 1 )) && (( fix_delta != 0 || dismiss_delta != 0 )); then
  echo "pr_fix_round_inc: --trigger cannot be combined with --fix or --dismiss" >&2
  exit 1
fi

target_root=$(git rev-parse --show-toplevel)
state_dir="$target_root/.smith/state/pr-fix-rounds"
state_file="$state_dir/pr-$PR.json"
mkdir -p "$state_dir"

now=$(date -u +%FT%TZ)

if [[ ! -f "$state_file" ]]; then
  jq -n --argjson pr "$PR" --arg now "$now" '{
    pr: $pr,
    rounds: 0,
    fix_total: 0,
    dismiss_total: 0,
    augment_trigger_count: 0,
    first_round_at: $now,
    last_round_at: $now
  }' > "$state_file"
fi

tmp=$(mktemp)
jq --arg now "$now" \
   --argjson fix "$fix_delta" \
   --argjson dis "$dismiss_delta" \
   --argjson trig "$trigger" '
  if $trig == 1 then
    .augment_trigger_count = (.augment_trigger_count + 1)
  else
    .rounds = (.rounds + 1)
    | .fix_total = (.fix_total + $fix)
    | .dismiss_total = (.dismiss_total + $dis)
    | .last_round_at = $now
  end
' "$state_file" > "$tmp"
mv "$tmp" "$state_file"

jq -r '.rounds' "$state_file"
