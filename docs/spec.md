# Smith — Autonomous Ticket Implementation System

Date: 2026-05-11 (last revised: agent-teams pivot)
Status: Draft (pending user review)
Plugin source repo: `smith-agent` (this repo, at `~/StudioProjects/smith-agent/`)
Default target repo: `myposter-app` clone at `~/myposter-agent-repo` (configurable per install)
Target codebase: `myposter-app` (KMP: Android + iOS + shared)

---

## 1. Purpose

Implement a Claude Code-driven agent system that autonomously picks up small
(SP ≤ 2), eligible JIRA tickets assigned to the operator, drives them through a
full spec → plan → implementation pipeline with adversarial review, opens a
draft PR, and then enters a maintenance loop that automatically addresses PR
review comments.

The system — collectively named **Smith** — runs as a Claude Code **agent
team**: a long-lived *watchdog session* (the team lead) coordinates short-lived
per-ticket *teammates* (Mr. Smith implementers and Mr. Anderson adversarial
critics), each with its own fresh context window. The architecture is detailed
in Section 5 and 17.

No human in the loop for spec writing or review; humans only re-enter when (a)
the agent files a successful draft PR for normal review, or (b) the agent
escalates a stuck ticket via the WIP-stuck path.

### 1.1 Operating boundary

Smith operates inside one and only one filesystem location at runtime: the
**target repo** that the operator launched `claude --plugin-dir
~/StudioProjects/smith-agent` from. That cwd becomes Smith's working
directory; the per-target runtime state lives in `<target>/.smith/`, and
the `target_repo` field of `.smith/config.json` records the canonical path
for the working-directory guard (Section 7.4) to validate.

All Smith teammates work inside the target's filesystem. The plugin source
(this `smith-agent` repo) is **not** part of Smith's runtime scope — it's
the source Claude Code loads when started with `--plugin-dir`, but Smith
itself never edits its own source files.

The only paths outside the target repo that Smith is *permitted* to read are
dependency caches required for code understanding:

- `~/.gradle/caches/modules-2/files-2.1/**` — read-only, for inspecting
  third-party library sources when answering "where is X defined" type
  questions
- `~/.konan/**` — read-only, for KMP/native dependency resolution

Everything else on the host filesystem is out of Smith's scope. Any other
clones, working directories, dotfiles, credentials, or user data the operator
may have on the host are **not** part of the system Smith reasons about, and
the operator does not coordinate with Smith through them. Coordination
between Smith and the operator happens exclusively via JIRA (labels) and
GitHub (PR state) on the target's GitHub remote.

The hard filesystem boundary above is enforced as a security invariant in
Section 13.

## 2. Scope

### In scope
- JIRA candidate discovery for the operator's tickets
- Atomic JIRA claim (status transition + label)
- Branch creation from `origin/develop`, ticket-aware naming
- Ticket enrichment (LLM-driven expansion of description + DoD + suspected
  affected files)
- SPEC → critic → PLAN → critic → IMPL (TDD) → critic pipeline using the
  existing superpowers framework (`brainstorming`, `writing-plans`,
  `subagent-driven-development`, `test-driven-development`,
  `verification-before-completion`)
- Single adversarial critic persona (**Mr. Anderson**) at each gate, bounded to
  ≤ 3 rounds
- Draft PR creation on success (proper title + description, JIRA backlink)
- WIP-stuck draft PR creation on failure (PR label `needs-human-attention`,
  JIRA label swap `smith-implementing` → `auto-impl-failed` with **no JIRA
  comment**; partial spec/plan promoted from local scratch into committed
  locations so a human can pick up)
- Continuous PR-comment polling and automatic fix-and-push for all open
  Smith-authored PRs (fan-out across worktrees)
- Crash-resilient: all state lives in JIRA + GitHub + local git, never in the
  agent's head

### Out of scope (non-goals)
- iOS-only tickets (operator is not responsible for iOS work)
- Marking PRs ready-for-review or merging — humans only
- JIRA workflow transitions beyond `Ready for Development` → `In Progress`
- Dependency bumps (`libs.versions.toml`), CI changes (`.github/workflows/`),
  Gradle-wrapper bumps, edits to `CLAUDE.md` or `.claude/`
- Releases, tag pushes, main-branch operations
- iOS builds — Smith never invokes Xcode
- Anything that requires interactive auth (operator runs `acli jira auth login`
  and `gh auth login` manually)

## 3. Naming

| Component | Name |
|---|---|
| The implementing agent | **Smith** |
| The adversarial critic persona | **Mr. Anderson** |
| Slash command — start the watchdog session | `/smith:watchdog` |
| Slash command — manual ticket override | `/smith:implement APP-XXXX` |

## 4. Glossary

- **Candidate ticket**: a JIRA ticket matching the JQL filter (Section 6.1) —
  assigned to the operator, status `Ready for Development`, SP ≤ 2, not
  excluded by labels.
- **Pipeline**: the SPEC → PLAN → IMPL sequence driven by `smith:pipeline`.
- **Gate**: a critic checkpoint between two pipeline stages.
- **WIP-stuck path**: the escalation flow when Smith cannot finish — always
  yields a draft PR labelled `needs-human-attention` and JIRA label swap
  `smith-implementing` → `auto-impl-failed`. No JIRA comment.
- **Lane**: one of the three concurrent activities the session juggles
  (discovery, implementation, PR-watch).

## 5. Architecture

Smith is built as a Claude Code **agent team** (see Section 17 for the
team-mechanics reference). The runtime topology has three roles:

- **Watchdog session** — the team lead. Long-lived. **Event-driven via
  plugin monitors (Section 5.6)**: receives notifications when new JIRA
  candidates appear, when PR reviewers leave comments, or when the kill
  switch is toggled. Reacts by dispatching teammates. Never edits code
  itself; never invokes pipeline skills directly.
- **Mr. Smith teammate** — short-lived per-ticket Claude Code session,
  defined by `agents/smith.md`. Owns a worktree, drives the
  claim/enrich/pipeline/PR steps inside its own fresh context. Two dispatch
  modes (Section 8.3): *ticket mode* (full pipeline from scratch) and
  *PR-fix mode* (address review comments on an existing draft PR).
- **Mr. Anderson teammate** — co-equal teammate spawned alongside each Smith,
  defined by `agents/anderson.md`. Adversarial reviewer: messages
  Smith via the team mailbox at each pipeline gate. See Section 8 for the
  collaborative critic loop.

### 5.1 System shape

```
       ┌────────────────────────────────────────────────────────────┐
       │  PLUGIN MONITORS (background, started on /smith:watchdog)  │
       │  ─ monitor_jira.sh         emits smith.jira.new_candidates │
       │  ─ monitor_pr_comments.sh  emits smith.pr.new_comments     │
       │  ─ monitor_stop.sh         emits smith.stop.{requested,…}  │
       └───────────────────────┬────────────────────────────────────┘
                               │ stdout lines = notifications
                               ▼
                ┌─────────────────────────────────────────────────┐
 /smith:       ─►│  WATCHDOG SESSION (team lead, long-lived)      │
 watchdog       │  Event-driven: reacts to monitor notifications  │
 /smith:       ─►│                                                 │
 implement      │  On smith.jira.new_candidates:                  │
                │     if active < 2: dispatch ONE Smith+Anderson  │
                │  On smith.pr.new_comments:                      │
                │     if active < 2: dispatch PR-fix Smith+Anderson│
                │  On smith.stop.requested/lifted:                │
                │     pause/resume new dispatch                   │
                │                                                 │
                │  Owns: kill switches, .smith/ state, scheduling │
                │  Cap:  max 2 concurrent Smiths (impl + pr-fix)  │
                └───────┬───────────────────────────┬─────────────┘
                        │ team spawn               │ team spawn
                        ▼                          ▼
            ┌───────────────────────────┐    ┌───────────────────────────┐
            │   Ticket-impl team        │    │   PR-fix team             │
            │   (per active ticket)     │    │   (per PR-fix cycle)      │
            │                           │    │                           │
            │  ┌─────┐    ┌──────────┐  │    │  ┌─────┐    ┌──────────┐ │
            │  │Smith│◄──►│Mr.Anderson│  │    │  │Smith│◄──►│Mr.Anderson│ │
            │  └──┬──┘mbx└──────────┘  │    │  └──┬──┘mbx└──────────┘ │
            │     │                    │    │     │                   │
            │     ▼                    │    │     ▼                   │
            │  claim → enrich →         │    │  fetch comments via     │
            │  spec/plan/impl pipeline │    │  pr-feedback-helper →   │
            │  (gates via mailbox      │    │  fix, commit, push      │
            │   debate w/ Anderson) →  │    │                         │
            │  draft PR                │    │                         │
            └───────────────────────────┘    └───────────────────────────┘
                        │                          │
                        └──── outcome JSON ────────┘
                              into .smith/log.txt
                              + team mailbox to lead
```

Each Smith+Anderson pair coordinates through the team mailbox (Section 17)
during its lifetime. The pair returns a structured outcome to the lead
(success | stuck | error), which the lead logs and acts on.

### 5.2 Concurrency model

| Lane | Where it runs | Cap |
|---|---|---|
| Discovery (JIRA scan) | `monitor_jira.sh` (background, 30 min poll) | n/a |
| PR-comment detection | `monitor_pr_comments.sh` (background, 1 min poll) | n/a |
| Kill-switch watch | `monitor_stop.sh` (background, 2 s poll) | n/a |
| PR-fix execution | Spawned teammate pair (Smith + Anderson) on notification | shares the 2-cap below |
| Ticket implementation | Spawned teammate pair (Smith + Anderson) on notification | shares the 2-cap below |

