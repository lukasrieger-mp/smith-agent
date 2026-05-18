---
name: pr
description: Open Smith's draft PR — success path (clean PR + label cleanup) or WIP-stuck path (escalation PR + needs-human-attention + JIRA label swap). Always --draft.
---

# smith:pr (inner-teammate)

You are inside a Mr. Smith teammate session (ticket mode). This skill
is the last step of the pipeline. It runs after `smith:pipeline`
returned a result.

(Design rationale: `docs/spec.md` §11.2.4 — informational; this file
suffices to operate.)

## Inputs (from your spawn prompt + skill chain)

- `ticket`, `branch`, `worktree`, `dry_run` — from spawn prompt
- `outcome` — the pipeline's result: `success`, `stuck`, or `error`
- `stuck_reason` — populated when `outcome != "success"`

## Two paths

### Path A — Success

The pipeline ran clean: spec + plan + impl committed, quality checks
green. Open a normal draft PR.

1. Ensure the GitHub labels Smith uses actually exist in the repo. The
   helper is idempotent — a no-op when the labels are already there:
   ```
   bash $SMITH_PLUGIN_ROOT/scripts/gh_ensure_labels.sh
   ```
2. Push the branch, then kick the PR-comments monitor so its cadence
   resets — reviewers may start commenting within minutes of the PR
   appearing:
   ```
   git push -u origin "$branch"
   bash $SMITH_PLUGIN_ROOT/scripts/pr_comments_reset.sh
   ```
3. Compose the PR title:
   ```
   title="[<TICKET-KEY>] <ticket-summary-from-jira>"
   ```
4. Compose the PR body — a Markdown doc with these sections:
   - **Links**: JIRA ticket URL (full link).
   - **What changed** — one bullet per high-level component touched.
     Derive from `git diff --stat origin/develop...HEAD` grouped by
     module/path.
   - **How it was tested** — list of `./gradlew` commands run via
     `run-silent.sh` during the pipeline.
     - If the spawn prompt had `confident = false`: include the
       `quality-check.sh` result. Normal case.
     - **If `confident = true`**: at the top of this section, emit a
       prominent callout:
       ```
       > ⚠️ This PR was created with `--confident`. The full quality
       > check (build + tests) was SKIPPED. Only the Kotlin formatter
       > ran. Reviewer must verify the change builds and tests pass
       > before merging.
       ```
       Then list only the formatter command.
   - **Footer**: `Drafted by Smith (autonomous agent).` Append
     ` [--confident]` when that flag was active.

   Do NOT include a "Spec & plan" links section on the success path.
   Spec and plan are agent-internal artefacts; they live only at
   `<worktree>/.smith/specs/` and `<worktree>/.smith/plans/`
   (gitignored) and are never committed to the branch on success. If
   you want to reference them in the PR body, inline a brief summary
   instead — do NOT link to repo paths that don't exist on the branch.
5. Create the draft PR:
   ```
   gh pr create --draft \
     --title "$title" \
     --body "$body" \
     --base develop \
     --head "$branch" \
     --label smith-authored
   ```
   Capture the PR URL from `gh`'s stdout.
6. **Trigger the Augment review bot.** Post a comment on the new PR
   to start the autonomous review loop. The pr-comments monitor will
   surface Augment's findings within ~3–5 minutes and the watchdog
   will dispatch a smith-fixer + anderson-fixer pair to handle them:
   ```
   gh pr comment "$pr_number" --body "augment review"
   ```
   Also kick the pr-comments monitor so its cadence resets to the
   active interval:
   ```
   bash $SMITH_PLUGIN_ROOT/scripts/pr_comments_reset.sh
   ```
7. Remove the `smith-implementing` JIRA label:
   ```
   acli jira workitem edit --key "$ticket" --label-remove smith-implementing
   ```
8. Append log:
   ```
   <ts> | smith:pr | $ticket | success-pr | url=<url> branch=$branch
   ```
9. Return the PR URL to the caller; populate the outcome JSON's
   `pr_url` field.

### Path B — WIP-stuck

The pipeline returned stuck or error after the retry. Smith is handing
this work back to a human. Open a WIP draft PR with all the context the
human will need.

