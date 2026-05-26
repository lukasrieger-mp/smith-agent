---
name: enrich
description: Read a JIRA ticket; write an enriched brief (acceptance criteria, ambiguities, proposed DoD). Step 2 of Smith's ticket mode; input to smith:pipeline.
---

# smith:enrich (inner-teammate)

You are inside a Mr. Smith teammate session (ticket mode). This skill
runs after `smith:claim`. It produces an enriched brief that
`smith:pipeline` consumes as the seed for the spec-writing gate.

(Design rationale: `docs/spec.md` §11.2.2 — informational; this file
suffices to operate.)

## Inputs (from your spawn prompt + skill chain)

- `ticket` — JIRA key
- `worktree` — your current working directory
- `dry_run` — from spawn prompt

## Outputs

- File: `<worktree>/.smith/briefs/<ticket>-brief.md`
- Stdout: the file path of the brief

The brief lives inside the *worktree's* `.smith/briefs/`, not the
target repo root's `.smith/`. The lead's `.smith/` is for cross-ticket
state; per-ticket scratch lives in the per-ticket worktree.

## Brief content (three sections)

```markdown
# Brief — <ticket-key>: <summary>

## Original ticket

<verbatim ADF body rendered as Markdown via bin/adf_to_markdown.sh>

## Smith's reading

- **Acceptance criteria** (extracted verbatim or near-verbatim from
  the ticket body; do NOT invent criteria the ticket doesn't state):
  - …
- **Genuine ambiguities for explicit deferral** (things the ticket
  leaves open that *materially* affect implementation; default the
  resolution to the *minimal* interpretation, do NOT maximalise. If
  you can implement without resolving the ambiguity, don't list it —
  this is not a brainstorming space):
  - …
- **Suspected affected files** (orientation from an Explore subagent
  pass — not a precise edit list):
  - <file>[:<line-range>] — <why>
- **Platform**: <components list from JIRA>  (purely informational)

## Proposed DoD

- [ ] <criterion 1>
- [ ] <criterion 2>
- [ ] All target-tracked tests pass: `./scripts/quality-check.sh`
- [ ] Branch ready for draft PR; no commits on `develop`/`main`.
```

## Workflow

In **both** dry-run and live modes, this skill writes a brief file at
`<worktree>/.smith/briefs/<ticket>-brief.md`. The acli read is a safe
operation (no state changes), so we perform it unconditionally — only
the Explore subagent dispatch (step 2) is gated on `dry_run`.

### Steps

1. Pre-flight:
   ```
   cd <worktree>
   assert_target_repo.sh
   ```

2. **(skip when `dry_run = true`)** Dispatch an orientation pass to
   give the spec gate a rough map of where in the codebase this work
   probably lives. **This is for orientation, not precision** — the
   spec gate does its own deeper exploration. The goal is to keep
   `superpowers:brainstorming` from starting from zero.

   Fetch the ticket text first so you can quote it in the prompt:
   ```
   ticket_json=$(acli jira workitem view "$ticket" --fields "summary,description" --json)
   summary=$(jq -r '.fields.summary' <<<"$ticket_json")
   ```

   Dispatch via the `Task` tool with `subagent_type: "Explore"`,
   breadth `medium` (or `very thorough` if the ticket is large), with
   this prompt:

   > Give a Smith implementation agent a rough orientation of where in
   > the target codebase this JIRA ticket's work probably touches.
   > **This is not a precise edit list** — the spec gate will do its
   > own deeper exploration. Goal: enough context that the spec writer
   > starts somewhere instead of from zero.
   >
   > Include:
   > - Files likely to be directly modified.
   > - Adjacent files (shared models/state, existing tests, related
   >   composables/screens) the spec writer should know about.
   > - Existing patterns or components the new code should be
   >   consistent with.
   >
   > Read the target repo's `CLAUDE.md` first for project conventions.
   >
   > Return **only** a JSON array (no prose around it), one element
   > per file, of the shape:
   > ```
   > [{"path": "<repo-relative path>", "line_range": "<optional, e.g. 42-120>", "why": "<one-line rationale>"}]
   > ```
   > Omit `line_range` for whole-file references. Return `[]` if
   > nothing meaningful can be identified.
   >
   > Ticket: $ticket
   > Summary: $summary
   > Description: <the `description` field flattened to text — let
   > `bin/adf_to_markdown.sh` do this if it's ADF>

   Validate the reply parses as a JSON array. If valid, write it to
   `<worktree>/.smith/briefs/<ticket>-affected.json`. If invalid (or
   if Explore failed for any reason), proceed without it — the brief
   gracefully falls back to a placeholder for that bullet. Do not
   fail the pipeline; orientation hints are nice-to-have, not
   load-bearing.

3. Fetch + flatten + write the brief, passing the affected-files JSON
   (if any) as the second argument:
   ```
   brief_path=$(write_brief.sh "$ticket" "$affected_files_path")
   ```
   If you didn't produce `$affected_files_path` (dry-run or Explore
   failure), call `write_brief.sh "$ticket"` instead.

4. Append log:
   ```
   <ts> | smith:enrich | $ticket | brief-written | path=$brief_path affected=<count|skipped>
   ```

5. Echo the brief path to stdout.

## On error

Failure to parse the ADF description, or `acli` returning an
unexpected shape, should produce `{result: "error"}` (retryable) — the
JIRA response might have been malformed on a single fetch. The Smith
teammate's outer logic decides whether to retry.

Failure to *find* the ticket (acli returns 404) is `{result: "stuck"}`
— the ticket was deleted or renamed mid-flight.
