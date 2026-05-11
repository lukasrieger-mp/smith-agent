#!/usr/bin/env bash
# Fetch unresolved review threads for a GitHub PR via GraphQL, return a
# JSON array on stdout.
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
# (monitor_pr_comments.sh) does its own thinner GraphQL fetch for
# diff detection; this script is the full fetcher for the Smith
# teammate's actual fix loop.
#
# `reviewThreads` lives in the GraphQL API only — `gh pr view --json
# reviewThreads` errors out with "Unknown JSON field". We use
# `gh api graphql` instead.
set -euo pipefail

PR="${1:?usage: gh_pr_unresolved_comments.sh <PR-NUMBER>}"

owner=$(gh repo view --json owner -q .owner.login)
repo=$(gh repo view --json name -q .name)

gh api graphql \
  -f query='query($owner:String!,$repo:String!,$number:Int!){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$number){
        reviewThreads(first:100){
          nodes{
            id isResolved path line
            comments(first:100){nodes{body author{login}}}
          }
        }
      }
    }
  }' \
  -f owner="$owner" -f repo="$repo" -F number="$PR" \
  | jq '[.data.repository.pullRequest.reviewThreads.nodes[]
         | select(.isResolved == false)
         | {id, path, line,
            comments: [.comments.nodes[] | {body, author: {login: .author.login}}]}]'
