---
description: Arm the autonomous Smith watchdog. Starts background monitors; lead reacts to notifications by dispatching teammate pairs within two separate caps, `max_concurrent_impl_smiths` and `max_concurrent_fixer_smiths` (both default 2). Flag: `--pr-only` (ignore JIRA candidates; only react to PR review comments).
---

# /smith:watchdog

You (the watchdog lead session) have been asked to arm the autonomous
watchdog. This is the entry point for Smith's event-driven operation
(spec Section 5.6).

> **HARD RULE — every Smith and Anderson dispatch goes through
> agent-teams, never the Agent/Task tool.** When a notification fires
> and you dispatch a teammate pair, you MUST use natural-language team
> creation (per `skills/watchdog/SKILL.md` "Spawn mechanism" and
> `commands/implement.md` "Spawn the teammate pair"). The `Agent` and
> `Task` tools produce one-shot subagents that exit after their first
> reply — that would strand Smith with no Anderson at the first review
> gate. A PreToolUse hook
> (`bin/hook_agent_teams_guard.sh`) denies any `Agent`/`Task`
> call whose `subagent_type` is one of `smith-impl`, `anderson-impl`,
> `smith-fixer`, `anderson-fixer`. If you see that denial, re-issue
> the dispatch with team-creation phrasing — do not retry the
> `Agent`/`Task` path.

## Arguments

- `$1` (optional): `--pr-only` — only react to `smith.pr.new_comments`
  notifications. JIRA-candidate notifications are received but ignored;
  no new ticket-mode dispatches happen in this session. Useful when an
  open Smith-authored PR is under active review and you want fast
  iteration on reviewer comments without the watchdog also picking up
  fresh tickets.

  When `--pr-only` is active, the `pr-comments` monitor also adapts its
  cadence: active polling at 60 sec, backing off to 30 min after 10
  consecutive quiet cycles (no new comments). Any new comment snaps it
  back to 60 sec. (The backoff is the monitor's default behaviour
  regardless of mode; --pr-only just makes it the dominant signal.)

## What this command actually does

The three plugin monitors (`monitors/monitors.json`) start as background
processes when Claude Code loads this plugin, but each one **gates its
work on the contents of `.smith/state/watchdog-mode`**. The gating is
asymmetric across monitors (see table below). While the file is absent,
all monitors are idle — no `gh` / `acli` calls, no state writes.
`/smith:watchdog` writes the file (with content `full` or `pr-only`),
which is what activates the relevant monitors for the chosen scope.

`/smith:watchdog` also loads the reaction skill into the lead session's
context so the lead knows how to handle incoming notifications.

Background monitors and their gating:

| Monitor | Active when `watchdog-mode` is… | Notes |
|---|---|---|
| `jira-candidates` | `full` only | Autonomous ticket pickup is an explicit opt-in; `pr-only` does not poll JIRA at all (saves `acli` calls; lead would ignore emissions anyway) |
| `pr-comments` | `full` OR `pr-only` | Reviewer / Augment iteration on already-open Smith PRs is in scope for both modes |
| `stop-sentinel` | any value | Kill switch is always honoured once armed |

- `jira-candidates` — polls JIRA every 30 min (configurable via the
  `polling_minutes` user-config); emits `smith.jira.new_candidates`
  only when a *new* eligible ticket key appears.
- `pr-comments` — polls open Smith-authored PRs every 60 sec (active),
  backing off to 30 min after 30 quiet cycles. Cadence resets on a
  new unresolved thread OR a Smith push (via pr_comments_reset.sh).
  Emits `smith.pr.new_comments`, which the watchdog turns into a
  smith-fixer + anderson-fixer dispatch (capped separately from impl,
  with a per-PR round cap of `max_fix_rounds`).
- `stop-sentinel` — watches `.smith/STOP` every 2 sec; emits
  `smith.stop.requested` or `smith.stop.lifted` on state change.

`/smith:implement` (the manual one-shot path) also writes `pr-only`
to `watchdog-mode` and loads this reaction skill **after** a
successful PR creation — so the fix loop engages for that one PR
without the operator having to run `/smith:watchdog` separately. The
JIRA monitor stays idle in that case (asymmetric gate), so no
autonomous ticket pickup happens.

To **disarm** the watchdog without exiting Claude Code:
```
rm .smith/state/watchdog-mode
```
Monitors stay alive but go back to idle. Re-arm by invoking
`/smith:watchdog` again.

(History: monitors were originally gated declaratively via
`on-skill-invoke:watchdog` in `monitors.json`, but that gate only fires
for direct user `/skill` invocations and not for LLM-driven Skill tool
calls from within slash commands. We moved the gate into each monitor
script via the `.smith/state/watchdog-mode` sentinel file.)

