#!/usr/bin/env bash
# Fetch a JIRA ticket and write its enriched brief to
# .smith/briefs/<KEY>-brief.md inside the current git worktree.
#
# Usage: write_brief.sh <KEY> [AFFECTED_FILES_JSON]
#   AFFECTED_FILES_JSON — optional path to a JSON array of orientation
#   hints produced by an Explore subagent pass. Each element:
#     { "path": "app/foo/Bar.kt", "line_range": "120-180", "why": "..." }
#   line_range is optional. When the file is missing or malformed,
#   the "Suspected affected files" bullet falls back to a placeholder.
#
# Output (stdout): the absolute path of the written brief.
#
# Brief structure: see spec Section 10.1 and skills/enrich/SKILL.md.
# The "Original ticket" section is populated from JIRA. "Suspected
# affected files" is populated from AFFECTED_FILES_JSON when provided.
# Remaining bullets in "Smith's reading" and "Proposed DoD" are
# emitted as placeholders for Smith to extend during the pipeline.
set -euo pipefail

KEY="${1:?usage: write_brief.sh <KEY> [AFFECTED_FILES_JSON]}"
AFFECTED_FILES_JSON="${2:-}"

worktree=$(git rev-parse --show-toplevel)
plugin_scripts=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
brief_dir="$worktree/.smith/briefs"
brief_path="$brief_dir/$KEY-brief.md"

mkdir -p "$brief_dir"

# Fetch ticket
ticket_json=$(acli jira workitem view "$KEY" \
              --fields "summary,description,components" --json)

summary=$(echo "$ticket_json" | jq -r '.fields.summary // "(no summary)"')
components=$(echo "$ticket_json" | jq -r '[.fields.components[]?.name] | join(", ") // "(none)"')

# Flatten ADF description (if present) to markdown.
description_md=""
if echo "$ticket_json" | jq -e '.fields.description.type == "doc"' >/dev/null 2>&1; then
  description_md=$(echo "$ticket_json" | jq -c '.fields.description' \
                   | bash "$plugin_scripts/adf_to_markdown.sh")
fi

# Render the "Suspected affected files" bullet. If a valid JSON array
# was passed, format it as a sub-list. If empty, mark it as such. If
# absent or malformed, leave the placeholder.
render_affected_files() {
  if [[ -n "$AFFECTED_FILES_JSON" && -f "$AFFECTED_FILES_JSON" ]] \
      && jq -e 'type == "array"' "$AFFECTED_FILES_JSON" >/dev/null 2>&1; then
    local n
    n=$(jq 'length' "$AFFECTED_FILES_JSON")
    if [[ "$n" -eq 0 ]]; then
      printf '%s\n' '- **Suspected affected files**: _(none identified)_'
    else
      printf '%s\n' '- **Suspected affected files**:'
      jq -r '.[] | "  - " + .path + (if .line_range then ":" + .line_range else "" end) + " — " + (.why // "(no reason given)")' \
        "$AFFECTED_FILES_JSON"
    fi
  else
    printf '%s\n' '- **Suspected affected files**: _to be filled in_'
  fi
}

# Write brief. Use `printf '%s\n'` patterns to avoid '-' being treated as
# a flag when lines begin with markdown bullets.
{
  printf '%s\n\n' "# Brief — $KEY: $summary"
  printf '%s\n\n' "_Components: ${components}_"
  printf '%s\n\n' "## Original ticket"
  if [[ -n "$description_md" ]]; then
    printf '%s\n' "$description_md"
  else
    printf '%s\n' '(No description body on JIRA ticket.)'
  fi
  printf '\n%s\n\n' "## Smith's reading"
  printf '%s\n' '- **Acceptance criteria** (extracted verbatim/near-verbatim from the ticket body — do NOT invent): _to be filled in_'
  printf '%s\n' '- **Genuine ambiguities for explicit deferral** (default to the minimal interpretation; do NOT maximalise): _to be filled in_'
  render_affected_files
  printf '%s\n' "- **Platform**: $components"
  printf '\n%s\n\n' "## Proposed DoD"
  printf '%s\n' '- [ ] _to be filled in_'
  printf '%s\n' '- [ ] All target-tracked tests pass: `./scripts/quality-check.sh`'
  printf '%s\n' '- [ ] Branch ready for draft PR; no commits on `develop`/`main`.'
} > "$brief_path"

echo "$brief_path"