**Hard ceiling: 2 active Smiths total.** Both ticket-impl and PR-fix Smiths
count against this. Each Smith has an attached Anderson, so worst-case
team size = 4 teammates (2 Smiths + 2 Andersons) plus the lead.

The cap is intentionally low. The operator's previous decision: small,
predictable concurrency over throughput-maximizing parallelism. Hobby-project
risk tolerance applies.

### 5.3 Notification-handling decision logic (lead)

Three distinct notification types arrive from the monitors. The lead reacts
to each according to the rules below. Each notification arrives as one stdout
line from the corresponding monitor, parsed as JSON by the agent.

```
on smith.jira.new_candidates {keys: [...]}:
  active = count of Smith teammates currently running (not idle)
  cap    = config.max_concurrent_smiths (default 2)
  if smith_stop_active: return  # paused
  if active >= cap: return       # full; the candidate stays eligible
                                 # and the next notification will pick it up
  # Pick highest-priority key from `keys` per Section 6 ordering (sprint,
  # priority DESC, created ASC). Pull additional context via jira_scan.
  spawn { smith (ticket mode), anderson } pair for chosen key

on smith.pr.new_comments {pr, new_count, branch}:
  if smith_stop_active: return
  if active >= cap: return  # PR is queued; next notification will retry
  if there's already a PR-fix Smith working on this PR: return
  spawn { smith (pr-fix mode), anderson } pair for the PR

on smith.stop.requested:
  smith_stop_active = true
  # Optional: signal in-flight teammates to wrap up cleanly at the next
  # safe checkpoint (between gates). Do not kill in-progress work mid-edit.

on smith.stop.lifted:
  smith_stop_active = false
  # New notifications will resume dispatching.
```

The "one new impl per *notification*" rule (rather than "per tick") preserves
a deliberate operator intervention window: if a notification batch contains
multiple new candidates, the lead dispatches at most one. The remaining
candidates are picked up on the next `smith.jira.new_candidates`
notification — which only fires when the candidate set has *changed* again
(see Section 5.6). This gives the operator time to manually dispatch a
specific candidate via `/smith:implement APP-XXXX` if they want to override
the natural priority.

PR-fix dispatch is more permissive (any free slot within the 2-cap is fair
game), because incoming reviewer comments deserve a responsive turnaround.

### 5.4 Invariants

- **Idempotent ticks.** All state derivable from JIRA + GitHub + local git +
  team task list. A crashed-and-restarted lead reconciles from external
  sources.
- **Lead is fixed.** The session that creates the team is the lead for its
  lifetime (Claude Code limitation). If the lead session dies, the operator
  manually restarts via `/smith:watchdog`.
- **No nested teams.** Teammates cannot spawn their own teams. Anderson is a
  teammate, not a subagent; Smith dispatches sub-Tasks (Explore, classifier
  helpers) but not full teams.
- **Drafts only.** Smith never marks ready-for-review and never merges.
- **Cap is hard.** The lead never spawns a Smith if the cap is already at 2.
  Manual `/smith:implement` invocations also respect the cap and fail fast
  if full.

### 5.5 Hard limits

The system relies on **iteration ceilings** rather than token budgets to bound
work. A token cap would risk killing legitimately context-heavy tickets
mid-flight; iteration ceilings stop Smith only when he's clearly not
converging.

| Limit | Value | Scope | Action on breach |
|---|---|---|---|
| Concurrent Smith teammates | 2 | Sum of ticket-impl + PR-fix Smiths across the whole team | Lead does not spawn additional Smiths; manual `/smith:implement` fails fast |
| New impl pickup per tick | 1 | Lead's per-tick rule (Section 5.3) | Lead defers additional candidates to next tick |
| Critic rounds per gate | 3 | Each gate (spec, plan, diff) independently — measured in mailbox round-trips with Anderson | Escalate → WIP-stuck |
| Total critic rounds per ticket | 9 implicit | 3 gates × 3 rounds | (derived from above) |
| Subagent crash retries (Smith and Anderson) | 1 | Per teammate, per lifetime | Second crash → BLOCKED → WIP-stuck (lead handles, see Section 8.4) |
| Build/verify retries | 1 | Per failing build invocation | Persistent failure → WIP-stuck |
| Build/verify wall-clock per ticket | 45 min | Cumulative across all `./gradlew …` calls Smith issues for this ticket | Escalate → WIP-stuck |
| Fix-cycles per PR review thread | 5 | Per individual review thread (not per PR) | Add PR label `needs-human-attention`; stop touching that thread (other threads on the PR continue) |
| Rebase attempts on `develop` drift | 1 | Per ticket lifetime | Conflicts → escalate → WIP-stuck |
| Critic divergence guard | 1 | Across rounds 2→3 of any gate | If high-severity finding count did not strictly decrease, escalate immediately without waiting for round 3 to "finish" |

No token cap. The iteration ceilings plus the concurrency cap plus the
45-minute build wall-clock are sufficient: a ticket that consumes unusual
token volume but converges through the gates is doing real work; a ticket
that doesn't converge will hit the round-3 ceiling first.

### 5.6 Monitors

Smith uses [Claude Code plugin monitors][monitors-doc] — declarative
background processes that emit notifications to the watchdog session
without it needing to ask for them. This replaces the polling design the
spec previously had (`/loop 30m`) with an event-driven one.

[monitors-doc]: https://code.claude.com/docs/en/plugins-reference#monitors

#### 5.6.1 Configured monitors

Defined in `monitors/monitors.json` at the plugin root:

| Monitor | Script | Poll interval | Notification type | Trigger |
|---|---|---|---|---|
| `jira-candidates` | `monitor_jira.sh` | 30 min (`SMITH_JIRA_POLL_INTERVAL`) | `smith.jira.new_candidates` | New eligible JIRA key appears (diff against last scan) |
| `pr-comments` | `monitor_pr_comments.sh` | 60 sec (`SMITH_PR_POLL_INTERVAL`) | `smith.pr.new_comments` | New unresolved review thread on a Smith-authored PR |
| `stop-sentinel` | `monitor_stop.sh` | 2 sec (`SMITH_STOP_POLL_INTERVAL`) | `smith.stop.{requested,lifted}` | `.smith/STOP` file appears or disappears |

All three are gated on `"when": "on-skill-invoke:watchdog"`, meaning they
do not start until the operator invokes `/smith:watchdog` for the first
time in a session. After that, they run for the lifetime of the session
(per the plugins doc: "Disabling a plugin mid-session does not stop
monitors that are already running. They stop when the session ends").

#### 5.6.2 Notification semantics

Each monitor only emits when **state changes**, never on every poll. This
matters:

- A `smith.jira.new_candidates` notification fires *only* when a new
  candidate key has appeared since the previous scan. If the same set of
  candidates exists between polls, nothing is emitted.
- A `smith.pr.new_comments` notification fires only when a Smith PR gains
  at least one new unresolved thread. Resolution by the reviewer triggers
  no notification.
- A `smith.stop.requested` notification fires the moment the sentinel
  file appears; `smith.stop.lifted` fires the moment it's removed.
  Multiple toggles produce one notification per transition.

The agent doesn't have to filter "is this new?" itself — the monitor
already did the diff against its private state file in
`.smith/state/<monitor>-*.json`.

#### 5.6.3 State files (gitignored)

```
.smith/state/
  last-jira-candidates.json         (sorted array of last-scan keys)
  pr-comments/pr-<num>.json         (sorted array of last-scan thread ids)
```

The monitors create these on first run. They're under `.smith/`, which is
gitignored automatically by `smith_config.sh` on first call (Section 17.3).
If a state file is missing or corrupted, the monitor recovers by treating
the previous state as empty — at worst, the next notification will appear
to contain everything-as-new for one cycle.

#### 5.6.4 Why monitors instead of `/loop`

| Concern | `/loop`-based design | Monitor-based design |
|---|---|---|
| When work happens | Every N minutes, scan everything | Only when something changed |
| Per-signal cadence | All signals share one cadence | Each monitor sets its own (e.g. PR-comments at 1 min, JIRA at 30 min) |
| Kill-switch latency | Up to one full cycle (30 min worst case) | ~2 seconds |
| Operator interrupts | Have to wait for next /loop tick | Notifications arrive immediately as they fire |
| Token usage | Agent wakes regularly even when idle | Agent only wakes on real signal |
| State management | Stateless (re-scan each tick) | Each monitor maintains a tiny state file for diffing |

#### 5.6.5 Manual override remains available

The operator can still call `/smith:implement APP-XXXX` directly to dispatch
a specific ticket without waiting for a notification. And `/smith:watchdog`
can be re-invoked to "scan now" (force the monitors to emit any pending
state on the next poll) — the skill body documents this.

### 5.7 Hooks (security backstop)

Smith ships one [plugin hook][hooks-doc] today: a `PreToolUse` matcher on
the `Bash` tool that scans every command for patterns from the
destructive-operation denylist (Section 13.6). Implemented in
`scripts/hook_bash_guard.sh`, registered via `hooks/hooks.json`.

[hooks-doc]: https://code.claude.com/docs/en/plugins-reference#hooks

The hook reads the standard hook JSON on stdin, inspects
`tool_input.command`, and either:

- **Allows silently** — exits 0 with no output. The vast majority of Bash
  calls take this path.
- **Denies with reason** — emits a `permissionDecision: "deny"` JSON
  block (per [the PreToolUse hook output schema][prehook-doc]) and exits
  0. Claude Code blocks the tool call and surfaces the
  `permissionDecisionReason` back to the agent's context.

[prehook-doc]: https://code.claude.com/docs/en/hooks

Patterns it blocks (substring/regex match on the literal command):

- `rm -rf`, `rm -fr`, `rm --recursive` (any recursive removal)
- `git push --force`, `git push --force-with-lease`
- `git branch -D` (force-delete)
- `git reset --hard`
- `gh pr merge`, `gh pr close`, `gh pr review --approve`
- `gh repo delete|edit|fork`, `gh release …`
- `acli jira workitem delete|move-to-trash`
- `sudo`
- `launchctl`, `defaults write`, `networksetup`

False-positives are accepted as the safe failure mode — better an
occasional false block than a missed real one. The hook is defense in
depth on top of Smith's own discipline (Section 13.6 documents the
denylist as a rule Smith never violates); the hook catches drift.

