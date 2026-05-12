# Augment-driven fix loop — design

## Problem

Today Smith opens a draft PR and then waits passively. Two consequences:

1. **No automated review trigger.** A human has to notice the PR and
   start review. Until then, Smith's work just sits.
2. **Smith's PR-fix mode is uncritical.** When reviewer comments do
   arrive, the existing PR-fix path tends to apply each finding
   wholesale — no judgement about applicability, severity, or whether
   the "fix" would worsen the code. Combined with the loop having no
   automated start, the practical outcome is either zero motion or
   over-eager change.

We want autonomous review with critical triage and a bounded retry
budget.

## High-level approach

Smith opens the PR, posts `augment review` as a PR comment, and exits.
The `augment review` comment is the trigger our internal Augment
review bot listens for (independent system, ~3–5 min response time).
Augment posts findings as review comments. The existing pr-comments
monitor picks those up and the watchdog dispatches a **fixer**
teammate pair (separate from the impl pair that opened the PR) to
handle that round. The fixer triages findings, applies the real ones,
dismisses the unworthy ones with justification, pushes any changes,
re-triggers Augment, and exits. The next round flows the same way via
the monitor.

After `MAX_FIX_ROUNDS` rounds (default 5), the watchdog refuses to
dispatch another fixer pair and labels the PR `needs-human-attention`.

## Architecture

```
Watchdog (lead, long-lived)
│
├── on smith.jira.new_candidates  ──→ IMPL pair: smith-impl + anderson-impl
│       │
│       │  claim → enrich → pipeline → smith:pr
│       │      └── on PR open: post "augment review" comment
│       └── send smith.outcome, exit
│
├── on smith.pr.new_comments      ──→ before dispatch: check round counter
│       │                              for this PR
│       │
│       │  if rounds[pr] >= MAX_FIX_ROUNDS:
│       │      label PR needs-human-attention
│       │      post summary comment ("Smith reached fix-round cap; see
│       │          last fixer's dismissal log")
│       │      do NOT dispatch
│       │  else:
│       │      spawn FIXER pair: smith-fixer + anderson-fixer
│       │      (subject to fixer-cap, separate from impl-cap)
│       │
│       │  fixer does:
│       │      fetch unresolved threads (GraphQL via gh_pr_unresolved_comments.sh)
│       │      for each finding: triage with Anderson
│       │      apply fixes / reply-and-resolve dismissals
│       │      push (if anything changed)
│       │      bump .smith/state/pr-fix-rounds/<pr>.json
│       │      post "augment review" comment
│       │      send fixer.outcome, exit
│       │
│       │  monitor picks up the next round of Augment findings
│       │  organically (or sees silence and backs off).
```

### New agent types

Introduce `smith-fixer` and `anderson-fixer` as distinct agent types,
not modes of the existing `smith`/`anderson` types. Why:

- Persona prose specializes naturally. The impl Smith is an
  implementer; the fixer Smith is a triage-and-patch agent. Combining
  them into one persona dilutes both.
- Removes mode-branching from the existing Smith persona (already a
  source of complexity — two-modes is more than the persona deserves).
