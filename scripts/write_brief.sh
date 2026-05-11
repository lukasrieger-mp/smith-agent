#!/usr/bin/env bash
# Fetch a JIRA ticket and write its enriched brief to
# .smith/briefs/<KEY>-brief.md inside the current git worktree.
#
# Usage: write_brief.sh <KEY>
# Output (stdout): the absolute path of the written brief.
#
# Brief structure: see spec Section 10.1 and skills/enrich/SKILL.md.
# Phase 2 includes only the "Original ticket" section fully populated;
# "Smith's reading" is filled in during Phase 2.x when the Explore
# subagent integration lands. Until then, that section is a placeholder.
set -euo pipefail

KEY="${1:?usage: write_brief.sh <KEY>}"

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
  printf '%s\n' '- **Acceptance criteria** (expanded): (Phase 2.x placeholder — Explore subagent fills this in)'
  printf '%s\n' '- **Identified ambiguities**: (Phase 2.x placeholder)'
  printf '%s\n' '- **Suspected affected files**: (Phase 2.x placeholder)'
  printf '%s\n' "- **Platform**: $components"
  printf '\n%s\n\n' "## Proposed DoD"
  printf '%s\n' '- [ ] (Phase 2.x placeholder DoD)'
  printf '%s\n' '- [ ] All target-tracked tests pass: `./scripts/quality-check.sh`'
  printf '%s\n' '- [ ] Branch ready for draft PR; no commits on `develop`/`main`.'
} > "$brief_path"

echo "$brief_path"