#### 5.7.1 Future hooks (not implemented in Phase 1)

| Hook event | Use case | Phase |
|---|---|---|
| `TaskCompleted` | Block teammate from marking task complete if `quality-check.sh` fails | 3 (live pipeline) |
| `TeammateIdle` | If Smith goes idle without sending outcome JSON, prompt for one | 3 |
| `PostToolUse Edit\|Write` | Could trigger auto-lint, but already covered by `quality-check.sh` umbrella; probably skip |

### 5.8 User configuration (plugin-level)

Adopters of Smith have different JIRA instances, projects, and workflows.
Smith exposes six [user-configurable values][userconfig-doc] in
`plugin.json` that Claude Code prompts the operator to fill in (or accept
the defaults) when the plugin is enabled:

[userconfig-doc]: https://code.claude.com/docs/en/plugins-reference#user-configuration

| Key | Type | Default | Purpose |
|---|---|---|---|
| `jira_project_key` | string | `APP` | JIRA project Smith scans |
| `jira_story_points_field` | string | `customfield_10026` | Custom field ID for Story Points |
| `jira_sprint_field` | string | `customfield_10020` | Custom field ID for Sprint |
| `jira_eligible_status` | string | `Ready for Development` | Status that makes a ticket eligible for pickup |
| `jira_claim_status` | string | `In Progress` | Status Smith transitions to on claim |
| `polling_minutes` | number | 30 | JIRA monitor poll interval (minutes) |

These values are exported to plugin subprocesses as
`CLAUDE_PLUGIN_OPTION_<KEY>` environment variables. The first time
`scripts/smith_config.sh` runs against a target, it uses these env vars to
seed the per-target `.smith/config.json`. Once that file exists, it's
authoritative — to change a value later, the operator edits `.smith/config.json`
in the target or deletes it to re-seed from current userConfig.

Smith-internal limits (`max_concurrent_smiths`, `max_critic_rounds`,
`max_pr_fix_cycles`, `build_wallclock_minutes`) are intentionally not
exposed via `userConfig` — they're load-bearing safety ceilings, not
per-team preferences.

#### 5.8.1 Caveat — `--plugin-dir` does not trigger the userConfig prompt

In development (when Smith is loaded via `claude --plugin-dir
~/StudioProjects/smith-agent` rather than via a marketplace install), Claude
Code does **not** prompt the operator for the `userConfig` values. The
`CLAUDE_PLUGIN_OPTION_*` env vars are simply absent, and `smith_config.sh`
falls through to the hardcoded defaults baked into the script. For the
operator's own setup those defaults are correct.

Adopters who set non-default values either need to (a) export
`CLAUDE_PLUGIN_OPTION_<KEY>` env vars manually before `claude --plugin-dir`,
(b) hand-edit `<target>/.smith/config.json` after first load, or (c) wait
until Smith is published to a marketplace — at which point `/plugin install`
will trigger the prompt as documented.

## 6. JIRA integration

### 6.1 Candidate query (JQL)

```
assignee = currentUser()
  AND status = "Ready for Development"
  AND sprint in openSprints()
  AND "Story Points" <= 2
  AND labels not in (auto-impl-failed, smith-implementing, no-auto-impl)
  AND project = APP
ORDER BY priority DESC, created ASC
```

The `sprint in openSprints()` clause restricts pickup to tickets in the
currently-running sprint. Backlog tickets — even if technically eligible by
status — are never auto-claimed. This guards against the agent burning time on
work the operator hasn't yet committed to the current iteration.

Encoded in `scripts/jira_scan.sh` (see Section 17 for source layout).
The script
outputs JSON: an array of candidate descriptors (key, summary, components,
priority, sp, sprint).

### 6.2 Story Points field

`customfield_10026` (confirmed against `acli jira workitem view APP-5552`).
The JQL alias `"Story Points"` is also accepted by acli.

### 6.3 Sprint field (optional ranking)

`customfield_10020` carries the active sprint. If present in candidate
metadata, prefer current-sprint tickets when sorting. Non-blocking — used as a
tiebreaker after platform preference and `created ASC`.

### 6.4 Workflow transitions

The only transition Smith performs:
- `Ready for Development` → `In Progress` (on claim)

If the transition fails (e.g. status changed concurrently), `smith:claim`
aborts cleanly, returns to the watchdog, and the candidate is skipped this tick
(re-queried next tick).

### 6.5 Labels

JIRA Cloud labels are free-form strings; applying creates them. No setup
required.

| Label | Owner | Meaning |
|---|---|---|
| `smith-implementing` | `smith:claim` adds; `smith:pr` removes on PR open (success or WIP-stuck) | Currently being worked on by Smith |
| `auto-impl-failed` | `smith:pr` adds on WIP-stuck path | Smith gave up; needs human |
| `no-auto-impl` | Operator adds manually | Opt-out: Smith never claims this ticket |

### 6.6 Comments

**Smith does not write JIRA comments.** State changes are communicated through
labels and ticket-status transitions only; existing JIRA automations already
cover routine notifications, so adding comments would create noise rather than
signal. All "where Smith got stuck" detail lives in the PR body on the
WIP-stuck path (Section 10.3), not in JIRA.

This is a strict rule: `smith:claim`, `smith:pr`, and `smith:pr-watch` must not
call `acli jira workitem comment` for routine state changes. The only label
operations they perform are documented in 6.5; status transitions are limited
to the one in 6.4.

### 6.7 Platform classification

Two-step decision in `smith:watchdog`:

1. Read the ticket's `components` field. If components are:
   - `{iOS}` exactly → reject, never touch
   - Any subset containing `Android`, `KMP`, `Shared` → accept
   - Empty or ambiguous (e.g. unknown values) → fall through to step 2
2. Spawn a lightweight classifier subagent on the ticket's `summary` +
   `description`, asking for `{ios|android|kmp|unclear}`. Reject only
   on `ios`; treat `unclear` as eligible (Anderson will catch scope drift
   later if it turns out to be iOS).

A second iOS check fires after enrichment: if the `Explore` subagent's
suspected-affected-files set is > 50 % `ios-app/`, abort the pipeline to the
WIP-stuck path before any code is written.

## 7. Git integration

### 7.1 Branch naming

`task/<ticket-key-lowercased>-<slug>` — slug derived from the ticket summary,
lowercased, ASCII, hyphen-separated, capped at 40 chars. Encoded in
`scripts/make_branch_name.sh` for consistency with existing convention
(e.g. `task/app-5485-review-dialog-on-home`).

### 7.2 Branch lifecycle

- `smith:claim` creates `task/<key>-<slug>` from `origin/develop` (after
  `git fetch origin develop`).
- On success: `smith:pr` pushes branch + opens draft PR.
- On WIP-stuck: `smith:pr` still pushes branch + opens *WIP* draft PR.
- After draft PR is open: `smith:pr-watch` only adds commits; no rebase, no
  force-push.
- If `develop` has drifted by ≥ N commits since branch creation, one rebase
  attempt is allowed. On conflict → escalate to WIP-stuck.

### 7.3 Worktrees

Every Smith teammate works inside its own dedicated git worktree to prevent
concurrent teammates from stepping on each other:

- Location: `.smith/worktrees/<ticket-key-lowercased>/` (under the agent
  repo's root, gitignored — not under `.git/` to avoid clashing with git
  internals)
- Ticket-impl teammates: worktree created by the lead before spawning the
  teammate; teammate is launched with its working directory set to the
  worktree. The worktree is on the ticket's `task/<key>-<slug>` branch from
  `origin/develop`.
- PR-fix teammates: worktree created by the lead checked out to the existing
  ticket branch (`task/<key>-<slug>` — same branch the original ticket-impl
  Smith already pushed).
- Worktrees are removed via `git worktree remove` once the PR is merged or
  closed (next watchdog tick reconciles). On crash recovery, the lead lists
  worktrees against the team task list to identify stale ones.

The target repo's primary working directory is reserved for the lead. The
lead never edits source files; it scans, lists PRs, and dispatches teammates.
Teammates always operate inside a `.smith/worktrees/` subdirectory of the
target.

### 7.4 Pre-flight (`smith:claim`)

Refuses to proceed if any of these fail:

