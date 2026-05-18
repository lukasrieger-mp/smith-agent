# Smith — Autonomous Ticket Implementation Agent

A Claude Code plugin that picks up small JIRA tickets and drives them
to a draft PR. Each ticket is worked by a paired team: Mr. Smith
implements, Mr. Anderson critiques at every gate. Built on Claude
Code's [agent teams][teams] feature.

See [`docs/spec.md`](docs/spec.md) for the full design.

[teams]: https://code.claude.com/docs/en/agent-teams

## Prerequisites

- Claude Code v2.1.105 or later (`claude --version`).
- Agent teams enabled in `~/.claude/settings.json`:
  ```json
  { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
  ```
- `acli` (Atlassian CLI) authenticated to your JIRA.
- `gh` (GitHub CLI) authenticated to your GitHub host.

The slash-command pre-flights verify the CLI auth state and abort with
a remediation message if either is missing.

## Install

This repository doubles as a one-plugin marketplace. From inside any
Claude Code session:

```
/plugin marketplace add lukasrieger-mp/smith-agent
/plugin install smith@smith-agent
```

Updates: `/plugin update smith@smith-agent`. Every commit on `main` is
a new release ([version resolution][release-channels]).

[release-channels]: https://code.claude.com/docs/en/plugin-marketplaces#version-resolution-and-release-channels

On first enable, Claude Code prompts for JIRA values (project key,
custom field IDs for Story Points and Sprint, eligible/claim status
names, poll interval). Per-target state (`.smith/config.json` + a
`.gitignore` entry for `.smith/`) is created lazily in the target repo
on first use; there is no bootstrap step.

## Entry points

Three slash commands. Pick one based on what you want to do.

### `/smith:implement <KEY>` — one specific ticket

Dispatches a Smith+Anderson pair to implement one JIRA ticket
end-to-end: claim → enrich → spec → plan → impl → draft PR. On a
successful PR creation, the command also arms `pr-only` mode (see
below) so reviewer and Augment comments on that PR trigger automatic
fixer dispatches. Autonomous JIRA ticket pickup is **not** activated
by this command.

Flags:
- `--dry-run` — walk the pipeline with no external side effects (no
  JIRA writes, no `git push`, no `gh pr create`, no fix-loop arming).
- `--confident` — skip the full `quality-check.sh` umbrella in the
  impl gate; only the formatter runs. The PR body flags the skipped
  checks for the human reviewer.

### `/smith:watchdog` — autonomous loop

Arms three background monitors. The watchdog session reacts to their
notifications by dispatching Smith+Anderson pairs:

- `jira-candidates` fires when a new eligible ticket appears →
  dispatch impl pair.
- `pr-comments` fires when reviewer/Augment comments arrive on an
  open Smith-authored PR → dispatch fixer pair.
- `stop-sentinel` fires when `.smith/STOP` is created/removed → pause
  or resume new dispatches.

Flags:
- `--pr-only` — watch PRs only; the JIRA monitor stays idle.

Arming is per-session: a `SessionStart` hook wipes the arming state
on every new Claude Code session, so autonomous behaviour never
resumes silently. Disarm without exiting: `rm .smith/state/watchdog-mode`.

### `/smith:abort <KEY-or-PR>` — manual cleanup

Tears down an in-flight pair, removes the worktree, reverts JIRA
state, and clears the active-smiths entry. Argument is a JIRA key
(impl pair) or a PR number (fixer pair).

### Kill switches

- `touch .smith/STOP` — stops new dispatches within ~2 sec; in-flight
  pairs wrap up at the next safe checkpoint.
- JIRA label `no-auto-impl` on a ticket → watchdog skips it.
- Ctrl-C the session → hard stop; monitors die with the session.

## What this plugin adds

### Agents

