#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/cleanup_pr_state.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
mkdir -p "$TMP/bin"
cp "${SCRIPT_DIR}/lib/fake_gh.sh" "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"

export PATH="$TMP/bin:$PATH"
export SMITH_FAKE_GH_LOG="$TMP/gh.log"

# Make TMP a git repo so the script can resolve its root.
( cd "$TMP" && git init -q && git commit --allow-empty -q -m init )

# Pre-create per-PR state files so we can assert removal.
mkdir -p "$TMP/.smith/state/pr-fix-rounds" "$TMP/.smith/state/pr-comments"
echo '{"rounds":3,"fix_total":4,"dismiss_total":7}' > "$TMP/.smith/state/pr-fix-rounds/pr-891.json"
echo '["thread-A","thread-B"]' > "$TMP/.smith/state/pr-comments/pr-891.json"
echo '["unrelated"]' > "$TMP/.smith/state/pr-comments/pr-999.json"   # unrelated PR — must NOT be deleted

( cd "$TMP" && bash "$SCRIPT" 891 )

# State files for PR 891 are gone.
[[ ! -f "$TMP/.smith/state/pr-fix-rounds/pr-891.json" ]] \
  || { echo "FAIL: rounds state not cleaned" >&2; exit 1; }
[[ ! -f "$TMP/.smith/state/pr-comments/pr-891.json" ]] \
  || { echo "FAIL: pr-comments state not cleaned" >&2; exit 1; }

# Unrelated state is preserved.
[[ -f "$TMP/.smith/state/pr-comments/pr-999.json" ]] \
  || { echo "FAIL: unrelated PR state was deleted" >&2; exit 1; }

# Summary comment was posted via gh pr comment.
grep -qF -e "pr comment 891" "$TMP/gh.log" \
  || { echo "FAIL: pr comment not invoked" >&2; cat "$TMP/gh.log" >&2; exit 1; }
grep -qF -e "converged" "$TMP/gh.log" \
  || { echo "FAIL: summary body missing 'converged'" >&2; cat "$TMP/gh.log" >&2; exit 1; }
grep -qF -e "rounds: 3" "$TMP/gh.log" \
  || { echo "FAIL: rounds count missing from comment" >&2; cat "$TMP/gh.log" >&2; exit 1; }

echo "PASS cleanup_pr_state.test.sh"
