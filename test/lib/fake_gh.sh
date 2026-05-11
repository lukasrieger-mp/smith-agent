#!/usr/bin/env bash
# Fake `gh` wrapper for tests. Mirrors the pattern of fake_acli.sh:
# place this file's directory first in PATH so scripts under test invoke
# this instead of the real gh.
#
# Logs every invocation to SMITH_FAKE_GH_LOG if set.
#
# Supported invocations:
#   gh auth status                                    → exit 0 silently
#   gh pr list ...--json...                           → cat $SMITH_FAKE_GH_PR_LIST_FIXTURE
#   gh pr view <N> --json reviewThreads...            → cat $SMITH_FAKE_GH_PR_VIEW_DIR/pr-<N>.json
#   gh pr create ...                                  → log, exit 0,
#                                                       prints "$SMITH_FAKE_GH_PR_URL" if set
#   gh pr edit <N> --add-label ...                    → log, exit 0
#
# Anything else exits 99 so unexpected gh usage is loud in tests.

set -uo pipefail

args="$*"

if [[ -n "${SMITH_FAKE_GH_LOG:-}" ]]; then
  printf 'gh %s\n' "$args" >> "$SMITH_FAKE_GH_LOG"
fi

case "$args" in
  "auth status")
    exit 0
    ;;
  "pr list"*"--json"*)
    [[ -n "${SMITH_FAKE_GH_PR_LIST_FIXTURE:-}" ]] || { echo "fake-gh: SMITH_FAKE_GH_PR_LIST_FIXTURE unset" >&2; exit 99; }
    cat "$SMITH_FAKE_GH_PR_LIST_FIXTURE"
    ;;
  "pr view "*"--json"*)
    # Extract the PR number, second arg after "view"
    pr_num=$(printf '%s\n' "$args" | awk '{for (i=1;i<=NF;i++) if ($i == "view") print $(i+1)}')
    fixture="${SMITH_FAKE_GH_PR_VIEW_DIR:-/no/such/dir}/pr-$pr_num.json"
    [[ -f "$fixture" ]] || { echo "fake-gh: no fixture at $fixture" >&2; exit 99; }
    cat "$fixture"
    ;;
  "pr create"*)
    # Already logged at top; pretend success.
    printf '%s\n' "${SMITH_FAKE_GH_PR_URL:-https://github.com/fake/fake/pull/9999}"
    exit 0
    ;;
  "pr edit"*)
    exit 0
    ;;
  *)
    echo "fake-gh: unexpected invocation: $args" >&2
    exit 99
    ;;
esac