## Pre-flight

1. Verify agent-teams is enabled (Smith and Anderson must spawn as
   real teammates, not one-shot subagents):
   ```
   assert_agent_teams_enabled.sh
   ```
2. Verify CWD is the configured target repo:
   ```
   assert_target_repo.sh
   ```
3. Initialize the watchdog's per-target state files (idempotent;
   smith_config.sh handles lazy bootstrap and gitignore management):
   ```
   smith_config.sh target_repo > /dev/null
   active_smiths.sh count > /dev/null
   ```
4. Record the watchdog mode so the skill knows how to react. Without
   `--pr-only`, write `full`; with it, write `pr-only`:
   ```
   mkdir -p .smith/state
   if [[ "${1:-}" == "--pr-only" ]]; then
     echo pr-only > .smith/state/watchdog-mode
   else
     echo full > .smith/state/watchdog-mode
   fi
   ```

Both should be silent on success.

## Optional: scan-now

Before the monitors emit their first notifications, you may want to do
an immediate manual scan to surface anything currently eligible:

```
jira_scan.sh
```

If candidates appear and the cap has room, apply the same dispatch
flow the watchdog skill describes for `smith.jira.new_candidates` — see
`skills/watchdog/SKILL.md` for the exact runbook (it's the same brief
the lead follows for monitor-driven dispatches).

## Notification-reaction rules

See **`skills/watchdog/SKILL.md`** for the canonical reaction rules.
This command file does NOT duplicate them — the skill body is the
single source of truth. After you invoke this command, the skill is
loaded into your context and its instructions apply to every
notification you receive for the rest of the session.

Summary of the rules:

- `smith.jira.new_candidates` → if the impl cap
  (`max_concurrent_impl_smiths`) has room, not stopped, **and mode
  is `full`**, fetch fresh candidates, pick top eligible, dispatch
  ticket-mode pair (smith-impl + anderson-impl). In `pr-only` mode, log
  "ignored (pr-only)" and skip.
- `smith.pr.new_comments` → if the fixer cap
  (`max_concurrent_fixer_smiths`) has room, no fixer pair already on
  that PR, and the PR's fix-round counter is below `max_fix_rounds`
  (default 5), dispatch a smith-fixer + anderson-fixer pair (regardless
  of mode). On cap-hit for `max_fix_rounds`, the watchdog labels the PR
  `needs-human-attention` and skips dispatch.
- `smith.stop.requested` → set `smith_stop_active = true`, pause new
  dispatches; in-flight teammates wrap up at next safe checkpoint
- `smith.stop.lifted` → clear the flag, resume

## On manual `/smith:watchdog` re-invocation

If the operator invokes this command a second time in the same session,
do not re-spawn monitors (already running per Claude Code's
agent-teams doc). Treat it as a "scan now" request and re-run the
optional scan-now step.

## On `/smith:implement APP-XXXX` while watchdog is armed

The two are complementary. Operator-driven `/smith:implement`
dispatches respect the same `active_smiths.sh` caps — two separate
budgets, `max_concurrent_impl_smiths` and `max_concurrent_fixer_smiths`
(both default 2) — and will not exceed them even with watchdog
dispatching alongside.

## Kill switches

- `touch .smith/STOP` — triggers `smith.stop.requested` within ~2 sec
- `rm .smith/STOP` — triggers `smith.stop.lifted`
- Ctrl-C the session — immediate hard stop; monitors die with the session
- JIRA label `no-auto-impl` on a specific ticket — `jira_scan.sh`
  excludes it from future scans

## How the autonomous loop runs

When armed, the watchdog runs fully autonomously:

- Both Smith dispatch modes (ticket-impl + pr-fixer) are active
- Cap enforcement via `active_smiths.sh` (read at every notification),
  using the two separate budgets `max_concurrent_impl_smiths` and
  `max_concurrent_fixer_smiths` (both default 2)
- Per-PR fix-round cap (`max_fix_rounds`, default 5) enforced before
  every fixer dispatch; on cap-hit the PR is labelled
  `needs-human-attention` and skipped
- Notification-reaction rules in `skills/watchdog/SKILL.md` are
  executable runbooks backed by helper scripts: `pick_top_candidate.sh`,
  `make_worktree.sh`, `checkout_pr_worktree.sh`,
  `gh_pr_unresolved_comments.sh`, `pr_fix_round_inc.sh`.

One piece is not enforced mechanically: Smith teammates must call
`active_smiths.sh remove` after they finish (their outcome contract
requires it). Without that, the cap can drift up over the session
lifetime. A future `TeammateIdle` hook could force this cleanup; for
now, an operator can spot-check with `active_smiths.sh list`.