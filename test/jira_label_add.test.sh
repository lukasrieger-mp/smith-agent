#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/bin/jira_label_add.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
mkdir -p "$TMP/bin"
cp "${SCRIPT_DIR}/lib/fake_acli.sh" "$TMP/bin/acli"
chmod +x "$TMP/bin/acli"

export PATH="$TMP/bin:$PATH"
export SMITH_FAKE_ACLI_LOG="$TMP/acli.log"

# Case 1: ticket has no labels yet → add ours; final label list is just ours
echo '{"fields":{"labels":[]}}' > "$TMP/view.json"
export SMITH_FAKE_ACLI_VIEW_FIXTURE="$TMP/view.json"
> "$TMP/acli.log"
bash "$SCRIPT" APP-1234 smith-implementing
got=$(cat "$TMP/acli.log")
assert_contains "$got" "view APP-1234" "case1-viewed"
assert_contains "$got" "edit --key APP-1234 --labels smith-implementing" "case1-edit-with-only-new-label"

# Case 2: ticket has existing labels → add ours; final list preserves originals
echo '{"fields":{"labels":["Android","iOS"]}}' > "$TMP/view.json"
> "$TMP/acli.log"
bash "$SCRIPT" APP-1234 smith-implementing
got=$(cat "$TMP/acli.log")
# Final --labels arg should contain all three, comma-separated (order: existing first, then new)
assert_contains "$got" "--labels Android,iOS,smith-implementing" "case2-preserves-existing"

# Case 3: label already present → idempotent; final list unchanged; no edit call
echo '{"fields":{"labels":["Android","smith-implementing","iOS"]}}' > "$TMP/view.json"
> "$TMP/acli.log"
bash "$SCRIPT" APP-1234 smith-implementing
got=$(cat "$TMP/acli.log")
assert_contains "$got" "view APP-1234" "case3-viewed"
grep -q "workitem edit" "$TMP/acli.log" && { echo "FAIL: should NOT edit when label already present" >&2; exit 1; }

# Case 4: missing args -> non-zero
if bash "$SCRIPT" 2>/dev/null; then echo "FAIL: missing args" >&2; exit 1; fi
if bash "$SCRIPT" APP-1234 2>/dev/null; then echo "FAIL: missing label" >&2; exit 1; fi

echo "PASS jira_label_add.test.sh"
