---
name: pr
description: Open the draft PR for a Smith-implemented ticket. Two paths — success (clean title/body, smith-implementing label removed) and WIP-stuck (escalation PR with needs-human-attention label, JIRA label swap to auto-impl-failed, promoted spec/plan/brief artefacts committed). Always opens DRAFT — never marks ready-for-review, never merges.
---

# smith:pr (inner-teammate)

You are inside a Mr. Smith teammate session (ticket mode). This skill
is the last step of the pipeline. It runs after `smith:pipeline`
returned a result.

For the full contract see `docs/spec.md` Section 11.2.4.

## Inputs (from your spawn prompt + skill chain)

- `ticket`, `branch`, `worktree`, `dry_run` — from spawn prompt
- `outcome` — the pipeline's result: `success`, `stuck`, or `error`
- `stuck_reason` — populated when `outcome != "success"`

## Two paths

### Path A — Success

The pipeline ran clean: spec + plan + impl committed, quality checks
green. Open a normal draft PR.

1. Push the branch:
   ```
   git push -u origin "$branch"
   ```
2. Compose the PR title:
   ```
   title="[<TICKET-KEY>] <ticket-summary-from-jira>"
   ```
3. Compose the PR body — a Markdown doc with these sections:
   - **Links**: JIRA ticket URL (full link).
   - **What changed** — one bullet per high-level component touched.
     Derive from `git diff --stat origin/develop...HEAD` grouped by
     module/path.
   - **How it was tested** — list of `./gradlew` commands run via
     `run-silent.sh` during the pipeline, plus the umbrella
     `quality-check.sh` result.
   - **Spec & plan** — links to the committed files
     (`docs/superpowers/specs/<…>-design.md`, `docs/superpowers/plans/<…>.md`).
   - **Footer**: `Drafted by Smith (autonomous agent).`
4. Create the draft PR:
   ```
   gh pr create --draft \
     --title "$title" \
     --body "$body" \
     --base develop \
     --head "$branch" \
     --label smith-authored
   ```
   Capture the PR URL from `gh`'s stdout.
5. Remove the `smith-implementing` JIRA label:
   ```
   acli jira workitem edit --key "$ticket" --label-remove smith-implementing
   ```
6. Append log:
   ```
   <ts> | smith:pr | $ticket | success-pr | url=<url> branch=$branch
   ```
7. Return the PR URL to the caller; populate the outcome JSON's
   `pr_url` field.

### Path B — WIP-stuck

The pipeline returned stuck or error after the retry. Smith is handing
this work back to a human. Open a WIP draft PR with all the context the
human will need.

1. **Promote artefacts** so the next human sees them in the PR:
   ```
   bash $SMITH_PLUGIN_ROOT/scripts/promote_smith_artifacts.sh "$ticket"
   ```
   This script copies the brief from `.smith/briefs/<ticket>-brief.md`
   into the tracked location `docs/superpowers/specs/<ticket>-brief.md`,
   and commits any uncommitted partial work as a single
   `wip(smith): partial work at point of stuck — <ticket>` commit.
   Spec and plan files were already committed per-gate by
   `smith:pipeline`, so they ride along automatically.
2. Push the branch (still no force):
   ```
   git push -u origin "$branch"
   ```
3. Compose title:
   ```
   title="[WIP - agent-stuck] [<TICKET-KEY>] <summary>"
   ```
4. Compose body — same sections as the success path PLUS a prominent
   "Where Smith got stuck" section at the top, containing:
   - Which gate failed (spec / plan / diff / build)
   - The `stuck_reason` verbatim
   - Anderson's last findings (if applicable), formatted as a list
   - The last log entries from `<target>/.smith/log.txt`
5. Create the draft PR with both labels:
   ```
   gh pr create --draft \
     --title "$title" \
     --body "$body" \
     --base develop \
     --head "$branch" \
     --label smith-authored \
     --label needs-human-attention
   ```
6. **Swap the JIRA labels**:
   ```
   acli jira workitem edit --key "$ticket" \
        --label-remove smith-implementing \
        --label-add auto-impl-failed
   ```
   **Do not** post a JIRA comment (per spec Section 6.6 — labels carry
   the signal; the PR body holds the narrative).
7. Append log:
   ```
   <ts> | smith:pr | $ticket | wip-stuck-pr | url=<url> reason=<one-line>
   ```
8. Return the PR URL; populate the outcome JSON.

## Hard rules (always)

- **Always `--draft`.** Never `gh pr ready`. Never `gh pr merge`.
- **Always `--base develop`.** Never against `main` or release branches.
- **Never force-push.** Push only adds commits. If push fails because
  the remote moved (someone else pushed to the branch), abort with
  `{result: "error"}` — let the lead retry.
- The bash-guard hook (Section 5.7) is a backstop: any of the above
  rules violated by your Bash command will get denied.

## Workflow gated on dry_run

The two paths described above (Success and WIP-stuck) are the **live**
Phase 4 behaviour, executed when `dry_run = false` in your spawn
prompt. When `dry_run = true`, skip every external side effect:

- Don't `git push`
- Don't `gh pr create`
- Don't touch JIRA labels
- Don't invoke `promote_smith_artifacts.sh` (the wip commit it makes is
  also a side effect)

Instead, log the intended actions to `<target>/.smith/log.txt`:

```
<ts> | smith:pr | $ticket | would-push | branch=$branch
<ts> | smith:pr | $ticket | would-create-draft-pr | title=<title>
<ts> | smith:pr | $ticket | would-label-pr | labels=smith-authored
<ts> | smith:pr | $ticket | would-remove-jira-label | label=smith-implementing
```

…and return `dry-run://pr/$ticket` as the PR URL in your outcome JSON.

## Hard rules (unchanged across modes)

- **Always `--draft`.** Never `gh pr ready`. Never `gh pr merge`.
- **Always `--base develop`.** Never against `main` or release branches.
- **Never force-push.** Push only adds commits. If push fails because
  the remote moved, abort with `{result: "error"}` — let the lead retry.
- The bash-guard hook (Section 5.7) is a backstop: any of the above
  rules violated by your Bash command will get denied at runtime.

## On error

Any failure (push rejected, gh pr create errors, acli failure) → return
`{result: "error", reason}`. Lead retries once with a fresh teammate
pair. If the retry also fails, hand off to WIP-stuck (this very skill,
Path B, on retry).

## On error

Any failure (push rejected, gh pr create errors, acli failure) → return
`{result: "error", reason}`. Lead retries once with a fresh teammate
pair. If the retry also fails, hand off to WIP-stuck (this very skill,
Path B, on retry).
