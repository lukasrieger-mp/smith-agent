---
description: Manually dispatch a Smith+Anderson teammate pair to implement one specific JIRA ticket. Use `--dry-run` to drive the orchestration without external side effects.
---

# /smith:implement

You (the watchdog lead session) have been asked to dispatch a Smith
implementer team for a specific JIRA ticket. This is the operator-driven
manual override path; the watchdog monitors (Section 5.6 of the spec)
trigger the same flow automatically when new candidates appear.

## Arguments

- `$1` (required): JIRA ticket key, e.g. `APP-5601`
- `$2` (optional): `--dry-run` — drive the full orchestration without
  any external side effect

Examples:

```
/smith:implement APP-5601
/smith:implement APP-5601 --dry-run
```

## Pre-flight (do this first, in order)

1. Verify your CWD is the configured target repo:
   ```
   bash $CLAUDE_PLUGIN_ROOT/scripts/assert_target_repo.sh
   ```
   If this fails, abort with the script's error message. Do not continue.
2. Read the cap and active-Smith count:
   ```
   max=$(bash $CLAUDE_PLUGIN_ROOT/scripts/smith_config.sh max_concurrent_smiths)
   ```
   Count current active Smith teammates by checking your team's task list
   for in-progress tasks. If `active >= max`, abort with message:
   "At max parallelism ($active/$max active). Wait for a Smith to finish,
   or shutdown a teammate, then retry."
3. Verify the ticket via `acli` (skip the full JQL — just confirm the
   ticket exists, is assigned to you, and is in the eligible status):
   ```
   acli jira workitem view "$1" --fields "summary,status,assignee,components" --json
   ```
   If status is not the configured eligible status (default `Ready for
   Development`) or assignee is not currentUser, abort with the reason.
4. Classify platform:
   ```
   components=$(... extract components from the acli output ...)
   echo "$components" | bash $CLAUDE_PLUGIN_ROOT/scripts/classify_platform.sh
   ```
   If the result is `ios`, abort with: "iOS-only ticket; Smith does not
   handle iOS work."

## Worktree setup (skipped when --dry-run)

Compute the branch name:
```
ticket="$1"
summary=$(... from acli output ...)
branch=$(bash $CLAUDE_PLUGIN_ROOT/scripts/make_branch_name.sh "$ticket" "$summary")
```

Worktree path: `<target>/.smith/worktrees/<ticket-key-lowercased>/`

In **normal mode**, create the worktree:
```
git fetch origin develop
git worktree add ".smith/worktrees/${ticket,,}" -b "$branch" origin/develop
```

In **--dry-run mode**, skip the worktree creation. Log the intended
command to `.smith/log.txt` and continue with the placeholder worktree
path so the spawn prompt has a value to embed.

## Spawn the teammate pair

Use the agent-team spawn mechanism (see spec Section 18.3 for the
canonical spawn-prompt structure). Spawn two teammates with deterministic
names so the operator can reference them later:

**Teammate 1 — Mr. Smith**, agent type `smith`, name `smith-<ticket>`:

> Mode: ticket
> Ticket: $1
> Worktree: .smith/worktrees/<ticket-lowercased>/
> Branch: $branch
> Dry-run: ${DRY_RUN:-false}
> Your Anderson is: anderson-<ticket>
> Execute smith:claim, smith:enrich, smith:pipeline, smith:pr per spec Section 8.
> Send {type: smith.outcome, ...} to the lead via mailbox when done.

**Teammate 2 — Mr. Anderson**, agent type `anderson`, name `anderson-<ticket>`:

> You are reviewing Smith's work on $1.
> Worktree: .smith/worktrees/<ticket-lowercased>/
> Wait for review requests from smith-<ticket> via mailbox.
> Per spec Section 8.2, only report findings at confidence >= 80.
> Reply with the documented JSON schema for each gate (mode=spec, mode=plan, mode=diff).

Add a team task: `implement <ticket>`, assigned to Smith.

## Wait for outcome

Smith and Anderson coordinate via mailbox during the run. The lead's job
is to wait for Smith's final `{type: "smith.outcome", ...}` message.

When it arrives, parse the result:

- `success`: print a summary including PR URL, mode, log_entries.
- `stuck`: print the reason and the path to the WIP-stuck PR (if any).
- `error`: per spec Section 8.5, dispatch ONE retry with a fresh teammate
  pair (new names: `smith-<ticket>-retry`, `anderson-<ticket>-retry`).
  If the retry also returns error → escalate to final WIP-stuck.

## On dispatch failure

If the team spawn itself fails (rare) or Smith never returns an outcome
JSON before going idle, treat as `{result: "error", reason: "teammate
failed to report"}` per spec Section 8.5.

## Output format

After the outcome is received, print:

```
Smith implement complete (dry-run=<true|false>)
  Ticket:   $1
  Branch:   $branch
  Worktree: .smith/worktrees/<ticket-lowercased>/
  Outcome:  <success|stuck|error> — <reason or "ok">
  PR:       <url or "not opened">
```

Then `tail -5 .smith/log.txt` so the operator sees the recent log lines.

## Phase status (today: Phase 2)

What's live and what's placeholder, by skill:

| Skill | Phase 2 status | Notes |
|---|---|---|
| `smith:claim` | **LIVE** (real JIRA transition + label add) when `--dry-run` is NOT passed; placeholder when it is | The `dry_run` flag in the spawn prompt picks the branch |
| `smith:enrich` | **LIVE** brief writing always (no side effects beyond a file in the worktree); Explore subagent dispatch deferred to Phase 2.x | Brief lands in `<worktree>/.smith/briefs/<key>-brief.md` |
| `smith:pipeline` | Placeholder — Anderson always replies `{"findings": []}`; gates pass on round 1 | Phase 3 activates the real critic loop |
| `smith:pr` | Placeholder — logs intended actions, no `git push`, no `gh pr create` | Phase 4 activates real PR opening |

**Consequence for operators today**: running `/smith:implement APP-XXXX`
without `--dry-run` WILL:

- Transition the JIRA ticket from the eligible status to the claim status
- Add the `smith-implementing` label
- Create a `task/<key>-<slug>` branch in `<target>/.smith/worktrees/<key>/`
- Write a brief file inside that worktree
- Walk through pipeline + pr in placeholder mode (Smith's working tree
  gains a spec + plan + impl commit but the pipeline's critic dialogue
  is a no-op and the PR is never opened)

To revert: manually transition the ticket back, `acli ... edit
--remove-labels smith-implementing`, and `git worktree remove
.smith/worktrees/<key>`.

**Prefer `--dry-run` until Phase 4 closes the loop** (real PR open
gives you a clean way to land or close out the work).
