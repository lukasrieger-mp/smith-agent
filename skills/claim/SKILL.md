---
name: claim
description: Claim a JIRA ticket for autonomous implementation. Runs pre-flight guards, transitions the ticket to "In Progress", adds the smith-implementing label, and creates a task/<key>-<slug> branch from origin/develop. Use when smith-watchdog dispatches a candidate for implementation.
---

# Smith Claim

See `docs/spec.md` Section 11.2 for the full contract.

## Inputs

- `$TICKET` (env or first arg) — JIRA ticket key, e.g. `APP-5601`
- `$SMITH_DRY_RUN` (env) — when `1`, never write to JIRA or git remote; log
  intended actions to `.smith/log.txt` instead.

## Outputs

- Stdout: created branch name (e.g. `task/app-5601-hide-skeleton-loader`)
- Side effects (production mode): JIRA status transition, JIRA label add, new
  local branch checked out
- Side effects (dry-run mode): only `.smith/log.txt` entries

## Pre-flight (all modes)

Run before any write:

1. `bash scripts/assert_target_repo.sh`
2. `bash scripts/assert_clean_worktree.sh`
3. `acli jira auth status` and `gh auth status` both succeed
4. `git fetch origin develop`
5. Re-query the ticket via acli; abort if status ≠ "Ready for Development"
   or assignee ≠ currentUser() (race-condition guard)

## Phase 1 workflow

All actions in Phase 1 are dry-run only:

1. Resolve ticket summary via `acli jira workitem view $TICKET --fields summary --json`.
2. Compute branch name via `bash scripts/make_branch_name.sh $TICKET "$SUMMARY"`.
3. Append to `.smith/log.txt`:
   `<ts> | smith-claim | $TICKET | dry-run-claim | branch=<name>, would-transition=Ready->InProgress, would-label=smith-implementing`
4. Print the branch name to stdout.

## Out of scope for Phase 1

- Real status transition (`acli jira workitem transition`)
- Real label addition
- Real branch creation
