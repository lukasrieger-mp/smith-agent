#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/assert_target_repo.sh"

# Case 1: inside a fresh git repo with no .smith/ -> fail (no .smith/config.json)
TMP1=$(mktemp -d)
trap 'rm -rf "$TMP1" "$TMP2" "$TMP3"' EXIT
git -C "$TMP1" init -q
git -C "$TMP1" commit --allow-empty -m initial -q
if ( cd "$TMP1" && bash "$SCRIPT" ) 2>/dev/null; then
  echo "FAIL: should reject repo with no .smith/config.json" >&2; exit 1
fi

# Case 2: inside a repo WITH .smith/config.json -> pass
TMP2=$(mktemp -d)
git -C "$TMP2" init -q
git -C "$TMP2" commit --allow-empty -m initial -q
mkdir -p "$TMP2/.smith"
echo '{"target_repo":"x"}' > "$TMP2/.smith/config.json"
( cd "$TMP2" && bash "$SCRIPT" ) >/dev/null
assert_exit_code 0 $? "smith-installed"

# Case 3: inside a worktree of TMP2 -> still passes (works from worktrees)
TMP3=$(mktemp -d)
rm -rf "$TMP3"   # git worktree add needs the dir not to exist
git -C "$TMP2" worktree add -q "$TMP3" -b feature/test 2>/dev/null || \
  git -C "$TMP2" worktree add -q "$TMP3" -B feature/test
( cd "$TMP3" && bash "$SCRIPT" ) >/dev/null
assert_exit_code 0 $? "worktree-passes"

# Case 4: SMITH_TARGET_REPO env override - matching path -> pass
( cd "$TMP2" && SMITH_TARGET_REPO="$TMP2" bash "$SCRIPT" ) >/dev/null
assert_exit_code 0 $? "env-match"

# Case 5: SMITH_TARGET_REPO env override - non-matching path -> fail
if ( cd "$TMP2" && SMITH_TARGET_REPO="/tmp/nonexistent-elsewhere" bash "$SCRIPT" ) 2>/dev/null; then
  echo "FAIL: env override mismatch should reject" >&2; exit 1
fi

echo "PASS assert_target_repo.test.sh"
