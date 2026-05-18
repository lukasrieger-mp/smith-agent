#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Receives the standard hook JSON on stdin
# and inspects `tool_input.command` for patterns from Smith's destructive-
# operation denylist (spec Section 13.6).
#
# On match: emit a `permissionDecision: "deny"` JSON output and exit 0
#   (which causes Claude Code to honour the deny and feed the reason back
#   to the agent's context).
# On no match: exit 0 with no output (silent allow).
#
# This is a security backstop — Smith's own discipline already keeps these
# commands out of his repertoire, but the hook catches drift.
#
# Notes:
# - We deliberately match SUBSTRINGS, not full commands, because the agent
#   could compose pipelines like `git push origin HEAD --force-with-lease`
#   or `rm -rf $WORKTREE/old`.
# - We don't try to be clever about quoting or eval'd subshells — if any
#   pattern appears literally in the command string, we block. False
#   positives are accepted as the safe failure mode.

set -uo pipefail

# Read JSON input.
payload=$(cat)
command_str=$(jq -r '.tool_input.command // empty' <<< "$payload" 2>/dev/null || echo "")

if [[ -z "$command_str" ]]; then
  # Not a Bash command we can inspect; allow.
  exit 0
fi

# Test-only override: dump the parsed command and exit (used by the test
# harness to inspect what the hook saw).
if [[ "${SMITH_HOOK_DEBUG:-0}" == "1" ]]; then
  printf '%s' "$command_str" >&2
fi

# Denylist patterns. Each is a literal substring or a small POSIX ERE.
# When adding patterns, prefer over-blocking to under-blocking.
deny_pattern() {
  case "$1" in
    'rm -rf'|'rm -fr'|'rm --recursive')
      echo "$1 — recursive deletion is not allowed"
      ;;
  esac
}

deny_regex() {
  # Regex patterns checked with `grep -E`. Return reason on stdout, or
  # nothing if not matched.
  local cmd="$1"
  if echo "$cmd" | grep -qE '\brm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*[[:space:]]|--recursive)'; then
    echo "recursive rm — not allowed (spec Section 13.6)"
    return
  fi
  if echo "$cmd" | grep -qE '\bgit[[:space:]]+push[[:space:]]+.*--force(-with-lease)?\b'; then
    echo "git push --force / --force-with-lease — not allowed"
    return
  fi
  if echo "$cmd" | grep -qE '\bgit[[:space:]]+branch[[:space:]]+-D\b'; then
    echo "git branch -D — destructive branch deletion not allowed"
    return
  fi
  if echo "$cmd" | grep -qE '\bgit[[:space:]]+reset[[:space:]]+(--hard|.*--hard)\b'; then
    echo "git reset --hard — destructive working tree mutation not allowed"
    return
  fi
  if echo "$cmd" | grep -qE '\bgh[[:space:]]+pr[[:space:]]+(merge|close|review[[:space:]]+--approve)\b'; then
    echo "gh pr merge/close/approve — only humans may do these"
    return
  fi
  if echo "$cmd" | grep -qE '\bgh[[:space:]]+repo[[:space:]]+(delete|edit|fork)\b'; then
    echo "gh repo delete/edit/fork — not allowed"
    return
  fi
  if echo "$cmd" | grep -qE '\bgh[[:space:]]+release\b'; then
    echo "gh release — release management is a human operation"
    return
  fi
  if echo "$cmd" | grep -qE '\bacli[[:space:]]+jira[[:space:]]+workitem[[:space:]]+(delete|move-to-trash)\b'; then
    echo "acli jira workitem delete/move-to-trash — never"
    return
  fi
  if echo "$cmd" | grep -qE '\bsudo\b'; then
    echo "sudo — privilege escalation not allowed"
    return
  fi
  if echo "$cmd" | grep -qE '\b(launchctl|defaults[[:space:]]+write|networksetup)\b'; then
    echo "system configuration commands — not allowed"
    return
  fi
}

reason=$(deny_regex "$command_str")
if [[ -n "$reason" ]]; then
  jq -nc --arg reason "smith bash-guard denied: $reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
fi

# Allow.
exit 0
