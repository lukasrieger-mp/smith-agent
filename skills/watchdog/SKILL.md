---
name: watchdog
description: Outer-session notification handler. Runs in the watchdog lead session. Documents how to react to monitor notifications (smith.jira.new_candidates, smith.pr.new_comments, smith.stop.*) by dispatching Smith+Anderson teammate pairs within the concurrency cap. Invoke as `/smith:watchdog` to arm the monitors.
---

# Smith Watchdog (outer-session)

This skill is loaded in the **watchdog lead session** — the long-lived
Claude Code session the operator launches via
`claude --plugin-dir ~/StudioProjects/smith-agent`. It's the
counterpart to the `/smith:watchdog` slash command (which is what
actually arms the monitors via the agent-teams `on-skill-invoke` gating).

For the full architectural picture, see `docs/spec.md` Sections 5 + 18.

## Role

The watchdog session never edits code. Its job is:

1. **Arm monitors** when `/smith:watchdog` is invoked (the
   `"when": "on-skill-invoke:watchdog"` gate on each monitor in
   `monitors/monitors.json` starts the background process at that moment).
2. **Receive notifications** from the running monitors (each emits a
   structured JSON line on stdout; Claude Code surfaces these as agent
   notifications).
3. **Dispatch teammate pairs** (Smith + Anderson) in response to
   notifications, respecting the 2-concurrency cap and the kill switch.
4. **Track state**: the team task list, the kill-switch flag, the cap.

Code-editing happens entirely inside teammate subsessions — never in the
lead.

## What this skill contains

The same notification-reaction rules documented in
`commands/watchdog.md`. Both files describe the same behaviour from
different entry points (the command file is what the operator types; this
skill file is what the agent re-reads as it operates).

Treat both as the same brief: if there's any conflict between this file
and `commands/watchdog.md`, the command file wins.

## Notification schemas (quick reference)

```
{"type": "smith.jira.new_candidates", "keys": ["APP-1234", ...]}
{"type": "smith.pr.new_comments",     "pr": 4321, "new_count": 2, "branch": "task/..."}
{"type": "smith.stop.requested"}
{"type": "smith.stop.lifted"}
```

## Reaction rules (mirror of `commands/watchdog.md`)

- **`smith.jira.new_candidates`** → if not stopped and cap has room:
  pick highest-priority key (Section 6 ordering) and dispatch a
  ticket-mode Smith+Anderson pair (same flow as
  `/smith:implement <key>`).
- **`smith.pr.new_comments`** → if not stopped and cap has room and no
  PR-fix Smith already on that PR: fetch unresolved comments via
  `gh pr view N --json reviewThreads`; dispatch a PR-fix-mode pair.
- **`smith.stop.requested`** → set `smith_stop_active = true`; stop
  dispatching new pairs.
- **`smith.stop.lifted`** → set `smith_stop_active = false`; resume.

## Scripts available to the lead

- `scripts/assert_target_repo.sh` — pre-flight before any action.
- `scripts/jira_scan.sh` — manual scan-now (the JIRA monitor already
  runs this on its 30-min cadence).
- `scripts/smith_config.sh <key>` — read per-target config.
- `scripts/make_branch_name.sh <key> <summary>` — branch name for spawn
  prompts.
- `scripts/classify_platform.sh` — components → platform tag; iOS-only
  candidates are rejected at dispatch time.

## Logging

Append one line to `<target>/.smith/log.txt` for every notification
received AND for every dispatch decision (including the "ignored
because cap full" case). Format:

```
<ISO-8601 ts> | watchdog | <notification-type-or-action> | <details>
```

Examples:
```
2026-05-11T14:32:00Z | watchdog | smith.jira.new_candidates | keys=APP-5601; chose APP-5601
2026-05-11T14:32:01Z | watchdog | dispatch.ticket | ticket=APP-5601 worktree=.smith/worktrees/app-5601
2026-05-11T15:14:23Z | watchdog | smith.pr.new_comments | pr=4321 new_count=2; ignored (cap 2/2)
```

The operator's audit trail.

## Phase 1 caveats

Inner-teammate skills are placeholders. When this skill triggers a
dispatch (or `/smith:implement` does it manually), the spawned Smith
teammate walks through the workflow without actually changing JIRA
status, creating branches, or opening PRs. The outcome JSON arrives as
faux-success. This is intentional Phase 1 behaviour to exercise
orchestration.
