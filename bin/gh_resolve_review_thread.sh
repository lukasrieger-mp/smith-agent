#!/usr/bin/env bash
# Reply to a GitHub PR review thread, then mark it resolved. Two
# GraphQL mutations, one logical action. Used by smith-fixer when
# Smith+Anderson agree to dismiss a finding — the reply explains the
# dismissal and the resolve clears it from the active thread list.
#
# Usage: gh_resolve_review_thread.sh <THREAD-ID> <REPLY-BODY>
#
# THREAD-ID: a GraphQL PullRequestReviewThread node ID (PRRT_...)
# REPLY-BODY: the comment text to post as the reply.

set -euo pipefail

THREAD="${1:?usage: gh_resolve_review_thread.sh <THREAD-ID> <REPLY-BODY>}"
BODY="${2:?usage: gh_resolve_review_thread.sh <THREAD-ID> <REPLY-BODY>}"

# 1. Post the reply.
gh api graphql \
  -f query='mutation($threadId:ID!,$body:String!){
    addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$threadId, body:$body}){
      comment { id }
    }
  }' \
  -f threadId="$THREAD" -f body="$BODY" >/dev/null

# 2. Resolve the thread.
gh api graphql \
  -f query='mutation($threadId:ID!){
    resolveReviewThread(input:{threadId:$threadId}){
      thread { id isResolved }
    }
  }' \
  -f threadId="$THREAD" >/dev/null
