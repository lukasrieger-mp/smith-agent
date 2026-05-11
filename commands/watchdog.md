---
description: Arm the autonomous Smith watchdog. Starts background monitors; lead reacts to notifications by dispatching teammate pairs within the 2-cap.
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
  `polling_minutes` user-config); emits `smith.jira.new_candidates`
  only when a *new* eligible ticket key appears.
- `pr-comments` — polls open Smith-authored PRs every 60 sec; emits
  `smith.pr.new_comments` when a PR gains new unresolved threads.
- `stop-sentinel` — watches `.smith/STOP` every 2 sec; emits
  `smith.stop.requested` or `smith.stop.lifted` on state change.

After this command, the watchdog runs for the lifetime of the session.

## Pre-flight

1. Verify CWD is the configured target repo:
   ```
   bash $SMITH_PLUGIN_ROOT/scripts/assert_target_repo.sh
   ```
2. Initialize the watchdog's per-target state files (idempotent;
   smith_config.sh handles lazy bootstrap and gitignore management):
   ```
   bash $SMITH_PLUGIN_ROOT/scripts/smith_config.sh target_repo > /dev/null
   bash $SMITH_PLUGIN_ROOT/scripts/active_smiths.sh count > /dev/null
   ```

Both should be silent on success.

## Optional: scan-now

Before the monitors emit their first notifications, you may want to do
an immediate manual scan to surface anything currently eligible:

```
bash $SMITH_PLUGIN_ROOT/scripts/jira_scan.sh
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

- `smith.jira.new_candidates` → if cap has room and not stopped,
  fetch fresh candidates, pick top eligible, dispatch ticket-mode pair
- `smith.pr.new_comments` → if cap has room and no PR-fix Smith
  already on that PR, dispatch PR-fix-mode pair
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
dispatches respect the same `active_smiths.sh` cap and will not
exceed 2 active Smiths even with watchdog dispatching alongside.

## Kill switches

- `touch .smith/STOP` — triggers `smith.stop.requested` within ~2 sec
- `rm .smith/STOP` — triggers `smith.stop.lifted`
- Ctrl-C the session — immediate hard stop; monitors die with the session
- JIRA label `no-auto-impl` on a specific ticket — `jira_scan.sh`
  excludes it from future scans

## Phase 6 status

As of Phase 6, the watchdog is **fully autonomous**:

- Both Smith dispatch modes (ticket + pr-fix) live since Phases 4–5
- Cap enforcement via `active_smiths.sh` (read at every notification)
- All notification-reaction rules in `skills/watchdog/SKILL.md` are
  executable runbooks (not just doctrine), backed by helper scripts:
  `pick_top_candidate.sh`, `make_worktree.sh`,
  `checkout_pr_worktree.sh`, `gh_pr_unresolved_comments.sh`,
  `pr_fix_cycle_inc.sh`.

What's *not* enforced mechanically (depends on LLM-driven discipline):

- Smith teammates calling `active_smiths.sh remove` after they finish
  (their outcome contract requires it). Without that, the cap can
  drift up over the session lifetime. Future iteration: a
  `TeammateIdle` hook to force the cleanup (deferred per spec
  Section 5.7.1).