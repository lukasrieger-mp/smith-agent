#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/smith_config.sh"

# Isolate state in a temp dir that itself sits inside a git repo (so the
# script's git-toplevel fallback for default_target_repo works).
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Canonicalize (macOS /var → /private/var) to match scripts' `pwd -P`.
TMP=$(cd "$TMP" && pwd -P)
git -C "$TMP" init -q
git -C "$TMP" commit --allow-empty -m initial -q

# First call should create defaults and return the configured target repo —
# which defaults to the parent of SMITH_HOME (i.e. the repo SMITH_HOME lives in).
got=$(SMITH_HOME="$TMP/.smith" bash "$SCRIPT" target_repo)
assert_eq "$TMP" "$got" "default-target-repo"

# Config file should now exist
[[ -f "$TMP/.smith/config.json" ]] || { echo "FAIL: config not written" >&2; exit 1; }

# First-time setup also added `.smith/` to the target's .gitignore (lazy bootstrap)
grep -qxF '### Smith ###' "$TMP/.gitignore" || { echo "FAIL: missing smith marker in gitignore" >&2; exit 1; }
grep -qxF '.smith/' "$TMP/.gitignore" || { echo "FAIL: missing .smith/ entry in gitignore" >&2; exit 1; }

# Subsequent calls don't add duplicate gitignore entries (idempotent)
SMITH_HOME="$TMP/.smith" bash "$SCRIPT" target_repo >/dev/null
count=$(grep -cF '.smith/' "$TMP/.gitignore")
assert_eq "1" "$count" "idempotent-gitignore"

# Override value persists across calls
echo '{"target_repo": "/tmp/other", "polling_minutes": 45}' > "$TMP/.smith/config.json"
got=$(SMITH_HOME="$TMP/.smith" bash "$SCRIPT" target_repo)
assert_eq "/tmp/other" "$got" "override"
got=$(SMITH_HOME="$TMP/.smith" bash "$SCRIPT" polling_minutes)
assert_eq "45" "$got" "polling"

# max_concurrent_smiths key present in defaults (2 per spec Section 5.5)
rm -rf "$TMP/.smith"
got=$(SMITH_HOME="$TMP/.smith" bash "$SCRIPT" max_concurrent_smiths)
assert_eq "2" "$got" "max-concurrent-smiths-default"

# Unknown key -> non-zero
if SMITH_HOME="$TMP/.smith" bash "$SCRIPT" no_such_key 2>/dev/null; then
  echo "FAIL: should error on unknown key" >&2; exit 1
fi

# Pre-existing .gitignore entry: smith_config does NOT duplicate
rm -rf "$TMP/.smith"
echo ".smith/" > "$TMP/.gitignore"   # entry already present, no header
SMITH_HOME="$TMP/.smith" bash "$SCRIPT" target_repo >/dev/null
count=$(grep -cF '.smith/' "$TMP/.gitignore")
assert_eq "1" "$count" "preserves-existing-entry"

echo "PASS smith_config.test.sh"
