#!/usr/bin/env bash
# Background monitor: polls open Smith-authored PRs for unresolved review
# comments. Emits a JSON notification line whenever a PR gains new comments
# compared to the previous poll.
#
# Active interval: 60s (reviewer responsiveness matters more than JIRA).
# Backoff: after SMITH_PR_POLL_QUIET_CYCLES consecutive cycles with no new
# comments, the interval steps up to SMITH_PR_POLL_BACKOFF_INTERVAL (default
# 30 min). Default cycle threshold is 30 — so we poll every 60s for at
# least 30 minutes before stepping up.
#
# Cadence resets to the active interval on two signals:
#   1. A new unresolved review thread shows up (the natural case).
#   2. `.smith/state/pr-comments/kick` exists — Smith creates this file
#      via `pr_comments_reset.sh` after every git push. A push can
#      trigger fresh reviewer activity within minutes; we don't want
#      to be at the 30-min backoff during that response window.
#
# Notification schema:
#   {"type":"smith.pr.new_comments","pr":4321,"new_count":2,"branch":"task/app-1234-foo"}
#
# Per-PR state lives at `.smith/state/pr-comments/pr-<num>.json` — sorted
# thread-id list, used for diffing.
#
# Errors from `gh` (network, auth) are swallowed; monitor retries next interval.

set -uo pipefail
ACTIVE_INTERVAL="${SMITH_PR_POLL_INTERVAL:-60}"
BACKOFF_INTERVAL="${SMITH_PR_POLL_BACKOFF_INTERVAL:-1800}"
QUIET_CYCLE_THRESHOLD="${SMITH_PR_POLL_QUIET_CYCLES:-30}"
MAX_CYCLES="${SMITH_MONITOR_MAX_CYCLES:-0}"   # 0 = unbounded; test hook
STATE_DIR=".smith/state/pr-comments"
KICK_FILE="$STATE_DIR/kick"
ONESHOT="${SMITH_MONITOR_ONESHOT:-0}"
NOTIFY_COUNT=0   # set by emit_diff_for_each_pr each cycle

# Test override: feed a fake `gh pr list` via SMITH_DRY_RUN_PRS_FIXTURE (a path to
# a JSON fixture). Used by the test suite to avoid network calls.
gh_list_open_prs() {
  if [[ -n "${SMITH_DRY_RUN_PRS_FIXTURE:-}" ]]; then
    cat "$SMITH_DRY_RUN_PRS_FIXTURE"
  else
    gh pr list --label smith-authored --state open \
       --json number,headRefName 2>/dev/null || echo "[]"
  fi
}

# Test override: feed a fake per-PR thread list via SMITH_DRY_RUN_PR_THREADS_DIR
# (a directory with files named pr-<num>.json containing a JSON array of
# unresolved thread ids).
#
# Note: `reviewThreads` only exists on the GraphQL API — `gh pr view --json
# reviewThreads` errors out with "Unknown JSON field". So we go through
# `gh api graphql` instead.
gh_pr_unresolved_threads() {
  local pr="$1"
  if [[ -n "${SMITH_DRY_RUN_PR_THREADS_DIR:-}" ]]; then
    cat "$SMITH_DRY_RUN_PR_THREADS_DIR/pr-$pr.json" 2>/dev/null || echo "[]"
  else
    local owner repo
    owner=$(gh repo view --json owner -q .owner.login 2>/dev/null) || { echo "[]"; return; }
    repo=$(gh repo view --json name -q .name 2>/dev/null) || { echo "[]"; return; }
    gh api graphql \
      -f query='query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100){nodes{id isResolved}}}}}' \
      -f owner="$owner" -f repo="$repo" -F number="$pr" 2>/dev/null \
      | jq -c '[.data.repository.pullRequest.reviewThreads.nodes[]
               | select(.isResolved | not) | .id] | sort' \
      || echo "[]"
  fi
}

emit_diff_for_each_pr() {
  local prs pr current last branch new_count
  NOTIFY_COUNT=0
  prs=$(gh_list_open_prs)

  while IFS=$'\t' read -r pr branch; do
    [[ -z "$pr" ]] && continue
    local state_file="$STATE_DIR/pr-$pr.json"

    current=$(gh_pr_unresolved_threads "$pr")
    if [[ -f "$state_file" ]]; then
      last=$(cat "$state_file")
    else
      last="[]"
    fi

    if [[ "$current" != "$last" ]]; then
      new_count=$(jq --argjson old "$last" '(. - $old) | length' <<< "$current")
      if [[ "${new_count:-0}" -gt 0 ]]; then
        printf '{"type":"smith.pr.new_comments","pr":%s,"new_count":%s,"branch":"%s"}\n' \
               "$pr" "$new_count" "$branch"
        NOTIFY_COUNT=$((NOTIFY_COUNT + 1))
      fi
      mkdir -p "$STATE_DIR"
      echo "$current" > "$state_file"
    fi
  done < <(echo "$prs" | jq -r '.[] | [.number, .headRefName] | @tsv' 2>/dev/null)
}

if [[ "$ONESHOT" == "1" ]]; then
  emit_diff_for_each_pr
  exit 0
fi

quiet_cycles=0
interval="$ACTIVE_INTERVAL"
cycle=0
while true; do
  # Gate: only do real work when watchdog is armed. The /smith:watchdog
  # command writes .smith/state/watchdog-mode on invocation. While the
  # file is absent, sleep at the active interval and loop. Cheap
  # idle — no gh calls, no state writes.
  if [[ ! -f .smith/state/watchdog-mode ]]; then
    sleep "$ACTIVE_INTERVAL"
    cycle=$((cycle + 1))
    if (( MAX_CYCLES > 0 && cycle >= MAX_CYCLES )); then break; fi
    continue
  fi

  # Consume any pending kick signal (from a Smith push). Resetting
  # quiet_cycles to 0 and dropping back to the active interval ensures
  # we catch reviewer responses quickly. Remove the kick file so we
  # only honour it once.
  if [[ -f "$KICK_FILE" ]]; then
    rm -f "$KICK_FILE"
    quiet_cycles=0
    interval="$ACTIVE_INTERVAL"
  fi

  emit_diff_for_each_pr
  if (( NOTIFY_COUNT > 0 )); then
    quiet_cycles=0
    interval="$ACTIVE_INTERVAL"
  else
    quiet_cycles=$((quiet_cycles + 1))
    if (( quiet_cycles >= QUIET_CYCLE_THRESHOLD )); then
      interval="$BACKOFF_INTERVAL"
    fi
  fi
  mkdir -p "$STATE_DIR"
  printf '{"quiet_cycles":%d,"interval":%d}\n' "$quiet_cycles" "$interval" \
    > "$STATE_DIR/cadence.json"
  cycle=$((cycle + 1))
  if (( MAX_CYCLES > 0 && cycle >= MAX_CYCLES )); then
    break
  fi
  sleep "$interval"
done
