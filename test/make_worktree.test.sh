#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/make_worktree.sh"

# Stage a fake target repo with a fake `origin/develop` branch.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)

# Create a "remote" bare repo + a "target" working clone with origin set.
git init -q --bare "$TMP/remote.git"
git clone -q "$TMP/remote.git" "$TMP/target"
git -C "$TMP/target" commit --allow-empty -m initial -q
git -C "$TMP/target" branch -M develop
git -C "$TMP/target" push -q -u origin develop

# Case 1: happy path - creates worktree at .smith/worktrees/app-1234/ on branch task/app-1234-foo
cd "$TMP/target"
bash "$SCRIPT" APP-1234 task/app-1234-foo
[[ -d ".smith/worktrees/app-1234" ]] || { echo "FAIL: worktree dir not created" >&2; exit 1; }
got_branch=$(git -C ".smith/worktrees/app-1234" rev-parse --abbrev-ref HEAD)
assert_eq "task/app-1234-foo" "$got_branch" "case1-branch-checked-out"

# Case 2: same arguments again - idempotent (no error, no duplicate worktree)
bash "$SCRIPT" APP-1234 task/app-1234-foo
assert_exit_code 0 $? "case2-idempotent"

# Case 3: try to use the same branch for a DIFFERENT ticket - should fail (branch occupied)
if bash "$SCRIPT" APP-5678 task/app-1234-foo 2>/dev/null; then
  echo "FAIL: should reject branch already checked out elsewhere" >&2; exit 1
fi

# Case 4: missing args
if bash "$SCRIPT" 2>/dev/null; then echo "FAIL: missing args" >&2; exit 1; fi
if bash "$SCRIPT" APP-1234 2>/dev/null; then echo "FAIL: missing branch" >&2; exit 1; fi

# Case 5: branch arg doesn't start with task/ - reject
if bash "$SCRIPT" APP-2222 main 2>/dev/null; then
  echo "FAIL: should reject non-task/* branch names" >&2; exit 1
fi

echo "PASS make_worktree.test.sh"
