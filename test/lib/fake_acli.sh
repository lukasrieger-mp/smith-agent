#!/usr/bin/env bash
# Fake `acli` wrapper for tests. Place its directory first in PATH so
# scripts under test invoke this instead of the real acli.
#
# Behaviour:
#   `acli jira workitem view <key> --fields ... --json` →
#         prints contents of $SMITH_FAKE_ACLI_VIEW_FIXTURE
#   `acli jira workitem search --jql ... --json` →
#         prints contents of $SMITH_FAKE_ACLI_SEARCH_FIXTURE
#   `acli jira workitem transition ...` →
#         appends one line to $SMITH_FAKE_ACLI_LOG describing the call
#         and exits 0 (does NOT call real JIRA).
#   `acli jira workitem edit ...` → same pattern.
#   `acli jira auth status` → exit 0 silently (auth always succeeds in tests).
#   `acli jira workitem comment ...` → forbidden in Smith (Section 6.6);
#         logs and exits 1 so tests catch a comment-add attempt.
#
# Other invocations cause exit 99 so unexpected acli usage shows up loudly.

set -uo pipefail

args="$*"

# Log every acli invocation if SMITH_FAKE_ACLI_LOG is set. This is the test's
# only way to verify what the script under test sent to acli (real and fake
# alike). For commands that we mock (view, search), the fixture content is
# still returned on stdout afterwards.
if [[ -n "${SMITH_FAKE_ACLI_LOG:-}" ]]; then
  printf 'acli %s\n' "$args" >> "$SMITH_FAKE_ACLI_LOG"
fi

case "$args" in
  "jira auth status")
    # Tests set SMITH_FAKE_ACLI_AUTH_FAIL=1 to simulate an unauthenticated
    # client. Default: auth always succeeds in tests.
    if [[ "${SMITH_FAKE_ACLI_AUTH_FAIL:-0}" == "1" ]]; then
      echo "AUTH: not logged in (fake)" >&2
      exit 1
    fi
    exit 0
    ;;
  "jira workitem view"*"--json"*)
    [[ -n "${SMITH_FAKE_ACLI_VIEW_FIXTURE:-}" ]] || { echo "fake-acli: no SMITH_FAKE_ACLI_VIEW_FIXTURE" >&2; exit 99; }
    cat "$SMITH_FAKE_ACLI_VIEW_FIXTURE"
    ;;
  "jira workitem search"*"--json"*)
    [[ -n "${SMITH_FAKE_ACLI_SEARCH_FIXTURE:-}" ]] || { echo "fake-acli: no SMITH_FAKE_ACLI_SEARCH_FIXTURE" >&2; exit 99; }
    cat "$SMITH_FAKE_ACLI_SEARCH_FIXTURE"
    ;;
  "jira workitem transition"*|"jira workitem edit"*)
    # Already logged at top; just exit success — no real call.
    exit 0
    ;;
  "jira workitem comment"*)
    # Logged at top; comment-add is forbidden per spec 6.6.
    echo "fake-acli: comment-add attempted (forbidden per spec 6.6)" >&2
    exit 1
    ;;
  *)
    echo "fake-acli: unexpected invocation: $args" >&2
    exit 99
    ;;
esac
