---
name: claim
description: Claim a JIRA ticket — transition status, add smith-implementing label, confirm worktree branch. Step 1 of Smith's ticket mode.
---

# smith:claim (inner-teammate)

You are inside a Mr. Smith teammate session (ticket mode). This is the
first skill you invoke after spawn. Don't run it manually — the spawn
prompt told you to.

(Design rationale lives in `docs/spec.md` §11.2.1 — informational only;
this file is sufficient to operate.)

## Inputs (from your spawn prompt)

- `ticket` — JIRA key, e.g. `APP-5601`
- `worktree` — path the lead already created (`<target>/.smith/worktrees/<key>/`)
- `branch` — branch name the lead pre-computed via `make_branch_name.sh`
- `dry_run` — boolean from spawn prompt

## Outputs

- Stdout: the branch name (echo for downstream confirmation).
- Side effects (real mode): JIRA status transition `Ready for Development`
  → `In Progress`, JIRA label `smith-implementing` added.
- Side effects (dry-run mode): same set of intended actions logged to
  `<target>/.smith/log.txt`, no JIRA writes.
- In both modes: confirm `git rev-parse --abbrev-ref HEAD` inside the
  worktree matches `branch`.

## Pre-flight (always, even in dry-run)

```
cd <worktree>
assert_target_repo.sh
assert_clean_worktree.sh
```

Then verify both CLIs are authenticated:
```
assert_clis_authenticated.sh
```

If any pre-flight fails, return immediately with
`{result: "stuck", reason: "<concrete failure>"}` per the Smith persona
(`agents/smith-impl.md`) outcome contract. For the auth check
specifically, the stderr text already names the exact remedy command —
include it in the `reason` field so the operator's log entry is
actionable.

## Race-condition guard

Right before the JIRA transition, re-query the ticket:
```
acli jira workitem view $ticket --fields "status,assignee" --json
```

If status is no longer the configured eligible status, or assignee is
no longer `currentUser()`, abort with
`{result: "stuck", reason: "ticket state changed during claim race"}`.

The operator may have manually claimed the ticket while you were
spawning. Respect their override.

## Workflow

The dry-run flag from your spawn prompt picks the branch:

### When `dry_run = true`

1. Pre-flight (above).
2. Race-condition re-query (above).
3. Append to `<target>/.smith/log.txt`:
   ```
   <ts> | smith:claim | $ticket | would-transition | from=<current> to=<claim_status>
   <ts> | smith:claim | $ticket | would-label | label=smith-implementing
   <ts> | smith:claim | $ticket | branch-confirmed | $branch
   ```
4. Confirm the worktree's current branch is `$branch`. If not, abort
   with `{result: "stuck", reason: "worktree branch mismatch"}`.
5. Echo `$branch` to stdout.

### When `dry_run = false`

The pre-flight is identical (above). Replace the dry-run logging with
actual writes via the helper scripts:

```bash
# Resolve config
claim_status=$(smith_config.sh claim_status)
eligible_status=$(smith_config.sh eligible_status)

# Race-guarded transition. The SMITH_EXPECTED_FROM_STATUS env tells
# jira_transition.sh to verify the current status is still the
# eligible one before transitioning — guards against the operator
# manually grabbing the ticket between spawn and now.
SMITH_EXPECTED_FROM_STATUS="$eligible_status" \
  jira_transition.sh \
       "$ticket" "$claim_status"

# Add the smith-implementing label (idempotent; no-op if already there)
jira_label_add.sh \
     "$ticket" smith-implementing
```

If `jira_transition.sh` exits 1 (race detected), return
`{result: "stuck", reason: "ticket state changed during claim race"}`.
Any other non-zero exit from the scripts: `{result: "error", reason}`
— let the lead retry once.

Then write the live log entries:
```
<ts> | smith:claim | $ticket | transitioned | from=<eligible> to=<claim>
<ts> | smith:claim | $ticket | labelled | label=smith-implementing
<ts> | smith:claim | $ticket | branch-confirmed | $branch
```

Worktree branch check (step 4 from dry-run) and echo of `$branch`
(step 5) are identical.

## On stuck / error outcomes

`smith:claim` is the earliest place in the pipeline where you might
return stuck. Reasons that warrant `{result: "stuck"}`:

- Pre-flight fails (dirty worktree, missing acli/gh auth)
- Race: ticket no longer matches expected state
- Branch mismatch in the worktree

Reasons that warrant `{result: "error"}` (retryable):

- acli command timeout
- Network blip on the verify call

Per spec Section 8.5, stuck → straight to WIP-stuck path. Error →
retry-once via the lead.
