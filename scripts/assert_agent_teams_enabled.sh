#!/usr/bin/env bash
# Verify CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is enabled. The Smith plugin
# depends on agent-teams for the Smith/Anderson teammate pair — without
# the flag, "spawn a teammate" silently falls back to one-shot Agent
# subagents, and Anderson can't persist across pipeline gates.
#
# Checks the live env var first, then ~/.claude/settings.json (where
# Claude Code reads it from on startup). Exits non-zero with a
# pointed message if neither is set.

set -uo pipefail

if [[ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" == "1" ]]; then
  exit 0
fi

settings="${HOME}/.claude/settings.json"
if [[ -f "$settings" ]]; then
  val=$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS // ""' "$settings" 2>/dev/null)
  if [[ "$val" == "1" ]]; then
    exit 0
  fi
fi

cat >&2 <<'EOF'
agent-teams not enabled

Smith needs the CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS feature flag.
Without it, "spawn the teammate pair" silently degrades to one-shot
Agent subagents — Anderson exits after his first turn and Smith is
stranded with no reviewer.

Fix:
  jq '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"' ~/.claude/settings.json \
    > ~/.claude/settings.json.tmp && mv ~/.claude/settings.json.tmp ~/.claude/settings.json

Then restart Claude Code. Verify with:
  jq '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' ~/.claude/settings.json
EOF

exit 1
