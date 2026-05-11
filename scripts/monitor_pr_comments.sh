#!/usr/bin/env bash
# Background monitor: polls open Smith-authored PRs for unresolved review
# comments. Emits a JSON notification line whenever a PR gains new comments
# compared to the previous poll.
#
# Default interval: 60s (reviewer responsiveness matters more than JIRA).
#
# Notification schema:
#   {"type":"smith.pr.new_comments","pr":4321,"new_count":2,"branch":"task/app-1234-foo"}
#
# Per-PR state lives at `.smith/state/pr-comments/pr-<num>.json` — sorted
# thread-id list, used for diffing.
#
# Errors from `gh` (network, auth) are swallowed; monitor retries next interval.

set -uo pipefail
INTERVAL="${SMITH_PR_POLL_INTERVAL:-60}"
STATE_DIR=".smith/state/pr-comments"
ONESHOT="${SMITH_MONITOR_ONESHOT:-0}"

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
gh_pr_unresolved_threads() {
  local pr="$1"
  if [[ -n "${SMITH_DRY_RUN_PR_THREADS_DIR:-}" ]]; then
    cat "$SMITH_DRY_RUN_PR_THREADS_DIR/pr-$pr.json" 2>/dev/null || echo "[]"
  else
    gh pr view "$pr" --json reviewThreads 2>/dev/null \
      | jq -c '[.reviewThreads[] | select(.isResolved | not) | .id] | sort' \
      || echo "[]"
  fi
}

emit_diff_for_each_pr() {
  local prs pr current last branch new_count
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

while true; do
  emit_diff_for_each_pr
  sleep "$INTERVAL"
done
