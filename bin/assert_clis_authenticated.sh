#!/usr/bin/env bash
# Verify both the GitHub CLI and the Atlassian CLI are authenticated.
# Smith depends on `gh` for PR operations and `acli` for JIRA reads/writes.
# Without auth on either, downstream skills fail at confusing points:
#  - acli surfaces an opaque error during ticket lookup in `smith:implement`
#  - gh fails during PR creation in `smith:pr`
#  - the background monitors swallow auth errors and emit no notifications,
#    so an unarmed-feeling watchdog actually has zero JIRA visibility
#
# This script is the single chokepoint that catches both at the slash-
# command pre-flight, before any work is dispatched. Reports BOTH failures
# in one run (no early-exit) so the operator fixes everything at once.
#
# Exits 0 on success, 1 if either CLI is unauthenticated.

set -uo pipefail

failed=0

# --- gh ---
if ! gh auth status >/dev/null 2>&1; then
  cat >&2 <<'EOF'
GitHub CLI (`gh`) is not authenticated.

Smith needs `gh` to push branches, open draft PRs, fetch PR review
comments, and post fix-loop replies. Without auth, the implement and
PR-fix paths fail partway through with opaque errors.

Fix:
  gh auth login

Verify with:
  gh auth status
EOF
  failed=1
fi

# --- acli ---
if ! acli jira auth status >/dev/null 2>&1; then
  cat >&2 <<'EOF'
Atlassian CLI (`acli`) is not authenticated to JIRA.

Smith needs `acli` to scan for eligible tickets, transition them on
claim, swap labels, and read ticket descriptions. Without auth, the
watchdog's JIRA monitor silently emits no notifications and the
implement path fails at ticket lookup.

Fix:
  acli jira auth login

Verify with:
  acli jira auth status
EOF
  failed=1
fi

exit "$failed"
