#!/usr/bin/env bash
# Map a JSON array of platform-marker strings (on stdin) to a platform tag.
# The input can be JIRA components, labels, or the union of both — Smith's
# callers merge components+labels before invoking this script.
#
#   kmp     - has "Shared/KMP", "KMP", "Shared", or "Multiplatform"
#   android - has "Android" (and no higher-precedence kmp marker)
#   ios     - only iOS marker(s)
#   unclear - empty or no recognised platform marker
#
# Precedence: kmp > android > ios > unclear.
# Rationale: "Multiplatform" implies the work spans iOS+Android+shared; treat
# as kmp so the agent works in shared code first. The post-enrichment 50%-iOS
# safety net (spec Section 6.7) catches mis-tagged iOS-only multiplatform
# tickets.
set -euo pipefail

input=$(cat)
echo "$input" | jq -e 'type == "array"' >/dev/null

has() {
  echo "$input" | jq -er --arg name "$1" 'map(. == $name) | any' >/dev/null
}

[[ "$(echo "$input" | jq 'length')" -eq 0 ]] && { echo "unclear"; exit 0; }

if has "Shared/KMP" || has "KMP" || has "Shared" || has "Multiplatform"; then
  echo "kmp"
elif has "Android"; then
  echo "android"
elif has "iOS"; then
  echo "ios"
else
  echo "unclear"
fi