| Name | Role |
|---|---|
| `smith-impl` | Implements one ticket (claim → enrich → pipeline → PR) |
| `anderson-impl` | Adversarial reviewer paired with `smith-impl`; gates spec, plan, diff |
| `smith-fixer` | Triages and applies one round of PR review feedback |
| `anderson-fixer` | Validates `smith-fixer`'s dismissal decisions; runs final diff review |

Pairs are spawned as long-lived agent-team teammates, never as
one-shot subagents. A `PreToolUse` hook (`agent-teams-guard`)
enforces this.

### Skills

Internal — invoked inside Smith teammate sessions, not by the operator
directly.

| Name | Role |
|---|---|
| `smith:claim` | Transitions JIRA status; adds `smith-implementing` label; confirms worktree |
| `smith:enrich` | Reads the ticket; writes a structured brief under `.smith/briefs/` |
| `smith:pipeline` | The three-gate spec → plan → impl loop with Anderson critic rounds |
| `smith:pr` | Opens the draft PR (success path) or the WIP-stuck PR (escalation) |
| `smith:watchdog` | Reaction runbook loaded into the lead session for notification handling |

### Background monitors

| Name | What it does |
|---|---|
| `jira-candidates` | Polls JIRA every 30 min (configurable) for newly eligible tickets |
| `pr-comments` | Polls open Smith PRs every 60 sec for new review threads; backs off to 30 min after 30 quiet cycles |
| `stop-sentinel` | Watches `.smith/STOP` every 2 sec |

All three gate on `.smith/state/watchdog-mode` and stay idle until
one of the entry-point commands writes it.

### Hooks

| Hook | Purpose |
|---|---|
| `bash-guard` (PreToolUse) | Denies destructive commands (`rm -rf`, `git push --force`, `git reset --hard`, `gh pr merge/close`, etc.) |
| `agent-teams-guard` (PreToolUse) | Denies `Task` calls whose `subagent_type` is one of the four Smith/Anderson agent types — they must be spawned via agent-teams |
| `keep-anderson-alive` (TeammateIdle) | Re-prompts Anderson teammates between mailbox round-trips so they don't self-terminate |
| SessionStart | Wipes `.smith/state/watchdog-mode` so autonomous behaviour is per-session opt-in |

### Bin scripts

`bin/` is added to the Bash tool's `PATH` while the plugin is
enabled, so skills and agents invoke helpers by bare name (e.g.
`active_smiths.sh count`, `jira_scan.sh`). About 30 helpers covering
JIRA reads/writes, GitHub PR operations, worktree management,
concurrency tracking, and the auth pre-flight.

## Concurrency model

Two independent caps, both default 2:

- `max_concurrent_impl_smiths` — in-flight impl pairs.
- `max_concurrent_fixer_smiths` — in-flight fixer pairs.

Each open PR also has a `max_fix_rounds` counter (default 5). On
cap-hit, the fixer dispatch is refused and the PR is labelled
`needs-human-attention`. Removing the label or deleting the per-PR
counter file revives the loop.

## Layout

```
.claude-plugin/
  plugin.json          Plugin manifest
  marketplace.json     One-plugin marketplace manifest
agents/                Four teammate personas
commands/              Three slash commands
skills/                Five skill bodies
monitors/monitors.json Three background monitors
hooks/hooks.json       PreToolUse + SessionStart + TeammateIdle hooks
bin/                   Bash helpers on PATH (~30 scripts)
test/                  Script tests + JSON fixtures
docs/spec.md           Full design spec
```

## Tests

```bash
for t in test/lib/*.test.sh test/*.test.sh; do bash "$t" || exit 1; done
echo "All tests pass."
```

## Developing on Smith

To iterate on this plugin itself (rather than just use it), clone the
repo and load the local copy with `--plugin-dir` instead of installing
from the marketplace:

```bash
git clone https://github.com/lukasrieger-mp/smith-agent.git ~/smith-agent
cd /path/to/your/target-repo
claude --plugin-dir ~/smith-agent
```

`/reload-plugins` picks up edits without restarting the session.
