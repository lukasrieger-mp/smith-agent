---
description: Arm the autonomous Smith watchdog. Starts three background monitors (JIRA candidates, PR comments, kill switch). The watchdog session reacts to monitor notifications by dispatching Smith+Anderson teammate pairs within the 2-concurrency cap.
---

# /smith:watchdog

You (the watchdog lead session) have been asked to arm the autonomous
watchdog. This is the entry point for Smith's event-driven operation
(spec Section 5.6).

## What this command actually does

The three plugin monitors (`monitors/monitors.json`) are gated on
`"when": "on-skill-invoke:watchdog"`. Until you invoke this skill, they
stay dormant. Invoking it starts them:

- `jira-candidates` — polls JIRA every 30 min (configurable via the
  `polling_minutes` user-config); emits a `smith.jira.new_candidates`
  notification only when a *new* eligible ticket key appears.
- `pr-comments` — polls open Smith-authored PRs every 60 sec; emits
  `smith.pr.new_comments` when a PR gains new unresolved threads.
- `stop-sentinel` — watches `.smith/STOP` every 2 sec; emits
  `smith.stop.requested` or `smith.stop.lifted` on state change.

After this command, the watchdog runs for the lifetime of the session.

## Pre-flight

1. Verify CWD is the configured target repo:
   ```
   bash $CLAUDE_PLUGIN_ROOT/scripts/assert_target_repo.sh
   ```
2. Confirm `.smith/config.json` exists (it auto-creates on first call to
   smith_config.sh; the `pr-comments` monitor reads from it):
   ```
   bash $CLAUDE_PLUGIN_ROOT/scripts/smith_config.sh target_repo > /dev/null
   ```

Both should be silent on success.

## Optional: scan-now

Before the monitors emit their first notifications, you may want to do
an immediate manual scan. Invoke:
```
bash $CLAUDE_PLUGIN_ROOT/scripts/jira_scan.sh
```

If candidates appear, the agent may choose to dispatch one (per the
notification-reaction rules below) without waiting for the first poll.

## Notification-reaction rules (this is the watchdog's standing brief)

These are the rules the session follows for every monitor notification
that arrives during the rest of the session. The rules implement spec
Section 5.3.

State you maintain in working memory:

- `smith_stop_active`: bool, initial `false`. Toggled by stop notifications.
- For each candidate spawn, track the teammate names you assigned.

### On `{"type": "smith.jira.new_candidates", "keys": [...]}`

1. If `smith_stop_active` → ignore.
2. Count currently-active Smith teammates (impl + pr-fix combined). If
   `active >= max_concurrent_smiths` (config; default 2) → ignore. The
   candidate stays eligible; a subsequent notification or operator
   override will dispatch it.
3. From the `keys` array, pick ONE — the highest priority per Section 6
   ordering (sprint, priority DESC, created ASC). Use
   `scripts/jira_scan.sh` for fresh detail on the chosen key.
4. Dispatch `/smith:implement <key>` — i.e. follow the implement
   command's flow (pre-flight, worktree, team spawn).

### On `{"type": "smith.pr.new_comments", "pr": N, "new_count": M, "branch": "..."}`

1. If `smith_stop_active` → ignore.
2. Check if there's already a PR-fix Smith working on this PR (search
   team task list for a task tagged with PR-N). If yes → ignore.
3. Count active Smith teammates. If `active >= max_concurrent_smiths`
   → ignore. The notification was emitted on diff, so the next change
   in that PR's comment set will re-trigger.
4. Fetch the unresolved comments via `gh pr view N --json reviewThreads`,
   filter for `isResolved: false`.
5. Dispatch a PR-fix-mode Smith+Anderson pair (spawn names
   `smith-pr-N` / `anderson-pr-N`), passing the PR number, branch,
   worktree path, and unresolved-comments JSON in the spawn prompt
   (see spec Section 18.3 PR-fix variant).

### On `{"type": "smith.stop.requested"}`

1. Set `smith_stop_active = true`.
2. Optionally, message in-flight Smith teammates: "Operator requested
   stop. Finish your current safe-checkpoint and exit gracefully."
3. From this point on, ignore new candidate / new-comment notifications.

### On `{"type": "smith.stop.lifted"}`

1. Set `smith_stop_active = false`.
2. Resume reacting to notifications normally. No automatic catch-up — the
   next real notification picks up where we paused.

## On manual `/smith:watchdog` re-invocation

If the operator invokes this command a second time in the same session,
do not re-spawn monitors (the agent-teams doc: monitors already running
stay running). Instead, treat it as a "scan now" request and re-run the
optional scan-now step above.

## On `/smith:implement APP-XXXX` while watchdog is armed

The two are complementary. The operator may manually dispatch a specific
ticket at any time; that dispatch competes for the same 2-Smith cap. The
watchdog's automatic dispatching respects the cap and will not exceed
2 active Smiths even with operator overrides in play.

## Kill switches (recap)

- `touch .smith/STOP` — triggers `smith.stop.requested` notification
  within ~2 sec; watchdog pauses
- `rm .smith/STOP` — triggers `smith.stop.lifted`; watchdog resumes
- Ctrl-C the Claude Code session — immediate hard stop; monitors die
  with the session per the plugins doc
- Add JIRA label `no-auto-impl` to a specific ticket — the next
  jira-candidates poll will exclude it; watchdog will not consider it

## Phase 1 caveats

Same as `/smith:implement`: the inner-teammate skills are placeholders,
so spawning a teammate pair on a notification will exercise the
orchestration but not change real external state. Once Phases 2–4 land,
each notification translates into actual JIRA writes and PR commits.
