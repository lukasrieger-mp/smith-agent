#!/usr/bin/env bash
# Single source of truth for label names used across GitHub PRs and JIRA
# tickets. Sourceable (exports vars) or invocable (prints one value).
#
# Sourced — in bash scripts that use multiple labels:
#   . "$(dirname "${BASH_SOURCE[0]}")/smith_labels.sh"
#   gh pr create --label "$SMITH_LABEL_PR_AUTHORED"
#
# Invoked — in skill bash blocks or one-off shells:
#   gh pr create --label "$(smith_labels.sh PR_AUTHORED)"
#
# Keys (also the suffix after SMITH_LABEL_ when sourced):
#   PR_AUTHORED          — GitHub label on every Smith PR
#   PR_NEEDS_ATTENTION   — GitHub label on stuck PRs needing human review
#   JIRA_IMPLEMENTING    — JIRA label while Smith is working a ticket
#   JIRA_NO_AUTO         — JIRA opt-out label; watchdog skips the ticket
#   JIRA_FAILED          — JIRA label after WIP-stuck (replaces JIRA_IMPLEMENTING)

SMITH_LABEL_PR_AUTHORED="smith-authored"
SMITH_LABEL_PR_NEEDS_ATTENTION="needs-human-attention"
SMITH_LABEL_JIRA_IMPLEMENTING="smith-implementing"
SMITH_LABEL_JIRA_NO_AUTO="no-auto-impl"
SMITH_LABEL_JIRA_FAILED="auto-impl-failed"

# Only run the print-mode block when invoked directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  key="${1:?usage: smith_labels.sh <PR_AUTHORED|PR_NEEDS_ATTENTION|JIRA_IMPLEMENTING|JIRA_NO_AUTO|JIRA_FAILED>}"
  var="SMITH_LABEL_$key"
  if [[ -z "${!var:-}" ]]; then
    echo "smith_labels: unknown key: $key" >&2
    exit 1
  fi
  printf '%s\n' "${!var}"
fi
