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

- Claude Code v2.1.105 or later (`claude --version`) — needed for plugin
  monitors. Agent teams alone require v2.1.32+, but Smith uses monitors
  as well.
- Agent teams enabled in `~/.claude/settings.json`:
  ```json
  { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
  ```
- `acli` (Atlassian CLI) authenticated to the operator's JIRA
- `gh` (GitHub CLI) authenticated to the target repo

## Run Smith against a target repo

Smith is loaded as a Claude Code plugin via `--plugin-dir`. No install step,
no symlinks, no marketplace required.

**Important:** Smith's skill content references `$SMITH_PLUGIN_ROOT` in
the Bash commands it issues. You must set this env var to the plugin
source path **before** launching Claude Code — Claude Code does not
populate `$CLAUDE_PLUGIN_ROOT` for skill-driven Bash invocations (only
for monitor/hook/MCP/LSP commands, where Claude Code substitutes at
read-time).

```bash
cd /path/to/your/target-repo
export SMITH_PLUGIN_ROOT=~/StudioProjects/smith-agent
claude --plugin-dir ~/StudioProjects/smith-agent
```

On first enable, Claude Code prompts you for a few JIRA-specific values
(project key, custom field IDs for Story Points and Sprint, eligible/claim
status names, poll interval). Defaults work for the operator's setup; other
adopters override at the prompt.

Inside the session, just use the commands. Per-target setup
(`.smith/config.json` + a `.gitignore` entry for `.smith/`) is created
**lazily** on the first invocation that needs it — no explicit bootstrap
step.

- `/smith:implement APP-1234` — dispatch a Smith+Anderson team to implement
  one specific ticket
- `/smith:implement APP-1234 --dry-run` — walk the pipeline without external
  side effects (no JIRA writes, no git push, no PR creation)
- `/smith:watchdog` — arm the autonomous watchdog. This starts three
  background **monitors** (JIRA candidates, PR review comments, kill
  switch) that emit notifications whenever something changes. The agent
  reacts to those notifications by dispatching teammate pairs.

Until `/smith:watchdog` is invoked the first time in a session, no monitors
run and Smith stays passive. Run it once to "arm" — monitors then run for
the lifetime of the session.

### Suggested shell alias

```bash
# in ~/.zshrc or equivalent
alias claude-smith='SMITH_PLUGIN_ROOT=~/StudioProjects/smith-agent claude --plugin-dir ~/StudioProjects/smith-agent'
```

Then `cd target-repo && claude-smith` is the day-to-day entry point.
The alias sets `SMITH_PLUGIN_ROOT` for the entire Claude Code session
so every skill-driven Bash invocation can find the plugin's scripts.

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
monitors/monitors.json       Background notification monitors (Section 5.6)
scripts/                     Shared bash helpers (jira_scan, classify, ...)
                             + monitor scripts (monitor_jira.sh, etc.)
test/                        Script tests + JSON fixtures
docs/spec.md                 Design spec
docs/plans/                  One plan per phase
```

## Kill switches (in the target repo)

- `touch <target>/.smith/STOP` — watchdog exits cleanly at next tick
- Add JIRA label `no-auto-impl` to a ticket — watchdog skips it
- Ctrl-C the Claude Code session running the watchdog

## Status

**Phase 6 of 7 done. Smith is functionally end-to-end autonomous.**

The full flow:

1. Operator runs `claude --plugin-dir ~/StudioProjects/smith-agent`
   from inside a target repo
2. Operator invokes `/smith:watchdog` once — monitors start
3. From this point: when a new eligible JIRA candidate appears (or
   reviewer comments arrive on a Smith-authored PR), the watchdog
   dispatches a Smith+Anderson teammate pair within the 2-cap
4. Smith implements the ticket (or addresses comments) with Anderson
   critiquing at each gate, ending with a draft PR

Both dispatch modes are live:

- **Ticket mode** — claim → enrich → pipeline (with 3-gate Anderson
  critic) → PR open (success or WIP-stuck)
- **PR-fix mode** — checkout PR worktree → fetch unresolved threads →
  fix each (cap 5/thread) → Anderson diff review → push

Autonomous dispatch (Phase 6): the watchdog session reacts to monitor
notifications by:
- Counting active pairs via `active_smiths.sh count`
- Picking top eligible JIRA key via `pick_top_candidate.sh`
- Spawning the teammate pair via the agent-teams API
- Registering the pair in `active_smiths.sh` so the cap holds

Operator interventions still possible: `/smith:implement APP-XXXX`
manual override; `touch .smith/STOP` kill switch (~2 sec response).

Deferred:
- **Phase 2.x** — Explore subagent integration in `smith:enrich` (the
  brief's "Smith's reading" section is currently a placeholder)
- Integration testing against real tickets — the only way to validate
  the LLM-driven critic dialogue and orchestration

See [`docs/spec.md`](docs/spec.md) Section 16 for the full decomposition.
