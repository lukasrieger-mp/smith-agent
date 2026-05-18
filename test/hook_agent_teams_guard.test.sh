#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

GUARD="${ROOT}/bin/hook_agent_teams_guard.sh"

# Run guard with a tool_input.subagent_type payload and capture stdout.
run_guard() {
  local subagent_type="$1"
  jq -nc --arg t "$subagent_type" '{
    hook_event_name: "PreToolUse",
    tool_name: "Task",
    tool_input: { subagent_type: $t, prompt: "irrelevant" },
    cwd: "/tmp",
    session_id: "test"
  }' | bash "$GUARD"
}

# Returns "deny" or "" based on guard output.
guard_decision() {
  run_guard "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null
}

guard_reason() {
  run_guard "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null
}

# --- Should DENY (the four guarded agent types) ---

for t in smith-impl anderson-impl smith-fixer anderson-fixer; do
  got=$(guard_decision "$t")
  assert_eq "deny" "$got" "deny-$t"
  reason=$(guard_reason "$t")
  case "$reason" in
    *"agent-teams"*) ;;
    *) echo "FAIL: deny reason for $t should mention agent-teams; got: $reason" >&2; exit 1 ;;
  esac
done

# --- Should ALLOW (legitimate subagent types used inside teammates) ---

for t in Explore general-purpose Plan code-reviewer; do
  out=$(run_guard "$t")
  if [[ -n "$out" ]]; then
    echo "FAIL: guard should be silent for $t; got: $out" >&2
    exit 1
  fi
done

# --- Should ALLOW (no subagent_type field at all — e.g. a non-Task call) ---

out=$(jq -nc '{
  hook_event_name: "PreToolUse",
  tool_name: "Task",
  tool_input: { prompt: "no subagent_type field" },
  cwd: "/tmp",
  session_id: "test"
}' | bash "$GUARD")
if [[ -n "$out" ]]; then
  echo "FAIL: guard should be silent when subagent_type is absent; got: $out" >&2
  exit 1
fi

echo "OK: hook_agent_teams_guard"
