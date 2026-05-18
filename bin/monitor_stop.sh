#!/usr/bin/env bash
# Background monitor: watches the .smith/STOP sentinel file. Emits a
# notification when STOP appears (operator wants to pause new claims)
# and another when it disappears (operator resumed).
#
# Notification schema:
#   {"type":"smith.stop.requested"}
#   {"type":"smith.stop.lifted"}
#
# Default poll interval: 2s — operator wants the kill switch to feel
# immediate.

set -uo pipefail
INTERVAL="${SMITH_STOP_POLL_INTERVAL:-2}"
SENTINEL="${SMITH_STOP_SENTINEL:-.smith/STOP}"
ONESHOT="${SMITH_MONITOR_ONESHOT:-0}"
# Initial state: "unknown" so first poll always emits the correct line.
last_state=""

poll_once() {
  local current
  if [[ -f "$SENTINEL" ]]; then
    current="requested"
  else
    current="lifted"
  fi
  if [[ "$current" != "$last_state" ]]; then
    # Skip emitting "lifted" on the very first poll (the system isn't
    # really transitioning from anywhere — it's just starting up clean).
    if [[ "$last_state" != "" ]] || [[ "$current" == "requested" ]]; then
      printf '{"type":"smith.stop.%s"}\n' "$current"
    fi
    last_state="$current"
  fi
}

if [[ "$ONESHOT" == "1" ]]; then
  poll_once
  exit 0
fi

while true; do
  # Gate: only watch the kill switch when watchdog is armed.
  if [[ -f .smith/state/watchdog-mode ]]; then
    poll_once
  fi
  sleep "$INTERVAL"
done
