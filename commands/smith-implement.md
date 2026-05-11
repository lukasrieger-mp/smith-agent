---
description: Run the full Smith pipeline against a specific JIRA ticket. Use --dry-run to walk the pipeline without any external side effects.
---

# /smith-implement

Args:
- `$1` (required): JIRA ticket key, e.g. `APP-5601`
- `$2` (optional): `--dry-run` to skip all external side effects

## Usage

```
/smith-implement APP-5601
/smith-implement APP-5601 --dry-run
```

## Workflow

Parse args. If `$2` is `--dry-run`, set env `SMITH_DRY_RUN=1` for all
subsequent skill invocations and (in Phase 1) set
`SMITH_DRY_RUN_FIXTURE` to point at the candidate fixture for jira_scan.

Then drive the pipeline by invoking these skills **in order** via the Skill
tool, passing `$TICKET` and `$SMITH_DRY_RUN` through:

1. `smith-claim` — produces a branch name (or aborts if pre-flight fails).
2. `smith-enrich` — produces an enriched brief path.
3. `smith-pipeline` — produces a pipeline-outcome JSON
   (`{"result": "success"|"stuck", "reason": "..."}`).
4. `smith-pr` — produces a (dry-run) PR URL.

At each step, if the skill exits non-zero, halt and report which step failed.

## Output

On success, print:

```
Smith implement complete (dry-run=<true|false>)
  Ticket:  $TICKET
  Branch:  <branch>
  Brief:   <brief path>
  Outcome: <success|stuck> (<reason>)
  PR:      <url>
```

Then `tail -5 .smith/log.txt` so the human can see what was logged.

## Phase 1 notes

In Phase 1, every skill is dry-run-aware. With `--dry-run`, no JIRA, git
remote, or GitHub state is changed. Without `--dry-run`, **the skills still
run in their Phase 1 placeholder mode** (they have not been wired to perform
real writes yet) — so it's safe to invoke without `--dry-run`, but you
won't get a real PR until Phase 4. Phase 6 enables the autonomous watchdog.
