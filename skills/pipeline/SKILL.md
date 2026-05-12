---
name: pipeline
description: Drive Smith's three-gate pipeline (SPEC → PLAN → IMPL) with bounded Anderson critic dialogue; commit per gate. Step 3 of ticket mode.
---

# smith:pipeline (inner-teammate)

You are inside a Mr. Smith teammate session (ticket mode). This skill
is the meat of Smith's work. It runs after `smith:enrich`.

(Design rationale: `docs/spec.md` §8 — informational; this file
suffices to operate.)

## Inputs (from your spawn prompt + skill chain)

- `ticket`, `branch`, `worktree`, `dry_run` — from spawn prompt
- `brief_path` — produced by `smith:enrich` (a path under `<worktree>/.smith/briefs/`)
- `anderson_name` — the name of your paired Anderson teammate (mailbox addressing)

## Outputs

- Branch state: a spec file, a plan file, implementation commits, each
  committed per gate as documented below.
- Stdout: outcome JSON `{result: "success" | "stuck" | "error", reason, log_entries[]}`
- Side effects: git commits inside the worktree.

## Three gates, mailbox-driven

Each gate is one mailbox round-trip with Anderson per critic round, up
to 3 rounds. The gates run in order.

**Anderson must respond. You must not review your own work.** If your
paired Anderson teammate (named in your spawn prompt as
`anderson_name`) doesn't reply within 120s, or the mailbox tool isn't
available to you, return `{result: "error", reason: "anderson not
reachable"}` and stop. The lead retries the whole pipeline with a
fresh pair. Doing your own diff review in place of Anderson defeats
the entire point of the adversarial-pair design — don't rationalize
it as a fallback, no matter how reasonable it feels.

### Gate 1: SPEC

1. Invoke the global `superpowers:brainstorming` skill with `$brief_path`
   as input. It walks Smith through writing
   `<worktree>/docs/superpowers/specs/<date>-<ticket>-design.md`. (When
   running in Smith's context, brainstorming should skip the interactive
   "Let me ask clarifying questions" loop — your spawn prompt is the
   complete brief.)
2. Mailbox to Anderson:
   ```
   to:   $anderson_name
   body: {
     "type": "review.request",
     "mode": "spec",
     "artifact_ref": "<worktree>/docs/superpowers/specs/<date>-<ticket>-design.md",
     "round": 1
   }
   ```
3. Wait for Anderson's mailbox reply with `{type: "anderson.review.findings", findings: [...]}`.
   Timeout: 120s. On timeout → `{result: "error", reason: "anderson timeout at spec gate"}`.
4. Filter for high-severity findings. If empty → commit the spec file
   (`git add docs/superpowers/specs/<...>-design.md && git commit -m "spec(smith): $ticket"`) and proceed to Gate 2.
5. Otherwise: address the high findings (edit the spec). Increment
   round. Goto step 2. Cap at 3 rounds.
6. Divergence guard (spec Section 5.5): if round 2 → 3 high-finding
   count didn't strictly decrease, return
   `{result: "stuck", reason: "spec gate not converging"}`.
7. Round 3 exhausted with high findings remaining → same stuck.

### Gate 2: PLAN

Same shape as Gate 1, but use `superpowers:writing-plans` to produce
`<worktree>/docs/superpowers/plans/<date>-<ticket>.md`, and mailbox
Anderson with `mode: "plan"`. Commit message:
`plan(smith): $ticket`.

### Gate 3: IMPL

1. Invoke `superpowers:subagent-driven-development` (or
   `superpowers:executing-plans`) with the plan as input. This
   delegates per-task implementation to subagents (per the plan's task
   list). The subagent-driven skill handles TDD discipline, per-task
   commits, and review.
2. Run quality checks. The exact command depends on the `confident`
   flag from your spawn prompt:

   - **If `confident = false` (default)**: run the full umbrella
     check (build + tests + lint) from the *target* repo per its
     CLAUDE.md:
     ```
     ./scripts/run-silent.sh "Quality checks" "./scripts/quality-check.sh"
     ```
     A failure here means the impl is broken; address before
     proceeding to Anderson.

   - **If `confident = true`**: skip the full umbrella. Only run the
     Kotlin formatter (auto-fix mode):
     ```
     ./scripts/run-silent.sh "Kotlin lint" "./gradlew lintKotlin"
     ```
     The `--confident` flag is the operator's explicit "I trust this
     change, ship without running the test/build cycle" mode. The
     operator's PR review and Anderson's diff review remain the only
     gates. Smith MUST surface the `--confident` flag in the PR body
     (smith:pr handles this).

3. Mailbox Anderson:
   ```
   to:   $anderson_name
   body: {
     "type": "review.request",
     "mode": "diff",
     "artifact_ref": "git diff origin/develop...HEAD",
     "round": 1
   }
   ```
4. Same 3-round / divergence logic as Gates 1 + 2.

## Crash and stuck handling

- Anderson timeout → `{result: "error", reason}`. Lead retries once
  with a fresh teammate pair per spec Section 8.5.
- Quality-check failure → `run-silent.sh`'s filtered output is in your
  context. If you can identify a fix, edit and retry (subject to the
  build wall-clock budget — Section 5.5: 45 min cumulative). If not,
  `{result: "stuck", reason: "quality-check failed: <one-line summary>"}`.
- Divergence at any gate → stuck per Gate-1 rules.

## Reply parsing

Smith **must** validate every Anderson reply against the schema before
acting on it. Use:

```
echo "$reply_json" | bash $SMITH_PLUGIN_ROOT/scripts/validate_anderson_reply.sh
```

Exit 0 = valid; exit 1 = malformed. A malformed reply is treated as
`{result: "error", reason: "malformed anderson reply"}` — the lead
retries with a fresh pair.

To get the high-severity count without re-parsing in skill prose:

```
high_count=$(echo "$reply_json" \
             | bash $SMITH_PLUGIN_ROOT/scripts/validate_anderson_reply.sh --count-high)
```

## Anderson dialogue

The Anderson teammate runs the live critic prompt (see
`agents/anderson-impl.md`). The pipeline drives real round-trips with
structured JSON in both directions:

- Smith mails `review.request` → Anderson reads artefact → mails
  `anderson.review.findings`
- Smith parses (via the validator), counts high-severity findings,
  decides to address-and-iterate or commit-and-advance
- Smith may mail `rebut` for individual findings; Anderson replies
  `anderson.finding.drop` or `anderson.finding.hold`. Rebuts stay
  within the same critic round (don't count as a new round).

Anderson runs in vacuous mode **only** when `dry_run=true`. In that
case, Smith should still send the mailbox request (to exercise the
team plumbing) but Anderson's reply will be empty and the gate passes
trivially.

## Log entries

Append one line per gate result to `<target>/.smith/log.txt`:

```
<ts> | smith:pipeline | $ticket | gate-result | gate=spec rounds=1 high=0
<ts> | smith:pipeline | $ticket | gate-result | gate=plan rounds=2 high=3
<ts> | smith:pipeline | $ticket | gate-result | gate=diff rounds=1 high=0
```

These become part of the `log_entries` array in your final outcome
JSON.
