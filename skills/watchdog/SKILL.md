---
name: watchdog
description: Outer-session notification handler. Reacts to monitor events (jira/pr/stop) by dispatching Smith+Anderson pairs within the 2-cap. Invoke as /smith:watchdog to arm.
---

# Smith Watchdog (outer-session)

This skill is loaded in the **watchdog lead session** — the long-lived
Claude Code session the operator launches via
`claude --plugin-dir ~/StudioProjects/smith-agent`. It's the
counterpart to the `/smith:watchdog` slash command (which arms the
monitors by writing `.smith/state/watchdog-mode`).

For the full architectural picture, see `docs/spec.md` Sections 5 + 18.

## Role

The watchdog session never edits code. Its job is:

1. **Arm monitors** when `/smith:watchdog` is invoked.
2. **Receive notifications** from the running monitors.
3. **Dispatch teammate pairs** (Smith + Anderson) in response to
   notifications, respecting the 2-concurrency cap and kill switch.
4. **Track state**: the cap is enforced via
   `scripts/active_smiths.sh`; the kill-switch flag lives in your
   in-context working memory.

Code-editing happens entirely inside teammate subsessions — never in
the lead.

## State you maintain in working memory

- `smith_stop_active`: boolean, initially `false`. Toggled by
  `smith.stop.requested` / `smith.stop.lifted` notifications.

The cap-count is *not* in working memory — read it fresh from
`active_smiths.sh count` whenever you need it (defends against
restart-after-crash and against working memory drift).

## Watchdog mode (from the slash command)

The `/smith:watchdog` command writes the active mode to
`.smith/state/watchdog-mode` (either `full` or `pr-only`). Read this
file fresh whenever a `smith.jira.new_candidates` notification arrives
— do not cache it. Default to `full` if the file is missing.

In `pr-only` mode, the operator has signalled that they want this
session to focus on reviewer iteration on existing PRs without
picking up new tickets. The JIRA monitor still runs and emits
notifications; the lead simply ignores them.

## Notification reactions

### On `{"type": "smith.jira.new_candidates", "keys": [...]}`

```
if smith_stop_active: log "ignored (stopped)"; return
mode=$(cat .smith/state/watchdog-mode 2>/dev/null || echo full)
if [[ "$mode" == "pr-only" ]]: log "ignored (pr-only)"; return
active=$(bash $SMITH_PLUGIN_ROOT/scripts/active_smiths.sh count)
max=$(bash $SMITH_PLUGIN_ROOT/scripts/smith_config.sh max_concurrent_impl_smiths)
if [[ $active -ge $max ]]: log "ignored (cap $active/$max)"; return

# Fetch fresh candidates (notification keys may be stale by now)
candidates=$(bash $SMITH_PLUGIN_ROOT/scripts/jira_scan.sh)

# Pick the top key not already being worked on
key=$(echo "$candidates" \
     | bash $SMITH_PLUGIN_ROOT/scripts/pick_top_candidate.sh) \
  || { log "ignored (all candidates already active)"; return; }

# Dispatch: follow the /smith:implement command's flow exactly,
# without the manual --dry-run option (default: live)
dispatch_impl_mode "$key"
```

### On `{"type": "smith.pr.new_comments", "pr": N, "new_count": M, "branch": "..."}`

```
if smith_stop_active: log "ignored (stopped)"; return
active=$(bash $SMITH_PLUGIN_ROOT/scripts/active_smiths.sh count)
max=$(bash $SMITH_PLUGIN_ROOT/scripts/smith_config.sh max_concurrent_impl_smiths)
if [[ $active -ge $max ]]: log "ignored (cap $active/$max)"; return

# Is a Smith already on this PR?
if bash $SMITH_PLUGIN_ROOT/scripts/active_smiths.sh has-subject "$N" 2>/dev/null:
  log "ignored (already in flight)"; return

# Dispatch PR-fix mode
dispatch_pr_fix_mode "$N" "$branch"
```

### On `{"type": "smith.stop.requested"}`

```
smith_stop_active=true
log "stop requested — pausing new dispatches"
# Optional: message in-flight Smith teammates to wrap up cleanly.
```

### On `{"type": "smith.stop.lifted"}`

```
smith_stop_active=false
log "stop lifted — resuming new dispatches"
# No automatic catch-up; next real notification picks up where we paused.
```

## Dispatch sub-routines

These are not separate skills — they are the same flow `/smith:implement`
already documents in its slash command body. The watchdog inlines them.

