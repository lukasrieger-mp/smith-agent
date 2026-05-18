---
description: Dispatch a Smith+Anderson pair to implement one JIRA ticket. Flags: `--dry-run` (no external side effects), `--confident` (skip full build+tests, only run formatter).
---

# /smith:implement

You (the watchdog lead session) have been asked to dispatch a Smith
implementer team for a specific JIRA ticket. This is the operator-driven
manual override path; the watchdog monitors (Section 5.6 of the spec)
trigger the same flow automatically when new candidates appear.

> **HARD RULE — spawning is via agent-teams, never the Agent/Task tool.**
> Smith and Anderson must be created as long-lived teammates through
> natural-language team creation (see "Spawn the teammate pair" below).
> Do NOT use the `Agent` or `Task` tool to spawn them — that produces
> one-shot subagents that die after their first reply, breaking the
> multi-turn mailbox protocol and leaving Smith self-reviewing. A
> PreToolUse hook (`hook_agent_teams_guard.sh`) will deny any
> `Agent`/`Task` call whose `subagent_type` is `smith-impl`,
> `anderson-impl`, `smith-fixer`, or `anderson-fixer`. If you see that
> denial, re-issue the dispatch using team-creation phrasing; don't try
> to work around the hook.

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

1. Verify agent-teams is enabled. Without it the Smith/Anderson pair
   spawn degrades silently to one-shot subagents:
   ```
   bash $SMITH_PLUGIN_ROOT/scripts/assert_agent_teams_enabled.sh
   ```
   If this fails, abort with the script's error message. Do not continue.
2. Verify your CWD is the configured target repo:
   ```
   bash $SMITH_PLUGIN_ROOT/scripts/assert_target_repo.sh
   ```
   If this fails, abort with the script's error message. Do not continue.
3. Read the cap and active-Smith count:
   ```
   max=$(bash $SMITH_PLUGIN_ROOT/scripts/smith_config.sh max_concurrent_impl_smiths)
   ```
   Count current active Smith teammates by checking your team's task list
   for in-progress tasks. If `active >= max`, abort with message:
   "At max parallelism ($active/$max active). Wait for a Smith to finish,
   or shutdown a teammate, then retry."
4. Verify the ticket via `acli` (skip the full JQL — just confirm the
   ticket exists, is assigned to you, and is in the eligible status):
   ```
   ticket_json=$(acli jira workitem view "$1" --fields "summary,status,assignee,components,labels" --json)
   ```
   If status is not the configured eligible status (default `Ready for
   Development`) or assignee is not currentUser, abort with the reason.
5. Classify platform. We merge **components AND labels** because some
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

**Do NOT use the `Agent` tool here.** That spawns one-shot subagents
that finish their first turn and exit — Anderson would die before the
spec gate. This pair must be spawned via the **agent-teams** mechanism,
which produces long-lived teammates that persist across mailbox
round-trips and trigger the `TeammateIdle` hook.

The agent-teams spawn is initiated by natural language. Phrase your
request to create a team with two teammates. Example phrasing:

> Create an agent team with two teammates for ticket APP-XXXX:
>
> - First teammate uses agent type `smith-impl`, named `smith-impl-APP-XXXX`,
>   with the spawn prompt below.
> - Second teammate uses agent type `anderson-impl`, named
>   `anderson-impl-APP-XXXX`, with the spawn prompt below.
>
> Both must persist for the lifetime of this ticket. Do not shut them
> down on idle.

The spawn-prompt structure is shown below in full — don't go fetch the
spec for this; everything needed is right here. Spawn two teammates
with deterministic names so the operator can reference them later.

**Both must be spawned.** Smith requires a paired Anderson to do
adversarial review at every gate; without Anderson, Smith aborts the
ticket with `{result: "error", reason: "anderson not reachable"}`.
Spawning only Smith is not a valid dispatch — it just burns a Smith
slot to no effect. The two names must match exactly between Smith's
spawn prompt ("Your Anderson is: ...") and Anderson's actual spawn
name; a mismatched name is the same as a missing Anderson.

**If you find yourself using the `Agent` tool**, stop and re-read this
section. The `Agent` tool is always available regardless of whether
agent-teams is enabled; you can reach for it by reflex. That is the
failure mode this paragraph exists to prevent.

**Teammate 1 — Mr. Smith**, agent type `smith-impl`, name `smith-impl-<ticket>`:

> Mode: ticket
> Ticket: $1
> Worktree: .smith/worktrees/<ticket-lowercased>/
> Branch: $branch
> Dry-run: ${DRY_RUN:-false}
> Confident: ${CONFIDENT:-false}
> Your Anderson is: anderson-impl-<ticket>
> Execute smith:claim, smith:enrich, smith:pipeline, smith:pr per spec Section 8.
> Send {type: smith.outcome, ...} to the lead via mailbox when done.

