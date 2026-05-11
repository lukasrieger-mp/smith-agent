---
name: pr
description: Open the draft PR for a Smith-implemented ticket. Two paths: success (clean PR title and body) and WIP-stuck (escalation PR with needs-human-attention label, JIRA label swap, promoted spec/plan/brief). Always opens DRAFT — never marks ready-for-review, never merges.
---

# Smith PR

See `docs/spec.md` Section 11.5 for the full contract.

## Inputs

- `$TICKET`, `$BRANCH`
- `$OUTCOME` — `success` or `stuck`
- `$STUCK_REASON` — required when `$OUTCOME=stuck`
- `$SMITH_DRY_RUN` — when `1`, log intended actions only

## Outputs

- Stdout: would-be PR URL placeholder in Phase 1 (`dry-run://pr/$TICKET`)
- Side effects (production): `git push`, `gh pr create --draft`, JIRA label
  ops, optional artifact promotion (stuck path)
- Side effects (dry-run): log entries only

## Phase 1 workflow

All actions are dry-run:

1. Compose PR title:
   - `$OUTCOME=success` → `[<TICKET>] <summary>`
   - `$OUTCOME=stuck` → `[WIP - agent-stuck] [<TICKET>] <summary>`
2. Compose PR body (full structure per spec Section 10.3; placeholder body
   acceptable for Phase 1).
3. Log: `<ts> | smith-pr | $TICKET | dry-run-pr | outcome=$OUTCOME, would-push=$BRANCH, title="<title>"`
4. Print `dry-run://pr/$TICKET`.

## Out of scope for Phase 1

- Real `git push`
- Real `gh pr create --draft`
- Label add/remove operations
- WIP-stuck artifact promotion
