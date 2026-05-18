#!/usr/bin/env bash
# PreToolUse hook (matcher: Task). Denies any Task dispatch whose
# `subagent_type` is one of Smith's or Anderson's agent types — those
# MUST be spawned via Claude Code's agent-teams feature (long-lived
# teammates), not via the Agent/Task tool (one-shot subagents).
#
# Why: a one-shot subagent exits after its first turn. Smith and
# Anderson coordinate over multiple mailbox round-trips (one per gate
# for impl; per-finding triage + final diff for fixer). If they are
# spawned as subagents, Anderson dies after one reply and Smith ends
# up self-reviewing — which defeats the whole adversarial design.
#
# Lead-session spawn discipline is documented in:
#   - commands/implement.md  ("Spawn the teammate pair")
#   - commands/watchdog.md   (pre-flight assert_agent_teams_enabled)
#   - skills/watchdog/SKILL.md  ("Spawn mechanism: agent-teams")
#
# On match: emit a permissionDecision: "deny" with a remediation
# message. On no match: silent allow. Other Task dispatches (e.g. an
# Explore subagent fired by Smith from inside enrich) pass through —
# only the four Smith/Anderson types are guarded.

set -uo pipefail

payload=$(cat)
subagent_type=$(jq -r '.tool_input.subagent_type // empty' <<< "$payload" 2>/dev/null || echo "")

if [[ -z "$subagent_type" ]]; then
  exit 0
fi

# Test-only debug: print parsed subagent_type to stderr.
if [[ "${SMITH_HOOK_DEBUG:-0}" == "1" ]]; then
  printf '%s' "$subagent_type" >&2
fi

case "$subagent_type" in
  smith-impl|anderson-impl|smith-fixer|anderson-fixer)
    reason="smith agent-teams guard: \"${subagent_type}\" must be spawned as a long-lived teammate via Claude Code's agent-teams feature, NOT via the Agent/Task tool. The Agent tool produces a one-shot subagent that exits after its first reply, which breaks the multi-turn mailbox protocol between Smith and Anderson and leaves Smith self-reviewing. Re-issue the dispatch using natural-language team-creation phrasing per commands/implement.md (\"Spawn the teammate pair\"); do not retry with the Agent/Task tool."
    jq -nc --arg reason "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
    exit 0
    ;;
esac

exit 0
