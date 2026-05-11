---
name: enrich
description: Read a JIRA ticket and produce an enriched brief — expanded acceptance criteria, suspected affected files, identified ambiguities, proposed DoD. Runs inside the Smith teammate context as step 2 of ticket mode. The brief becomes the input to smith:pipeline's brainstorming step.
---

# smith:enrich (inner-teammate)

You are inside a Mr. Smith teammate session (ticket mode). This skill
runs after `smith:claim`. It produces an enriched brief that
`smith:pipeline` consumes as the seed for the spec-writing gate.

For the full contract see `docs/spec.md` Section 11.2.2.

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

<verbatim ADF body rendered as Markdown — lossy fidelity is OK in Phase 1;
 Phase 2 uses a proper ADF walker>

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

## Phase 1 workflow (placeholder)

The Explore subagent integration is wired in Phase 2. For now:

1. Pre-flight:
   ```
   bash $CLAUDE_PLUGIN_ROOT/scripts/assert_target_repo.sh
   ```
2. Fetch the ticket:
   ```
   acli jira workitem view $ticket --fields "summary,description,components" --json
   ```
3. Flatten the ADF `description` to plain markdown text. A rough
   jq walk is acceptable in Phase 1:
   ```
   description=$(echo "$ticket_json" | jq -r '
     .fields.description | .. | objects | select(.type == "text") | .text
   ' 2>/dev/null | paste -sd' ' -)
   ```
   (Phase 2 replaces with a proper ADF→Markdown converter.)
4. Write the brief file with the three sections. For "Smith's reading"
   and "Proposed DoD", emit Phase-1 placeholder bullets:
   - `(Phase 1 placeholder: enrichment via Explore subagent comes in Phase 2.)`
   - `(Phase 1 placeholder DoD.)`
5. Append to `<target>/.smith/log.txt`:
   ```
   <ts> | smith:enrich | $ticket | brief-written | path=<worktree>/.smith/briefs/$ticket-brief.md
   ```
6. Echo the brief path.

## Phase 2 — when this skill goes live

The Explore subagent is dispatched via the Task tool with a focused
prompt:

> Read the JIRA ticket below. Identify files in the target repo that are
> likely to be affected by this work. Return a JSON array of
> `{path, line_range, why}` objects. Be conservative — only include files
> you can justify. Read `CLAUDE.md` for repo conventions before searching.
>
> Ticket: $ticket
> Summary: $summary
> Description (markdown-rendered): $description

The Smith teammate (you) parses Explore's reply and substitutes its
findings into the "Suspected affected files" section of the brief.

## On error

Failure to parse the ADF description, or `acli` returning an
unexpected shape, should produce `{result: "error"}` (retryable) — the
JIRA response might have been malformed on a single fetch. The Smith
teammate's outer logic decides whether to retry.

Failure to *find* the ticket (acli returns 404) is `{result: "stuck"}`
— the ticket was deleted or renamed mid-flight.
