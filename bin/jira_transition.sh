#!/usr/bin/env bash
# Transition a JIRA ticket to a target status.
#
# Usage: jira_transition.sh <KEY> <TARGET_STATUS>
#
# Optional pre-check: set SMITH_EXPECTED_FROM_STATUS to the status the
# ticket SHOULD currently be in. If set, the script verifies the current
# status matches before transitioning, and aborts cleanly on mismatch
# (the race-guard from spec Section 7.4 step 6).
#
# Exit codes:
#   0  transition succeeded
#   1  pre-check failed (status mismatch); no transition attempted
#   2  acli command failed
set -euo pipefail

KEY="${1:?usage: jira_transition.sh <KEY> <TARGET_STATUS>}"
TO="${2:?usage: jira_transition.sh <KEY> <TARGET_STATUS>}"
EXPECTED_FROM="${SMITH_EXPECTED_FROM_STATUS:-}"

if [[ -n "$EXPECTED_FROM" ]]; then
  current=$(acli jira workitem view "$KEY" --fields "status" --json \
            | jq -er '.fields.status.name')
  if [[ "$current" != "$EXPECTED_FROM" ]]; then
    echo "jira_transition: $KEY is in status '$current' (expected '$EXPECTED_FROM')" >&2
    exit 1
  fi
fi

acli jira workitem transition --key "$KEY" --status "$TO" --yes
