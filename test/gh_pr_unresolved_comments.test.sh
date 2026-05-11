#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/gh_pr_unresolved_comments.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
mkdir -p "$TMP/bin" "$TMP/pr-view"
cp "${SCRIPT_DIR}/lib/fake_gh.sh" "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"

export PATH="$TMP/bin:$PATH"
export SMITH_FAKE_GH_LOG="$TMP/gh.log"
export SMITH_FAKE_GH_PR_VIEW_DIR="$TMP/pr-view"

# Fixture: PR #4321 with 3 threads (2 unresolved, 1 resolved). Shape is
# the GraphQL response since gh_pr_unresolved_comments.sh now calls
# `gh api graphql` instead of `gh pr view --json reviewThreads`.
cat > "$TMP/pr-view/pr-4321.json" <<'EOF'
{
  "data": {
    "repository": {
      "pullRequest": {
        "reviewThreads": {
          "nodes": [
            {
              "id": "PRRT_thread1",
              "isResolved": false,
              "path": "src/foo.kt",
              "line": 42,
              "comments": {"nodes": [
                {"body": "consider null safety here", "author": {"login": "alice"}}
              ]}
            },
            {
              "id": "PRRT_thread2",
              "isResolved": true,
              "path": "src/bar.kt",
              "line": 17,
              "comments": {"nodes": [
                {"body": "fixed already", "author": {"login": "bob"}}
              ]}
            },
            {
              "id": "PRRT_thread3",
              "isResolved": false,
              "path": "src/baz.kt",
              "line": 100,
              "comments": {"nodes": [
                {"body": "missing test", "author": {"login": "carol"}}
              ]}
            }
          ]
        }
      }
    }
  }
}
EOF

# Run
got=$(bash "$SCRIPT" 4321)

# Output is a JSON array of unresolved threads (so 2)
count=$(echo "$got" | jq 'length')
assert_eq "2" "$count" "unresolved-count"

# IDs preserved
ids=$(echo "$got" | jq -r '.[].id' | sort | tr '\n' ',' | sed 's/,$//')
assert_eq "PRRT_thread1,PRRT_thread3" "$ids" "ids-preserved"

# Resolved thread is excluded
echo "$got" | jq -e 'all(.id != "PRRT_thread2")' >/dev/null || { echo "FAIL: resolved thread leaked" >&2; exit 1; }

# Each thread has path, line, comments
echo "$got" | jq -e 'all(has("id") and has("path") and has("line") and has("comments"))' >/dev/null \
  || { echo "FAIL: missing schema fields" >&2; exit 1; }

# Empty PR (no review threads at all)
echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}' \
  > "$TMP/pr-view/pr-9999.json"
got=$(bash "$SCRIPT" 9999)
assert_eq "[]" "$got" "empty-pr"

# All threads resolved
cat > "$TMP/pr-view/pr-5555.json" <<'EOF'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
  {"id":"x","isResolved":true,"path":"a","line":1,"comments":{"nodes":[]}}
]}}}}}
EOF
got=$(bash "$SCRIPT" 5555)
assert_eq "[]" "$got" "all-resolved"

# Missing arg
if bash "$SCRIPT" 2>/dev/null; then echo "FAIL: missing arg" >&2; exit 1; fi

# Verify gh was called via GraphQL API with number=4321
grep -qF -e "api graphql" "$TMP/gh.log" \
  || { echo "FAIL: gh api graphql not invoked" >&2; cat "$TMP/gh.log" >&2; exit 1; }
grep -qF -e "number=4321" "$TMP/gh.log" \
  || { echo "FAIL: gh not invoked with number=4321" >&2; cat "$TMP/gh.log" >&2; exit 1; }

echo "PASS gh_pr_unresolved_comments.test.sh"
