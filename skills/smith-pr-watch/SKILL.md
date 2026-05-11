---
name: smith-pr-watch
description: Fan-out poller for all open Smith-authored draft PRs. Per-PR: ensure worktree exists, fetch unresolved comments, address them via pr-feedback-helper, commit and push. Tracks per-thread fix cycles; tags needs-human-attention after 5 cycles on the same thread.
---

# Smith PR Watch

See `smith/docs/spec.md` Section 11.6 for the full contract.

## Inputs

- None (discovers state via `gh pr list --label smith-authored`)
- `$SMITH_DRY_RUN` env

## Outputs

- One log line per PR processed
- Side effects (production): per-PR worktree create, commit, push, label ops
- Side effects (dry-run): log only

## Phase 1 workflow

Phase 1 only lists candidate PRs and logs them:

1. `gh pr list --label smith-authored --state open --json number,title,headRefName`
   (in dry-run mode this is allowed because it's a read-only API call;
   alternately when `$SMITH_DRY_RUN_FIXTURE_PRS` is set, read that fixture.)
2. For each PR, log:
   `<ts> | smith-pr-watch | PR-<N> | dry-run-scan | branch=<head>`

No comment fetching, no worktree creation, no commits.

## Out of scope for Phase 1

- Per-PR worktree creation under `.smith/worktrees/`
- pr-feedback-helper integration
- Per-thread fix-cycle counter and `needs-human-attention` labelling
- Real commit + push
