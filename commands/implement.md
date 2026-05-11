---
description: Dispatch a Smith+Anderson pair to implement one JIRA ticket. Flags: `--dry-run` (no external side effects), `--confident` (skip full build+tests, only run formatter).
---

# /smith:implement

You (the watchdog lead session) have been asked to dispatch a Smith
implementer team for a specific JIRA ticket. This is the operator-driven
manual override path; the watchdog monitors (Section 5.6 of the spec)
trigger the same flow automatically when new candidates appear.

## Arguments

- `$1` (required): JIRA ticket key, e.g. `APP-5601`
- `$2`, `$3` (optional, any order): zero or more of:
  - `--dry-run` — drive the orchestration without any external side
    effect (no JIRA writes, no `git push`, no `gh pr create`)
  - `--confident` — skip the full `quality-check.sh` umbrella (build
    + tests) in the IMPL gate. Only the formatter (`lintKotlin` per
    the target's CLAUDE.md) runs. Anderson's diff review still runs.
    The resulting PR body is marked so the human reviewer knows tests
    were skipped.

`--confident` is **only available on this manual command**, not on
watchdog auto-dispatches. The watchdog always runs the full pipeline.

Examples:

```
/smith:implement APP-5601
/smith:implement APP-5601 --dry-run
/smith:implement APP-5601 --confident
/smith:implement APP-5601 --dry-run --confident
```

## Pre-flight (do this first, in order)

1. Verify your CWD is the configured target repo:
   ```
   bash $SMITH_PLUGIN_ROOT/scripts/assert_target_repo.sh
   ```
   If this fails, abort with the script's error message. Do not continue.
2. Read the cap and active-Smith count:
   ```
   max=$(bash $SMITH_PLUGIN_ROOT/scripts/smith_config.sh max_concurrent_smiths)
   ```
   Count current active Smith teammates by checking your team's task list
   for in-progress tasks. If `active >= max`, abort with message:
   "At max parallelism ($active/$max active). Wait for a Smith to finish,
   or shutdown a teammate, then retry."
3. Verify the ticket via `acli` (skip the full JQL — just confirm the
   ticket exists, is assigned to you, and is in the eligible status):
   ```
   ticket_json=$(acli jira workitem view "$1" --fields "summary,status,assignee,components,labels" --json)
   ```
   If status is not the configured eligible status (default `Ready for
   Development`) or assignee is not currentUser, abort with the reason.
4. Classify platform. We merge **components AND labels** because some
   teams put the platform marker in labels rather than components:
   ```
   markers=$(echo "$ticket_json" | jq -c '
     (.fields.components // [] | map(.name)) + (.fields.labels // [])
   ')
   platform=$(echo "$markers" | bash $SMITH_PLUGIN_ROOT/scripts/classify_platform.sh)
   ```
   `classify_platform.sh` recognises: `Shared/KMP`, `KMP`, `Shared`,
   `Multiplatform` → `kmp`; `Android` → `android`; pure `iOS` → `ios`;
   anything else → `unclear`. If the result is `ios`, abort with:
   "iOS-only ticket; Smith does not handle iOS work."

## Worktree setup (always live, even in --dry-run)

Compute the branch name. **Important: the slug passed to
`make_branch_name.sh` must be in English**, even if the JIRA summary
is in German (or another language). myposter-app convention: tickets
written by non-developers may be in German, but branches, commits,
PRs, and all code-related artefacts stay in English. If the ticket
summary is non-English, compose a 3–6 word English descriptive phrase
that captures the same intent, and pass *that* as the slug:

```
ticket="$1"
raw_summary=$(... from acli output ...)
# If raw_summary is non-English, translate to a short English phrase.
# Example: "Größere Schrift für ältere Nutzer" → "larger font for older users"
english_summary=<your English rendering of the ticket's intent>
branch=$(bash $SMITH_PLUGIN_ROOT/scripts/make_branch_name.sh "$ticket" "$english_summary")
```

Worktree path: `<target>/.smith/worktrees/<ticket-key-lowercased>/`

Create the worktree unconditionally:

```
bash $SMITH_PLUGIN_ROOT/scripts/make_worktree.sh "$ticket" "$branch"
```

This is local-only and trivially reversible (`git worktree remove`
later). The `--dry-run` flag gates only side effects that are visible
*outside* the target repo (JIRA writes, git push, gh PR create) —
local-only file/git operations stay live so the orchestration can
actually walk end-to-end.

Without this, Smith's spawn prompt would name a worktree path that
doesn't exist on disk, and the inner skills (`smith:claim`,
`smith:enrich`) would fail at their first `cd <worktree>` pre-flight.

After the test, clean up if you want:
```
git worktree remove .smith/worktrees/<ticket-lowercased>
git branch -D task/<ticket-lowercased>-<slug>   # local-only; never pushed in dry-run
```

## Spawn the teammate pair

Use the agent-team spawn mechanism. The spawn-prompt structure is
shown below in full — don't go fetch the spec for this; everything
needed is right here. Spawn two teammates with deterministic names so
the operator can reference them later:

**Teammate 1 — Mr. Smith**, agent type `smith`, name `smith-<ticket>`:

> Mode: ticket
> Ticket: $1
> Worktree: .smith/worktrees/<ticket-lowercased>/
> Branch: $branch
> Dry-run: ${DRY_RUN:-false}
> Confident: ${CONFIDENT:-false}
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

## Phase status (today: Phase 4)

What's live, by skill (all gated on `dry_run=false` from the spawn prompt):

| Skill | Phase 4 status |
|---|---|
| `smith:claim` | **LIVE** — JIRA transition + label add |
| `smith:enrich` | **LIVE** brief writing; Explore subagent dispatch deferred to Phase 2.x |
| `smith:pipeline` | **LIVE** Anderson critic loop; real spec/plan/diff gates |
| `smith:pr` | **LIVE** PR open — success path (clean draft PR + JIRA label remove) and WIP-stuck path (artefact promotion + draft PR with needs-human-attention + JIRA label swap) |

**Consequence for operators today** — running `/smith:implement APP-XXXX`
without `--dry-run` walks the full pipeline end-to-end:

1. JIRA: eligible status → claim status, add `smith-implementing`
2. Worktree created on `task/<key>-<slug>`
3. Brief written to `.smith/briefs/<key>-brief.md`
4. Spec / plan / impl committed per gate (subject to Anderson's review)
5. Either:
   - **Success**: `git push`, `gh pr create --draft`, JIRA `smith-implementing` removed
   - **WIP-stuck**: artefacts promoted + wip commit, `git push`, `gh pr create --draft --label needs-human-attention`, JIRA labels swapped to `auto-impl-failed`

In both cases, the operator ends with a draft PR they can land (after
review) or close out. No manual JIRA cleanup needed for either path.

`--dry-run` exercises the orchestration without external side effects —
useful for confirming a candidate ticket's brief is reasonable before
letting Smith claim and commit.
