#!/usr/bin/env bash
# Scan JIRA for candidate tickets and return them as a JSON array.
#
# Supports a stub mode for tests: set SMITH_DRY_RUN_FIXTURE=<path>
# and the script returns the fixture JSON verbatim instead of querying
# acli.
set -euo pipefail

# Stub mode short-circuit
if [[ -n "${SMITH_DRY_RUN_FIXTURE:-}" ]]; then
  if [[ ! -f "$SMITH_DRY_RUN_FIXTURE" ]]; then
    echo "jira_scan: fixture not found: $SMITH_DRY_RUN_FIXTURE" >&2
    exit 1
  fi
  cat "$SMITH_DRY_RUN_FIXTURE"
  exit 0
fi

# Resolve our sibling scripts via the script's own directory, so jira_scan
# works when called from within a target repo (where git toplevel = target,
# not the plugin source).
PLUGIN_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
config_get() { bash "$PLUGIN_SCRIPTS/smith_config.sh" "$1"; }

. "$PLUGIN_SCRIPTS/smith_labels.sh"

project=$(config_get jira_project_key)
status=$(config_get eligible_status)
sp_field=$(config_get story_points_field)
sprint_field=$(config_get sprint_field)

jql="assignee = currentUser() \
  AND status = \"$status\" \
  AND sprint in openSprints() \
  AND \"Story Points\" <= 2 \
  AND labels not in ($SMITH_LABEL_JIRA_FAILED, $SMITH_LABEL_JIRA_IMPLEMENTING, $SMITH_LABEL_JIRA_NO_AUTO) \
  AND project = $project \
  ORDER BY priority DESC, created ASC"

acli jira workitem search --jql "$jql" \
  --fields "summary,components,labels,priority,$sp_field,$sprint_field" \
  --json \
  | jq --arg sp "$sp_field" --arg sprint "$sprint_field" '
      [ .[] | {
          key: .key,
          summary: .fields.summary,
          components: (.fields.components // [] | map(.name)),
          labels: (.fields.labels // []),
          priority: (.fields.priority.name // "None"),
          story_points: (.fields[$sp] // null),
          sprint: (.fields[$sprint][0].name // null)
        }
      ]'
