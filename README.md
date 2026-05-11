# Smith — Autonomous Ticket Implementation Agent

Self-contained Claude Code plugin that picks up small JIRA tickets and drives
them to a draft PR autonomously, with adversarial review by Mr. Anderson.

Smith is implemented on top of Claude Code's [agent teams][teams] feature: a
long-lived watchdog session (the team lead) coordinates short-lived per-ticket
teammates — Mr. Smith (implementer) and Mr. Anderson (adversarial critic) —
each in its own fresh context. Up to 2 Smiths active in parallel.

See `docs/spec.md` for the full design. Implementation plans live in
`docs/plans/`.

[teams]: https://code.claude.com/docs/en/agent-teams

## Prerequisites

- Claude Code v2.1.32 or later (check `claude --version`)
- Agent teams enabled in `~/.claude/settings.json`:
  ```json
  { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
  ```
- `acli` (Atlassian CLI) authenticated to the operator's JIRA
- `gh` (GitHub CLI) authenticated to the target repo

## Install into a target repo

Smith is a plugin — it runs *against* a target repo, not inside this one. To
wire it in:

```bash
./install.sh /path/to/your/target-repo
```

This creates symlinks under `<target>/.claude/{agents,commands,skills}/`
pointing back to this plugin source, and adds `.smith/` to the target's
`.gitignore`. Idempotent — safe to re-run after the plugin gains new skills
or agents.

## Usage (from inside the target repo)

- `/smith-implement APP-1234` — manually dispatch a Smith+Anderson team to
  implement one specific ticket
- `/smith-implement APP-1234 --dry-run` — walk the pipeline without any
  external side effects (no JIRA writes, no git push, no PR creation)
- `/smith-watchdog` — start the autonomous watchdog loop (default 30 min)

## Run the test suite

From the plugin source root:

```bash
for t in test/lib/*.test.sh test/*.test.sh; do bash "$t" || exit 1; done
echo "All tests pass."
```

## Layout

```
.claude-plugin/plugin.json   Plugin manifest
agents/anderson.md           Adversarial critic (teammate)
agents/smith.md              Implementer (teammate)   ← added in Phase 1.5
commands/smith-*.md          Slash commands
skills/smith-*/SKILL.md      Six skills
scripts/                     Pure-bash helpers (jira_scan, classify, ...)
test/                        Script tests + JSON fixtures
docs/spec.md                 Design spec
docs/plans/                  One plan per phase
install.sh                   Install into a target repo (takes target path)
```

## Kill switches (in the target repo)

- `touch <target>/.smith/STOP` — watchdog exits cleanly at next tick
- Add JIRA label `no-auto-impl` to a ticket — watchdog skips it
- Ctrl-C the Claude Code session running the watchdog

## Status

Phase 1 of 7 partially complete. The agent-teams pivot triggered a rewrite of
some Phase 1 deliverables (the SKILL.md skeletons, slash commands, and a new
`agents/smith.md`). See `docs/spec.md` Section 16 for the phase decomposition
and `docs/plans/2026-05-11-phase-1-skeleton.md` for current Phase 1 status.
