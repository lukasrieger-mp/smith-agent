---
name: smith-pipeline
description: The full Smith pipeline. Takes an enriched brief and drives SPEC → Anderson → PLAN → Anderson → IMPL (TDD) → Anderson → verify, with bounded iteration at each gate. Commits per gate so partial progress is recoverable.
---

# Smith Pipeline

See `smith/docs/spec.md` Section 8 for the full contract.

## Inputs

- `$BRIEF_PATH` — path to the enriched brief from smith-enrich
- `$SMITH_DRY_RUN` — when `1`, skip the actual brainstorming /
  writing-plans / subagent-driven-development invocations and only call the
  Anderson placeholder; no commits.

## Outputs

- Stdout: pipeline outcome JSON: `{ "result": "success" | "stuck", "reason": "..." }`
- Side effects (production): one commit per gate on the ticket branch
- Side effects (dry-run): log entries only

## Phase 1 workflow (all dry-run)

For each of the three gates (spec, plan, diff):

1. Log: `<ts> | smith-pipeline | $TICKET | gate-start | gate=<name>`
2. Invoke Anderson placeholder via the `anderson` agent. Capture its JSON.
3. Log: `<ts> | smith-pipeline | $TICKET | gate-result | gate=<name>, findings=<N>`

Always returns `{"result": "success", "reason": "phase-1 dry-run all gates passed"}`
since the placeholder Anderson always returns no findings.

## Out of scope for Phase 1

- Real brainstorming / writing-plans / TDD invocations
- Real Anderson critique (3 review modes)
- 3-round critic loop with divergence detection
- Commit-per-gate hygiene
- Build/verify integration
