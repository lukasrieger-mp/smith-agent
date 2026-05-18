#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/bin/checkout_pr_worktree.sh"

# Stage a fake target repo with an existing remote branch `task/app-1234-foo`
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)

git init -q --bare "$TMP/remote.git"
git clone -q "$TMP/remote.git" "$TMP/target"
git -C "$TMP/target" commit --allow-empty -m initial -q
git -C "$TMP/target" branch -M develop
git -C "$TMP/target" push -q -u origin develop

# Create the PR's branch in the remote (simulating what Smith pushed in
# ticket mode)
git -C "$TMP/target" checkout -q -b task/app-1234-foo
git -C "$TMP/target" commit --allow-empty -m "feat: thing" -q
git -C "$TMP/target" push -q -u origin task/app-1234-foo
git -C "$TMP/target" checkout -q develop
git -C "$TMP/target" branch -D task/app-1234-foo
git -C "$TMP/target" fetch -q origin

cd "$TMP/target"

# Case 1: happy path - creates worktree at .smith/worktrees/app-1234 checked out to task/app-1234-foo
bash "$SCRIPT" APP-1234 task/app-1234-foo
[[ -d ".smith/worktrees/app-1234" ]] || { echo "FAIL: worktree dir not created" >&2; exit 1; }
got_branch=$(git -C ".smith/worktrees/app-1234" rev-parse --abbrev-ref HEAD)
assert_eq "task/app-1234-foo" "$got_branch" "case1-branch-checked-out"

# Tracking branch is set to origin/task/app-1234-foo
upstream=$(git -C ".smith/worktrees/app-1234" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo "")
assert_eq "origin/task/app-1234-foo" "$upstream" "case1-upstream"

# Case 2: idempotent re-run (worktree already exists on right branch)
bash "$SCRIPT" APP-1234 task/app-1234-foo
assert_exit_code 0 $? "case2-idempotent"

# Case 3: branch doesn't exist on remote -> fail
if bash "$SCRIPT" APP-9999 task/app-9999-nope 2>/dev/null; then
  echo "FAIL: should reject non-existent remote branch" >&2; exit 1
fi

# Case 4: missing args
if bash "$SCRIPT" 2>/dev/null; then echo "FAIL: no args" >&2; exit 1; fi
if bash "$SCRIPT" APP-1234 2>/dev/null; then echo "FAIL: missing branch" >&2; exit 1; fi

# Case 5: branch doesn't start with task/ - reject
if bash "$SCRIPT" APP-2222 develop 2>/dev/null; then
  echo "FAIL: should reject non-task/* branches" >&2; exit 1
fi

echo "PASS checkout_pr_worktree.test.sh"
