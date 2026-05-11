#!/usr/bin/env bash
# Idempotently remove a label from a JIRA ticket.
#
# Reads the current label list first. If the target label is present, calls
# `acli ... edit --remove-labels <label>`. If absent, exits 0 with no acli
# write.
#
# Usage: jira_label_remove.sh <KEY> <LABEL>
set -euo pipefail

KEY="${1:?usage: jira_label_remove.sh <KEY> <LABEL>}"
LABEL="${2:?usage: jira_label_remove.sh <KEY> <LABEL>}"

current_json=$(acli jira workitem view "$KEY" --fields "labels" --json)
current=$(echo "$current_json" | jq -r '.fields.labels[]?' 2>/dev/null || true)

if ! echo "$current" | grep -qxF "$LABEL"; then
  # Already absent — done.
  exit 0
fi

acli jira workitem edit --key "$KEY" --remove-labels "$LABEL" --yes
