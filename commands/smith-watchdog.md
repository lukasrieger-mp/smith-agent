---
description: Start the autonomous Smith watchdog. Uses the loop skill to poll JIRA every 30 minutes (configurable) for eligible candidate tickets and to fan-out PR-watch across open Smith PRs.
---

# /smith-watchdog

Args: optional `--dry-run`

## Usage

```
/smith-watchdog
/smith-watchdog --dry-run
```

## Workflow

In Phase 1 this is a thin shell:

1. Resolve polling cadence via
   `bash smith/scripts/smith_config.sh polling_minutes` (default 30).
2. Invoke the global `loop` skill with that cadence, asking it to repeatedly
   invoke the `smith-watchdog` skill.

`/loop 30m /smith-watchdog-tick` (the tick command is the `smith-watchdog`
skill, surfaced as a no-arg invocation).

Pass `SMITH_DRY_RUN=1` through if invoked with `--dry-run`.

## Phase 1 limitations

The `smith-watchdog` skill currently just lists candidates and logs them —
no claim, no implementation, no PR-watch fan-out. Phase 6 makes this end-to-end.

## Kill switches

- Ctrl-C the Claude Code session
- `touch .smith/STOP` — next tick exits cleanly
- Add `no-auto-impl` label to a specific JIRA ticket
