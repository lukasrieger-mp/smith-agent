#!/usr/bin/env bash
# Abort an in-flight Smith dispatch and clean up local + JIRA state.
#
# Usage: abort_smith.sh <SUBJECT>
#   SUBJECT = ticket key (e.g. APP-1234) for impl mode, OR
#             PR number (e.g. 4321) for fixer mode.
#
# Looks up the active entry in `.smith/state/active-smiths.json` to
# determine mode and teammate names, then tears down:
#
#   - Worktree at .smith/worktrees/<key-lower>/  (git worktree remove --force)
#   - Local branch task/<key>-<slug>             (impl mode only;
#                                                 SAFE: only deletes if NOT
#                                                 pushed to origin)
#   - Brief at .smith/briefs/<KEY>-brief.md       (impl mode only)
#   - active-smiths entry
#   - JIRA: if status is claim_status, revert to eligible_status;
#           if smith-implementing label present, remove it
#           (impl mode only)
#
# What this script does NOT do:
#   - Shut down the running Smith/Anderson teammates. That's an
#     LLM-level operation done via the team API (see commands/abort.md
#     which orchestrates both).
#   - Touch fixer-mode branches on the remote (they belong to a real PR
#     and are owned by GitHub).
#
# Idempotent: re-running on a partially-cleaned-up subject is fine.
set -euo pipefail

SUBJECT="${1:?usage: abort_smith.sh <SUBJECT>}"

plugin_scripts=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
target_root=$(git rev-parse --show-toplevel)
cd "$target_root"

# Look up the active entry
entry=$(bash "$plugin_scripts/active_smiths.sh" list \
        | jq -c --arg subj "$SUBJECT" '.[] | select(.subject == $subj)' 2>/dev/null \
        || echo "")

if [[ -z "$entry" ]]; then
  echo "abort_smith: no active Smith for subject '$SUBJECT'" >&2
  echo "  (run: $plugin_scripts/active_smiths.sh list)" >&2
  echo "  to clean up stale state without an active entry, remove the worktree" >&2
  echo "  and branch manually." >&2
  exit 1
fi

smith_name=$(echo "$entry" | jq -r '.smith_name')
anderson_name=$(echo "$entry" | jq -r '.anderson_name')
mode=$(echo "$entry" | jq -r '.mode')

echo "Aborting $smith_name (mode=$mode, subject=$SUBJECT)..."

key_lower=$(echo "$SUBJECT" | tr '[:upper:]' '[:lower:]')
worktree_path=".smith/worktrees/$key_lower"

# 1. Worktree
if [[ -d "$worktree_path/.git" || -f "$worktree_path/.git" ]]; then
  git worktree remove --force "$worktree_path" >/dev/null 2>&1 \
    && echo "  ✓ worktree removed: $worktree_path" \
    || echo "  ✗ worktree removal failed: $worktree_path"
elif [[ -d "$worktree_path" ]]; then
  rm -rf "$worktree_path" && echo "  ✓ worktree directory removed (was not a git worktree)"
fi

if [[ "$mode" == "impl" ]]; then
  # 2a. Local branch (impl-mode created it from origin/develop)
  # Safe rule: only delete if the branch is NOT pushed to origin.
  branch=$(git branch --list "task/$key_lower-*" --format='%(refname:short)' 2>/dev/null | head -1)
  if [[ -n "$branch" ]]; then
    if git ls-remote --exit-code origin "$branch" >/dev/null 2>&1; then
      echo "  ! branch '$branch' is pushed to origin — leaving local in place (delete manually if intended)"
    else
      git branch -D "$branch" >/dev/null 2>&1 \
        && echo "  ✓ local branch deleted: $branch" \
        || echo "  ✗ failed to delete local branch: $branch"
    fi
  fi

  # 2b. Brief
  if [[ -f ".smith/briefs/$SUBJECT-brief.md" ]]; then
    rm -f ".smith/briefs/$SUBJECT-brief.md"
    echo "  ✓ brief removed: .smith/briefs/$SUBJECT-brief.md"
  fi

  # 2c. JIRA cleanup (best-effort, idempotent)
  eligible_status=$(bash "$plugin_scripts/smith_config.sh" eligible_status)
  claim_status=$(bash "$plugin_scripts/smith_config.sh" claim_status)
  current_status=$(acli jira workitem view "$SUBJECT" --fields "status" --json 2>/dev/null \
                   | jq -r '.fields.status.name // ""' 2>/dev/null || echo "")
  if [[ "$current_status" == "$claim_status" ]]; then
    if SMITH_EXPECTED_FROM_STATUS="$claim_status" \
       bash "$plugin_scripts/jira_transition.sh" "$SUBJECT" "$eligible_status" >/dev/null 2>&1; then
      echo "  ✓ JIRA reverted: $claim_status → $eligible_status"
    else
      echo "  ✗ JIRA revert failed (manual cleanup may be needed)"
    fi
  elif [[ -n "$current_status" ]]; then
    echo "  ✓ JIRA status is '$current_status' (not claim status; no revert needed)"
  fi

  # Label remove is itself idempotent
  if bash "$plugin_scripts/jira_label_remove.sh" "$SUBJECT" smith-implementing >/dev/null 2>&1; then
    echo "  ✓ smith-implementing label state cleaned (was either removed or not present)"
  fi
fi

# 3. active-smiths entry
bash "$plugin_scripts/active_smiths.sh" remove "$smith_name" >/dev/null
echo "  ✓ active_smiths entry removed: $smith_name"

# 4. Audit log
mkdir -p .smith
printf '%s | abort | %s | %s subject=%s\n' \
       "$(date -u +%FT%TZ)" "$smith_name" "$mode" "$SUBJECT" >> .smith/log.txt

echo ""
echo "Done. The teammate sessions themselves were NOT shut down by this"
echo "script — that's an LLM-level operation. Use /smith:abort to do"
echo "both: shut down teammates AND run this cleanup."
