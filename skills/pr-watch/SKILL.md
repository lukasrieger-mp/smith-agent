---
name: pr-watch
description: Legacy skill — superseded by the pr-comments monitor (Section 5.6). Kept only as a manual "rescan all Smith PRs for unresolved comments now" trigger. May be removed in a later phase.
---

# smith:pr-watch (legacy — see also: pr-comments monitor)

This skill was the pre-monitor design's PR-fix fan-out mechanism. The
`pr-comments` monitor in `monitors/monitors.json` now handles that role
event-driven (spec Section 5.6).

This file is kept as a thin operator-driven escape hatch: when invoked,
it does a one-shot rescan of all open Smith-authored PRs for unresolved
comments and dispatches PR-fix-mode Smith+Anderson pairs (within the
concurrency cap) for any PR with unresolved comments — equivalent to
the `pr-comments` monitor firing manually.

## When you might use this

- The monitor's last poll was less than 60 seconds ago and a reviewer
  just left comments you want addressed *now* — skip the wait.
- You temporarily stopped the watchdog (via `.smith/STOP`), lifted the
  stop, and want to drain any PR-comment backlog without waiting for
  the next natural poll.
- Debugging: you want to manually trigger the same logic the monitor
  uses to verify it works.

## Workflow

1. Pre-flight (same as the other outer-session skills):
   ```
   bash $CLAUDE_PLUGIN_ROOT/scripts/assert_target_repo.sh
   ```
2. Run the monitor script in oneshot mode:
   ```
   SMITH_MONITOR_ONESHOT=1 \
     bash $CLAUDE_PLUGIN_ROOT/scripts/monitor_pr_comments.sh
   ```
   Capture any emitted notification lines.
3. For each `smith.pr.new_comments` notification: apply the same
   reaction rules as `/smith:watchdog` ("On smith.pr.new_comments").
   Dispatch a PR-fix-mode Smith+Anderson pair per matching PR, subject
   to the concurrency cap.

## Phase 1 caveat

Same Phase-1 placeholder rules apply: PR-fix-mode Smith teammates log
intended writes (`would-fix`, `would-push`) without performing them.

## Future

This skill may be removed once the `pr-comments` monitor is proven
reliable in real-world use. The plugin doesn't need redundant entry
points for the same logic.
