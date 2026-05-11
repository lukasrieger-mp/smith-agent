#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/assert_target_repo.sh"

# Case 1: inside a fresh git repo with no .smith/ → PASS via lazy bootstrap.
# (assert_target_repo now auto-invokes smith_config.sh which creates config
# + gitignore entry. This is the lazy-setup contract.)
TMP1=$(mktemp -d)
trap 'rm -rf "$TMP1" "$TMP2" "$TMP3"' EXIT
TMP1=$(cd "$TMP1" && pwd -P)
git -C "$TMP1" init -q
git -C "$TMP1" commit --allow-empty -m initial -q

( cd "$TMP1" && bash "$SCRIPT" ) >/dev/null
assert_exit_code 0 $? "case1-lazy-bootstrap-fresh-repo"

# After the first call, .smith/config.json exists
[[ -f "$TMP1/.smith/config.json" ]] || { echo "FAIL: config not auto-created" >&2; exit 1; }
# And .gitignore has the .smith/ entry
grep -qxF '.smith/' "$TMP1/.gitignore" || { echo "FAIL: .gitignore not updated" >&2; exit 1; }

# Case 2: inside a repo with pre-existing .smith/config.json → pass, no clobber
TMP2=$(mktemp -d)
TMP2=$(cd "$TMP2" && pwd -P)
git -C "$TMP2" init -q
git -C "$TMP2" commit --allow-empty -m initial -q
mkdir -p "$TMP2/.smith"
echo '{"target_repo":"custom"}' > "$TMP2/.smith/config.json"
( cd "$TMP2" && bash "$SCRIPT" ) >/dev/null
assert_exit_code 0 $? "case2-existing-config"
# Existing config not overwritten
got=$(jq -r '.target_repo' "$TMP2/.smith/config.json")
assert_eq "custom" "$got" "case2-config-preserved"

# Case 3: inside a worktree of TMP2 -> still passes (works from worktrees)
TMP3=$(mktemp -d)
rm -rf "$TMP3"   # git worktree add needs the dir not to exist
git -C "$TMP2" worktree add -q "$TMP3" -b feature/test 2>/dev/null || \
  git -C "$TMP2" worktree add -q "$TMP3" -B feature/test
( cd "$TMP3" && bash "$SCRIPT" ) >/dev/null
assert_exit_code 0 $? "case3-worktree-passes"

# Case 4: SMITH_TARGET_REPO env override - matching path -> pass
( cd "$TMP2" && SMITH_TARGET_REPO="$TMP2" bash "$SCRIPT" ) >/dev/null
assert_exit_code 0 $? "case4-env-match"

# Case 5: SMITH_TARGET_REPO env override - non-matching path -> fail
if ( cd "$TMP2" && SMITH_TARGET_REPO="/tmp/nonexistent-elsewhere" bash "$SCRIPT" ) 2>/dev/null; then
  echo "FAIL: env override mismatch should reject" >&2; exit 1
fi

# Case 6: not inside a git repo at all -> fail
NOTREPO=$(mktemp -d)
if ( cd "$NOTREPO" && bash "$SCRIPT" ) 2>/dev/null; then
  echo "FAIL: should fail outside any git repo" >&2; exit 1
fi
rm -rf "$NOTREPO"

echo "PASS assert_target_repo.test.sh"