- "Promote the fixer team to a true subteam that acts independently"
  (operator's words) is reified at the type level, not just by
  convention.

The four agent files end up:

| File | Role |
|---|---|
| `agents/smith-impl.md` | Renamed from current `agents/smith.md` (ticket mode only) |
| `agents/anderson-impl.md` | Renamed from current `agents/anderson.md` |
| `agents/smith-fixer.md` | NEW — triage, justified dismissal, augment-trigger |
| `agents/anderson-fixer.md` | NEW — dismissal validator (different mailbox protocol) |

(The rename is destructive on git history. Alternative: keep the
existing files as the impl variant and add only the two new fixer
files. I lean toward the rename for symmetry, but it's a judgement
call — flag if you'd prefer additive-only.)

### Fixer team workflow (per round)

A single fixer dispatch handles **one round** of Augment's review. No
in-session looping — the pr-comments monitor drives the next round.

1. **Fetch**. Pull the current unresolved threads via
   `scripts/gh_pr_unresolved_comments.sh <pr>` (GraphQL).
2. **Triage**. For each finding, Smith proposes one of three actions:
   - **fix**: the finding is real, applicable, and worth applying
   - **dismiss-not-applicable**: the finding misunderstands the code,
     references a non-existent issue, or doesn't apply to this change
   - **dismiss-not-worth-it**: the finding is technically valid but the
     fix would be a regression on idiomatic design, code size, or
     reader cognition (e.g., "split this 8-line function into three
     2-line ones")
   For each dismissal, Smith mails Anderson a `fix.triage.propose`
   message with the finding + reason. Anderson replies
   `anderson.triage.hold` (force Smith to fix), `anderson.triage.drop`
   (dismissal stands), or `anderson.triage.escalate` (genuinely
   unclear, mark for human review).
3. **Apply**. For findings classified `fix`: edit the worktree.
   Quality-check via `./scripts/quality-check.sh` (or formatter only
   if a `--confident` analogue is configured for fixer dispatches).
4. **Resolve dismissed threads**. For each Anderson-approved
   dismissal: post a reply on the GitHub thread (`gh api graphql`
   `addPullRequestReviewThreadReply`), then mark the thread resolved
   (`resolveReviewThread`). Reply body: 1–3 sentences explaining the
   dismissal — concrete enough that a human reviewer reading the
   thread sees the reasoning.
5. **Anderson final-diff review**. After all fixes are applied,
   Anderson reviews the cumulative diff with `mode: "diff"`. Same
   3-round critic logic as the impl pipeline's IMPL gate.
6. **Push**. `git push` if anything changed. No force-push.
7. **Determine the round outcome** (see "Convergence and cleanup"
   below — four-way matrix on `fix_count` × `push_succeeded`).
8. **Bump the round counter**:
   `scripts/pr_fix_round_inc.sh <pr>` (new helper, replaces the
   old `pr_fix_cycle_inc.sh` per-thread counter).
9. **If not converged and not stuck**: kick the PR-comments monitor
   (`scripts/pr_comments_reset.sh`) and trigger Augment again
   (`gh pr comment <pr> --body "augment review"`).
   **If converged**: post the summary comment, run cleanup, skip the
   Augment trigger (see below).
   **If stuck**: escalate via the existing WIP-stuck pattern,
   preserve state for the audit trail.
10. Send `fixer.outcome` to the lead and exit.

### Mailbox protocol for triage

New message types in addition to the existing review-mode messages:

```json
// Smith → Anderson
{
  "type": "fix.triage.propose",
  "thread_id": "PRRT_...",
  "finding_summary": "<one line>",
  "proposed_action": "dismiss-not-applicable" | "dismiss-not-worth-it",
  "reasoning": "<2-4 sentences justifying the dismissal>"
}

// Anderson → Smith
{
  "type": "anderson.triage.hold",
  "thread_id": "PRRT_...",
  "counter": "<why Smith's reasoning is insufficient; Smith must fix>"
}
{
  "type": "anderson.triage.drop",
  "thread_id": "PRRT_...",
  "reason": "<why the dismissal is approved>"
}
{
  "type": "anderson.triage.escalate",
  "thread_id": "PRRT_...",
  "reason": "<why this needs a human, not us>"
}
```

For findings Smith proposes to `fix` (no dismissal), no triage round
needed — Smith fixes them directly and they show up in the final-diff
review where Anderson can object.

### Round counter and escalation

State file: `.smith/state/pr-fix-rounds/<pr>.json`

```json
{
  "rounds": 3,
  "first_round_at": "2026-05-12T14:00:00Z",
  "last_round_at":  "2026-05-12T16:23:00Z",
  "augment_trigger_count": 4
}
```

The watchdog reads this file before dispatching a fixer. If
`rounds >= MAX_FIX_ROUNDS` (default 5, configurable via
`smith_config.sh`):

1. Add label `needs-human-attention` to the PR.
2. Post a comment summarising what's still unresolved:
   - List of currently-unresolved thread IDs + their locations
   - Note that Smith has hit the iteration cap
   - Link to the round-counter file (or quote its contents) for the audit trail
3. Do not dispatch a fixer.

The pr-comments monitor will still fire on future comments, but
because the round counter is at the cap, the watchdog will keep
no-op'ing until a human resets the counter or removes the
`needs-human-attention` label. (Removal of the label is the signal
that "a human looked at this, please continue trying" — that resets
the counter.)

### Convergence and cleanup

The fix loop needs an explicit terminator. Without one, every PR would
eventually hit `MAX_FIX_ROUNDS` and get the `needs-human-attention`
label, even when Smith+Anderson kept arriving at "all current findings
are valid dismissals." We don't want that — a PR where Smith
deliberately decided nothing more is worth fixing is *done*, not
escalated.

The fixer tracks two values per round:

- `fix_count` — number of findings triaged as `fix` (intent to change
  code)
- `push_succeeded` — did `git push` actually push new commits at the
  end of the round (quality-check green, push not rejected)

Smith always tries to get the quality check green for fix-class
findings before exiting the round — same retry logic as the impl
pipeline's IMPL gate (run-silent, address failures, retry within the
bounded budget). `push_succeeded = false` only when that effort
genuinely couldn't recover.

#### Outcome matrix

| `fix_count` | `push_succeeded` | Outcome | Action |
|---|---|---|---|
| 0 | n/a (nothing to push) | **converged** | Post summary, cleanup state, exit. Do NOT post `augment review`. |
| > 0 | true | **continuing** | Kick the monitor, post `augment review`, exit. |
| > 0 | false | **stuck** | Escalate via WIP-stuck path. Preserve state. Do NOT post `augment review`. |
| 0 | n/a | **degenerate** | Augment posted nothing of substance; fixer found nothing to triage. Exit silently — no summary, no cleanup, no Augment trigger. The monitor will catch the next real round naturally. |

The "degenerate" case is rare but worth handling: if the monitor fires
because of a transient state-cache desync (or a thread got resolved
externally between the monitor poll and the fixer fetch), the fixer
shouldn't fabricate an outcome. Just exit.

#### Convergence summary comment

On the converged path, before cleanup, Smith posts a single PR
comment so the human reviewer sees the loop terminated:

```
Smith fix loop converged after <N> round(s).

- Findings fixed: <fix_total across all rounds>
- Findings dismissed with reasoning: <dismiss_total across all rounds>
  (see the resolved review threads for per-thread justifications)

The current code reflects Smith's and Anderson's final position on
this PR. Ready for human review.
```

The fix/dismiss totals across all rounds come from the round counter
file — bump `pr_fix_round_inc.sh` to also accumulate these. The file
becomes:

```json
{
  "rounds": 3,
  "fix_total": 4,
  "dismiss_total": 7,
  "first_round_at": "2026-05-12T14:00:00Z",
  "last_round_at":  "2026-05-12T16:23:00Z",
  "augment_trigger_count": 4
}
```

#### Cleanup ordering

Cleanup runs only after the summary comment posts successfully. Order:

1. `gh pr comment <pr> --body "<summary>"` — fails-loud if it fails
   (e.g., gh auth lapse). On failure: do NOT cleanup; return
   `{result: "error", reason: "convergence summary comment failed"}`
   and let the lead retry the round.
2. `rm .smith/state/pr-fix-rounds/pr-<N>.json`
3. `rm .smith/state/pr-comments/pr-<N>.json` (thread cache for this
   PR only — leave caches for other PRs alone; the kick file is
   shared and is not removed)
4. Log the cleanup:
   `<ts> | smith-fixer | converged | pr=<N> rounds=<N> cleanup-ok`

Cleanup is local-only and reversible — `git` history of the state
files lives in `.smith/log.txt`. We can rebuild the per-PR cache by
re-querying GitHub if a human later wants to revive the loop on the
same PR (e.g., they comment on a previously-resolved thread).

#### Cap-escalation cleanup (no cleanup)

When the watchdog refuses to dispatch because `rounds >=
MAX_FIX_ROUNDS`: no cleanup. The state files are the audit trail. The
operator's path to recover:

- Investigate via the round counter and the resolved threads
- Delete `.smith/state/pr-fix-rounds/pr-<N>.json` manually to reset
- Optionally remove the `needs-human-attention` label as the signal
  to retry

#### PR merged / closed cleanup (deferred)

When a PR is merged or closed, its state files become garbage. We
don't currently detect this. A future
`scripts/gc_closed_pr_state.sh` can sweep state files for PRs that
`gh pr view` reports as `MERGED` or `CLOSED`. Not blocking; the files
are small.

### Concurrency caps

Two separate caps, both default 2:

- `max_concurrent_impl_smiths` — applies to `smith-impl`
- `max_concurrent_fixer_smiths` — applies to `smith-fixer`

Worst case: 2 impl + 2 fixer = 4 Smith teammates concurrent
(+ matching Andersons). Different cost shapes justify the split: impl
is expensive deep-think with the full pipeline; fixer is short
triage-and-patch.

`scripts/active_smiths.sh` gains a `role` field on the add command:
`active_smiths.sh add <smith> <anderson> <impl|fixer-round|fixer-pr-fix> <subject>`.
(The existing `pr-fix` role from human-comment-driven dispatches stays
for backward compat — see "Existing PR-fix mode" below.)

### Augment silence

If Augment fails to post within ~30 min after a trigger, the
pr-comments monitor's backoff kicks in (active 30 min → backoff
30 min). No special timeout, no retry comment. The PR effectively
parks in a "waiting on Augment" state until either Augment responds or
a human intervenes. Cheap, simple, no false escalations from a flaky
bot.

### Existing reviewer-comment-driven PR-fix mode

The current PR-fix mode (the one triggered by *human* reviewer
comments) keeps working unchanged: it's the same monitor, the same
dispatch path, just routed to the fixer pair instead of inventing a
third type. The fixer doesn't care whether the comments came from
Augment or a human — its triage logic applies equally. The "augment
review" trigger is just one specific way comments end up on the PR;
humans posting comments triggers exactly the same flow.

What gets retired: the old `agents/smith.md` PR-fix mode (lines
85–127 in current revision). It's superseded by `agents/smith-fixer.md`.
The per-thread cycle counter (`pr_fix_cycle_inc.sh`, capped at 5 per
thread) is replaced by the per-PR round counter. Reasoning: a single
thread surviving 5 rounds is a different signal than 5 rounds of
total churn — the per-PR counter aligns better with the new
"augment-round" mental model.

### Operator overrides

- **Reset the round counter for a PR**: `rm .smith/state/pr-fix-rounds/<pr>.json`. Useful
  if Smith got stuck on something the operator solved another way.
- **Stop the fix loop on a specific PR**: add the `no-auto-impl`
  label (same convention as the JIRA-side opt-out) — the fixer
  dispatch checks for it and skips.
- **Force a fix round**: post any comment on the PR — the monitor
  picks it up and triggers as if from Augment.

## Open questions for the plan phase

- "Real and severe" definition for escalation: today's framing says
  `needs-human-attention` is added when the round cap is hit, full
  stop. Should we also add it mid-loop if Anderson flags something
  with severity HIGH that Smith couldn't fix in one round? (Probably
  yes, but defer for now — the round cap is the safety net.)
