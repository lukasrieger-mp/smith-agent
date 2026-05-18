#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/bin/validate_anderson_reply.sh"

run() { bash "$SCRIPT" "$@" 2>&1; }

# --- VALID replies ---

# Empty findings (gate passes)
echo '{"type":"anderson.review.findings","mode":"spec","round":1,"findings":[]}' \
  | bash "$SCRIPT" >/dev/null
assert_exit_code 0 $? "valid-empty"

# One high-conf finding
cat <<'JSON' | bash "$SCRIPT" >/dev/null
{
  "type": "anderson.review.findings",
  "mode": "diff",
  "round": 2,
  "findings": [
    {"severity":"high","confidence":85,"location":"foo.kt:42","issue":"x","suggestion":"y"}
  ]
}
JSON
assert_exit_code 0 $? "valid-one-finding"

# Three findings, mixed severities
cat <<'JSON' | bash "$SCRIPT" >/dev/null
{
  "type":"anderson.review.findings","mode":"plan","round":3,
  "findings":[
    {"severity":"high","confidence":90,"location":"a","issue":"i","suggestion":"s"},
    {"severity":"medium","confidence":80,"location":"b","issue":"i","suggestion":"s"},
    {"severity":"low","confidence":95,"location":"c","issue":"i","suggestion":"s"}
  ]
}
JSON
assert_exit_code 0 $? "valid-mixed"

# --- INVALID replies ---

# Not JSON
if echo "not json" | bash "$SCRIPT" 2>/dev/null; then echo "FAIL: not-json should reject" >&2; exit 1; fi

# Wrong type
if echo '{"type":"wrong","mode":"spec","round":1,"findings":[]}' | bash "$SCRIPT" 2>/dev/null; then echo "FAIL: wrong type" >&2; exit 1; fi

# Bad mode
if echo '{"type":"anderson.review.findings","mode":"bogus","round":1,"findings":[]}' | bash "$SCRIPT" 2>/dev/null; then echo "FAIL: bad mode" >&2; exit 1; fi

# Round out of range
if echo '{"type":"anderson.review.findings","mode":"spec","round":5,"findings":[]}' | bash "$SCRIPT" 2>/dev/null; then echo "FAIL: round 5" >&2; exit 1; fi

# Confidence below 80
if cat <<'JSON' | bash "$SCRIPT" 2>/dev/null; then echo "FAIL: conf<80" >&2; exit 1; fi
{"type":"anderson.review.findings","mode":"spec","round":1,
 "findings":[{"severity":"high","confidence":50,"location":"x","issue":"y","suggestion":"z"}]}
JSON

# Bad severity
if cat <<'JSON' | bash "$SCRIPT" 2>/dev/null; then echo "FAIL: bad severity" >&2; exit 1; fi
{"type":"anderson.review.findings","mode":"spec","round":1,
 "findings":[{"severity":"urgent","confidence":85,"location":"x","issue":"y","suggestion":"z"}]}
JSON

# Missing required field
if cat <<'JSON' | bash "$SCRIPT" 2>/dev/null; then echo "FAIL: missing field" >&2; exit 1; fi
{"type":"anderson.review.findings","mode":"spec","round":1,
 "findings":[{"severity":"high","confidence":85,"location":"x"}]}
JSON

# --- Convenience: count-high subcommand ---
got=$(cat <<'JSON' | bash "$SCRIPT" --count-high
{"type":"anderson.review.findings","mode":"diff","round":1,
 "findings":[
   {"severity":"high","confidence":90,"location":"a","issue":"i","suggestion":"s"},
   {"severity":"high","confidence":85,"location":"b","issue":"i","suggestion":"s"},
   {"severity":"medium","confidence":80,"location":"c","issue":"i","suggestion":"s"}
 ]}
JSON
)
assert_eq "2" "$got" "count-high"

# Empty -> 0
got=$(echo '{"type":"anderson.review.findings","mode":"spec","round":1,"findings":[]}' | bash "$SCRIPT" --count-high)
assert_eq "0" "$got" "count-high-empty"

echo "PASS validate_anderson_reply.test.sh"
