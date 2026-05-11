#!/usr/bin/env bash
# Read Smith config. Auto-creates .smith/config.json with defaults on first call.
# Usage: smith_config.sh <key>
# Env: SMITH_HOME overrides the runtime state dir (default $target_repo_root/.smith).
#      The state dir lives inside the TARGET repo Smith is operating on,
#      not inside the smith-agent plugin source.
set -euo pipefail

KEY="${1:?usage: smith_config.sh <key>}"

home="${SMITH_HOME:-$(git rev-parse --show-toplevel)/.smith}"
config="$home/config.json"

if [[ ! -f "$config" ]]; then
  mkdir -p "$home"
  # Default target_repo is the current git toplevel — the repo whose .smith/
  # dir we're populating. The install.sh wrapper overrides this with the
  # actual target path when it runs.
  default_target_repo="$(cd "$home/.." && pwd -P)"
  cat > "$config" <<JSON
{
  "target_repo": "$default_target_repo",
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
fi

if ! jq -e --arg k "$KEY" 'has($k)' "$config" >/dev/null; then
  echo "smith_config: unknown key: $KEY" >&2
  exit 1
fi

jq -er --arg k "$KEY" '.[$k]' "$config"