- Does the fixer respect `--confident` for its own quality check, the
  way impl does? Probably yes; default to full quality-check, skip on
  flag.
- How does this interact with `/smith:abort`? Aborting a PR's fixer
  shouldn't roll back the round counter (Augment's findings are still
  valid).

## Tech / files touched

- New: `agents/smith-fixer.md`, `agents/anderson-fixer.md`
- New: `scripts/pr_fix_round_inc.sh` (replaces `pr_fix_cycle_inc.sh`;
  accumulates `rounds`, `fix_total`, `dismiss_total`,
  `augment_trigger_count`)
- New: helper for the dismissal reply+resolve GraphQL call
- New: `scripts/gc_closed_pr_state.sh` — deferred (out of scope for
  this redesign; placeholder noted)
- Modified: `skills/pr/SKILL.md` — post `augment review` after open
- Modified: `skills/watchdog/SKILL.md` + `commands/watchdog.md` —
  round-counter check before fixer dispatch, escalation logic
- Modified: `scripts/active_smiths.sh` — `role` field, per-role counts
- Modified: `scripts/smith_config.sh` — split `max_concurrent_smiths`
  into impl + fixer caps
- Deleted (in the rename): `agents/smith.md` PR-fix-mode section
- Deleted: `scripts/pr_fix_cycle_inc.sh`
