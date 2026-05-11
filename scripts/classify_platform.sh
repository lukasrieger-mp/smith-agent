#!/usr/bin/env bash
# Map a JIRA components JSON array (on stdin) to a platform tag:
#   kmp     - has "Shared/KMP" or "KMP" or "Shared"
#   android - has "Android" (and not exclusively iOS)
#   ios     - only iOS components
#   unclear - empty or no recognised platform components
# Precedence: kmp > android > ios > unclear.
set -euo pipefail

input=$(cat)
# Validate JSON first.
echo "$input" | jq -e 'type == "array"' >/dev/null

has() {
  echo "$input" | jq -er --arg name "$1" 'map(. == $name) | any' >/dev/null
}

# Empty array
[[ "$(echo "$input" | jq 'length')" -eq 0 ]] && { echo "unclear"; exit 0; }

if has "Shared/KMP" || has "KMP" || has "Shared"; then
  echo "kmp"
elif has "Android"; then
  echo "android"
elif has "iOS"; then
  echo "ios"
else
  echo "unclear"
fi
