#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

GUARD="${ROOT}/bin/hook_bash_guard.sh"

# Run guard with a tool_input.command payload and capture stdout.
run_guard() {
  local cmd="$1"
  jq -nc --arg cmd "$cmd" '{
    hook_event_name: "PreToolUse",
    tool_name: "Bash",
    tool_input: { command: $cmd },
    cwd: "/tmp",
    session_id: "test"
  }' | bash "$GUARD"
}

# Returns "deny" or "" based on guard output
guard_decision() {
  run_guard "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null
}

# --- Should DENY ---

# rm -rf
got=$(guard_decision "rm -rf /tmp/build")
assert_eq "deny" "$got" "rm-rf"

got=$(guard_decision "rm -fr foo")
assert_eq "deny" "$got" "rm-fr-alias"

# git push --force
got=$(guard_decision "git push origin HEAD --force")
assert_eq "deny" "$got" "git-push-force"

got=$(guard_decision "git push --force-with-lease origin task/app-1234")
assert_eq "deny" "$got" "git-push-force-with-lease"

# git branch -D
got=$(guard_decision "git branch -D feature/old")
assert_eq "deny" "$got" "git-branch-D"

# git reset --hard
got=$(guard_decision "git reset --hard origin/main")
assert_eq "deny" "$got" "git-reset-hard"

# gh pr merge
got=$(guard_decision "gh pr merge 4321 --squash")
assert_eq "deny" "$got" "gh-pr-merge"

got=$(guard_decision "gh pr close 4321")
assert_eq "deny" "$got" "gh-pr-close"

# gh repo delete
got=$(guard_decision "gh repo delete user/foo")
assert_eq "deny" "$got" "gh-repo-delete"

# gh release
got=$(guard_decision "gh release create v1.0")
assert_eq "deny" "$got" "gh-release"

# acli jira delete
got=$(guard_decision "acli jira workitem delete APP-1234")
assert_eq "deny" "$got" "acli-delete"

# sudo
got=$(guard_decision "sudo ls /etc")
assert_eq "deny" "$got" "sudo"

# launchctl
got=$(guard_decision "launchctl unload com.foo.bar")
assert_eq "deny" "$got" "launchctl"

# --- Should ALLOW (no output, decision is empty) ---

got=$(guard_decision "git status")
assert_eq "" "$got" "git-status-allowed"

got=$(guard_decision "git commit -m \"feat: thing\"")
assert_eq "" "$got" "git-commit-allowed"

got=$(guard_decision "git push origin task/app-1234")
assert_eq "" "$got" "git-push-normal-allowed"

got=$(guard_decision "rm /tmp/single-file.txt")
assert_eq "" "$got" "rm-single-file-allowed"

got=$(guard_decision "./gradlew assembleStagingDebug")
assert_eq "" "$got" "gradle-build-allowed"

got=$(guard_decision "gh pr create --draft --title 'x'")
assert_eq "" "$got" "gh-pr-create-allowed"

got=$(guard_decision "gh pr view 4321")
assert_eq "" "$got" "gh-pr-view-allowed"

# --- Edge cases ---

# Empty command (e.g. missing tool_input.command) -> allow silently
got=$(echo '{"tool_name":"Bash","tool_input":{}}' | bash "$GUARD")
assert_eq "" "$got" "empty-command-allow"

# Non-Bash tool (e.g. Read) -> allow silently
got=$(echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' | bash "$GUARD")
assert_eq "" "$got" "non-bash-allow"

# Verify the deny reason is informative
reason=$(run_guard "rm -rf /tmp/foo" | jq -r '.hookSpecificOutput.permissionDecisionReason')
assert_contains "$reason" "recursive" "deny-reason-contains-keyword"

echo "PASS hook_bash_guard.test.sh"