**Teammate 2 — Mr. Anderson**, agent type `anderson-impl`, name `anderson-impl-<ticket>`:

> You are reviewing Smith's work on $1.
> Worktree: .smith/worktrees/<ticket-lowercased>/
> Wait for review requests from smith-impl-<ticket> via mailbox.
> Per spec Section 8.2, only report findings at confidence >= 80.
> Reply with the documented JSON schema for each gate (mode=spec, mode=plan, mode=diff).
> **Stay alive until the lead sends you a shutdown request.** Smith
> will send multiple review.request messages across the pipeline (one
> per gate). After replying to one, wait silently for the next — do
> not self-terminate. An empty inbox is not "done"; it's "waiting".

**Verify both came up** before considering dispatch successful. After
the two spawn calls, list active teammates and confirm you see both
`smith-impl-<ticket>` and `anderson-impl-<ticket>`. If either is missing, retry
that one spawn. If after retry one is still missing, do not let Smith
proceed — tear down the half-spawned dispatch via `/smith:abort
<ticket>` and report `{result: "error", reason: "teammate pair spawn
incomplete"}` to the operator.

Add a team task: `implement <ticket>`, assigned to Smith.

## Wait for outcome

Smith and Anderson coordinate via mailbox during the run. The lead's job
is to wait for Smith's final `{type: "smith.outcome", ...}` message.

When it arrives, parse the result:

- `success`: print a summary including PR URL, mode, log_entries.
  Then **arm the fix loop** (see "Arm fix loop on success" below) so
  reviewer / Augment comments on the new PR get picked up.
- `stuck`: print the reason and the path to the WIP-stuck PR (if any).
  Do NOT arm the fix loop — WIP-stuck is a human-handoff path.
- `error`: per spec Section 8.5, dispatch ONE retry with a fresh teammate
  pair (new names: `smith-impl-<ticket>-retry`, `anderson-impl-<ticket>-retry`).
  If the retry also returns error → escalate to final WIP-stuck.

## On dispatch failure

If the team spawn itself fails (rare) or Smith never returns an outcome
JSON before going idle, treat as `{result: "error", reason: "teammate
failed to report"}` per spec Section 8.5.

## Arm fix loop on success

After Smith returns `{result: "success", pr_url: ...}` (NOT for `stuck`
or `error`), arm `pr-only` mode and load the watchdog reaction skill so
this same lead session can dispatch fixer pairs when reviewer or
Augment comments arrive on the new PR.

The `smith:pr` skill posted `augment review` as the PR's first comment.
Without arming, that comment goes into the void — the pr-comments
monitor is gated on `.smith/state/watchdog-mode` and the lead has no
reaction-skill runbook loaded. Arming closes the loop.

1. Set the watchdog mode to `pr-only`, but **do not demote `full`** if
   the operator already explicitly armed full autonomy in this session:
   ```
   mkdir -p .smith/state
   current_mode=$(cat .smith/state/watchdog-mode 2>/dev/null || echo "")
   if [[ "$current_mode" != "full" ]]; then
     echo pr-only > .smith/state/watchdog-mode
   fi
   ```
   - File absent → write `pr-only`.
   - File contains `pr-only` → no-op (overwrite with same).
   - File contains `full` → leave it (already broader scope).

2. Load the watchdog reaction skill into this session's context so the
   lead knows how to handle `smith.pr.new_comments` notifications when
   they arrive:
   ```
   Skill watchdog
   ```
   (Invoke via the `Skill` tool with `skill: watchdog`. After load,
   the dispatch sub-routines in `skills/watchdog/SKILL.md` apply for
   the rest of the session — including the `HARD RULE` about
   agent-teams spawning.)

3. Print a one-line confirmation in the operator output:
   ```
   Fix loop armed (pr-only). Watching PR for reviewer / Augment
   comments. Disarm with: rm .smith/state/watchdog-mode
   ```

The JIRA candidates monitor is **separately gated on `full` mode**, so
arming `pr-only` does NOT start autonomous ticket pickup. Only
`/smith:watchdog` (with no flag) enables that. The two monitors gate
asymmetrically on purpose: `/smith:implement` is a one-shot for the
impl side but a fix-loop entrypoint for the PR side.

The SessionStart hook wipes `.smith/state/watchdog-mode` on every new
Claude Code session — so the fix-loop arming is per-session, not
durable. A fresh session in the same target repo will NOT auto-resume
watching a previously-armed PR. That is intentional: every autonomous
behaviour must be operator-initiated once per session.

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

## End-to-end behaviour

Running `/smith:implement APP-XXXX` without `--dry-run` walks the full
pipeline:

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
