#!/usr/bin/env bash
# Pick the top eligible JIRA candidate from a scan result, skipping any
# whose `key` is already an active Smith subject.
#
# Input  (stdin): JSON array of candidates from `jira_scan.sh`
#                 (each must have a `key` field)
# Output (stdout): the chosen `key` string
# Exit code:
#   0  picked a key
#   1  no eligible candidate (either input was empty, all candidates
#      are already active, or input was malformed)
#
# Assumes the input is already sorted per the JQL `ORDER BY priority
# DESC, created ASC` clause — picks the FIRST candidate not already
# in `active_smiths.sh list`.
set -euo pipefail

plugin_scripts=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# Read + validate input
input=$(cat)
echo "$input" | jq -e 'type == "array"' >/dev/null

# Get the active-subject list
active_subjects=$(bash "$plugin_scripts/active_smiths.sh" list \
                  | jq -c '[.[].subject]')

# Find the first key not in active_subjects
choice=$(echo "$input" | jq -er --argjson active "$active_subjects" '
  map(select(.key as $k | $active | contains([$k]) | not))
  | .[0].key // empty
')

if [[ -z "$choice" || "$choice" == "null" ]]; then
  echo "pick_top_candidate: no eligible candidate" >&2
  exit 1
fi

echo "$choice"
