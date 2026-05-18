#!/usr/bin/env bash
# Idempotently add a label to a JIRA ticket.
#
# acli's `--labels` flag overwrites the entire label list. To add without
# losing existing labels, we read the current list, append ours if missing,
# and write the merged list back.
#
# Usage: jira_label_add.sh <KEY> <LABEL>
#
# Exit codes:
#   0  label is present after this call (either we added it, or it was
#      already there — no edit was made in the latter case)
#   non-zero  acli command failed
set -euo pipefail

KEY="${1:?usage: jira_label_add.sh <KEY> <LABEL>}"
LABEL="${2:?usage: jira_label_add.sh <KEY> <LABEL>}"

# Read current labels
current_json=$(acli jira workitem view "$KEY" --fields "labels" --json)
current=$(echo "$current_json" | jq -r '.fields.labels[]?' 2>/dev/null || true)

# Already present? Done.
if echo "$current" | grep -qxF "$LABEL"; then
  exit 0
fi

# Build merged comma-separated list
merged=$(printf '%s\n%s\n' "$current" "$LABEL" \
         | grep -v '^$' \
         | paste -sd, -)

acli jira workitem edit --key "$KEY" --labels "$merged" --yes
