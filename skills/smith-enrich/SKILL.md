---
name: smith-enrich
description: Read a JIRA ticket and produce an enriched brief (expanded acceptance criteria, suspected affected files, identified ambiguities, suggested DoD). Used by smith-pipeline as input to the brainstorming step.
---

# Smith Enrich

See `smith/docs/spec.md` Section 11.3 for the full contract.

## Inputs

- `$TICKET` — JIRA ticket key
- `$SMITH_DRY_RUN` — when `1`, write the brief to `.smith/dry-run-briefs/`
  instead of `docs/superpowers/specs/.smith/` and skip the Explore subagent.

## Outputs

- File: `docs/superpowers/specs/.smith/$TICKET-brief.md` (production) or
  `.smith/dry-run-briefs/$TICKET-brief.md` (dry-run)
- Stdout: path to the written brief

## Phase 1 workflow

1. Resolve ticket summary + description via
   `acli jira workitem view $TICKET --fields summary,description,components --json`.
2. Write a minimal brief containing:
   - Section "Original ticket" — the verbatim JIRA description text (ADF
     flattened to markdown via `jq` walk; acceptable to be lossy in Phase 1)
   - Section "Smith's reading" — placeholder line:
     `(Phase 1 placeholder: enrichment via Explore subagent comes in Phase 2.)`
   - Section "Proposed DoD" — one bullet:
     `(Phase 1 placeholder.)`
3. Append to `.smith/log.txt`:
   `<ts> | smith-enrich | $TICKET | brief-written | path=<path>`
4. Print the brief path.

## Out of scope for Phase 1

- Explore subagent invocation
- ADF → markdown fidelity (Phase 2 will use a proper ADF walker)
- Real DoD synthesis
