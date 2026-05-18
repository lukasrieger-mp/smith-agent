#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/bin/write_brief.sh"

# Stage worktree + fake acli
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
git -C "$TMP" init -q
git -C "$TMP" commit --allow-empty -m initial -q
mkdir -p "$TMP/bin"
cp "${SCRIPT_DIR}/lib/fake_acli.sh" "$TMP/bin/acli"
chmod +x "$TMP/bin/acli"
export PATH="$TMP/bin:$PATH"
export SMITH_FAKE_ACLI_LOG="$TMP/acli.log"
export SMITH_FAKE_ACLI_VIEW_FIXTURE="${SCRIPT_DIR}/fixtures/jira-ticket-with-adf.json"

# Run inside the temp dir so the script's `git rev-parse` resolves cleanly
cd "$TMP"

# Happy path: writes brief at the expected path
brief_path=$(bash "$SCRIPT" APP-5601)
[[ -n "$brief_path" ]] || { echo "FAIL: script printed empty path" >&2; exit 1; }
[[ -f "$brief_path" ]] || { echo "FAIL: brief file not created at '$brief_path'" >&2; exit 1; }

# Brief lives under .smith/briefs/ in the worktree
[[ "$brief_path" == *".smith/briefs/APP-5601-brief.md" ]] || { echo "FAIL: unexpected brief path: $brief_path" >&2; exit 1; }

# Content checks
content=$(cat "$brief_path")
assert_contains "$content" "# Brief — APP-5601: Hide skeleton loader for repeat visits" "title"
assert_contains "$content" "## Original ticket" "section-original"
assert_contains "$content" "## Smith's reading" "section-reading"
assert_contains "$content" "## Proposed DoD" "section-dod"
assert_contains "$content" "## Background" "adf-h2-1"
assert_contains "$content" "On repeat visits" "adf-paragraph"
assert_contains "$content" "- Skeleton is hidden if cached data is present on visit" "adf-bullet"
assert_contains "$content" "Android" "components"

# Re-run is idempotent — overwrites the brief with the same content
bash "$SCRIPT" APP-5601 >/dev/null
assert_exit_code 0 $? "idempotent"

# Missing arg
if bash "$SCRIPT" 2>/dev/null; then echo "FAIL: missing arg" >&2; exit 1; fi

echo "PASS write_brief.test.sh"
