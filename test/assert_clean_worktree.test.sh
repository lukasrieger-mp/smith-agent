#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/bin/assert_clean_worktree.sh"

# Make a throwaway worktree to test in. Use $(mktemp -d) under repo so the
# script's git rev-parse resolves cleanly.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

git -C "$TMP" init -q
git -C "$TMP" commit --allow-empty -m initial -q

# clean worktree -> exit 0
( cd "$TMP" && bash "$SCRIPT" ) >/dev/null
assert_exit_code 0 $? "clean"

# dirty worktree -> non-zero
touch "$TMP/dirty.txt"
if ( cd "$TMP" && bash "$SCRIPT" ) 2>/dev/null; then
  echo "FAIL: should fail on dirty worktree" >&2; exit 1
fi

echo "PASS assert_clean_worktree.test.sh"