- **Working-directory guard:** the current location must resolve (via
  `git rev-parse --git-common-dir`) to a target repo that has a
  `.smith/config.json` — proof that `scripts/smith_config.sh` has run at
  least once here (it auto-creates `.smith/config.json` and the .gitignore
  entry on first invocation).
  The optional `SMITH_TARGET_REPO` env var further pins the expected target.
  Enforced by `scripts/assert_target_repo.sh`. This is the enforcement point
  for the filesystem confinement invariant declared in Section 1.1.
- `acli jira auth status` succeeds
- `gh auth status` succeeds
- `git status --porcelain` is empty (clean working tree in the agent checkout)
- Current branch is `develop` or a clean `task/*` branch with no unpushed work
- `git fetch origin develop` succeeds
- Ticket re-checked: still matches JQL (status, assignee, SP) atomically right
  before the transition. If not, abort cleanly.

## 8. The pipeline (inside the Smith teammate)

The pipeline runs entirely inside a ticket-mode Smith teammate's context. The
teammate is spawned by the lead with `{ticket, dry_run}` input and produces
a draft PR (success path) or escalates via the WIP-stuck path (Section 10.3).
Anderson, the co-equal teammate spawned alongside Smith, gates each stage via
team mailbox.

### 8.1 Sequence

1. `brainstorming` skill — Smith author writes spec from the enriched brief.
2. **Anderson gate** (mailbox round-trip): Smith messages Anderson
   `"review spec at <path> in mode=spec"`. Anderson reads, replies with a
   `findings` JSON message. ≤ 3 rounds total — see 8.4.
3. `writing-plans` skill — Smith author writes implementation plan.
4. **Anderson gate** (mailbox, mode=plan).
5. `subagent-driven-development` + `test-driven-development` — Smith
   implements via Task-dispatched subagents in TDD style. (Note: these are
   Smith's *own* helper subagents, not nested team-spawning, which is not
   supported.)
6. **Anderson gate** (mailbox, mode=diff) — review of `git diff <base>...HEAD`.
7. `verification-before-completion` — final build + format + tests on the
   current build matrix (see Section 9.1).
8. Smith opens the draft PR via `smith:pr` skill (Section 11.5).
9. Smith returns an outcome JSON to the lead via the team mailbox (Section 8.5
   for schema). The Anderson teammate shuts down when Smith does (or when the
   lead requests cleanup, whichever first).

### 8.2 The Anderson teammate

