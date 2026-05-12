#!/usr/bin/env bash
# Validate Mr. Anderson's mailbox reply JSON against the documented schema
# (see agents/anderson-impl.md "Your reply" section). Read JSON on stdin.
#
# Modes:
#   (default)        validate; exit 0 on valid, 1 on invalid
#   --count-high     validate AND print the count of high-severity findings
#
# Used by smith:pipeline to:
#   1. Confirm Anderson's reply parses (defends against malformed JSON)
#   2. Get the high-severity count without re-parsing in skill prose
set -euo pipefail

MODE="${1:-validate}"
case "$MODE" in
  validate|--count-high) ;;
  *) echo "validate_anderson_reply: unknown mode '$MODE'" >&2; exit 2 ;;
esac

input=$(cat)

# Validate top-level shape
echo "$input" | jq -e '
  (.type == "anderson.review.findings")
  and (.mode | IN("spec","plan","diff"))
  and (.round | type == "number" and . >= 1 and . <= 3)
  and (.findings | type == "array")
  and ([.findings[] |
        (.severity | IN("high","medium","low"))
        and (.confidence | type == "number" and . >= 80 and . <= 100)
        and (.location | type == "string")
        and (.issue | type == "string")
        and (.suggestion | type == "string")
       ] | all)
' >/dev/null

if [[ "$MODE" == "--count-high" ]]; then
  echo "$input" | jq '[.findings[] | select(.severity == "high")] | length'
fi
