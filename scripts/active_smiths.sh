#!/usr/bin/env bash
# Manage the watchdog's tally of currently-active Smith+Anderson pairs.
# Stored at `.smith/state/active-smiths.json` in the target repo. The
# watchdog reads/writes this to enforce the 2-Smith cap (spec Section
# 5.5) and to avoid dispatching a second Smith for a subject (ticket
# key or PR number) that's already in flight.
#
# Usage:
#   active_smiths.sh count
#       Print the current number of active pairs.
#   active_smiths.sh list
#       Print the full state JSON array.
#   active_smiths.sh add <SMITH_NAME> <ANDERSON_NAME> <MODE> <SUBJECT>
#       Record a new pair. MODE = "ticket" | "pr-fix".
#       SUBJECT = ticket key (e.g. APP-1234) or PR number (e.g. 4321).
#       Fails if SMITH_NAME already present.
#   active_smiths.sh remove <SMITH_NAME>
#       Remove the entry for SMITH_NAME. No-op if not found.
#   active_smiths.sh has-subject <SUBJECT>
#       Exit 0 if SUBJECT is in flight, 1 otherwise.
#
# State entry schema:
#   {
#     "smith_name":   "smith-APP-1234",
#     "anderson_name":"anderson-APP-1234",
#     "mode":         "ticket" | "pr-fix",
#     "subject":      "APP-1234",       // ticket key or PR number string
#     "spawned_at":   "<ISO-8601 UTC>"
#   }
set -euo pipefail

CMD="${1:-}"

target_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "active_smiths: not inside a git repo" >&2; exit 1
}
state_dir="$target_root/.smith/state"
state_file="$state_dir/active-smiths.json"

mkdir -p "$state_dir"
if [[ ! -f "$state_file" ]]; then
  echo "[]" > "$state_file"
fi

case "$CMD" in
  count)
    jq 'length' "$state_file"
    ;;
  list)
    cat "$state_file"
    ;;
  add)
    smith_name="${2:?usage: add <SMITH_NAME> <ANDERSON_NAME> <MODE> <SUBJECT>}"
    anderson_name="${3:?usage: add <SMITH_NAME> <ANDERSON_NAME> <MODE> <SUBJECT>}"
    mode="${4:?usage: add <SMITH_NAME> <ANDERSON_NAME> <MODE> <SUBJECT>}"
    subject="${5:?usage: add <SMITH_NAME> <ANDERSON_NAME> <MODE> <SUBJECT>}"

    case "$mode" in
      ticket|pr-fix) ;;
      *) echo "active_smiths: mode must be 'ticket' or 'pr-fix' (got '$mode')" >&2; exit 1 ;;
    esac

    # Reject duplicate smith_name
    if jq -e --arg n "$smith_name" 'any(.smith_name == $n)' "$state_file" >/dev/null; then
      echo "active_smiths: smith_name '$smith_name' already active" >&2
      exit 1
    fi

    now=$(date -u +%FT%TZ)
    tmp=$(mktemp)
    jq --arg s "$smith_name" --arg a "$anderson_name" --arg m "$mode" \
       --arg subj "$subject" --arg now "$now" \
       '. + [{smith_name: $s, anderson_name: $a, mode: $m, subject: $subj, spawned_at: $now}]' \
       "$state_file" > "$tmp"
    mv "$tmp" "$state_file"
    ;;
  remove)
    smith_name="${2:?usage: remove <SMITH_NAME>}"
    tmp=$(mktemp)
    jq --arg n "$smith_name" 'map(select(.smith_name != $n))' "$state_file" > "$tmp"
    mv "$tmp" "$state_file"
    ;;
  has-subject)
    subject="${2:?usage: has-subject <SUBJECT>}"
    jq -e --arg subj "$subject" 'any(.subject == $subj)' "$state_file" >/dev/null
    ;;
  *)
    echo "active_smiths: unknown subcommand '$CMD'" >&2
    echo "  see header comment for usage" >&2
    exit 1
    ;;
esac