**Spawn mechanism: agent-teams, not the `Agent` tool.** Smith and
Anderson must be spawned as long-lived teammates via the agent-teams
mechanism (natural-language team creation per
`docs/agent-teams` — see the example phrasing in
`commands/implement.md`). The plain `Agent` tool produces one-shot
subagents that exit after their first turn and would strand Smith with
no Anderson at the first review gate. The agent-teams flag must be
enabled (the watchdog command's pre-flight verifies this; without it,
the dispatch will silently degrade).

### `dispatch_impl_mode <key>`

1. Run `/smith:implement <key>`'s pre-flight (assert_target_repo,
   acli verify, classify_platform) inline. If pre-flight rejects,
   log and return.
2. Compute branch name with `make_branch_name.sh`.
3. Create the worktree with `make_worktree.sh <key> <branch>`.
4. Spawn the teammate pair (`smith-impl-<key>`, `anderson-impl-<key>`) via the
   agent-teams API. Spawn prompt per spec Section 18.3, mode=ticket.
   **Both spawns are required.** After spawning, list active teammates
   and confirm both names came up — a missing Anderson means Smith
   will abort the ticket with `{result: "error", reason: "anderson
   not reachable"}`, wasting the slot. If one didn't spawn, retry it;
   if still missing, do not register the pair, log
   `dispatch.failed-pair-spawn`, and return.
5. Register the pair:
   ```
   bash $SMITH_PLUGIN_ROOT/scripts/active_smiths.sh add \
        "smith-impl-$key" "anderson-impl-$key" impl "$key"
   ```
6. Log: `<ts> | watchdog | dispatch.impl | key=$key`

### `dispatch_pr_fix_mode <pr> <branch>`

1. Run pre-flight (assert_target_repo).
2. Check out the existing branch:
   `bash $SMITH_PLUGIN_ROOT/scripts/checkout_pr_worktree.sh <key> <branch>`
   where `<key>` is derived from the branch suffix (e.g.,
   `task/app-1234-foo` → key `APP-1234`).
3. Spawn the teammate pair (`smith-pr-$pr`, `anderson-pr-$pr`) per
   spec Section 18.3 PR-fix variant. Same rule as ticket mode: verify
   both teammates exist after the spawn calls. Smith aborts on missing
   Anderson, so a half-spawned dispatch wastes the slot.
4. Register:
   ```
   bash $SMITH_PLUGIN_ROOT/scripts/active_smiths.sh add \
        "smith-pr-$pr" "anderson-pr-$pr" pr-fix "$pr"
   ```
5. Log: `<ts> | watchdog | dispatch.pr-fix | pr=$pr`

## On teammate completion

When Smith sends a `smith.outcome` mailbox message:

1. Log the outcome JSON to `.smith/log.txt`.
2. Remove the pair from active-smiths:
   ```
   bash $SMITH_PLUGIN_ROOT/scripts/active_smiths.sh remove "$smith_name"
   ```
3. The Anderson teammate shuts down (the agent-teams shutdown hook
   handles this; you don't need to do it explicitly).

## Logging format

Append one line per notification AND per dispatch decision (including
"ignored" cases) to `<target>/.smith/log.txt`:

```
<ISO-8601 ts> | watchdog | <notification-type-or-action> | <details>
```

Examples:
```
2026-05-11T14:32:00Z | watchdog | smith.jira.new_candidates | keys=APP-5601; chose APP-5601
2026-05-11T14:32:01Z | watchdog | dispatch.impl | key=APP-5601
2026-05-11T15:14:23Z | watchdog | smith.pr.new_comments | pr=4321 new_count=2; ignored (cap 2/2)
2026-05-11T15:30:00Z | watchdog | smith.outcome | smith-impl-APP-5601 result=success pr=https://github.com/...
```

## Operational caveats

The dispatch flow above relies on the agent-teams spawn API, which is
LLM-driven (Claude composes the spawn prompt and the team API
handles spawn-and-track). The watchdog's correctness depends on:

- The agent (you, when this skill is loaded) actually invoking
  `active_smiths.sh add` after each spawn — without that, the cap can
  drift
- The teammate Smith actually sending the outcome mailbox before going
  idle — without that, `active_smiths.sh remove` is never called and
  the entry leaks until the session ends

Both are documented as Smith's contract (`agents/smith-impl.md` "Outcome
JSON schema"). The schema validator and the log line gate help catch
drift. A future iteration could add a `TeammateIdle` hook to force
cleanup; that's flagged as future work in spec Section 5.7.