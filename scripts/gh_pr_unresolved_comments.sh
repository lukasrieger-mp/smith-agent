#!/usr/bin/env bash
# Fetch unresolved review threads for a GitHub PR via `gh pr view`, filter
# out resolved threads, and return a JSON array on stdout.
#
# Usage: gh_pr_unresolved_comments.sh <PR-NUMBER>
#
# Output schema (each element):
#   {
#     "id":       "PRRT_...",
#     "path":     "src/foo.kt",
#     "line":     42,
#     "comments": [{"body":"...","author":{"login":"..."}}, ...]
#   }
#
# Used by smith:pr-fix-mode to know what to address. The monitor
# (monitor_pr_comments.sh) uses a thinner version internally for
# diff detection; this script is the full fetcher for the Smith
# teammate's actual fix loop.
set -euo pipefail

PR="${1:?usage: gh_pr_unresolved_comments.sh <PR-NUMBER>}"

gh pr view "$PR" --json reviewThreads \
  | jq '[.reviewThreads[]
         | select(.isResolved == false)
         | {id, path, line, comments}]'