1. Ensure the GitHub labels Smith uses actually exist:
   ```
   bash $SMITH_PLUGIN_ROOT/scripts/gh_ensure_labels.sh
   ```
2. **Promote artefacts** so the next human sees them in the PR:
   ```
   bash $SMITH_PLUGIN_ROOT/scripts/promote_smith_artifacts.sh "$ticket"
   ```
   This script:
   - Copies the brief from `.smith/briefs/<ticket>-brief.md` into the
     tracked location `docs/superpowers/specs/<ticket>-brief.md`.
   - Promotes every markdown under `.smith/specs/` and `.smith/plans/`
     (where `smith:pipeline` wrote spec and plan files during the run,
     gitignored) into `docs/superpowers/specs/` and
     `docs/superpowers/plans/`, then `git add`s them.
   - Commits all uncommitted work — promoted artefacts plus any
     partial impl — as a single `wip(smith): partial work at point of
     stuck — <ticket>` commit.

   This is the ONLY codepath that lands spec/plan markdown on the
   branch. The success path (Path A) leaves them in `.smith/`.
3. Push the branch (still no force), then kick the PR-comments monitor
   so cadence resets:
   ```
   git push -u origin "$branch"
   bash $SMITH_PLUGIN_ROOT/scripts/pr_comments_reset.sh
   ```
4. Compose title:
   ```
   title="[WIP - agent-stuck] [<TICKET-KEY>] <summary>"
   ```
5. Compose body — same sections as the success path PLUS:
   - A prominent **"Where Smith got stuck"** section at the top,
     containing:
     - Which gate failed (spec / plan / diff / build)
     - The `stuck_reason` verbatim
     - Anderson's last findings (if applicable), formatted as a list
     - The last log entries from `<target>/.smith/log.txt`
   - A **"Spec & plan"** section linking to the promoted markdown
     files under `docs/superpowers/specs/` and `docs/superpowers/plans/`
     (this is the WIP-stuck path's exception to the success-path rule
     of omitting that section — here the files DO exist on the branch
     because `promote_smith_artifacts.sh` just committed them).
6. Create the draft PR with both labels:
   ```
   gh pr create --draft \
     --title "$title" \
     --body "$body" \
     --base develop \
     --head "$branch" \
     --label smith-authored \
     --label needs-human-attention
   ```
   Note: do NOT post "augment review" — this PR is being handed to a
   human. The needs-human-attention label is the signal.
7. **Swap the JIRA labels**:
   ```
   acli jira workitem edit --key "$ticket" \
        --label-remove smith-implementing \
        --label-add auto-impl-failed
   ```
   **Do not** post a JIRA comment (per spec Section 6.6 — labels carry
   the signal; the PR body holds the narrative).
8. Append log:
   ```
   <ts> | smith:pr | $ticket | wip-stuck-pr | url=<url> reason=<one-line>
   ```
9. Return the PR URL; populate the outcome JSON.

## Hard rules (always)

- **Always `--draft`.** Never `gh pr ready`. Never `gh pr merge`.
- **Always `--base develop`.** Never against `main` or release branches.
- **Never force-push.** Push only adds commits. If push fails because
  the remote moved (someone else pushed to the branch), abort with
  `{result: "error"}` — let the lead retry.
- The bash-guard hook (Section 5.7) is a backstop: any of the above
  rules violated by your Bash command will get denied.

## Workflow gated on dry_run

The two paths described above (Success and WIP-stuck) execute when
`dry_run = false` in your spawn prompt. When `dry_run = true`, skip
every external side effect:

- Don't `git push`
- Don't `gh pr create`
- Don't touch JIRA labels
- Don't invoke `promote_smith_artifacts.sh` (the wip commit it makes is
  also a side effect)
- Don't post "augment review" comment
- Don't kick pr_comments_reset.sh

Instead, log the intended actions to `<target>/.smith/log.txt`:

```
<ts> | smith:pr | $ticket | would-push | branch=$branch
<ts> | smith:pr | $ticket | would-create-draft-pr | title=<title>
<ts> | smith:pr | $ticket | would-label-pr | labels=smith-authored
<ts> | smith:pr | $ticket | would-remove-jira-label | label=smith-implementing
<ts> | smith:pr | $ticket | would-trigger-augment | pr=<pr_number>
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
