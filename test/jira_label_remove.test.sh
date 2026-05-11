#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/jira_label_remove.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
mkdir -p "$TMP/bin"
cp "${SCRIPT_DIR}/lib/fake_acli.sh" "$TMP/bin/acli"
chmod +x "$TMP/bin/acli"

export PATH="$TMP/bin:$PATH"
export SMITH_FAKE_ACLI_LOG="$TMP/acli.log"
export SMITH_FAKE_ACLI_VIEW_FIXTURE="$TMP/view.json"

# Case 1: label present → remove
echo '{"fields":{"labels":["Android","smith-implementing","iOS"]}}' > "$TMP/view.json"
> "$TMP/acli.log"
bash "$SCRIPT" APP-1234 smith-implementing
got=$(cat "$TMP/acli.log")
assert_contains "$got" "view APP-1234" "case1-viewed"
assert_contains "$got" "edit --key APP-1234 --remove-labels smith-implementing" "case1-remove-called"

# Case 2: label NOT present → idempotent; no edit call
echo '{"fields":{"labels":["Android","iOS"]}}' > "$TMP/view.json"
> "$TMP/acli.log"
bash "$SCRIPT" APP-1234 smith-implementing
got=$(cat "$TMP/acli.log")
assert_contains "$got" "view APP-1234" "case2-viewed"
grep -q "workitem edit" "$TMP/acli.log" && { echo "FAIL: should NOT edit when label absent" >&2; exit 1; }

# Case 3: missing args
if bash "$SCRIPT" 2>/dev/null; then echo "FAIL: missing args" >&2; exit 1; fi
if bash "$SCRIPT" APP-1234 2>/dev/null; then echo "FAIL: missing label" >&2; exit 1; fi

echo "PASS jira_label_remove.test.sh"
