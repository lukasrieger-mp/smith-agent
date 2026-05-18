#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/bin/gh_resolve_review_thread.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
mkdir -p "$TMP/bin"
cp "${SCRIPT_DIR}/lib/fake_gh.sh" "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"

export PATH="$TMP/bin:$PATH"
export SMITH_FAKE_GH_LOG="$TMP/gh.log"

# Happy path: script accepts thread id + body, makes the two GraphQL calls.
bash "$SCRIPT" PRRT_xyz "Not applicable: this caller is removed."

# Verify both GraphQL mutations were attempted: addPullRequestReviewThreadReply, resolveReviewThread
grep -qF -e "addPullRequestReviewThreadReply" "$TMP/gh.log" \
  || { echo "FAIL: addPullRequestReviewThreadReply not called" >&2; cat "$TMP/gh.log" >&2; exit 1; }
grep -qF -e "resolveReviewThread" "$TMP/gh.log" \
  || { echo "FAIL: resolveReviewThread not called" >&2; cat "$TMP/gh.log" >&2; exit 1; }
grep -qF -e "PRRT_xyz" "$TMP/gh.log" \
  || { echo "FAIL: thread id not passed" >&2; cat "$TMP/gh.log" >&2; exit 1; }

# Missing args error out.
if bash "$SCRIPT" 2>/dev/null; then echo "FAIL: missing args" >&2; exit 1; fi
if bash "$SCRIPT" PRRT_only 2>/dev/null; then echo "FAIL: missing body" >&2; exit 1; fi

echo "PASS gh_resolve_review_thread.test.sh"
