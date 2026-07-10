#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

HOOK="${ROOT}/bin/hook_keep_anderson_alive.sh"

# Run the hook from a temp cwd (payload probe writes .smith/state/ there),
# with the legacy env vars cleared unless a test sets them explicitly.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

run_hook() {
  # $1: stdin payload ("" for none); rest: env VAR=VALUE pairs
  local payload="$1"; shift
  local rc=0
  (
    cd "$TMP"
    unset CLAUDE_TEAMMATE_NAME CLAUDE_TEAMMATE_TYPE
    export "$@" DUMMY=1
    if [[ -n "$payload" ]]; then
      printf '%s' "$payload" | bash "$HOOK" 2>/dev/null
    else
      bash "$HOOK" < /dev/null 2>/dev/null
    fi
  ) || rc=$?
  echo "$rc"
}

# --- Anderson detected from stdin JSON (candidate keys) -> exit 2 ---

rc=$(run_hook '{"hook_event_name":"TeammateIdle","teammate_name":"anderson-impl-APP-1234"}')
assert_eq "2" "$rc" "stdin-teammate_name-anderson"

rc=$(run_hook '{"hook_event_name":"TeammateIdle","teammate":{"name":"anderson-fixer-4321"}}')
assert_eq "2" "$rc" "stdin-nested-teammate-name-anderson"

rc=$(run_hook '{"hook_event_name":"TeammateIdle","agent_name":"anderson-impl-APP-9"}')
assert_eq "2" "$rc" "stdin-agent_name-anderson"

rc=$(run_hook '{"hook_event_name":"TeammateIdle","teammate_type":"anderson-impl","teammate_name":"custom-name"}')
assert_eq "2" "$rc" "stdin-type-anderson"

# --- Anderson detected via legacy env fallback -> exit 2 ---

rc=$(run_hook '{"hook_event_name":"TeammateIdle"}' CLAUDE_TEAMMATE_NAME=anderson-impl-APP-1234)
assert_eq "2" "$rc" "env-name-anderson"

rc=$(run_hook "" CLAUDE_TEAMMATE_TYPE=anderson-fixer)
assert_eq "2" "$rc" "env-type-anderson-no-stdin"

# --- Non-Anderson -> exit 0 ---

rc=$(run_hook '{"hook_event_name":"TeammateIdle","teammate_name":"smith-impl-APP-1234"}')
assert_eq "0" "$rc" "smith-idle-allowed"

rc=$(run_hook '{"hook_event_name":"TeammateIdle"}')
assert_eq "0" "$rc" "unknown-teammate-allowed"

rc=$(run_hook "")
assert_eq "0" "$rc" "no-payload-no-env-allowed"

# --- Stay-alive message lands on stderr ---

msg=$(cd "$TMP" && printf '%s' '{"teammate_name":"anderson-impl-APP-1"}' | bash "$HOOK" 2>&1 >/dev/null) || true
assert_contains "$msg" "Do not go idle" "stderr-stay-alive-message"

# --- Payload probe written once ---

[[ -f "$TMP/.smith/state/teammate-idle-payload.json" ]] \
  || { echo "FAIL: payload probe file not written" >&2; exit 1; }

echo "PASS hook_keep_anderson_alive.test.sh"
