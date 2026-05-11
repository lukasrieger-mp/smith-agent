---
name: claim
description: Claim a JIRA ticket. Runs inside the Smith teammate context as step 1 of ticket mode. Transitions ticket status to the configured claim-status, adds the smith-implementing label, and confirms the worktree branch (already created by the lead before spawn) is the expected `task/<key>-<slug>`.
---

# smith:claim (inner-teammate)

You are inside a Mr. Smith teammate session (ticket mode). This is the
first skill you invoke after spawn. Don't run it manually — the spawn
prompt told you to.

For the full contract see `docs/spec.md` Section 11.2.1.

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
bash $CLAUDE_PLUGIN_ROOT/scripts/assert_target_repo.sh
bash $CLAUDE_PLUGIN_ROOT/scripts/assert_clean_worktree.sh
```

Then verify auth:
```
acli jira auth status >/dev/null && gh auth status >/dev/null
```

If any pre-flight fails, return immediately with
`{result: "stuck", reason: "<concrete failure>"}` per the Smith persona
(`agents/smith.md`) outcome contract.

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

## Phase 1 workflow (dry-run-equivalent for everyone)

In Phase 1, `smith:claim` is a placeholder. It does NOT perform real
JIRA writes regardless of the `dry_run` flag. Instead:

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

## Phase 2 — when this skill goes live

In Phase 2, replace steps 3 above with real writes:

```bash
# Read the target transition ID
transitions=$(acli jira workitem view-transitions $ticket --json)
to_status=$(bash $CLAUDE_PLUGIN_ROOT/scripts/smith_config.sh claim_status)
transition_id=$(echo "$transitions" | jq -r --arg name "$to_status" \
  '.[] | select(.to.name == $name) | .id' | head -1)

acli jira workitem transition $ticket --transition-id $transition_id
acli jira workitem edit $ticket --label-add smith-implementing
```

The log entries become `transitioned` / `labelled` instead of
`would-transition` / `would-label`. Pre-flight and race-guard stay
identical.

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
