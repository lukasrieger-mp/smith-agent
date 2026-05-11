#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/abort_smith.sh"

# Stage: temp target git repo + fake acli on PATH
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)

git init -q --bare "$TMP/remote.git"
git clone -q "$TMP/remote.git" "$TMP/target"
TARGET="$TMP/target"
git -C "$TARGET" config user.email "test@example.com"
git -C "$TARGET" config user.name "Test"
git -C "$TARGET" commit --allow-empty -m initial -q
git -C "$TARGET" branch -M develop
git -C "$TARGET" push -q -u origin develop

mkdir -p "$TMP/bin"
cp "${SCRIPT_DIR}/lib/fake_acli.sh" "$TMP/bin/acli"
chmod +x "$TMP/bin/acli"

export PATH="$TMP/bin:$PATH"
export SMITH_FAKE_ACLI_LOG="$TMP/acli.log"
export SMITH_FAKE_ACLI_VIEW_FIXTURE="$TMP/view.json"

# ===== Case 1: ticket-mode abort, JIRA in claim status =====
cd "$TARGET"
# Set up worktree + brief + active_smiths entry
( cd "$TARGET" && bash "${ROOT}/scripts/make_worktree.sh" APP-1234 task/app-1234-foo )
mkdir -p .smith/briefs
echo "# Brief" > .smith/briefs/APP-1234-brief.md
bash "${ROOT}/scripts/active_smiths.sh" add smith-APP-1234 anderson-APP-1234 ticket APP-1234

# JIRA returns "In Progress" (claim status)
echo '{"fields":{"status":{"name":"In Progress"},"labels":["smith-implementing"]}}' > "$SMITH_FAKE_ACLI_VIEW_FIXTURE"
> "$TMP/acli.log"

bash "$SCRIPT" APP-1234 >/dev/null

# Worktree gone
[[ ! -d ".smith/worktrees/app-1234" ]] || { echo "FAIL: worktree not removed" >&2; exit 1; }
# Brief gone
[[ ! -f ".smith/briefs/APP-1234-brief.md" ]] || { echo "FAIL: brief not removed" >&2; exit 1; }
# Local branch gone (was never pushed since make_worktree creates from develop)
git -C "$TARGET" rev-parse --verify refs/heads/task/app-1234-foo >/dev/null 2>&1 \
  && { echo "FAIL: local branch not deleted" >&2; exit 1; } || true
# active_smiths empty
got=$(bash "${ROOT}/scripts/active_smiths.sh" count)
assert_eq "0" "$got" "case1-active-empty"
# JIRA: should have attempted transition + label removal
grep -q "transition --key APP-1234 --status Ready for Development" "$TMP/acli.log" \
  || { echo "FAIL: JIRA transition revert missing" >&2; cat "$TMP/acli.log" >&2; exit 1; }
grep -q "edit --key APP-1234 --remove-labels smith-implementing" "$TMP/acli.log" \
  || { echo "FAIL: label remove missing" >&2; cat "$TMP/acli.log" >&2; exit 1; }
# Log entry
grep -q "abort | smith-APP-1234" .smith/log.txt \
  || { echo "FAIL: no abort log entry" >&2; exit 1; }

# ===== Case 2: ticket-mode abort, JIRA already back to Ready (idempotent) =====
( cd "$TARGET" && bash "${ROOT}/scripts/make_worktree.sh" APP-2222 task/app-2222-bar )
mkdir -p .smith/briefs
echo "# Brief" > .smith/briefs/APP-2222-brief.md
bash "${ROOT}/scripts/active_smiths.sh" add smith-APP-2222 anderson-APP-2222 ticket APP-2222

echo '{"fields":{"status":{"name":"Ready for Development"},"labels":[]}}' > "$SMITH_FAKE_ACLI_VIEW_FIXTURE"
> "$TMP/acli.log"

bash "$SCRIPT" APP-2222 >/dev/null

# JIRA already in ready state; no transition should be attempted
grep -q "transition" "$TMP/acli.log" && { echo "FAIL: should NOT transition (already ready)" >&2; exit 1; }
# Label not present; remove should be a no-op
grep -qF -e "--remove-labels" "$TMP/acli.log" && { echo "FAIL: should NOT remove (label absent)" >&2; exit 1; }

# ===== Case 3: pr-fix-mode abort =====
git -C "$TARGET" checkout -q -b task/app-3333-baz develop
git -C "$TARGET" commit --allow-empty -m "pr commit" -q
git -C "$TARGET" push -q -u origin task/app-3333-baz
git -C "$TARGET" checkout -q develop
git -C "$TARGET" branch -D task/app-3333-baz
( cd "$TARGET" && bash "${ROOT}/scripts/checkout_pr_worktree.sh" APP-3333 task/app-3333-baz )
bash "${ROOT}/scripts/active_smiths.sh" add smith-pr-5050 anderson-pr-5050 pr-fix 5050

> "$TMP/acli.log"
bash "$SCRIPT" 5050 >/dev/null

# Worktree gone
[[ ! -d ".smith/worktrees/5050" || ! -d ".smith/worktrees/app-3333" ]] \
  || { echo "FAIL: pr-fix worktree not removed" >&2; exit 1; }
# Branch on remote → should NOT delete local even if exists (we deleted it already, but the safety would have kicked in)
# JIRA NOT touched (pr-fix mode never called claim)
grep -q "transition" "$TMP/acli.log" && { echo "FAIL: pr-fix should not touch JIRA" >&2; exit 1; }
# active_smiths empty
got=$(bash "${ROOT}/scripts/active_smiths.sh" count)
assert_eq "0" "$got" "case3-active-empty"

# ===== Case 4: no active entry → fail with helpful error =====
> "$TMP/acli.log"
if bash "$SCRIPT" APP-9999 2>/dev/null; then
  echo "FAIL: should reject when no active entry" >&2; exit 1
fi

# ===== Case 5: missing arg → fail =====
if bash "$SCRIPT" 2>/dev/null; then echo "FAIL: missing arg" >&2; exit 1; fi

# ===== Case 6: ticket-mode but branch is on remote (live-mode partial run) → don't delete local =====
( cd "$TARGET" && bash "${ROOT}/scripts/make_worktree.sh" APP-4444 task/app-4444-qux )
git -C "$TARGET" push -q origin task/app-4444-qux:task/app-4444-qux  # simulate Smith pushed the branch
mkdir -p .smith/briefs
echo "# Brief" > .smith/briefs/APP-4444-brief.md
bash "${ROOT}/scripts/active_smiths.sh" add smith-APP-4444 anderson-APP-4444 ticket APP-4444

echo '{"fields":{"status":{"name":"In Progress"},"labels":["smith-implementing"]}}' > "$SMITH_FAKE_ACLI_VIEW_FIXTURE"
> "$TMP/acli.log"
bash "$SCRIPT" APP-4444 >/dev/null

# Worktree gone
[[ ! -d ".smith/worktrees/app-4444" ]] || { echo "FAIL: worktree not removed" >&2; exit 1; }
# Local branch should still exist (because it's pushed; abort refuses to delete)
git -C "$TARGET" rev-parse --verify refs/heads/task/app-4444-qux >/dev/null 2>&1 \
  || { echo "FAIL: pushed-branch deletion was supposed to be refused" >&2; exit 1; }

echo "PASS abort_smith.test.sh"
