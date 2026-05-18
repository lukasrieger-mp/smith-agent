#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/promote_smith_artifacts.sh"

# Set up a temp git repo as the "worktree"
mk_worktree() {
  local dir=$1
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" commit --allow-empty -m initial -q
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)

# --- Case 1: brief exists, no uncommitted work ---
W="$TMP/case1"
mk_worktree "$W"
mkdir -p "$W/.smith/briefs"
echo "# Brief — APP-1234: foo" > "$W/.smith/briefs/APP-1234-brief.md"
( cd "$W" && bash "$SCRIPT" APP-1234 )

# Brief was copied to committed location
[[ -f "$W/docs/superpowers/specs/APP-1234-brief.md" ]] || { echo "FAIL: brief not promoted" >&2; exit 1; }
# Content matches
assert_eq "$(cat "$W/.smith/briefs/APP-1234-brief.md")" "$(cat "$W/docs/superpowers/specs/APP-1234-brief.md")" "case1-content-matches"
# Promoted file is committed (tracked)
git -C "$W" ls-files --error-unmatch docs/superpowers/specs/APP-1234-brief.md >/dev/null 2>&1 \
  || { echo "FAIL: promoted brief not committed" >&2; exit 1; }
# Commit message style
last_msg=$(git -C "$W" log -1 --pretty=%s)
assert_contains "$last_msg" "wip(smith)" "case1-wip-prefix"
assert_contains "$last_msg" "APP-1234" "case1-ticket-key"

# --- Case 2: brief exists AND uncommitted changes in worktree ---
W="$TMP/case2"
mk_worktree "$W"
mkdir -p "$W/.smith/briefs"
echo "# Brief" > "$W/.smith/briefs/APP-2222-brief.md"
echo "uncommitted edit" > "$W/some-file.txt"
mkdir -p "$W/src"
echo "partial impl" > "$W/src/Foo.kt"
( cd "$W" && bash "$SCRIPT" APP-2222 )

# All uncommitted files are now committed
[[ $(git -C "$W" status --porcelain | wc -l | tr -d ' ') == "0" ]] || \
  { echo "FAIL: uncommitted work remains after promote" >&2; exit 1; }
git -C "$W" ls-files --error-unmatch some-file.txt >/dev/null 2>&1 || { echo "FAIL: some-file.txt not committed" >&2; exit 1; }
git -C "$W" ls-files --error-unmatch src/Foo.kt >/dev/null 2>&1 || { echo "FAIL: src/Foo.kt not committed" >&2; exit 1; }

# --- Case 3: no brief, clean tree -> no-op (no commit, no error) ---
W="$TMP/case3"
mk_worktree "$W"
before_sha=$(git -C "$W" rev-parse HEAD)
( cd "$W" && bash "$SCRIPT" APP-3333 )
after_sha=$(git -C "$W" rev-parse HEAD)
assert_eq "$before_sha" "$after_sha" "case3-noop-no-new-commit"

# --- Case 4: idempotent re-run ---
W="$TMP/case4"
mk_worktree "$W"
mkdir -p "$W/.smith/briefs"
echo "# Brief" > "$W/.smith/briefs/APP-4444-brief.md"
( cd "$W" && bash "$SCRIPT" APP-4444 )
sha_first=$(git -C "$W" rev-parse HEAD)
( cd "$W" && bash "$SCRIPT" APP-4444 )
sha_second=$(git -C "$W" rev-parse HEAD)
# Second run on a clean tree with brief already promoted: no new commit
assert_eq "$sha_first" "$sha_second" "case4-idempotent"

# --- Case 4b: spec and plan promotion from gitignored .smith/ paths ---
W="$TMP/case4b"
mk_worktree "$W"
# Add .smith/ to gitignore so the source files are actually gitignored.
echo ".smith/" > "$W/.gitignore"
git -C "$W" add .gitignore && git -C "$W" commit -q -m "ignore .smith"
mkdir -p "$W/.smith/specs" "$W/.smith/plans"
echo "# Spec for APP-4500" > "$W/.smith/specs/2026-05-18-APP-4500-design.md"
echo "# Plan for APP-4500" > "$W/.smith/plans/2026-05-18-APP-4500.md"
( cd "$W" && bash "$SCRIPT" APP-4500 )

# Promoted spec and plan exist in tracked locations
[[ -f "$W/docs/superpowers/specs/2026-05-18-APP-4500-design.md" ]] \
  || { echo "FAIL: spec not promoted" >&2; exit 1; }
[[ -f "$W/docs/superpowers/plans/2026-05-18-APP-4500.md" ]] \
  || { echo "FAIL: plan not promoted" >&2; exit 1; }
# Content matches
assert_eq "$(cat "$W/.smith/specs/2026-05-18-APP-4500-design.md")" \
          "$(cat "$W/docs/superpowers/specs/2026-05-18-APP-4500-design.md")" \
          "case4b-spec-content"
assert_eq "$(cat "$W/.smith/plans/2026-05-18-APP-4500.md")" \
          "$(cat "$W/docs/superpowers/plans/2026-05-18-APP-4500.md")" \
          "case4b-plan-content"
# Both are committed (tracked)
git -C "$W" ls-files --error-unmatch docs/superpowers/specs/2026-05-18-APP-4500-design.md >/dev/null 2>&1 \
  || { echo "FAIL: promoted spec not committed" >&2; exit 1; }
git -C "$W" ls-files --error-unmatch docs/superpowers/plans/2026-05-18-APP-4500.md >/dev/null 2>&1 \
  || { echo "FAIL: promoted plan not committed" >&2; exit 1; }
# The wip commit message style holds
last_msg=$(git -C "$W" log -1 --pretty=%s)
assert_contains "$last_msg" "wip(smith)" "case4b-wip-prefix"

# --- Case 4c: idempotent re-run with spec+plan already promoted ---
( cd "$W" && bash "$SCRIPT" APP-4500 )
sha_after=$(git -C "$W" rev-parse HEAD)
sha_first_4b=$(git -C "$W" log --format=%H | sed -n '1p')
# Second run on clean tree should be a no-op
assert_eq "$sha_first_4b" "$sha_after" "case4c-idempotent"

# --- Case 5: missing arg ---
if bash "$SCRIPT" 2>/dev/null; then echo "FAIL: missing arg" >&2; exit 1; fi

# --- Case 6: not inside a git repo -> non-zero ---
mkdir -p "$TMP/not-a-repo"
if ( cd "$TMP/not-a-repo" && bash "$SCRIPT" APP-5555 ) 2>/dev/null; then
  echo "FAIL: should fail outside git repo" >&2; exit 1
fi

echo "PASS promote_smith_artifacts.test.sh"
