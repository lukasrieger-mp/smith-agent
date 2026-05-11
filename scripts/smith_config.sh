#!/usr/bin/env bash
# Read Smith config. Auto-creates .smith/config.json with defaults on first call,
# and idempotently ensures `.smith/` is in the target's .gitignore at the same time
# (so the user never has to remember a separate bootstrap step).
#
# Usage: smith_config.sh <key>
# Env: SMITH_HOME overrides the runtime state dir (default $target_repo_root/.smith).
#      The state dir lives inside the TARGET repo Smith is operating on,
#      not inside the smith-agent plugin source.
set -euo pipefail

KEY="${1:?usage: smith_config.sh <key>}"

home="${SMITH_HOME:-$(git rev-parse --show-toplevel)/.smith}"
config="$home/config.json"

# Target repo is the parent of $home (since $home == <target>/.smith).
target_repo="$(cd "$home/.." 2>/dev/null && pwd -P || dirname "$home")"

ensure_gitignored() {
  # Idempotently add `### Smith ###` block + `.smith/` entry to <target>/.gitignore.
  local gitignore="$target_repo/.gitignore"
  local marker="### Smith ###"
  local entry=".smith/"

  if [[ -f "$gitignore" ]] && grep -qxF "$entry" "$gitignore"; then
    return 0   # already covered
  fi

  {
    if [[ -f "$gitignore" ]] && [[ -s "$gitignore" ]] && [[ "$(tail -c1 "$gitignore")" != "" ]]; then
      printf '\n'
    fi
    if [[ ! -f "$gitignore" ]] || ! grep -qxF "$marker" "$gitignore"; then
      printf '\n%s\n' "$marker"
    fi
    printf '%s\n' "$entry"
  } >> "$gitignore"
}

if [[ ! -f "$config" ]]; then
  mkdir -p "$home"
  cat > "$config" <<JSON
{
  "target_repo": "$target_repo",
  "max_concurrent_smiths": 2,
  "polling_minutes": 30,
  "jira_project_key": "APP",
  "story_points_field": "customfield_10026",
  "sprint_field": "customfield_10020",
  "eligible_status": "Ready for Development",
  "claim_status": "In Progress",
  "max_critic_rounds": 3,
  "max_pr_fix_cycles": 5,
  "build_wallclock_minutes": 45
}
JSON
  # First-time setup: also ensure the gitignore covers .smith/
  ensure_gitignored
fi

if ! jq -e --arg k "$KEY" 'has($k)' "$config" >/dev/null; then
  echo "smith_config: unknown key: $KEY" >&2
  exit 1
fi

jq -er --arg k "$KEY" '.[$k]' "$config"
