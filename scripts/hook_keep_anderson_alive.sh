#!/usr/bin/env bash
# TeammateIdle hook. Fires when an agent-teams teammate is about to go
# idle. If the teammate is an Anderson, exit 2 with a "stay alive"
# message so Claude Code keeps the teammate alive and pings it back to
# work. For any other teammate (or the lead), exit 0 and let the idle
# proceed.
#
# Why: Anderson must stay alive for the entire lifetime of a Smith
# ticket / PR-fix cycle, across multiple gates. Left alone after one
# mailbox round-trip, an LLM teammate hits a "I'm done here" point and
# self-terminates, which strands Smith with no reviewer. The pair-spawn
# verification on the lead side catches missing-from-the-start cases;
# this hook catches the mid-run shutdown case.
#
# Available env vars (per Claude Code hook env):
#   CLAUDE_TEAMMATE_NAME  — the teammate's name (e.g. anderson-app-5601)
#   CLAUDE_TEAMMATE_TYPE  — the teammate's agent type (e.g. anderson)

set -uo pipefail

name="${CLAUDE_TEAMMATE_NAME:-}"
type="${CLAUDE_TEAMMATE_TYPE:-}"

is_anderson=0
[[ "$type" == "anderson" ]] && is_anderson=1
[[ "$name" == anderson-* ]] && is_anderson=1

if (( is_anderson )); then
  cat >&2 <<'EOF'
Do not go idle. Your job is to stay available for Smith's review
requests across every gate of his pipeline (spec, plan, diff) — or
for PR-fix-mode diff reviews. Smith may send another `review.request`
at any moment. If you have no message to process right now, that is
normal: wait. Only exit when you receive an explicit shutdown request
from the lead.
EOF
  exit 2
fi

exit 0
