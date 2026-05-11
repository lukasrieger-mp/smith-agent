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

<verbatim ADF body rendered as Markdown via scripts/adf_to_markdown.sh>

## Smith's reading

- **Acceptance criteria** (expanded, parsed from the ticket body):
  - …
- **Identified ambiguities** (things the ticket doesn't say but should):
  - …
- **Suspected affected files** (from an Explore subagent pass):
  - <file>:<line-range> — <why>
- **Suspected affected modules**: <list>
- **Platform**: <android | kmp | mixed>  (per components classification)

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
the optional Explore subagent dispatch is gated on `dry_run`.

### Steps

1. Pre-flight:
   ```
   cd <worktree>
   bash $SMITH_PLUGIN_ROOT/scripts/assert_target_repo.sh
   ```
2. Fetch + flatten + write the brief in one call:
   ```
   brief_path=$(bash $SMITH_PLUGIN_ROOT/scripts/write_brief.sh "$ticket")
   ```
   The script fetches the ticket via `acli`, flattens the ADF
   `description` to Markdown via `scripts/adf_to_markdown.sh`, and
   writes the structured brief.
3. Append log:
   ```
   <ts> | smith:enrich | $ticket | brief-written | path=$brief_path
   ```
4. Echo the brief path to stdout.

### Future: Explore subagent integration

The "Smith's reading" section's "Suspected affected files" bullet is
currently filled by `write_brief.sh` with a static placeholder. A
follow-up could dispatch the Explore subagent via the Task tool after
`write_brief.sh` returns:

> Read the JIRA ticket below. Identify files in the target repo likely
> to be affected by this work. Return a JSON array of
> `{path, line_range, why}` objects. Be conservative — only include
> files you can justify. Read `CLAUDE.md` for repo conventions before
> searching.
>
> Ticket: $ticket
> Summary: $summary
> Description (Markdown-rendered): <contents of the brief's "Original ticket" section>

Parse Explore's reply and rewrite the "Suspected affected files"
section of the brief in-place.

In `dry_run = true` mode, this Explore dispatch should be skipped —
Explore is read-only so it has no side effects, but the call is
non-trivial in token cost and dry-run is meant to be cheap.

## On error

Failure to parse the ADF description, or `acli` returning an
unexpected shape, should produce `{result: "error"}` (retryable) — the
JIRA response might have been malformed on a single fetch. The Smith
teammate's outer logic decides whether to retry.

Failure to *find* the ticket (acli returns 404) is `{result: "stuck"}`
— the ticket was deleted or renamed mid-flight.
