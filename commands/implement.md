---
description: Dispatch a Smith+Anderson pair to implement one JIRA ticket. Flags: `--dry-run` (no external side effects), `--confident` (skip full build+tests, only run formatter).
---

# /smith:implement

You (the watchdog lead session) have been asked to dispatch a Smith
implementer team for a specific JIRA ticket. This is the operator-driven
manual override path; the watchdog monitors (Section 5.6 of the spec)
trigger the same flow automatically when new candidates appear.

> **HARD RULE — Smith and Anderson are spawned as named teammates,
> never as anonymous one-shot subagents.** Spawn each via the `Agent`
> tool with an explicit `name` parameter (see "Spawn the teammate pair"
> below). With agent-teams enabled, every session has one implicit
> team; a named Agent spawn creates a long-lived teammate on it that
> persists across mailbox round-trips and triggers the `TeammateIdle`
> hook. An Agent call *without* a `name` produces a one-shot subagent
> that dies after its first reply — that breaks the multi-turn mailbox
> protocol and leaves Smith self-reviewing. Never spawn Smith or
> Anderson without a `name`.
>
> (History: before Claude Code v2.1.178, teammates were created via
> `TeamCreate` / natural-language team creation and the Agent tool was
> forbidden here. Those tools no longer exist — the named Agent spawn
> IS the agent-teams mechanism now.)

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
   assert_agent_teams_enabled.sh
   ```
   If this fails, abort with the script's error message. Do not continue.
2. Verify your CWD is the configured target repo:
   ```
   assert_target_repo.sh
   ```
   If this fails, abort with the script's error message. Do not continue.
3. Verify both CLIs (gh, acli) are authenticated. Without this, the
   ticket lookup at step 5 fails with an opaque acli error, and any
   downstream `gh` write would fail mid-pipeline:
   ```
   assert_clis_authenticated.sh
   ```
   If this fails, surface the script's stderr verbatim to the operator —
   it names the exact remedy command (`gh auth login` /
   `acli jira auth login`) — and do not continue.
4. Read the cap and active-Smith count:
   ```
   max=$(smith_config.sh max_concurrent_impl_smiths)
   ```
   Count current active Smith teammates by checking your team's task list
   for in-progress tasks. If `active >= max`, abort with message:
   "At max parallelism ($active/$max active). Wait for a Smith to finish,
   or shutdown a teammate, then retry."
5. Verify the ticket via `acli` (skip the full JQL — just confirm the
   ticket exists, is assigned to you, and is in the eligible status):
   ```
   ticket_json=$(acli jira workitem view "$1" --fields "summary,status,assignee" --json)
   ```
   If status is not the configured eligible status (default `Ready for
   Development`) or assignee is not currentUser, abort with the reason.

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
branch=$(make_branch_name.sh "$ticket" "$english_summary")
```

Worktree path: `<target>/.smith/worktrees/<ticket-key-lowercased>/`

Create the worktree unconditionally:

```
make_worktree.sh "$ticket" "$branch"
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

Spawn both teammates via the **`Agent` tool**, one call per teammate,
**both calls in the same message** so they come up concurrently. Each
call MUST carry:

- `subagent_type`: `smith-impl` / `anderson-impl`
- `name`: `smith-impl-<ticket>` / `anderson-impl-<ticket>` — the
  `name` parameter is what makes the spawn a long-lived teammate on
  the session's implicit team (addressable via `SendMessage`) instead
  of a one-shot subagent. **An Agent call without `name` is a bug.**
- `prompt`: the spawn prompt below.

The spawn-prompt structure is shown below in full — don't go fetch the
spec for this; everything needed is right here. Use the deterministic
names above so the operator can reference the teammates later.

**Both must be spawned.** Smith requires a paired Anderson to do
adversarial review at every gate; without Anderson, Smith aborts the
ticket with `{result: "error", reason: "anderson not reachable"}`.
Spawning only Smith is not a valid dispatch — it just burns a Smith
slot to no effect. The two names must match exactly between Smith's
spawn prompt ("Your Anderson is: ...") and Anderson's actual spawn
name; a mismatched name is the same as a missing Anderson.

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

**Verify both came up** before considering dispatch successful. Both
`Agent` calls must return a successful spawn result naming the
teammate (a failed or denied call means that teammate does not exist).
If either spawn failed, retry that one spawn — re-issuing the same
`Agent` call with the same `name` is safe. If after retry one is
still missing, do not let Smith proceed — tear down the half-spawned
dispatch via `/smith:abort <ticket>` and report `{result: "error",
reason: "teammate pair spawn incomplete"}` to the operator.

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
   the rest of the session — including the `HARD RULE` about spawning
   teammates as *named* Agent calls, never anonymous one-shots.)

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
