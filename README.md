# Smith — Autonomous Ticket Implementation Agent

A Claude Code plugin that autonomously picks up small JIRA tickets and drives
them to a draft PR, with adversarial review by Mr. Anderson.

Smith is built on Claude Code's [agent teams][teams] feature: a long-lived
watchdog session (the team lead) coordinates two short-lived teammate-pair
flavours — an **impl pair** (`smith-impl` + `anderson-impl`) that drives a
ticket from claim to draft PR, and a **fixer pair** (`smith-fixer` +
`anderson-fixer`) that handles one round of PR review feedback. Each pair
runs in its own fresh context, with separate concurrency caps (default 2
each).

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
agents/smith-impl.md         Implementer (impl-pair teammate, ticket mode)
agents/anderson-impl.md      Adversarial critic (impl-pair teammate)
agents/smith-fixer.md        Per-round PR-fix triager (fixer-pair teammate)
agents/anderson-fixer.md     Dismissal validator (fixer-pair teammate)
commands/                    Slash commands  → /smith:implement, /smith:watchdog
skills/                      → /smith:watchdog, /smith:claim, /smith:enrich,
                                /smith:pipeline, /smith:pr, /smith:pr-watch
monitors/monitors.json       Background notification monitors (Section 5.6)
scripts/                     Shared bash helpers (jira_scan, classify, ...)
                             + monitor scripts (monitor_jira.sh, etc.)
test/                        Script tests + JSON fixtures
docs/spec.md                 Design spec
docs/plans/                  Historical build plans (one per phase)
```

## Kill switches (in the target repo)

- `touch <target>/.smith/STOP` — watchdog exits cleanly at next tick
- Add JIRA label `no-auto-impl` to a ticket — watchdog skips it
- Ctrl-C the Claude Code session running the watchdog

## How it runs

1. Operator runs `claude --plugin-dir ~/StudioProjects/smith-agent`
   from inside a target repo
2. Operator invokes `/smith:watchdog` once (or `/smith:watchdog --pr-only`
   for PR-fix-only mode) — monitors begin polling
3. From this point: when a new eligible JIRA candidate appears the
   watchdog dispatches an impl pair; when reviewer comments arrive on
   a Smith-authored PR it dispatches a fixer pair. Each pair runs
   within its own concurrency cap.
4. Smith implements the ticket (impl pair) or triages and addresses
   one round of comments (fixer pair) with Anderson critiquing along
   the way.

Two distinct teammate-pair roles drive everything:

- **Impl pair** (`smith-impl` + `anderson-impl`) — implements one
  ticket end-to-end: claim → enrich → pipeline (with 3-gate Anderson
  critic) → open draft PR with `augment review` triggered.
- **Fixer pair** (`smith-fixer` + `anderson-fixer`) — handles one
  round of PR review feedback (Augment-bot-driven or human-reviewer-driven).
  Triages findings, applies fixes or dismisses with Anderson-validated
  justification, pushes, re-triggers Augment OR converges.

The fixer dispatch is **separate** from impl dispatch — they have
their own concurrency caps (`max_concurrent_impl_smiths` and
`max_concurrent_fixer_smiths`, both default 2). Each PR has its own
round counter (`max_fix_rounds`, default 5). On convergence (a round
that produced zero fix-class findings), the fixer cleans up per-PR
state and posts a summary comment; on hitting the round cap, the
watchdog escalates the PR with the `needs-human-attention` label.

The watchdog session reacts to monitor notifications by:
- Counting active pairs per role via `active_smiths.sh count <role>`
- Picking top eligible JIRA key via `pick_top_candidate.sh` (impl path)
- Reading the per-PR round counter before fixer dispatch
- Spawning the teammate pair via the agent-teams API
- Registering the pair in `active_smiths.sh` so the cap holds

Operator overrides: `/smith:implement APP-XXXX` for a manual dispatch;
`touch .smith/STOP` for a soft kill switch (~2 sec response); remove
the `needs-human-attention` label (or delete the per-PR round-counter
file) to revive a capped-out fix loop.

Known gap: the brief's "Suspected affected files" section is a static
placeholder. A follow-up could populate it via an Explore subagent
dispatch — useful for larger tickets where Smith would benefit from
a precomputed pointer set.
