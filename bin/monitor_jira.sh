#!/usr/bin/env bash
# Background monitor: polls JIRA every SMITH_JIRA_POLL_INTERVAL seconds
# (default 1800) for tickets matching the candidate JQL. Emits a single
# JSON notification line on stdout whenever the set of eligible candidate
# keys gains a new entry compared to the previous poll.
#
# Notification schema:
#   {"type":"smith.jira.new_candidates","keys":["APP-1234","APP-5601"]}
#
# State file (`.smith/state/last-jira-candidates.json`) is the previous
# scan's key list, sorted, used for diffing. Created on first poll.
#
# Errors from `jira_scan.sh` (network blip, auth lapse) are swallowed —
# the monitor stays alive and retries on the next interval. Persistent
# errors would manifest as silence rather than crash loops.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
INTERVAL="${SMITH_JIRA_POLL_INTERVAL:-1800}"
STATE_FILE=".smith/state/last-jira-candidates.json"

# Test/dev override: emit one diff and exit (so tests can assert behaviour
# without running the infinite loop).
ONESHOT="${SMITH_MONITOR_ONESHOT:-0}"

emit_diff_if_any() {
  local current last new
  current=$(bash "$PLUGIN_ROOT/bin/jira_scan.sh" 2>/dev/null \
            | jq -c '[.[] | .key] | sort' 2>/dev/null \
            || echo "[]")

  if [[ -f "$STATE_FILE" ]]; then
    last=$(cat "$STATE_FILE")
  else
    last="[]"
  fi

  if [[ "$current" != "$last" ]]; then
    new=$(jq -c --argjson old "$last" '. - $old' <<< "$current")
    if [[ -n "$new" && "$new" != "[]" && "$new" != "null" ]]; then
      printf '{"type":"smith.jira.new_candidates","keys":%s}\n' "$new"
    fi
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$current" > "$STATE_FILE"
  fi
}

if [[ "$ONESHOT" == "1" ]]; then
  emit_diff_if_any
  exit 0
fi

while true; do
  # Gate: only poll JIRA when the watchdog is armed in `full` mode.
  # `pr-only` (written by `/smith:implement` on success-path PR creation,
  # or by `/smith:watchdog --pr-only`) deliberately suppresses JIRA
  # candidate scanning — the lead would ignore the emissions anyway, so
  # we save the `acli` calls. Only `full` (written by `/smith:watchdog`
  # with no flag) activates this monitor.
  mode=$(cat .smith/state/watchdog-mode 2>/dev/null || echo "")
  if [[ "$mode" == "full" ]]; then
    emit_diff_if_any
  fi
  sleep "$INTERVAL"
done
