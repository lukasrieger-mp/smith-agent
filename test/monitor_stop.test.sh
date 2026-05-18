#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/bin/monitor_stop.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
SENTINEL="$TMP/STOP"

# Each oneshot run resets `last_state`, so to test transitions we need a
# different pattern: we test individual-poll behaviour. The monitor's
# initial empty `last_state` and skip-first-lifted logic mean:
#   - First poll, no sentinel → no output (skip-first-lifted)
#   - First poll, sentinel present → emit "smith.stop.requested"
# Subsequent transitions (within a long-running loop) emit both lifted
# and requested. Oneshot only covers the first-poll case.

# Case A: no sentinel, first poll -> no output (skip-first-lifted suppression)
got=$( SMITH_MONITOR_ONESHOT=1 SMITH_STOP_SENTINEL="$SENTINEL" bash "$SCRIPT" )
assert_eq "" "$got" "first-poll-no-sentinel-no-output"

# Case B: sentinel exists, first poll -> emit "requested"
touch "$SENTINEL"
got=$( SMITH_MONITOR_ONESHOT=1 SMITH_STOP_SENTINEL="$SENTINEL" bash "$SCRIPT" )
[[ "$got" == '{"type":"smith.stop.requested"}' ]] || { echo "FAIL: expected requested notification, got: $got" >&2; exit 1; }
rm "$SENTINEL"

# Case C: confirm fast poll interval default is small (2s)
# Test by reading the script's INTERVAL default rather than waiting.
default=$(grep -E '^INTERVAL=' "$SCRIPT" | head -1)
[[ "$default" == *':-2}'* ]] || { echo "FAIL: expected default INTERVAL=2, got: $default" >&2; exit 1; }

echo "PASS monitor_stop.test.sh"
