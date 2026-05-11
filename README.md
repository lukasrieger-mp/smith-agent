# Smith — Autonomous Ticket Implementation Agent

A Claude Code plugin that autonomously picks up small JIRA tickets and drives
them to a draft PR, with adversarial review by Mr. Anderson.

Smith is built on Claude Code's [agent teams][teams] feature: a long-lived
watchdog session (the team lead) coordinates short-lived per-ticket teammates
— Mr. Smith (implementer) and Mr. Anderson (adversarial critic) — each in
its own fresh context. Up to 2 Smith pairs active in parallel.

See [`docs/spec.md`](docs/spec.md) for the full design. Implementation plans
live in [`docs/plans/`](docs/plans/).

[teams]: https://code.claude.com/docs/en/agent-teams

## Prerequisites

- Claude Code v2.1.32 or later (`claude --version`)
- Agent teams enabled in `~/.claude/settings.json`:
  ```json
  { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
  ```
- `acli` (Atlassian CLI) authenticated to the operator's JIRA
- `gh` (GitHub CLI) authenticated to the target repo

## Run Smith against a target repo

Smith is loaded as a Claude Code plugin via `--plugin-dir`. No install step,
no symlinks, no marketplace required.

```bash
cd /path/to/your/target-repo
claude --plugin-dir ~/StudioProjects/smith-agent
```

Inside the session, just use the commands. Per-target setup
(`.smith/config.json` + a `.gitignore` entry for `.smith/`) is created
**lazily** on the first invocation that needs it — no explicit bootstrap
step.

- `/smith:implement APP-1234` — dispatch a Smith+Anderson team to implement
  one specific ticket
- `/smith:implement APP-1234 --dry-run` — walk the pipeline without external
  side effects (no JIRA writes, no git push, no PR creation)
- `/smith:watchdog` — start the autonomous watchdog loop (default 30 min)

### Suggested shell alias

```bash
# in ~/.zshrc or equivalent
alias claude-smith='claude --plugin-dir ~/StudioProjects/smith-agent'
```

Then `cd target-repo && claude-smith` is the day-to-day entry point.

### Iterating on Smith itself

Editing files in this `smith-agent/` repo while a Claude Code session is
running? Run `/reload-plugins` in that session to pick up the changes
without restarting.

## Run the test suite

From the plugin source root:

```bash
for t in test/lib/*.test.sh test/*.test.sh; do bash "$t" || exit 1; done
echo "All tests pass."
```

## Layout

```
.claude-plugin/plugin.json   Plugin manifest (name, version, description)
agents/anderson.md           Adversarial critic (teammate)
agents/smith.md              Implementer (teammate)  ← added in Phase 1.5
commands/                    Slash commands  → /smith:implement, /smith:watchdog
skills/                      → /smith:watchdog, /smith:claim, /smith:enrich,
                                /smith:pipeline, /smith:pr, /smith:pr-watch
scripts/                     Shared bash helpers (jira_scan, classify, ...)
test/                        Script tests + JSON fixtures
docs/spec.md                 Design spec
docs/plans/                  One plan per phase
```

## Kill switches (in the target repo)

- `touch <target>/.smith/STOP` — watchdog exits cleanly at next tick
- Add JIRA label `no-auto-impl` to a ticket — watchdog skips it
- Ctrl-C the Claude Code session running the watchdog

## Status

Phase 1 of 7 partially complete. The agent-teams pivot triggered a rewrite of
some Phase 1 deliverables (the SKILL.md skeletons, slash commands, and a new
`agents/smith.md`). See [`docs/spec.md`](docs/spec.md) Section 16 for the
phase decomposition and [`docs/plans/2026-05-11-phase-1-skeleton.md`](docs/plans/2026-05-11-phase-1-skeleton.md)
for current status.