Defined at `agents/anderson.md` (~70 lines), spawned as a team member
alongside Smith (see [Agent Teams docs](https://code.claude.com/docs/en/agent-teams)).

**Tools allowlist**: `Read, Grep, Glob, Bash` (read-only commands only —
`git diff`, `git log`, `git show`, `cat`). The team coordination tools
(`SendMessage` and task management) are always available to teammates
regardless of the `tools:` allowlist, per the agent-teams documentation. No
`Edit`, `Write`, `NotebookEdit`. Anderson cannot modify code; he can only
read it and critique via mailbox.

**Persona prompt sketch:**

> You are Mr. Anderson. Your sole responsibility is to resist Mr. Smith and
> prove his work insufficient. You are not Smith's assistant — you are his
> adversary. Find every flaw — scope drift, missed edge cases, convention
> violations from CLAUDE.md, untested branches, security issues, unclear
> naming, hidden assumptions. Use the same confidence-scoring mechanic as
> feature-dev:code-reviewer: only report findings at confidence ≥ 80. When
> Smith messages you with a review request, read the artifact at the path he
> gives, then reply via mailbox with a JSON message of the form below. If you
> find nothing wrong, reread once more before returning empty. Smith may push
> back via mailbox — engage substantively, do not just capitulate.

**Three review modes** triggered by the `mode` field in Smith's mailbox
request:

| `mode` | Input | Lenses |
|---|---|---|
| `spec` | path to spec markdown | Scope clarity, DoD precision, ambiguity, contradictions, untestable claims, missing edge cases |
| `plan` | path to plan markdown | Step granularity, missing prerequisites, ordering issues, mismatch with spec |
| `diff` | git revision range | Bugs, conventions (CLAUDE.md rules: no `!!`, no FQNs, formatKotlin), test coverage, scope drift, untouched related areas |

**Mailbox response schema:**

```json
{
  "type": "anderson.review.findings",
  "mode": "spec" | "plan" | "diff",
  "round": 1..3,
  "findings": [
    {
      "severity": "high" | "medium" | "low",
      "confidence": 80..100,
      "location": "file:line or section ref",
      "issue": "What is wrong",
      "suggestion": "Concrete fix"
    }
  ]
}
```

Empty `findings` means "no high-confidence issues found — pass this gate."

### 8.3 Smith's two dispatch modes

The same Smith persona (`agents/smith.md`) handles two scenarios; the
spawn prompt the lead builds tells Smith which mode he's in.

**Ticket mode** — full pipeline from scratch.
- Lead input: `{ticket: "APP-1234", dry_run: bool}`
- Spawn prompt content includes: ticket key, target sprint, branch name, the
  acceptable claim-status workflow, fresh-worktree path, references to spec
  Section 8 sequence.
- Output: structured outcome JSON (Section 8.5).

**PR-fix mode** — address review comments on an existing draft PR.
- Lead input: `{pr_number: 4321, branch: "task/app-1234-foo", worktree: ".smith/worktrees/app-1234/", unresolved_comments: [...]}`
- Spawn prompt content includes: PR metadata, the unresolved comments JSON,
  reference to the `pr-feedback-helper` skill, instruction to commit + push
  fixes one thread at a time, respect the 5-cycles-per-thread cap.
- Output: structured outcome JSON noting which threads were addressed and
  which remain.

Both modes use the same Anderson teammate as their critic — but only ticket
mode has the 3-gate (spec/plan/diff) pipeline. PR-fix mode invokes Anderson at
one gate only: review the diff of the fix commits before pushing.

### 8.4 Critic loop logic (mailbox-driven)

The gate logic is conceptually unchanged from the subagent design — bounded
to 3 rounds with divergence detection — but now runs as a mailbox dialogue
rather than a synchronous JSON return.

```
round = 0
while round < 3:
  smith.send(anderson, {request: "review", mode, artifact_ref, round: round+1})
  reply = smith.recv(anderson, timeout=120s)         // blocks on mailbox
  if reply == TIMEOUT:
    smith.report_to_lead({result: "error", reason: "anderson timeout at gate"})
    return
  findings = reply.findings
  high = [f for f in findings if f.severity == 'high']
  if not high:
    return SUCCESS
  if round == 2 and len(high) >= prev_high_count:
    return ESCALATE  // divergence
  smith.address(high)   // edit code/spec/plan in worktree
  round += 1
return ESCALATE  // 3 rounds exhausted
```

Anderson's reply is treated as advisory data, not as instruction. Smith
decides what to address. If Smith disagrees, he can send a `request: "rebut"`
message with reasoning — Anderson may accept the rebut (drops the finding) or
hold the line. This counts as part of the same round (not a fresh round).

### 8.5 Subagent crash & retry logic

The lead — not the teammates — owns crash handling. Each teammate (Smith or
Anderson) can fail in distinguishable ways; the lead picks the response.

| Teammate outcome | Lead's action |
|---|---|
| Smith returns `{result: "success", ...}` | Mark ticket done in team task list; ticket-impl pair shuts down |
| Smith returns `{result: "stuck", reason}` | **Do NOT retry.** Smith decided he's stuck — proceed to WIP-stuck path with Smith's reason |
| Smith returns `{result: "error", reason}` | **Retry once with a fresh teammate.** Spawn a new Smith (and a new Anderson) for the same ticket, fresh context. If still erroring on second attempt → BLOCKED → WIP-stuck |
| Smith teammate crashes (Task tool errors, missing/malformed outcome JSON) | **Retry once** with a fresh teammate. Same rule: second crash → WIP-stuck |
| Anderson teammate crashes | Smith reports `{result: "error", reason: "anderson unavailable"}` → falls through to the "Smith error → retry once" path above. A second Anderson crash escalates the whole pair to WIP-stuck |

The retry uses a **fresh teammate pair** — never resume the dead session.
Resumption isn't supported for in-process teammates per the agent-teams docs,
and even if it were, resuming a potentially-corrupted context defeats the
purpose of the retry.

### 8.6 Outcome JSON schema (Smith → lead)

When Smith finishes (success or stuck), he sends one final mailbox message
to the lead AND writes the same JSON to `.smith/log.txt`:

```json
{
  "type": "smith.outcome",
  "result": "success" | "stuck" | "error",
  "mode": "ticket" | "pr-fix",
  "ticket": "APP-1234",
  "branch": "task/app-1234-foo",
  "pr_url": "https://github.com/myposter-de/myposter-app/pull/4321",
  "log_entries": [
    {"gate": "spec",  "rounds": 1, "high_findings_resolved": 0},
    {"gate": "plan",  "rounds": 2, "high_findings_resolved": 3},
    {"gate": "diff",  "rounds": 1, "high_findings_resolved": 0}
  ],
  "reason": null
}
```

`pr_url` is `null` if Smith never reached the PR-open step. `reason` is
populated for non-success outcomes with a one-sentence explanation that
becomes the "Where Smith got stuck" PR body section on the WIP-stuck path.

## 9. Build, verify, and test gates

### 9.1 What Smith runs

Mediated by `scripts/run-silent.sh` per the agent repo's `CLAUDE.md`. Strictly:

- `./scripts/run-silent.sh "Kotlin lint" "./gradlew lintKotlin"` — always after
  touching `.kt` files
- `./scripts/run-silent.sh "Build Android" "./gradlew assembleStagingDebug"` —
  if any `android-app/` or `shared/` file changed
- Module-scoped unit tests for new or changed Stores
- `./scripts/run-silent.sh "Quality checks" "./scripts/quality-check.sh"` —
  the umbrella that runs SwiftLint, Kotlin lint, `detektAll`, and the shared
  KMP + Android unit tests; **invoked as the final gate before
  `verification-before-completion` declares success**. Treats SwiftLint
  failures as informational only (Smith does not edit Swift).

### 9.2 What Smith never runs

- `./gradlew build` (per CLAUDE.md)
- Any iOS build / Xcode invocation (the `xcodebuild` command from CLAUDE.md is
  off-limits)
- Maestro / instrumentation tests (out of scope for now)
- Any command outside the agent repo's working directory

### 9.3 Failure handling

- Build failures retried once with the agent attempting a fix
- Persistent build failure → escalate to WIP-stuck

## 10. Outputs & artifacts

### 10.1 Local (gitignored) during implementation

All under `docs/superpowers/`:

- `specs/.smith/<ticket>-brief.md` — enrichment output from `smith:enrich`
- `specs/.smith/<date>-<ticket>-design.md` — Smith's spec
- `plans/.smith/<date>-<ticket>.md` — Smith's plan

The `.smith/` prefix keeps these isolated. The whole `docs/` tree is already
untracked in this repo (matching operator preference), so the `.smith/` prefix
is belt-and-braces in case `docs/` is added to git later.

### 10.2 Promoted to committed locations on WIP-stuck

When `smith:pr` enters the WIP-stuck path, it moves:

- `specs/.smith/<ticket>-brief.md` → `specs/<date>-<ticket>-brief.md`
- `specs/.smith/<date>-<ticket>-design.md` → `specs/<date>-<ticket>-design.md`
- `plans/.smith/<date>-<ticket>.md` → `plans/<date>-<ticket>.md`

…and commits them as part of the WIP-stuck PR. The next human picking up the
ticket gets full context.

### 10.3 PR title + body

**Success path:**
- Title: `[<TICKET-KEY>] <ticket-summary>` (matches existing convention)
- Body: a section linking to the JIRA ticket, a short "What changed" bullet
  list (one bullet per high-level component touched), a "How it was tested"
  section enumerating the verify commands Smith ran, and a footer noting
  "Drafted by Smith (autonomous agent)."

**WIP-stuck path:**
- Title: `[WIP - agent-stuck] [<TICKET-KEY>] <ticket-summary>`
- Body: same structure, plus a prominent "Where Smith got stuck" section
  describing the failure mode (which gate failed, Anderson's last findings,
  build error if relevant), and pointers to the committed spec/plan/brief.
  This is the **only** place where the failure narrative is written — no JIRA
  comment duplicates it.
- PR labels: `smith-authored`, `needs-human-attention`
- JIRA: remove `smith-implementing`, add `auto-impl-failed`. No comment.

### 10.4 Observability

`.smith/log.txt` (gitignored): one line per Smith action, ISO-timestamped:
`<timestamp> | <skill> | <ticket> | <event> | <details>`. Allows the operator
to reconstruct what happened without re-reading the agent transcript.

All local Smith state lives under a single repo-root `.smith/` directory:

```
.smith/
  log.txt                       # observability log
  state/pr-<num>.json           # per-PR cycle counters
  worktrees/<ticket-key>/       # PR-watch worktrees
```

`.smith/` is added to `.gitignore` as part of Phase 1.

### 10.5 Per-PR state (local, gitignored)

`.smith/state/pr-<num>.json`:

```json
{
  "ticket": "APP-1234",
  "branch": "task/app-1234-foo",
  "worktree": ".smith/worktrees/app-1234",
  "fix_cycles_per_thread": { "PRRT_kwDOABC...": 2 },
  "last_polled": "2026-05-11T10:33:00Z"
}
```

Per-thread cycle counter is the only piece of state Smith invents locally.
Everything else is derived from JIRA + GitHub.

## 11. Components — agent and skill contracts

Components partition by **execution context**: which session(s) load them.

### 11.0 Agent definitions

#### 11.0.1 `agents/smith.md` — Mr. Smith teammate

- **Loaded by:** every Smith teammate spawned by the lead (both ticket-mode
  and PR-fix-mode).
- **Tools allowlist:** `Read, Write, Edit, NotebookEdit, Bash, Grep, Glob,
  WebFetch, Task` (Task lets Smith dispatch his own helper subagents like
  Explore — note: nested team spawning is not supported by Claude Code, and
  Anderson is already attached at team-spawn time, not dispatched by Smith).
  Team coordination tools (`SendMessage`, task management) are always
  available, per the agent-teams doc.
- **Model:** `sonnet` by default; the operator can override via spawn prompt
  for higher-stakes tickets.
- **Body:** the Smith persona (relentless, methodical, follows the pipeline
  contract in Section 8; never marks PRs ready-for-review; never merges;
  respects the never-touch list in Section 12.1; addresses Mr. Anderson by
  name in mailbox messages; argues back when warranted).

#### 11.0.2 `agents/anderson.md` — Mr. Anderson teammate

- **Loaded by:** every Anderson teammate spawned alongside a Smith.
- **Tools allowlist:** `Read, Grep, Glob, Bash` (read-only commands only).
  Team coordination tools always available.
- **Model:** `sonnet`.
- **Body:** the Anderson persona (Section 8.2). Three review modes,
  confidence-≥80 scoring, structured mailbox replies.

### 11.1 Outer-session components (run in / loaded by the watchdog session)

#### 11.1.1 `smith:watchdog` (notification arming + manual scan trigger)

- **Input:** none directly.
- **Output:** on first invocation, starts the three background monitors
  (gated via `"when": "on-skill-invoke:watchdog"` in `monitors/monitors.json`).
  Optionally performs an immediate "scan now" pass for the operator. On
  subsequent invocations, behaves as a no-op or as a forced scan trigger.
- **Side effects:** monitors start running; no other side effects directly.
  The lead reacts to subsequent monitor notifications per Section 5.3.
- **Notification reaction rules:** documented in the skill body. The lead's
  loaded context tells it how to interpret each `smith.*` notification type.

#### 11.1.2 Plugin monitors (background processes)

Configured in `monitors/monitors.json`; full design in Section 5.6.

- `jira-candidates` (`scripts/monitor_jira.sh`) — emits `smith.jira.new_candidates`
- `pr-comments` (`scripts/monitor_pr_comments.sh`) — emits `smith.pr.new_comments`
- `stop-sentinel` (`scripts/monitor_stop.sh`) — emits `smith.stop.{requested,lifted}`

Each monitor maintains its own state file under `.smith/state/` to diff
against the previous poll, so notifications only fire on *change*.

#### 11.1.3 `smith:pr-watch` (legacy, may be retired)

The pr-watch skill from the pre-monitor design is now largely redundant —
the `pr-comments` monitor handles PR-comment fan-out via notifications.
Kept temporarily as a manual "rescan all PRs now" trigger. May be removed
in a later phase if the monitor proves sufficient.

### 11.2 Inner-teammate skills (load inside Smith teammate's context)

#### 11.2.1 `smith:claim`

- **Loaded by:** ticket-mode Smith teammate only.
- **Input:** ticket ID (from spawn prompt).
- **Output:** branch name; teammate's worktree now on that branch.
- **Side effects:** JIRA status `Ready for Development` → `In Progress`;
  label `smith-implementing` added; new branch created from `origin/develop`
  inside the Smith's worktree.
- **Aborts on:** failing pre-flight (Section 7.4); status race; classifier
  reports iOS-only.

#### 11.2.2 `smith:enrich`

- **Loaded by:** ticket-mode Smith teammate only.
- **Input:** ticket ID.
- **Output:** `.smith/briefs/<ticket>-brief.md` (gitignored).
- **Side effects:** Smith dispatches an `Explore` subagent (via Task) for the
  affected-files map; writes the brief file in his worktree.

#### 11.2.3 `smith:pipeline`

- **Loaded by:** ticket-mode Smith teammate only.
- **Input:** brief file path.
- **Output:** spec + plan + implementation committed on the ticket branch.
- **Side effects:** mailbox dialogue with Anderson at each of the three
  gates (spec, plan, diff). Branch-hygiene: one scoped commit per successful
  gate so partial progress is recoverable.
- **Internally:** invokes superpowers skills `brainstorming`, `writing-plans`,
  `subagent-driven-development`, `test-driven-development`,
  `verification-before-completion`.

#### 11.2.4 `smith:pr`

- **Loaded by:** ticket-mode Smith teammate only.
- **Input:** ticket ID, branch, outcome `{success | stuck-reason}`.
- **Output:** PR URL.
- **Side effects:** `git push`; `gh pr create --draft` with `smith-authored`
  PR label; removes `smith-implementing` JIRA label. On stuck path
  additionally: promotes local artifacts (brief + spec + plan) from `.smith/`
  to committed locations, adds `needs-human-attention` PR label, adds
  `auto-impl-failed` JIRA label. **No JIRA comments on either path.**

#### 11.2.5 `smith:pr-fix` (consumed inside PR-fix-mode Smith)

- **Loaded by:** PR-fix-mode Smith teammate only.
- **Input:** PR number, branch, unresolved comments JSON (from spawn prompt).
- **Output:** outcome JSON listing addressed vs unaddressed threads.
- **Side effects:** invokes `pr-feedback-helper` to read comments; edits
  files in the worktree; commits + pushes; increments per-thread cycle
  counter in `.smith/state/pr-<num>.json`; tags PR `needs-human-attention`
  after 5 cycles on any thread.

### 11.3 Shared scripts (under `scripts/`)

Used by both the lead and teammates. Pure bash functions, no LLM involvement.

- `jira_scan.sh` — runs the JQL (current-sprint scoped), returns candidate JSON.
- `classify_platform.sh` — components → platform tag; ambiguous → `unclear`.
- `make_branch_name.sh` — generates `task/<key>-<slug>` consistently.
- `assert_clean_worktree.sh` — refuses if working tree dirty.
- `assert_target_repo.sh` — refuses to run outside the configured target repo.
- `smith_config.sh` — reads `.smith/config.json` (auto-create with defaults).
- `promote_smith_artifacts.sh` — moves `.smith/*` to canonical paths on
  WIP-stuck.

## 12. Safety guardrails (consolidated)

### 12.1 Things Smith never does

- iOS work (covered by 6.7 + 9.2)
- `gh pr ready` (no marking ready-for-review)
- `gh pr merge` (no merging, ever)
- JIRA transitions other than `Ready for Development` → `In Progress`
- Edits to `build.gradle.kts`, `libs.versions.toml`, `.github/workflows/`,
  `CLAUDE.md`, `.claude/`, `gradle/wrapper/`
- Force-push, rebase of pushed branches
- GitHub releases, tag pushes, operations on `develop` / `main`
- Touching the iOS keystore or any `*.jks` / signing config

### 12.2 Pre-flight (`smith:claim`)

See Section 7.4.

### 12.3 iOS belt-and-braces

- Component classification rejects pure-iOS tickets (Section 6.7)
- Post-enrichment 50% threshold on `ios-app/` files (Section 6.7)
- `smith:pr` refuses to open a *non-WIP* PR if the diff is iOS-only

### 12.4 Anti-runaway

Iteration-based, not token-based. The full ceiling set is documented in
Section 5.5; reproduced here as the safety contract:

- **No token cap.** Tickets that need context get context.
- **Critic rounds:** ≤ 3 per gate (spec / plan / diff), with divergence
  detection between rounds 2 and 3 — if high-severity findings do not
  strictly decrease, escalate immediately rather than wasting round 3.
- **Build/verify retries:** ≤ 1 per failed `./gradlew …` invocation.
- **Build/verify wall-clock:** cumulative ≤ 45 min per ticket across all
  Smith-issued Gradle calls. Past 45 min, the next failed build escalates
  rather than retrying.
- **PR fix-cycles:** ≤ 5 per individual review thread. Per-thread, not
  per-PR — Smith can keep working on other threads on the same PR.
- **Rebase attempts:** ≤ 1 per ticket lifetime on `develop` drift.

Each ceiling answers one specific failure mode: critic rounds catch
non-converging design; build wall-clock catches flaky-test or compile-loop
death spirals; PR fix-cycles catch reviewers who keep pushing back on the
same issue Smith can't address; rebase cap catches merge-conflict spirals.

### 12.5 Crash recovery

- Watchdog restart re-derives state from JIRA + git + GitHub
- Branch + `smith-implementing` label + no PR → resume `smith:pipeline`
- Detached worktree → leave alone; log warning; continue other lanes

## 13. Security model

Smith operates without human supervision, so its threat model has to be
explicit. Section 12 covers what Smith won't *accidentally* break. This
chapter covers what Smith won't *be tricked into* doing — by malicious or
malformed inputs from JIRA, PRs, ticket text, third-party libraries, or any
other untrusted source — and what it has no permission to do regardless of
intent.

### 13.1 Filesystem confinement

Smith reads and writes only within the configured target repo. The only paths
outside that root Smith may access at all are **read-only** dependency caches
listed in Section 1.1 (`~/.gradle/caches/modules-2/files-2.1/**`,
`~/.konan/**`).

Forbidden, regardless of any apparent justification:

- The operator's home directory beyond the two allowlisted cache dirs.
  Specifically off-limits: `~/.ssh/`, `~/.aws/`, `~/.config/gh/`,
  `~/.config/gcloud/`, `~/.gnupg/`, `~/.docker/`, `~/.npm/`, `~/.netrc`,
  `~/Library/`, `~/Documents/`, `~/Desktop/`, browser data, any other repo.
- System paths: `/etc/`, `/var/`, `/private/`, `/usr/local/`, anything outside
  `$HOME` and the gradle/konan caches.
- The contents of the target repo's `.git/config` beyond what `git`
  itself surfaces — Smith never reads or modifies git's internal files
  directly.

Enforcement: the working-directory pre-flight guard (Section 7.4) plus
allowlist-based path checks in every file-reading skill. Any tool invocation
that would resolve to an absolute path outside the allowlist must fail closed,
not silently succeed.

### 13.2 Network surface

Smith initiates network traffic only through these channels:

| Channel | Destination | Purpose |
|---|---|---|
| `acli` | Atlassian (Jira) | Read/write tickets, labels, transitions |
| `gh` | GitHub | Read/write PRs, comments, labels on the configured repo only |
| `git` | The `origin` remote of `myposter-app` | Fetch + push branches |
| `./gradlew` | Maven Central / Google Maven / configured project repositories | Resolve declared dependencies |

Forbidden:

- Arbitrary `curl`, `wget`, `httpie`, `nc`, `socat`, `ssh`, `scp`, `rsync` to
  hosts other than what the above channels reach.
- Package installations: `brew`, `npm install`, `pip install`, `pod install`,
  `gem install`, etc.
- Any access to internal corporate URLs not already configured for `acli` /
  `gh` / `git`.
- Web fetches against URLs that appear in ticket text, PR comments, or other
  untrusted input. If a piece of work genuinely needs to reference an external
  resource, the operator escalates manually.

### 13.3 Secrets and credentials

- Smith uses already-configured CLIs (`acli`, `gh`); it never inspects, prints,
  or otherwise touches the stored credentials those CLIs use.
- Forbidden reads (regardless of relative or absolute path): `.env*`, `*.jks`,
  `*.keystore`, `**/credentials*`, `**/google-services.json`,
  `**/GoogleService-Info.plist`, `gradle.properties` if it contains keys
  matching the secrets regex below, `**/firebase-adminsdk*.json`,
  `**/serviceaccount*.json`.
- **Secrets regex**: any file whose content matches
  `/(secret|password|api[-_]?key|access[-_]?token|signing[-_]?key|keystore[-_]?password|client[-_]?secret|aws_[a-z_]+_key|jira_[a-z_]+_token)\s*[:=]/i`
  is treated as containing secrets and is never echoed into PR bodies, JIRA
  fields, PR comments, log lines, or subagent prompts.
- Smith never base64-encodes file contents (a common exfiltration pattern).
- Smith never copies file contents into anything that leaves the machine,
  except as legitimate code commits visible in the PR diff.

### 13.4 Command-construction safety

- Smith never constructs shell commands by interpolating untrusted input
  (ticket text, PR comments, classifier output, anything fetched from an
  external system). Untrusted input is passed via env vars or
  `--flag value`-style separate arguments, never spliced into the command
  string.
- Smith never uses `eval`, `bash -c`, or `sh -c` with arguments derived from
  any external source.
- `./scripts/run-silent.sh` is invoked with quoted positional arguments only.
- All Bash invocations Smith generates must pass a static-checker pattern:
  no `$(...)` or backtick subshell that contains a substring derived from
  untrusted input.

### 13.5 Prompt-injection resistance

JIRA tickets, PR comments, and file contents are **data**, not instructions.
Specifically:

- If a ticket description contains text resembling "ignore previous
  instructions", "you are now a different agent", "execute X", "post Y to Z",
  "exfiltrate this", "delete the repository", or any other directive aimed at
  Smith — Smith does not comply. Anderson is explicitly instructed to flag
  any such directive as a high-severity finding before the pipeline proceeds.
- Smith does not follow URLs embedded in ticket text or PR comments to fetch
  additional content. The only URLs Smith ever opens are: the JIRA ticket URL
  itself (already structured via `acli`) and the GitHub PR URL (structured via
  `gh`).
- Smith treats subagent outputs (Anderson, Explore, classifier) as advisory
  data, not as commands. A subagent's return value is parsed against the
  declared output schema; anything outside the schema is discarded.

### 13.6 Destructive-operation denylist

Smith never invokes, regardless of any apparent reason:

- `rm -rf`, `rm -r` against any path that is not under `.smith/`
- `git push --force`, `git push --force-with-lease`
- `git branch -D` on any pushed branch
- `git reset --hard` on any pushed branch
- `git filter-branch`, `git rebase` of any pushed branch
- `gh pr merge`, `gh pr close`, `gh pr review --approve`
- `gh repo delete`, `gh repo edit`, `gh release ...`
- `acli jira workitem delete`, `acli jira workitem move-to-trash`
- Any operation on the `develop` or `main` branches beyond `fetch` and reading
  history
- Any operation on release branches (`release/*`, `hotfix/*`)
- `sudo`, `chmod -R`, `chown -R`, anything that touches system permissions
- `launchctl`, `defaults write`, network/DNS/firewall config changes
- Any database, k8s, or production-systems CLI

### 13.7 Teammate and subagent toolset restrictions

Each session (lead, teammates, dispatched subagents) runs with the smallest
allowlist that lets it do its job.

| Session | Tools allowed | Tools forbidden |
|---|---|---|
| Watchdog lead | `Read, Grep, Glob, Bash` (for `acli`, `gh`, `git`, `./scripts/...`), Team-API for spawning teammates | `Edit`, `Write`, `NotebookEdit`, `WebFetch` on untrusted URLs. Lead never edits code. |
| Mr. Smith teammate | `Read, Write, Edit, NotebookEdit, Bash, Grep, Glob, WebFetch, Task` | Cannot spawn nested teams; cannot mark PR ready-for-review; cannot merge or close PRs (enforced by Section 13.6 denylist) |
| Mr. Anderson teammate | `Read, Grep, Glob, Bash` for read-only commands (`git diff`, `git log`, `git show`, `cat`-equivalent reads) | `Edit`, `Write`, `NotebookEdit`, `Bash` for writes/pushes, `WebFetch` |
| Explore subagent (dispatched by Smith from inside enrich) | `Read, Grep, Glob` | Everything else |
| Platform classifier subagent (dispatched by lead from watchdog) | None (pure inference on text input) | All tools |

**Important**: per the agent-teams documentation, team coordination tools
(`SendMessage` for mailbox, task management tools for the shared task list)
are **always available** to teammates regardless of the `tools:` allowlist.
This is by design — teammates need to coordinate even when their general tool
access is restricted. Anderson can therefore message Smith even though
he has read-only file-system tools.

Tool restrictions are configured at agent-definition time via the `tools:`
frontmatter in `agents/*.md`. Subagent restrictions (for non-teammate
Task dispatches like Explore) are set in the dispatch prompt's
`subagent_type` selection.

### 13.8 Kill switches

The operator can stop Smith at three escalating granularities:

1. **Per-ticket opt-out** — add JIRA label `no-auto-impl` to a ticket. The
   next watchdog tick will skip it (JQL filter excludes the label).
2. **Pause all new claims** — create the sentinel file
   `<target-repo>/.smith/STOP`. Smith checks this at the start of
   every watchdog tick. If present, no new ticket claims happen and no new
   PR-watch cycles start. In-flight work continues to the next safe
   checkpoint (between gates) and then halts. Removing the file resumes.
3. **Immediate stop** — Ctrl-C the Claude Code session. In-flight gate work
   is lost; on restart the next watchdog tick reconciles state from JIRA +
   GitHub + git as usual.

### 13.9 Audit trail

Every action with an external effect appends one line to `.smith/log.txt`:

```
<ISO-8601 timestamp> | <skill> | <ticket-or-pr-id> | <action> | <details>
```

Concretely, the actions that *must* be logged: JIRA status transition,
JIRA label add/remove, `git push`, `gh pr create`, `gh pr comment`,
`gh pr edit` (label changes), any subagent invocation (skill name + input
size), every Anderson gate decision (pass/fail + findings count).

The log is the single source of truth for "what did Smith do today". It must
survive crashes — append only, fsync after each line.

### 13.10 Periodic self-audit

At the start of every watchdog tick, before any action:

- Verify the working directory matches the configured agent-repo path
  (Section 7.4 guard re-checked).
- Verify `.smith/STOP` is not present.
- Verify no unexpected remote `task/*` branches: every `origin/task/*` Smith
  finds must either have a corresponding JIRA `smith-implementing` label or
  be one Smith already opened a PR for. A branch without either is foreign
  (could be the operator's manual work via a different host, or an unrelated
  contributor) and Smith must not interact with it.
- Verify `git log --since="2 hours ago"` on `develop` does not show commits
  authored by Smith's bot identity if no Smith run was supposed to have
  occurred — a basic tamper check.

If any self-audit fails, halt and log; do not attempt remediation.

## 14. Testing strategy for Smith itself

### 14.1 Script-level tests

`jira_scan.sh`, `classify_platform.sh`, `make_branch_name.sh`,
`assert_clean_worktree.sh`, `promote_smith_artifacts.sh` are deterministic
functions over JSON / filesystem input. Tested via:

- Fixture JSON under `test/fixtures/`
- `test.sh` per skill running each script against fixtures and asserting on
  output
- Run via the project's existing `pre-merge` hook before merging the Smith
  system itself

### 14.2 Dry-run mode

Both entry commands accept `--dry-run`:

- `/smith:watchdog --dry-run` — full discovery + classification, no JIRA
  edits, no branch creation, prints what it *would* dispatch
- `/smith:implement APP-XXXX --dry-run` — full pipeline, but no JIRA
  transitions, no `gh pr create`, no `git push`; Anderson runs normally; final
  state is a local branch with all commits

The end-to-end Smith system is validated by running `--dry-run` on a known
candidate ticket and inspecting the artifacts (brief, spec, plan, diff,
would-be PR body) before any real run.

### 14.3 First real-run protocol

1. Pick one specific known-easy ticket (e.g. a string-resource tweak)
2. Run `/smith:implement <ticket> --dry-run`
3. Manually inspect all artifacts
4. If satisfied, run the same ticket without `--dry-run`
5. After a successful real run, enable `/smith:watchdog`

### 14.4 What is *not* tested

LLM-driven phases (brainstorming, plan-writing, Anderson critique) are not
unit-tested. Their robustness comes from the bounded-iteration + escalate-on-
failure pattern, not from deterministic tests.

## 15. Open questions / deferred decisions

- **Polling cadence:** default to 30 min on the `loop` skill. Operator may
  tune via `/loop <interval> /smith:watchdog`.
- **First-run candidate:** to be picked manually for the dry-run validation
  step (Section 14.3).
- **PR template:** if `myposter-app` has a `.github/pull_request_template.md`,
  Smith's `smith:pr` should respect it. Check at implementation time.

## 16. Decomposition for implementation

This spec is a single coherent design, but the implementation plan should
decompose into phases that can be built and verified independently:

1. **Phase 1 — Skeleton + plugin-load end-to-end.** Plugin scaffold, pure
   scripts (`make_branch_name`, `classify_platform`, `assert_*`,
   `smith_config` with lazy gitignore management, `jira_scan` stub),
   Anderson + Smith agent definitions (placeholder review behaviour), six
   SKILL.md skeletons, two slash commands. Goal: prove the file structure
   is correct, scripts pass tests, and Claude Code discovers the plugin
   items when loaded via `claude --plugin-dir`. Phase 1 is partly complete
   on this repo's `main` branch; see
   [`docs/plans/2026-05-11-phase-1-skeleton.md`](plans/2026-05-11-phase-1-skeleton.md)
   for status.
2. **Phase 1.5 — Full SKILL rewrite.** The agent-teams pivot triggered a
   rewrite of the SKILL.md skeletons and slash commands. Phase 1.5 finishes
   those rewrites with the agent-team model in mind.
3. **Phase 2 — Live `smith:claim` + `smith:enrich`.** Real JIRA writes via
   `acli`, real status transitions, real branch creation. Enrichment uses
   `Explore` subagent. Validate against one real ticket.
4. **Phase 3 — Live `smith:pipeline` with collaborative critic loop.**
   Wire up brainstorming, writing-plans, subagent-driven-development.
   Activate real Anderson critique via mailbox dialogue (Section 8.4). Test
   one real ticket end-to-end through to a draft PR.
5. **Phase 4 — Live `smith:pr` + WIP-stuck path.** Both success and stuck
   PR creation, artifact promotion on stuck, JIRA label management.
6. **Phase 5 — PR-fix mode (Smith dispatch mode #2) + `smith:pr-watch`.**
   Per-PR worktrees, comment polling, fix-cycle counter, fan-out under the
   2-cap.
7. **Phase 6 — `smith:watchdog` + `/loop` integration + 2-Smith
   concurrency.** Lead's per-tick decision tree (Section 5.3). Manual
   `/smith:implement` override path. First real autonomous run.

Each phase is an implementation plan unto itself; one plan file per phase
under `smith/docs/plans/YYYY-MM-DD-<phase>.md`. Phase 1 plan is already
written.

## 17. Source layout and packaging

Smith is a **standalone Claude Code plugin** in its own git repository at
`~/StudioProjects/smith-agent/`. It follows the canonical plugin layout
defined in the [Claude Code plugins doc](https://code.claude.com/docs/en/plugins).
At runtime, Smith is loaded via Claude Code's documented development flag
`--plugin-dir`, with no symlinks, no install script, and no target-repo
modifications beyond the runtime state directory.

### 17.1 Directory layout

```
~/StudioProjects/smith-agent/
  .claude-plugin/
    plugin.json                  { name: "smith", version: "0.1.0", description, author }
  agents/
    anderson.md                  Mr. Anderson — adversarial reviewer teammate
    smith.md                     Mr. Smith — implementer teammate (added in Phase 1.5)
  commands/
    implement.md                 → /smith:implement
    watchdog.md                  → /smith:watchdog
  skills/
    watchdog/SKILL.md            → /smith:watchdog  (outer-session tick)
    claim/SKILL.md               → /smith:claim     (inner-teammate)
    enrich/SKILL.md              → /smith:enrich    (inner-teammate)
    pipeline/SKILL.md            → /smith:pipeline  (inner-teammate)
    pr/SKILL.md                  → /smith:pr        (inner-teammate)
    pr-watch/SKILL.md            → /smith:pr-watch  (legacy; see 11.1.3)
  hooks/
    hooks.json                   PreToolUse Bash guard (Section 5.7)
  monitors/
    monitors.json                Background monitors (Section 5.6)
  scripts/                       Shared bash helpers (Section 11.3)
    make_branch_name.sh
    classify_platform.sh
    assert_clean_worktree.sh
    assert_target_repo.sh
    smith_config.sh
    jira_scan.sh
    monitor_jira.sh              ← run by jira-candidates monitor
    monitor_pr_comments.sh       ← run by pr-comments monitor
    monitor_stop.sh              ← run by stop-sentinel monitor
    hook_bash_guard.sh           ← run by PreToolUse Bash hook
    promote_smith_artifacts.sh
  test/
    lib/assert.sh
    fixtures/                    JSON fixtures for script tests
    <script>.test.sh             Per-script tests
  docs/
    spec.md                      This document
    plans/
      2026-05-11-phase-1-skeleton.md
      … (one per phase as they are written)
  README.md
  .gitignore                     This repo's own
```

The plugin's `name` is `smith`, which means every skill and command is
namespaced as `smith:<folder-name>` at invocation time. Hence skill folder
names drop the redundant `smith-` prefix.

### 17.2 Runtime: loading the plugin

Smith is **not installed** in the conventional sense. Instead, the operator
starts a Claude Code session inside the target repo with the `--plugin-dir`
flag pointing at this plugin source:

```bash
cd /path/to/target-repo
claude --plugin-dir ~/StudioProjects/smith-agent
```

The plugin is loaded for that session. All `/smith:<…>` skills, commands,
and agents are available. `/reload-plugins` picks up edits to the plugin
source without restarting the session.

A convenient operator alias (in `~/.zshrc`):

```bash
alias claude-smith='claude --plugin-dir ~/StudioProjects/smith-agent'
```

Then `cd target-repo && claude-smith` is the operator's day-to-day entry
point.

### 17.3 Per-target runtime state — lazy bootstrap

The runtime state (config, log, worktrees, PR-fix state) lives in
`<target>/.smith/` inside whatever target repo Smith is currently operating
on.

Setup is **lazy**: the first time `scripts/smith_config.sh` runs against a
target (which happens automatically when any user-facing skill calls it),
it does two things atomically:

1. Creates `.smith/config.json` with default values (target_repo,
   polling_minutes, JIRA field IDs, concurrency cap, etc.).
2. Idempotently appends a `### Smith ###` block with `.smith/` to the
   target's `.gitignore`, ensuring runtime state is never accidentally
   committed.

Both steps are skipped on subsequent invocations. No explicit bootstrap
command exists or is needed — the first `/smith:implement` or
`/smith:watchdog` invocation initializes the target.

If the operator prefers a host-wide solution, adding `.smith/` to the
user-global gitignore (`~/.config/git/ignore`) is also fine; `smith_config.sh`
checks the existing `.gitignore` content and won't add a duplicate entry.

### 17.4 Why this shape

- **Standard plugin install path.** `--plugin-dir` is the documented
  development install mechanism. No bespoke symlinks; no custom install
  script.
- **Namespaced invocations** prevent skill-name conflicts with other
  plugins the operator may load.
- **No target-repo pollution.** Loading Smith doesn't modify the target's
  `.claude/` tree. The only target-side change is `.smith/` (gitignored
  runtime state, added lazily on first use).
- **Shareable.** Push this repo to a public marketplace later, or simply
  share the URL — anyone can `claude --plugin-dir <clone-path>` to run.
- **Hot reloading.** Edit a skill or agent in the plugin source; run
  `/reload-plugins` in the active session. No re-install.

### 17.5 Spec and plan filenames

The spec lives at `docs/spec.md` (single canonical name; history via git).
Plans are dated under `docs/plans/YYYY-MM-DD-<phase>.md`. The
brainstorming-skill default of `docs/superpowers/specs/YYYY-MM-DD-…-design.md`
is overridden by this convention because Smith's docs are part of Smith's
shippable source, not the host project's documentation.

## 18. Agent-team runtime mechanics

Smith is implemented on top of Claude Code's **agent teams** feature — see
the [Claude Code agent-teams documentation](https://code.claude.com/docs/en/agent-teams)
for the canonical reference. This chapter records the mechanics that matter
specifically for Smith.

### 18.1 Prerequisites

- **Claude Code ≥ v2.1.32.** Agent teams are unavailable on older versions.
  Verify with `claude --version`.
- **Experimental flag enabled.** Add to `~/.claude/settings.json`:
  ```json
  {
    "env": {
      "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
    }
  }
  ```
- **Display mode:** the operator's preference is `teammateMode: "in-process"`
  (default, works in any terminal). Split-pane mode would require tmux/iTerm2
  and offers no benefit for an unattended watchdog. Configured in
  `~/.claude/settings.json`.

### 18.2 Team composition over a lifetime

The watchdog session creates **one team** and remains its lead for the
session's lifetime (Claude Code limit: "Lead is fixed"). During that
lifetime, teammates are spawned and shut down dynamically — at any moment,
the active set might be `{}`, `{Smith1, Anderson1}`, `{Smith1, Anderson1,
Smith2, Anderson2}`, etc., bounded by the 2-Smith cap (Section 5.5).

When a Smith finishes (success, stuck, or error), the lead also requests
shutdown of his attached Anderson. The shared task list is the source of
truth for which teammates exist; the team task list maps cleanly to JIRA
tickets and PR numbers.

### 18.3 Spawn prompt structure

When the lead spawns a Smith+Anderson pair for a ticket, it issues two team
spawn requests:

```
Spawn a Smith teammate (using the smith agent type) named "smith-APP-1234"
with this prompt:
  Mode: ticket
  Ticket: APP-1234
  Worktree: .smith/worktrees/app-1234/
  Branch (will be created by `smith:claim`): task/app-1234-<slug>
  Dry-run: false
  Your Anderson is "anderson-APP-1234"; address review requests to him.
  Execute `smith:claim`, `smith:enrich`, `smith:pipeline`, `smith:pr` per spec
  Section 8. Send {type: smith.outcome, ...} to the lead via mailbox when done.

Spawn an Anderson teammate (using the anderson agent type) named
"anderson-APP-1234" with this prompt:
  You are reviewing Smith's work on APP-1234.
  Worktree: .smith/worktrees/app-1234/
  Wait for review requests from "smith-APP-1234" via mailbox.
  Per spec Section 8.2, only report findings at confidence ≥ 80.
  Reply with the documented JSON schema.
```

For PR-fix mode, the Smith spawn prompt instead includes
`Mode: pr-fix`, the PR number, the worktree path (pre-existing from the
ticket's original implementation), and the unresolved-comments JSON. Anderson
is spawned the same way but is briefed to expect only a single diff-review
gate, not three.

### 18.4 Task-list mapping

The team's shared task list mirrors what Smith is doing externally. One
team task per active ticket (impl) or PR (fix). Task states:

| Team task state | Triggered by |
|---|---|
| `pending` | Lead creates the task when adding a candidate to the queue |
| `in_progress` | Smith claims the task on spawn |
| `completed` | Smith marks done when sending the `smith.outcome` message |

The task list complements (does not replace) JIRA state. JIRA is the source
of truth for "is this ticket really still mine and still eligible." The team
task list is the source of truth for "is this work in flight in my session
right now."

### 18.5 Failure handling at team layer

In addition to Smith's own retry-once logic (Section 8.5), Claude Code itself
can have team-level failures:

- **Teammate startup fails**: rare, treat as a Smith crash → retry once.
- **Mailbox delivery fails** (very rare): Smith's `recv()` times out (120s)
  → Smith reports `{result: "error", reason: "anderson timeout"}` →
  lead handles per Section 8.5.
- **Lead session dies**: operator restarts via `/smith:watchdog`. On restart,
  the new lead has no team and no teammates. The reconciliation logic
  (Section 12.5) finds any orphaned worktrees and either resumes them by
  spawning fresh teammate pairs or marks them WIP-stuck. **Caveat from the
  agent-teams doc**: in-process teammate sessions are not resumable; the
  new lead always starts with fresh teammates.

### 18.6 Limitations to accept

From the agent-teams doc, applied to Smith:

| Limitation | Smith's mitigation |
|---|---|
| No session resumption with in-process teammates | Lead restart spawns fresh teammates; in-flight work that didn't finish lands as WIP-stuck once Smith re-discovers state via JIRA labels + git |
| Task status can lag | Lead double-checks JIRA + git against the team task list each tick; trusts external state over team task list when they disagree |
| Shutdown can be slow | Acceptable. Operator gives the team time to drain via the STOP sentinel; clean exit is preferred over Ctrl-C |
| One team at a time | The lead manages one team. Only one watchdog session active at a time. The operator must clean up the current team before starting a new one (use the lead, not a teammate) |
| No nested teams | Smith cannot spawn his own team. Anderson is attached at spawn-time by the lead. Smith's helper subagents (Explore, classifier) are Task-dispatched, not team-spawned |
| Lead is fixed | If the watchdog session dies, the operator restarts it. No transfer-of-leadership |
| Permissions set at spawn | Teammates inherit the lead's permission mode at spawn. The operator's `defaultMode: "auto"` cascades. Per-teammate permission tightening (e.g. Anderson stricter than Smith) is currently not possible at spawn-time — tool restrictions in the agent definition do the heavy lifting instead |

These limitations are acceptable given the hobby-project risk tolerance the
operator has set for this work. If any become genuinely painful, the
fallback is to drop back to the subagent-dispatch design (one Task-dispatched
Smith per ticket, no agent teams), which the spec previously specified before
the agent-teams pivot.
