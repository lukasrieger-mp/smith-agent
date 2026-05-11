---
name: watchdog
description: One watchdog tick. Scans JIRA for eligible candidate tickets (assigned, "Ready for Development", SP ≤ 2, no opt-out labels), checks open Smith PRs for unresolved comments, and dispatches at most one action (smith-claim, smith-pr-watch, or no-op). Use when /smith:watchdog command runs or when the loop skill fires.
---

# Smith Watchdog (Tick)

Phase 1 stub. Real JIRA polling and PR-watch dispatch are wired in later
phases. This skill currently:

1. Asserts working directory via `scripts/assert_target_repo.sh`.
2. Runs `scripts/jira_scan.sh` (stub mode in Phase 1 via
   `SMITH_DRY_RUN_FIXTURE`).
3. Logs the candidate count to `.smith/log.txt`.
4. Returns the JSON candidate list to the caller.

See `docs/spec.md` Section 5.3 (per-tick decision tree) and Section 6
(JIRA integration) for the full contract this skill must satisfy in later
phases.

## Inputs

None directly. Reads:
- `SMITH_DRY_RUN_FIXTURE` env (stub mode)
- `.smith/config.json` for polling cadence, status names, project key

## Outputs

- Stdout: JSON candidate array (possibly empty)
- Side effect: one line appended to `.smith/log.txt`

## Phase 1 workflow

1. `bash scripts/assert_target_repo.sh` — abort if not in agent repo.
2. `bash scripts/jira_scan.sh` — capture JSON output.
3. Log: `$(date -u +%FT%TZ) | smith-watchdog | - | scan | candidates=<N>`.
4. Print the candidate JSON.

## Out of scope for Phase 1

- Real `acli` JIRA querying (covered by jira_scan.sh's real-mode path; not
  exercised by Phase 1 tests).
- PR-watch dispatch (Phase 5).
- Candidate ranking / dispatch to smith-claim (Phase 2+).
