#!/usr/bin/env bash
# TeammateIdle hook. Fires when an agent-teams teammate is about to go
# idle. If the teammate is an Anderson, exit 2 with a "stay alive"
# message so Claude Code keeps the teammate alive and pings it back to
# work. For any other teammate (or the lead), exit 0 and let the idle
# proceed.
#
# Why: Anderson must stay alive for the entire lifetime of a Smith
# ticket (impl pair, three gates) or one PR-fix round (fixer pair,
# triage + diff). Left alone after one
# mailbox round-trip, an LLM teammate hits a "I'm done here" point and
# self-terminates, which strands Smith with no reviewer. The pair-spawn
# verification on the lead side catches missing-from-the-start cases;
# this hook catches the mid-run shutdown case.
#
# Identity detection: hooks receive a JSON payload on stdin. Since the
# Claude Code v2.1.178 agent-teams rework, the exact teammate fields in
# the TeammateIdle payload are not documented, so we probe several
# plausible keys and fall back to the pre-rework CLAUDE_TEAMMATE_NAME /
# CLAUDE_TEAMMATE_TYPE env vars. The raw payload is captured once per
# session to .smith/state/teammate-idle-payload.json so the real field
# names can be verified from a live run (and this probe list trimmed).

set -uo pipefail

payload=""
if [[ ! -t 0 ]]; then
  payload=$(cat 2>/dev/null || true)
fi

# One-time payload probe for empirical verification. Best-effort; never
# let it fail the hook.
probe=".smith/state/teammate-idle-payload.json"
if [[ -n "$payload" && ! -f "$probe" ]] && mkdir -p "$(dirname "$probe")" 2>/dev/null; then
  printf '%s\n' "$payload" > "$probe" 2>/dev/null || true
fi

# Candidate keys for the teammate's name and agent type, in order of
# plausibility. jq's `//` chain returns the first non-null/non-false hit.
name=""
type=""
if [[ -n "$payload" ]] && command -v jq >/dev/null 2>&1; then
  name=$(jq -r '(.teammate_name // .teammate.name // .agent_name // .name // empty)' <<<"$payload" 2>/dev/null || true)
  type=$(jq -r '(.teammate_type // .teammate.agent_type // .agent_type // .subagent_type // empty)' <<<"$payload" 2>/dev/null || true)
fi

# Fallback: pre-v2.1.178 hook env vars (kept in case they still exist).
[[ -z "$name" ]] && name="${CLAUDE_TEAMMATE_NAME:-}"
[[ -z "$type" ]] && type="${CLAUDE_TEAMMATE_TYPE:-}"

is_anderson=0
case "$type" in
  anderson-impl|anderson-fixer) is_anderson=1 ;;
esac
case "$name" in
  anderson-impl-*|anderson-fixer-*) is_anderson=1 ;;
esac

if (( is_anderson )); then
  cat >&2 <<'EOF'
Do not go idle. Your job is to stay available for Smith's review
requests across every gate of his pipeline — spec, plan, diff for
the impl pair, or triage and a final cumulative diff for the fixer
pair. Smith may send another `review.request` at any moment. If you
have no message to process right now, that is normal: wait. Only
exit when you receive an explicit shutdown request from the lead.
EOF
  exit 2
fi

exit 0
