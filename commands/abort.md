---
description: Abort an in-flight Smith dispatch — shut down the teammate pair and clean up local + JIRA state for that ticket/PR.
---

# /smith:abort

You (the watchdog lead session) have been asked to abort an in-flight
Smith dispatch. This tears down everything: shuts down the
teammate pair via the team API, removes the worktree + local branch +
brief, clears the active-smiths entry, and reverts JIRA state if it
was modified.

## Arguments

- `$1` (required): the subject — either a JIRA ticket key (e.g.
  `APP-1234`) for ticket-mode aborts, or a PR number (e.g. `4321`)
  for PR-fix-mode aborts.

Examples:

```
/smith:abort APP-5601
/smith:abort 4321
```

## Workflow

1. Look up the active entry to identify the teammates:

   ```
   entry=$(bash $SMITH_PLUGIN_ROOT/scripts/active_smiths.sh list \
           | jq -c --arg subj "$1" '.[] | select(.subject == $subj)')
   ```

   If `$entry` is empty, abort the command with: "No active Smith for
   subject `$1`. Run `active_smiths.sh list` to see active dispatches."

   Parse the teammate names:
   ```
   smith_name=$(echo "$entry" | jq -r '.smith_name')
   anderson_name=$(echo "$entry" | jq -r '.anderson_name')
   mode=$(echo "$entry" | jq -r '.mode')
   ```

2. **Shut down the teammate pair via the team API.** This is an
   LLM-level operation, not a shell command. In chat, you (the lead)
   send a shutdown request to both teammates:

   > Please shut down teammate `<smith_name>` and teammate
   > `<anderson_name>`. Their work for subject `$1` is being aborted
   > by the operator.

   The agent-teams runtime handles the actual shutdown. Teammates
   approve and exit. (If a teammate rejects shutdown, surface that
   and ask the operator how to proceed — typically Ctrl-C the
   session for a hard stop.)

3. **Run the cleanup script** to handle filesystem + JIRA state:

   ```
   bash $SMITH_PLUGIN_ROOT/scripts/abort_smith.sh "$1"
   ```

   This is idempotent and safe. It will:

   - Remove the worktree at `.smith/worktrees/<key-lower>/`
   - Delete the local `task/<key>-<slug>` branch IF it wasn't pushed
     to origin (pushed branches are left alone — the operator
     decides whether to clean them up manually)
   - Remove the brief at `.smith/briefs/<KEY>-brief.md`
   - Revert JIRA status from claim-status back to eligible-status
     (ticket mode only, and only if status is currently claim-status)
   - Remove the `smith-implementing` label (ticket mode only,
     idempotent)
   - Clear the active-smiths entry so the cap doesn't drift
   - Append an abort line to `.smith/log.txt`

   For PR-fix mode, the JIRA revert is skipped (claim wasn't called),
   and the branch (which lives on the remote PR) is left alone.

## Output

Print the cleanup script's output verbatim so the operator sees
exactly what was done, then a summary:

```
Aborted Smith dispatch for $1.
  Mode:    <ticket|pr-fix>
  Smith:   <smith_name> (shut down)
  Anderson: <anderson_name> (shut down)
  Local cleanup: <see lines above>
```

If the cleanup script exited non-zero (rare — usually means partial
cleanup), surface that too.

## What this command does NOT do

- **It does not close any open PR.** If `smith:pr` already pushed a
  PR before the operator decided to abort, the PR stays open. The
  operator can close it manually via GitHub UI or
  `gh pr close <number>`.
- **It does not undo git pushes.** If Smith pushed commits before the
  abort, those commits stay on the remote. The local branch is left
  in place so the operator can inspect / cherry-pick / force-clean if
  desired.
- **It does not delete `.smith/log.txt`.** The audit trail is
  preserved; the abort itself adds one line to it.

## When to use this

- Mid-dry-run, you decided to stop early
- Smith got stuck in a way you don't want to wait for (e.g. spinning
  on a gate)
- You spotted a problem with the ticket itself and want to clear
  Smith out so you can fix it manually
- You changed your mind about a manual `/smith:implement` dispatch

## Hard limits

- The cap (2 Smiths) means at most 2 entries can be aborted. Each
  invocation handles one subject.
- The `--force` semantics for `git worktree remove` are used so
  uncommitted partial work in the worktree IS discarded. If you want
  to preserve it, copy the worktree somewhere else BEFORE calling
  `/smith:abort`.
