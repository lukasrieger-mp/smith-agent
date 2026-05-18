#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/bin/assert_clis_authenticated.sh"

# Set up an isolated $PATH containing only our fake gh + acli.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
mkdir -p "$TMP/bin"
cp "${SCRIPT_DIR}/lib/fake_gh.sh"   "$TMP/bin/gh"
cp "${SCRIPT_DIR}/lib/fake_acli.sh" "$TMP/bin/acli"
chmod +x "$TMP/bin/gh" "$TMP/bin/acli"

run_assert() {
  PATH="$TMP/bin:/usr/bin:/bin" bash "$SCRIPT" 2>&1
}

# --- Case 1: both authenticated → exit 0, no stderr ---
set +e
out=$(run_assert)
ec=$?
set -e
assert_eq "0" "$ec" "both-authed-passes"
assert_eq "" "$out" "no stderr when both authed"

# --- Case 2: gh missing auth → exit 1, message mentions gh + remedy ---
set +e
out=$(SMITH_FAKE_GH_AUTH_FAIL=1 run_assert)
ec=$?
set -e
assert_eq "1" "$ec" "gh-fail-exits-nonzero"
[[ "$out" == *"GitHub CLI"* ]] \
  || { echo "FAIL: gh failure missing 'GitHub CLI' header in: $out" >&2; exit 1; }
[[ "$out" == *"gh auth login"* ]] \
  || { echo "FAIL: gh failure missing remedy command in: $out" >&2; exit 1; }
# acli was fine, so its block should NOT appear
[[ "$out" != *"Atlassian CLI"* ]] \
  || { echo "FAIL: acli block should not appear when only gh failed: $out" >&2; exit 1; }

# --- Case 3: acli missing auth → exit 1, message mentions acli + remedy ---
set +e
out=$(SMITH_FAKE_ACLI_AUTH_FAIL=1 run_assert)
ec=$?
set -e
assert_eq "1" "$ec" "acli-fail-exits-nonzero"
[[ "$out" == *"Atlassian CLI"* ]] \
  || { echo "FAIL: acli failure missing 'Atlassian CLI' header in: $out" >&2; exit 1; }
[[ "$out" == *"acli jira auth login"* ]] \
  || { echo "FAIL: acli failure missing remedy command in: $out" >&2; exit 1; }
[[ "$out" != *"GitHub CLI"* ]] \
  || { echo "FAIL: gh block should not appear when only acli failed: $out" >&2; exit 1; }

# --- Case 4: BOTH missing auth → exit 1, BOTH blocks present (no early exit) ---
set +e
out=$(SMITH_FAKE_GH_AUTH_FAIL=1 SMITH_FAKE_ACLI_AUTH_FAIL=1 run_assert)
ec=$?
set -e
assert_eq "1" "$ec" "both-fail-exits-nonzero"
[[ "$out" == *"GitHub CLI"* ]] \
  || { echo "FAIL: gh block missing in 'both fail' run: $out" >&2; exit 1; }
[[ "$out" == *"Atlassian CLI"* ]] \
  || { echo "FAIL: acli block missing in 'both fail' run: $out" >&2; exit 1; }

echo "PASS assert_clis_authenticated.test.sh"
