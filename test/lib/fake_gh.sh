#!/usr/bin/env bash
# Fake `gh` wrapper for tests. Mirrors the pattern of fake_acli.sh:
# place this file's directory first in PATH so scripts under test invoke
# this instead of the real gh.
#
# Logs every invocation to SMITH_FAKE_GH_LOG if set.
#
# Supported invocations:
#   gh auth status                                    → exit 0 silently
#   gh repo view --json owner -q .owner.login         → echo "fake-owner"
#   gh repo view --json name -q .name                 → echo "fake-repo"
#   gh pr list ...--json...                           → cat $SMITH_FAKE_GH_PR_LIST_FIXTURE
#   gh api graphql -f query=... -F number=<N> ...     → cat $SMITH_FAKE_GH_PR_VIEW_DIR/pr-<N>.json
#                                                       (GraphQL response shape — `reviewThreads`
#                                                       lives at `.data.repository.pullRequest`)
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
  "repo view --json owner"*)
    echo "fake-owner"
    ;;
  "repo view --json name"*)
    echo "fake-repo"
    ;;
  "pr list"*"--json"*)
    [[ -n "${SMITH_FAKE_GH_PR_LIST_FIXTURE:-}" ]] || { echo "fake-gh: SMITH_FAKE_GH_PR_LIST_FIXTURE unset" >&2; exit 99; }
    cat "$SMITH_FAKE_GH_PR_LIST_FIXTURE"
    ;;
  "api graphql"*)
    # Extract the integer from `-F number=<N>`. Use grep so multi-line
    # query strings don't trip up word-splitting.
    pr_num=$(printf '%s' "$args" | grep -oE 'number=[0-9]+' | tail -1 | sed 's/number=//')
    [[ -n "$pr_num" ]] || { echo "fake-gh: could not parse number= from: $args" >&2; exit 99; }
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
