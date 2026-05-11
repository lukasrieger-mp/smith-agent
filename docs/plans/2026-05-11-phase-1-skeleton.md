# Smith Phase 1 — Skeleton + Dry-Run End-to-End

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Status (2026-05-11, mid-Phase-1 pivot)

Phase 1 is **partially complete and paused**. Tasks 1–17 were implemented against an earlier (pre-pivot) design that dispatched Smith as a *single subagent per ticket*. After Task 17 the operator decided to pivot to **Claude Code agent teams**, which makes Smith and Anderson *co-equal teammates* rather than a controller dispatching a subagent. The spec has been updated to reflect this (see `../spec.md` Sections 5, 8, 11, 13.7, and the new Section 18).

Concrete consequence for this plan:

- Tasks 1–8 (plugin scaffold, pure scripts, fixtures, install.sh): **still valid**. The pure-helper scripts are unaffected by the agent-teams pivot.
- Tasks 9–17 (Anderson agent definition, six SKILL.md skeletons, two slash commands): **need rewrite** for the new architecture. They were committed in pre-pivot form on `smith/phase-1-skeleton`; git history preserves them. Rewrites land in Phase 1.5 (extraction).
- Tasks 18–20 (install.sh execution, smoke test, README wrap-up): **deferred** until Phase 1.5 completes (move to dedicated repo + generalize install.sh + rewrite affected files).

The "Phase 1.5 — Extraction" entry in `smith/docs/spec.md` Section 16 covers the extraction work that bridges this plan to the next. The post-extraction state will pick up the rewrites with a fresh, smaller plan focused only on Tasks 9–20 in their new form.

---

**Original goal (preserved for context):** Stand up the full `smith/` plugin scaffold (skills, agent, commands, scripts, tests, docs) so that `/smith-implement APP-XXXX --dry-run` can walk the entire pipeline end-to-end without any external side effects, proving the orchestration is correctly wired.

**Architecture (pre-pivot — superseded by spec):** Smith is packaged as a self-contained Claude Code plugin under `smith/`. Skills/agents/commands are surfaced into Claude Code via symlinks at `.claude/...` created by `smith/install.sh`. All runtime state lives at `.smith/` (gitignored). The dry-run mode short-circuits any external side effect (JIRA write, git push, gh PR create) into a log entry, so the orchestration is exercised without consequence.

**Tech Stack:** Bash 5 (macOS-default, BSD `sed`); `jq` for JSON; `acli` (Atlassian CLI); `gh` (GitHub CLI); `git` worktrees; Claude Code skills + agents + commands + agent teams (experimental, requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`). Tests are plain bash with a tiny `assert.sh` helper — no bats/shunit2 dependency.

**Reference:** [Smith Design Spec](../spec.md). All cross-references in this plan reference its section numbers.

---

## Conventions used in this plan

- **Working directory** for every shell command: `~/myposter-agent-repo` (use absolute paths in scripts; relative paths in editor refs).
- **Commit style:** Conventional Commits with scope `smith`. Examples: `feat(smith): add branch-name generator`, `chore(smith): bootstrap plugin scaffold`, `test(smith): cover make_branch_name edge cases`.
- **Test runner:** each script under `scripts/` has a sibling `test/<script>.test.sh` that exits 0 on pass, non-zero on fail.
- **Run-from-anywhere:** every script under `scripts/` starts with `set -euo pipefail` and resolves paths via `git rev-parse --show-toplevel`. Never assume cwd.

---

## File structure (created by this plan)

```
smith/
  .claude-plugin/
    plugin.json
  agents/
    anderson.md
  commands/
    smith-implement.md
    smith-watchdog.md
  skills/
    smith-watchdog/SKILL.md
    smith-claim/SKILL.md
    smith-enrich/SKILL.md
    smith-pipeline/SKILL.md
    smith-pr/SKILL.md
    smith-pr-watch/SKILL.md
  scripts/
    make_branch_name.sh
    classify_platform.sh
    assert_clean_worktree.sh
    assert_agent_repo.sh
    smith_config.sh
    jira_scan.sh
  test/
    lib/assert.sh
    fixtures/
      jira-candidates.json
      jira-empty.json
      jira-ios-only.json
    make_branch_name.test.sh
    classify_platform.test.sh
    assert_clean_worktree.test.sh
    assert_agent_repo.test.sh
    smith_config.test.sh
    jira_scan.test.sh
    install.test.sh
    smoke-dry-run.test.sh
  docs/
    spec.md                       (already present)
    plans/
      2026-05-11-phase-1-skeleton.md   (this file)
  install.sh
  README.md
.smith/                            (runtime state, gitignored)
.gitignore                         (modified: add `.smith/`)
.claude/                           (symlinks created by install.sh)
  commands/smith-implement.md      → ../../smith/commands/smith-implement.md
  commands/smith-watchdog.md       → ../../smith/commands/smith-watchdog.md
  agents/anderson.md               → ../../smith/agents/anderson.md
  skills/smith-watchdog/           → ../../smith/skills/smith-watchdog/
  skills/smith-claim/              → ../../smith/skills/smith-claim/
  skills/smith-enrich/             → ../../smith/skills/smith-enrich/
  skills/smith-pipeline/           → ../../smith/skills/smith-pipeline/
  skills/smith-pr/                 → ../../smith/skills/smith-pr/
  skills/smith-pr-watch/           → ../../smith/skills/smith-pr-watch/
```

---

### Task 1: Bootstrap the plugin scaffold and dev branch

**Files:**
- Create: `smith/.claude-plugin/plugin.json`
- Create: `smith/README.md`
- Create: `agents/.keep`, `commands/.keep`, `skills/.keep`, `scripts/.keep`, `test/lib/.keep`, `test/fixtures/.keep`
- Modify: `.gitignore` (append `.smith/`)

- [ ] **Step 1: Create the dev branch off origin/develop**

```bash
cd ~/myposter-agent-repo
git fetch origin develop
git switch -c smith/phase-1-skeleton origin/develop
git status
```

Expected: `On branch smith/phase-1-skeleton`, working tree clean.

- [ ] **Step 2: Create the `smith/` directory tree (placeholder files keep empty dirs trackable)**

```bash
mkdir -p smith/.claude-plugin \
         smith/agents \
         smith/commands \
         smith/skills \
         smith/scripts \
         smith/test/lib \
         smith/test/fixtures \
         smith/docs/plans
for d in smith/agents smith/commands smith/skills smith/scripts smith/test/lib smith/test/fixtures; do
  touch "$d/.keep"
done
ls -R smith
```

Expected: tree with all directories and `.keep` files visible.

- [ ] **Step 3: Write `smith/.claude-plugin/plugin.json`**

```json
{
  "name": "smith",
  "description": "Autonomous JIRA-driven ticket implementation agent for myposter-app. Picks up SP≤ 2 tickets, drives spec→plan→impl with adversarial review, files draft PRs, and self-corrects against PR review comments. See smith/docs/spec.md.",
  "author": {
    "name": "Lukas Rieger",
    "email": "lukas.rieger@myposter.de"
  }
}
```

- [ ] **Step 4: Write `smith/README.md`**

```markdown
# Smith — Autonomous Ticket Implementation Agent

Self-contained Claude Code plugin that picks up small JIRA tickets and drives
them to a draft PR autonomously, with adversarial review by Mr. Anderson.

See `docs/spec.md` for the full design. Implementation plans live in
`docs/plans/`.

## Install (development mode)

From the agent-repo root:

```bash
./smith/install.sh
```

This creates symlinks under `.claude/` so Claude Code discovers Smith's
skills, agents, and commands.

## Usage

- `/smith-implement APP-1234` — manually implement a specific ticket.
- `/smith-implement APP-1234 --dry-run` — walk the pipeline without side effects.
- `/smith-watchdog` — start the autonomous watchdog loop (30 min cadence).
```

- [ ] **Step 5: Append `.smith/` to `.gitignore`**

After existing entries, add:

```
### Smith ###
.smith/
```

- [ ] **Step 6: Commit**

```bash
git add smith/.claude-plugin/plugin.json smith/README.md smith/**/.keep .gitignore
git commit -m "chore(smith): bootstrap plugin scaffold and dev branch"
```

Expected: clean commit; `git log -1` shows the commit.

---

### Task 2: Test framework — `assert.sh` helper

**Files:**
- Create: `test/lib/assert.sh`
- Test: `test/lib/assert.test.sh` (self-test of the helper)

- [ ] **Step 1: Write a failing self-test of the helper**

`test/lib/assert.test.sh`:

```bash
#!/usr/bin/env bash
# Self-test of assert.sh helpers.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert.sh
source "${SCRIPT_DIR}/assert.sh"

# assert_eq passes on equal values
assert_eq "hello" "hello" "eq-positive"

# assert_eq fails on unequal values (run in subshell)
if ( set -e; assert_eq "a" "b" "eq-negative" ) 2>/dev/null; then
  echo "FAIL: assert_eq should have failed on a!=b" >&2
  exit 1
fi

# assert_exit_code passes on equal codes
assert_exit_code 0 0 "code-positive"

# assert_contains passes
assert_contains "the quick brown fox" "brown" "contains-positive"

# assert_contains fails when substring missing
if ( set -e; assert_contains "abc" "xyz" "contains-negative" ) 2>/dev/null; then
  echo "FAIL: assert_contains should have failed" >&2
  exit 1
fi

echo "PASS assert.test.sh"
```

- [ ] **Step 2: Run the test to confirm it fails (helper doesn't exist)**

```bash
bash smith/test/lib/assert.test.sh
```

Expected: failure with `assert.sh: No such file or directory`.

- [ ] **Step 3: Implement `test/lib/assert.sh`**

```bash
#!/usr/bin/env bash
# Minimal assertion helper for Smith script tests.
# Source from test files. All functions print FAIL on stderr and exit 1.

assert_eq() {
  local expected="$1" actual="$2" label="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    printf 'FAIL %s: expected %q got %q\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_exit_code() {
  local expected="$1" actual="$2" label="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    printf 'FAIL %s: expected exit %s got %s\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'FAIL %s: %q does not contain %q\n' "$label" "$haystack" "$needle" >&2
    exit 1
  fi
}
```

- [ ] **Step 4: Run the test to confirm it passes**

```bash
bash smith/test/lib/assert.test.sh
```

Expected: `PASS assert.test.sh` and exit 0.

- [ ] **Step 5: Commit**

```bash
git add smith/test/lib/assert.sh smith/test/lib/assert.test.sh
git rm smith/test/lib/.keep
git commit -m "test(smith): add assert.sh helper for shell-script tests"
```

---

### Task 3: `make_branch_name.sh` — pure function with TDD

**Files:**
- Create: `scripts/make_branch_name.sh`
- Test: `test/make_branch_name.test.sh`

- [ ] **Step 1: Write the failing test**

`test/make_branch_name.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/smith/scripts/make_branch_name.sh"

# basic happy path
got="$(bash "$SCRIPT" "APP-5485" "App Review-Dialog auf dem Home Screen")"
assert_eq "task/app-5485-app-review-dialog-auf-dem-home-screen" "$got" "happy-path"

# all-lowercase already
got="$(bash "$SCRIPT" "app-5485" "review dialog on home")"
assert_eq "task/app-5485-review-dialog-on-home" "$got" "already-lower"

# punctuation collapsed to single hyphen, leading/trailing stripped
got="$(bash "$SCRIPT" "APP-1" "  Fix  the   thing!!! Now???  ")"
assert_eq "task/app-1-fix-the-thing-now" "$got" "punctuation"

# truncated to 40 chars on the slug part
long="A very very very very very very very long summary that exceeds the cap"
got="$(bash "$SCRIPT" "APP-2" "$long")"
slug="${got#task/app-2-}"
[[ ${#slug} -le 40 ]] || { echo "FAIL: slug ${#slug}>40 for $got" >&2; exit 1; }
# no trailing hyphen after cut
[[ "$slug" != *- ]] || { echo "FAIL: trailing hyphen in $got" >&2; exit 1; }

# missing args -> non-zero exit
if bash "$SCRIPT" 2>/dev/null; then
  echo "FAIL: should error on missing args" >&2; exit 1
fi

# German umlauts transliterated (iconv //TRANSLIT)
got="$(bash "$SCRIPT" "APP-3" "Größere Schrift für ältere Nutzer")"
assert_contains "$got" "task/app-3-gr" "umlaut"
[[ "$got" != *"ö"* ]] || { echo "FAIL: umlaut survived in $got" >&2; exit 1; }

echo "PASS make_branch_name.test.sh"
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
bash smith/test/make_branch_name.test.sh
```

Expected: failure (script not found / missing).

- [ ] **Step 3: Implement `scripts/make_branch_name.sh`**

```bash
#!/usr/bin/env bash
# Generate branch name: task/<key-lower>-<slug-from-summary>
# Slug: ASCII-transliterated, lowercased, non-alphanumeric collapsed to "-",
# capped at 40 chars, trailing hyphens stripped.
set -euo pipefail

KEY="${1:?usage: make_branch_name.sh <KEY> <SUMMARY>}"
SUMMARY="${2:?usage: make_branch_name.sh <KEY> <SUMMARY>}"

key_lower=$(printf '%s' "$KEY" | tr '[:upper:]' '[:lower:]')

slug=$(printf '%s' "$SUMMARY" \
  | iconv -f UTF-8 -t ASCII//TRANSLIT//IGNORE 2>/dev/null \
  | tr '[:upper:]' '[:lower:]' \
  | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
  | cut -c1-40 \
  | LC_ALL=C sed -E 's/-+$//')

printf 'task/%s-%s\n' "$key_lower" "$slug"
```

- [ ] **Step 4: Run the test to confirm it passes**

```bash
chmod +x smith/scripts/make_branch_name.sh
bash smith/test/make_branch_name.test.sh
```

Expected: `PASS make_branch_name.test.sh`.

- [ ] **Step 5: Commit**

```bash
git add smith/scripts/make_branch_name.sh smith/test/make_branch_name.test.sh
git rm smith/scripts/.keep 2>/dev/null || true
git commit -m "feat(smith): add branch-name generator script"
```

---

### Task 4: `classify_platform.sh` — components → platform tag (TDD)

**Files:**
- Create: `scripts/classify_platform.sh`
- Test: `test/classify_platform.test.sh`

Phase 1 implements **only the components-based deterministic path** of Section 6.7. The fallback classifier subagent comes in Phase 2.

- [ ] **Step 1: Write the failing test**

`test/classify_platform.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/smith/scripts/classify_platform.sh"

# Pure iOS -> reject (exit 0, stdout "ios")
got=$(echo '["iOS"]' | bash "$SCRIPT")
assert_eq "ios" "$got" "pure-ios"

# Pure Android -> accept (exit 0, stdout "android")
got=$(echo '["Android"]' | bash "$SCRIPT")
assert_eq "android" "$got" "pure-android"

# Shared/KMP -> accept (exit 0, stdout "kmp")
got=$(echo '["Shared/KMP"]' | bash "$SCRIPT")
assert_eq "kmp" "$got" "pure-kmp"

# Mixed Android + iOS -> "android" (Android wins; spec 6.7 "any subset containing Android/KMP/Shared -> accept")
got=$(echo '["iOS","Android"]' | bash "$SCRIPT")
assert_eq "android" "$got" "mixed-android-ios"

# Mixed iOS + Shared -> "kmp"
got=$(echo '["iOS","Shared/KMP"]' | bash "$SCRIPT")
assert_eq "kmp" "$got" "mixed-shared-ios"

# Empty array -> "unclear"
got=$(echo '[]' | bash "$SCRIPT")
assert_eq "unclear" "$got" "empty"

# Unknown component only -> "unclear"
got=$(echo '["Backend"]' | bash "$SCRIPT")
assert_eq "unclear" "$got" "unknown"

# Malformed JSON -> non-zero exit
if echo 'not json' | bash "$SCRIPT" 2>/dev/null; then
  echo "FAIL: should error on bad JSON" >&2; exit 1
fi

echo "PASS classify_platform.test.sh"
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
bash smith/test/classify_platform.test.sh
```

Expected: failure (script not found).

- [ ] **Step 3: Implement `scripts/classify_platform.sh`**

```bash
#!/usr/bin/env bash
# Map a JIRA components JSON array (on stdin) to a platform tag:
#   kmp     - has "Shared/KMP" or "KMP" or "Shared"
#   android - has "Android" (and not exclusively iOS)
#   ios     - only iOS components
#   unclear - empty or no recognised platform components
# Precedence: kmp > android > ios > unclear.
set -euo pipefail

input=$(cat)
# Validate JSON first.
echo "$input" | jq -e 'type == "array"' >/dev/null

has() {
  echo "$input" | jq -er --arg name "$1" 'map(. == $name) | any' >/dev/null
}

# Empty array
[[ "$(echo "$input" | jq 'length')" -eq 0 ]] && { echo "unclear"; exit 0; }

if has "Shared/KMP" || has "KMP" || has "Shared"; then
  echo "kmp"
elif has "Android"; then
  echo "android"
elif has "iOS"; then
  echo "ios"
else
  echo "unclear"
fi
```

- [ ] **Step 4: Run the test to confirm it passes**

```bash
chmod +x smith/scripts/classify_platform.sh
bash smith/test/classify_platform.test.sh
```

Expected: `PASS classify_platform.test.sh`.

- [ ] **Step 5: Commit**

```bash
git add smith/scripts/classify_platform.sh smith/test/classify_platform.test.sh
git commit -m "feat(smith): add components->platform classifier (deterministic mode)"
```

---

### Task 5: Pre-flight guards — `assert_clean_worktree.sh` + `assert_agent_repo.sh`

**Files:**
- Create: `scripts/assert_clean_worktree.sh`
- Create: `scripts/assert_agent_repo.sh`
- Test: `test/assert_clean_worktree.test.sh`
- Test: `test/assert_agent_repo.test.sh`

- [ ] **Step 1: Write the failing test for `assert_clean_worktree.sh`**

`test/assert_clean_worktree.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/smith/scripts/assert_clean_worktree.sh"

# Make a throwaway worktree to test in. Use $(mktemp -d) under repo so the
# script's git rev-parse resolves cleanly.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

git -C "$TMP" init -q
git -C "$TMP" commit --allow-empty -m initial -q

# clean worktree -> exit 0
( cd "$TMP" && bash "$SCRIPT" ) >/dev/null
assert_exit_code 0 $? "clean"

# dirty worktree -> non-zero
touch "$TMP/dirty.txt"
if ( cd "$TMP" && bash "$SCRIPT" ) 2>/dev/null; then
  echo "FAIL: should fail on dirty worktree" >&2; exit 1
fi

echo "PASS assert_clean_worktree.test.sh"
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
bash smith/test/assert_clean_worktree.test.sh
```

Expected: failure (script missing).

- [ ] **Step 3: Implement `scripts/assert_clean_worktree.sh`**

```bash
#!/usr/bin/env bash
# Exits 0 if the current worktree is clean (no staged, unstaged, or untracked
# changes), non-zero otherwise. Prints a one-line reason on failure.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "assert_clean_worktree: working tree is dirty" >&2
  git status --short >&2
  exit 1
fi
```

- [ ] **Step 4: Run the test to confirm it passes**

```bash
chmod +x smith/scripts/assert_clean_worktree.sh
bash smith/test/assert_clean_worktree.test.sh
```

Expected: `PASS assert_clean_worktree.test.sh`.

- [ ] **Step 5: Write the failing test for `assert_agent_repo.sh`**

`test/assert_agent_repo.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/smith/scripts/assert_agent_repo.sh"

# Run inside the real agent repo with the canonical config -> pass.
( cd "$ROOT" && SMITH_AGENT_REPO="$ROOT" bash "$SCRIPT" ) >/dev/null
assert_exit_code 0 $? "real-agent-repo"

# Run inside a temp git repo with same env -> fail (top != configured path).
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q
git -C "$TMP" commit --allow-empty -m initial -q
if ( cd "$TMP" && SMITH_AGENT_REPO="$ROOT" bash "$SCRIPT" ) 2>/dev/null; then
  echo "FAIL: should reject foreign repo" >&2; exit 1
fi

echo "PASS assert_agent_repo.test.sh"
```

- [ ] **Step 6: Implement `scripts/assert_agent_repo.sh`**

```bash
#!/usr/bin/env bash
# Working-directory guard from spec Section 7.4.
# Exits 0 iff the current git toplevel matches the configured agent repo path
# (env var SMITH_AGENT_REPO, defaulting to $HOME/myposter-agent-repo).
set -euo pipefail

expected="${SMITH_AGENT_REPO:-$HOME/myposter-agent-repo}"
# Resolve both sides to absolute, symlink-resolved paths for comparison.
expected_real=$(cd "$expected" 2>/dev/null && pwd -P || echo "$expected")
actual_real=$(cd "$(git rev-parse --show-toplevel)" && pwd -P)

if [[ "$expected_real" != "$actual_real" ]]; then
  echo "assert_agent_repo: refusing to run outside agent repo" >&2
  echo "  expected: $expected_real" >&2
  echo "  actual:   $actual_real" >&2
  exit 1
fi
```

- [ ] **Step 7: Run both tests**

```bash
chmod +x smith/scripts/assert_agent_repo.sh
bash smith/test/assert_agent_repo.test.sh
bash smith/test/assert_clean_worktree.test.sh
```

Expected: both `PASS …`.

- [ ] **Step 8: Commit**

```bash
git add smith/scripts/assert_clean_worktree.sh smith/scripts/assert_agent_repo.sh \
        smith/test/assert_clean_worktree.test.sh smith/test/assert_agent_repo.test.sh
git commit -m "feat(smith): add pre-flight guards (clean-worktree, agent-repo)"
```

---

### Task 6: `smith_config.sh` — read `.smith/config.json` (TDD)

**Files:**
- Create: `scripts/smith_config.sh`
- Test: `test/smith_config.test.sh`

`smith_config.sh` provides one function: `smith_config_get <key>` that reads `.smith/config.json` (created on first use with defaults) and prints the value of `<key>`. Used everywhere the spec references "configurable via `.smith/config.json`" (Sections 5.5, 7.4).

- [ ] **Step 1: Write the failing test**

`test/smith_config.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/smith/scripts/smith_config.sh"

# Isolate state in a temp dir
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# First call should create defaults and return the configured agent repo.
got=$(SMITH_HOME="$TMP/.smith" bash "$SCRIPT" agent_repo)
assert_eq "$HOME/myposter-agent-repo" "$got" "default-agent-repo"

# Config file should now exist
[[ -f "$TMP/.smith/config.json" ]] || { echo "FAIL: config not written" >&2; exit 1; }

# Override value persists
echo '{"agent_repo": "/tmp/other", "polling_minutes": 45}' > "$TMP/.smith/config.json"
got=$(SMITH_HOME="$TMP/.smith" bash "$SCRIPT" agent_repo)
assert_eq "/tmp/other" "$got" "override"
got=$(SMITH_HOME="$TMP/.smith" bash "$SCRIPT" polling_minutes)
assert_eq "45" "$got" "polling"

# Unknown key -> non-zero
if SMITH_HOME="$TMP/.smith" bash "$SCRIPT" no_such_key 2>/dev/null; then
  echo "FAIL: should error on unknown key" >&2; exit 1
fi

echo "PASS smith_config.test.sh"
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
bash smith/test/smith_config.test.sh
```

Expected: script missing.

- [ ] **Step 3: Implement `scripts/smith_config.sh`**

```bash
#!/usr/bin/env bash
# Read Smith config. Auto-creates .smith/config.json with defaults on first call.
# Usage: smith_config.sh <key>
# Env: SMITH_HOME overrides the runtime state dir (default $repo_root/.smith).
set -euo pipefail

KEY="${1:?usage: smith_config.sh <key>}"

home="${SMITH_HOME:-$(git rev-parse --show-toplevel)/.smith}"
config="$home/config.json"

if [[ ! -f "$config" ]]; then
  mkdir -p "$home"
  cat > "$config" <<JSON
{
  "agent_repo": "$HOME/myposter-agent-repo",
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
```

- [ ] **Step 4: Run the test to confirm it passes**

```bash
chmod +x smith/scripts/smith_config.sh
bash smith/test/smith_config.test.sh
```

Expected: `PASS smith_config.test.sh`.

- [ ] **Step 5: Commit**

```bash
git add smith/scripts/smith_config.sh smith/test/smith_config.test.sh
git commit -m "feat(smith): add config reader with .smith/config.json defaults"
```

---

### Task 7: `jira_scan.sh` — stub mode with fixtures (TDD)

**Files:**
- Create: `scripts/jira_scan.sh`
- Create: `test/fixtures/jira-candidates.json`
- Create: `test/fixtures/jira-empty.json`
- Create: `test/fixtures/jira-ios-only.json`
- Test: `test/jira_scan.test.sh`

In Phase 1, `jira_scan.sh` only operates in stub mode: when env `SMITH_DRY_RUN_FIXTURE` is set, it returns the fixture's contents; otherwise it runs the real `acli` JQL. The real-mode code path is included but not exercised by Phase 1 tests.

- [ ] **Step 1: Write fixtures**

`test/fixtures/jira-candidates.json` (two candidates, KMP > Android):

```json
[
  {
    "key": "APP-5601",
    "summary": "Hide skeleton loader for repeat visits",
    "components": ["Android"],
    "priority": "Medium",
    "story_points": 1,
    "sprint": "SPRINT 150"
  },
  {
    "key": "APP-5612",
    "summary": "Surface localized error in shared snackbar",
    "components": ["Shared/KMP"],
    "priority": "High",
    "story_points": 2,
    "sprint": "SPRINT 150"
  }
]
```

`test/fixtures/jira-empty.json`:

```json
[]
```

`test/fixtures/jira-ios-only.json` (single iOS-only candidate, must be classified out by classify_platform.sh downstream — not by jira_scan.sh):

```json
[
  {
    "key": "APP-5700",
    "summary": "Fix navigation on iOS 18",
    "components": ["iOS"],
    "priority": "Medium",
    "story_points": 1,
    "sprint": "SPRINT 150"
  }
]
```

- [ ] **Step 2: Write the failing test**

`test/jira_scan.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/smith/scripts/jira_scan.sh"
FIX="${SCRIPT_DIR}/fixtures"

# Stub mode returns the fixture content verbatim.
got=$(SMITH_DRY_RUN_FIXTURE="${FIX}/jira-candidates.json" bash "$SCRIPT")
expected=$(cat "${FIX}/jira-candidates.json")
assert_eq "$expected" "$got" "stub-mode-candidates"

# Empty fixture yields empty array.
got=$(SMITH_DRY_RUN_FIXTURE="${FIX}/jira-empty.json" bash "$SCRIPT")
assert_eq "[]" "$got" "stub-mode-empty"

# Output is always a JSON array (validated via jq).
echo "$got" | jq -e 'type == "array"' >/dev/null

# Missing fixture path -> non-zero exit.
if SMITH_DRY_RUN_FIXTURE=/no/such/file bash "$SCRIPT" 2>/dev/null; then
  echo "FAIL: should error on missing fixture" >&2; exit 1
fi

echo "PASS jira_scan.test.sh"
```

- [ ] **Step 3: Run the test to confirm it fails**

```bash
bash smith/test/jira_scan.test.sh
```

Expected: script missing.

- [ ] **Step 4: Implement `scripts/jira_scan.sh`**

```bash
#!/usr/bin/env bash
# Scan JIRA for candidate tickets. Phase 1: stub mode via SMITH_DRY_RUN_FIXTURE.
# Real-mode (acli + JQL) included; exercised in Phase 2.
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

# Real mode (Phase 2 will validate this path end-to-end).
ROOT=$(git rev-parse --show-toplevel)
config_get() { bash "$ROOT/smith/scripts/smith_config.sh" "$1"; }

project=$(config_get jira_project_key)
status=$(config_get eligible_status)
sp_field=$(config_get story_points_field)
sprint_field=$(config_get sprint_field)

jql="assignee = currentUser() \
  AND status = \"$status\" \
  AND \"Story Points\" <= 2 \
  AND labels not in (auto-impl-failed, smith-implementing, no-auto-impl) \
  AND project = $project \
  ORDER BY priority DESC, created ASC"

acli jira workitem search --jql "$jql" \
  --fields "summary,components,priority,$sp_field,$sprint_field" \
  --json \
  | jq --arg sp "$sp_field" --arg sprint "$sprint_field" '
      [ .[] | {
          key: .key,
          summary: .fields.summary,
          components: (.fields.components // [] | map(.name)),
          priority: (.fields.priority.name // "None"),
          story_points: (.fields[$sp] // null),
          sprint: (.fields[$sprint][0].name // null)
        }
      ]'
```

- [ ] **Step 5: Run the test to confirm it passes**

```bash
chmod +x smith/scripts/jira_scan.sh
bash smith/test/jira_scan.test.sh
```

Expected: `PASS jira_scan.test.sh`.

- [ ] **Step 6: Commit**

```bash
git add smith/scripts/jira_scan.sh smith/test/jira_scan.test.sh smith/test/fixtures/*.json
git rm smith/test/fixtures/.keep 2>/dev/null || true
git commit -m "feat(smith): add jira_scan with fixture-driven stub mode"
```

---

### Task 8: `install.sh` — symlink the plugin into `.claude/` (TDD)

**Files:**
- Create: `smith/install.sh`
- Test: `test/install.test.sh`

`install.sh` makes `.claude/...` symlinks pointing at `smith/...` for every agent, command, and skill the plugin ships. Idempotent. Refuses to overwrite non-symlink files.

- [ ] **Step 1: Write the failing test**

`test/install.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

INSTALL="${ROOT}/smith/install.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Stage a fake plugin tree mirroring the real one.
mkdir -p "$TMP/smith"/{agents,commands,skills/smith-watchdog}
touch "$TMP/smith/agents/anderson.md"
touch "$TMP/smith/commands/smith-implement.md"
touch "$TMP/smith/skills/smith-watchdog/SKILL.md"

# Run install from the fake root
( cd "$TMP" && bash "$INSTALL" )

# Symlinks exist and resolve to the smith/ files
[[ -L "$TMP/.claude/agents/anderson.md" ]] || { echo "FAIL: agent symlink missing" >&2; exit 1; }
[[ -L "$TMP/.claude/commands/smith-implement.md" ]] || { echo "FAIL: command symlink missing" >&2; exit 1; }
[[ -L "$TMP/.claude/skills/smith-watchdog" ]] || { echo "FAIL: skill dir symlink missing" >&2; exit 1; }

# Re-running is idempotent (no error, no duplicates)
( cd "$TMP" && bash "$INSTALL" )

# Refuses to overwrite a non-symlink file
rm "$TMP/.claude/agents/anderson.md"
echo "real file" > "$TMP/.claude/agents/anderson.md"
if ( cd "$TMP" && bash "$INSTALL" ) 2>/dev/null; then
  echo "FAIL: should refuse to overwrite non-symlink" >&2; exit 1
fi

echo "PASS install.test.sh"
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
bash smith/test/install.test.sh
```

Expected: install script missing.

- [ ] **Step 3: Implement `smith/install.sh`**

```bash
#!/usr/bin/env bash
# Install Smith into Claude Code's project-local discovery paths via symlinks.
# Idempotent. Refuses to overwrite non-symlink files.
set -euo pipefail

# Resolve the repo root from this script's location, so install works from any cwd.
SMITH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SMITH_DIR/.." && pwd -P)"

created=0; skipped=0
link_one() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ -L "$dest" ]]; then
    local target; target=$(readlink "$dest")
    if [[ "$target" == "$src" ]]; then
      skipped=$((skipped+1)); return
    fi
    # Different target — replace
    rm "$dest"
  elif [[ -e "$dest" ]]; then
    echo "install: refusing to overwrite non-symlink $dest" >&2
    exit 1
  fi
  ln -s "$src" "$dest"
  created=$((created+1))
}

# Agents and commands: per-file symlinks
for kind in agents commands; do
  if [[ -d "$SMITH_DIR/$kind" ]]; then
    while IFS= read -r -d '' f; do
      rel="${f#$SMITH_DIR/$kind/}"
      # Skip placeholder files
      [[ "$rel" == ".keep" ]] && continue
      link_one "../../smith/$kind/$rel" "$ROOT/.claude/$kind/$rel"
    done < <(find "$SMITH_DIR/$kind" -maxdepth 1 -mindepth 1 -type f -print0)
  fi
done

# Skills: directory symlinks (one per skill)
if [[ -d "$SMITH_DIR/skills" ]]; then
  while IFS= read -r -d '' d; do
    name="$(basename "$d")"
    [[ "$name" == ".keep" ]] && continue
    link_one "../../smith/skills/$name" "$ROOT/.claude/skills/$name"
  done < <(find "$SMITH_DIR/skills" -maxdepth 1 -mindepth 1 -type d -print0)
fi

echo "smith/install.sh: $created created, $skipped already linked"
```

- [ ] **Step 4: Run the test to confirm it passes**

```bash
chmod +x smith/install.sh
bash smith/test/install.test.sh
```

Expected: `PASS install.test.sh`.

- [ ] **Step 5: Commit**

```bash
git add smith/install.sh smith/test/install.test.sh
git commit -m "feat(smith): add idempotent install.sh symlinker"
```

---

### Task 9: Mr. Anderson agent — Phase 1 placeholder

**Files:**
- Create: `agents/anderson.md`

Phase 1 ships a placeholder Anderson that always returns "no findings". Real Anderson critique logic and the three review modes (spec/plan/diff) are wired in Phase 3.

- [ ] **Step 1: Write `agents/anderson.md`**

```markdown
---
name: anderson
description: Adversarial critic for Smith pipeline. Reviews specs, plans, and diffs at each gate, returning structured findings with confidence scores. (Phase 1: placeholder returning no findings.)
tools: Read, Grep, Glob
model: sonnet
color: red
---

You are **Mr. Anderson**, the adversarial reviewer Smith dispatches at every
pipeline gate (spec, plan, diff). Your sole responsibility is to resist Mr.
Smith and prove his work insufficient. Find every flaw — scope drift, missed
edge cases, convention violations from `CLAUDE.md`, untested branches,
security issues, unclear naming, hidden assumptions.

## Confidence scoring

Rate each potential finding 0-100. **Only report findings with confidence
≥ 80.** Quality over quantity.

## Output schema

Return a JSON object on stdout:

```json
{
  "findings": [
    {
      "severity": "high" | "medium" | "low",
      "confidence": 80-100,
      "location": "file:line or section ref",
      "issue": "What is wrong, concretely",
      "suggestion": "Concrete fix"
    }
  ]
}
```

If you find nothing wrong, reread once more before returning `{"findings": []}`.

## Phase 1 placeholder behaviour

Until the real review modes are wired in Phase 3, return
`{"findings": []}` regardless of input. Log one line on stderr:
`anderson: placeholder mode, no review performed`.
```

- [ ] **Step 2: Smoke-check the file**

```bash
head -10 smith/agents/anderson.md
[[ -s smith/agents/anderson.md ]] && echo OK
```

Expected: YAML frontmatter visible; `OK`.

- [ ] **Step 3: Commit**

```bash
git add smith/agents/anderson.md
git rm smith/agents/.keep 2>/dev/null || true
git commit -m "feat(smith): add anderson agent (phase 1 placeholder)"
```

---

### Task 10: `smith-watchdog` skill skeleton

**Files:**
- Create: `skills/smith-watchdog/SKILL.md`

- [ ] **Step 1: Write `skills/smith-watchdog/SKILL.md`**

```markdown
---
name: smith-watchdog
description: One watchdog tick. Scans JIRA for eligible candidate tickets (assigned, "Ready for Development", SP ≤ 2, no opt-out labels), checks open Smith PRs for unresolved comments, and dispatches at most one action (smith-claim, smith-pr-watch, or no-op). Use when /smith-watchdog command runs or when the loop skill fires.
---

# Smith Watchdog (Tick)

Phase 1 stub. Real JIRA polling and PR-watch dispatch are wired in later
phases. This skill currently:

1. Asserts working directory via `scripts/assert_agent_repo.sh`.
2. Runs `scripts/jira_scan.sh` (stub mode in Phase 1 via
   `SMITH_DRY_RUN_FIXTURE`).
3. Logs the candidate count to `.smith/log.txt`.
4. Returns the JSON candidate list to the caller.

See `smith/docs/spec.md` Section 5.3 (per-tick decision tree) and Section 6
(JIRA integration) for the full contract this skill must satisfy in later
phases.

## Inputs

None directly. Reads:
- `SMITH_DRY_RUN_FIXTURE` env (stub mode)
- `.smith/config.json` for polling cadence, status names, project key

## Outputs

- Stdout: JSON candidate array (possibly empty)
- Side effect: one line appended to `.smith/log.txt`

## Phase 1 workflow

1. `bash smith/scripts/assert_agent_repo.sh` — abort if not in agent repo.
2. `bash smith/scripts/jira_scan.sh` — capture JSON output.
3. Log: `$(date -u +%FT%TZ) | smith-watchdog | - | scan | candidates=<N>`.
4. Print the candidate JSON.

## Out of scope for Phase 1

- Real `acli` JIRA querying (covered by jira_scan.sh's real-mode path; not
  exercised by Phase 1 tests).
- PR-watch dispatch (Phase 5).
- Candidate ranking / dispatch to smith-claim (Phase 2+).
```

- [ ] **Step 2: Commit**

```bash
git add smith/skills/smith-watchdog/SKILL.md
git rm smith/skills/.keep 2>/dev/null || true
git commit -m "feat(smith): add smith-watchdog skill skeleton"
```

---

### Task 11: `smith-claim` skill skeleton

**Files:**
- Create: `skills/smith-claim/SKILL.md`

- [ ] **Step 1: Write `skills/smith-claim/SKILL.md`**

```markdown
---
name: smith-claim
description: Claim a JIRA ticket for autonomous implementation. Runs pre-flight guards, transitions the ticket to "In Progress", adds the smith-implementing label, and creates a task/<key>-<slug> branch from origin/develop. Use when smith-watchdog dispatches a candidate for implementation.
---

# Smith Claim

See `smith/docs/spec.md` Section 11.2 for the full contract.

## Inputs

- `$TICKET` (env or first arg) — JIRA ticket key, e.g. `APP-5601`
- `$SMITH_DRY_RUN` (env) — when `1`, never write to JIRA or git remote; log
  intended actions to `.smith/log.txt` instead.

## Outputs

- Stdout: created branch name (e.g. `task/app-5601-hide-skeleton-loader`)
- Side effects (production mode): JIRA status transition, JIRA label add, new
  local branch checked out
- Side effects (dry-run mode): only `.smith/log.txt` entries

## Pre-flight (all modes)

Run before any write:

1. `bash smith/scripts/assert_agent_repo.sh`
2. `bash smith/scripts/assert_clean_worktree.sh`
3. `acli jira auth status` and `gh auth status` both succeed
4. `git fetch origin develop`
5. Re-query the ticket via acli; abort if status ≠ "Ready for Development"
   or assignee ≠ currentUser() (race-condition guard)

## Phase 1 workflow

All actions in Phase 1 are dry-run only:

1. Resolve ticket summary via `acli jira workitem view $TICKET --fields summary --json`.
2. Compute branch name via `bash smith/scripts/make_branch_name.sh $TICKET "$SUMMARY"`.
3. Append to `.smith/log.txt`:
   `<ts> | smith-claim | $TICKET | dry-run-claim | branch=<name>, would-transition=Ready->InProgress, would-label=smith-implementing`
4. Print the branch name to stdout.

## Out of scope for Phase 1

- Real status transition (`acli jira workitem transition`)
- Real label addition
- Real branch creation
```

- [ ] **Step 2: Commit**

```bash
git add smith/skills/smith-claim/SKILL.md
git commit -m "feat(smith): add smith-claim skill skeleton"
```

---

### Task 12: `smith-enrich` skill skeleton

**Files:**
- Create: `skills/smith-enrich/SKILL.md`

- [ ] **Step 1: Write `skills/smith-enrich/SKILL.md`**

```markdown
---
name: smith-enrich
description: Read a JIRA ticket and produce an enriched brief (expanded acceptance criteria, suspected affected files, identified ambiguities, suggested DoD). Used by smith-pipeline as input to the brainstorming step.
---

# Smith Enrich

See `smith/docs/spec.md` Section 11.3 for the full contract.

## Inputs

- `$TICKET` — JIRA ticket key
- `$SMITH_DRY_RUN` — when `1`, write the brief to `.smith/dry-run-briefs/`
  instead of `docs/superpowers/specs/.smith/` and skip the Explore subagent.

## Outputs

- File: `docs/superpowers/specs/.smith/$TICKET-brief.md` (production) or
  `.smith/dry-run-briefs/$TICKET-brief.md` (dry-run)
- Stdout: path to the written brief

## Phase 1 workflow

1. Resolve ticket summary + description via
   `acli jira workitem view $TICKET --fields summary,description,components --json`.
2. Write a minimal brief containing:
   - Section "Original ticket" — the verbatim JIRA description text (ADF
     flattened to markdown via `jq` walk; acceptable to be lossy in Phase 1)
   - Section "Smith's reading" — placeholder line:
     `(Phase 1 placeholder: enrichment via Explore subagent comes in Phase 2.)`
   - Section "Proposed DoD" — one bullet:
     `(Phase 1 placeholder.)`
3. Append to `.smith/log.txt`:
   `<ts> | smith-enrich | $TICKET | brief-written | path=<path>`
4. Print the brief path.

## Out of scope for Phase 1

- Explore subagent invocation
- ADF → markdown fidelity (Phase 2 will use a proper ADF walker)
- Real DoD synthesis
```

- [ ] **Step 2: Commit**

```bash
git add smith/skills/smith-enrich/SKILL.md
git commit -m "feat(smith): add smith-enrich skill skeleton"
```

---

### Task 13: `smith-pipeline` skill skeleton

**Files:**
- Create: `skills/smith-pipeline/SKILL.md`

- [ ] **Step 1: Write `skills/smith-pipeline/SKILL.md`**

```markdown
---
name: smith-pipeline
description: The full Smith pipeline. Takes an enriched brief and drives SPEC → Anderson → PLAN → Anderson → IMPL (TDD) → Anderson → verify, with bounded iteration at each gate. Commits per gate so partial progress is recoverable.
---

# Smith Pipeline

See `smith/docs/spec.md` Section 8 for the full contract.

## Inputs

- `$BRIEF_PATH` — path to the enriched brief from smith-enrich
- `$SMITH_DRY_RUN` — when `1`, skip the actual brainstorming /
  writing-plans / subagent-driven-development invocations and only call the
  Anderson placeholder; no commits.

## Outputs

- Stdout: pipeline outcome JSON: `{ "result": "success" | "stuck", "reason": "..." }`
- Side effects (production): one commit per gate on the ticket branch
- Side effects (dry-run): log entries only

## Phase 1 workflow (all dry-run)

For each of the three gates (spec, plan, diff):

1. Log: `<ts> | smith-pipeline | $TICKET | gate-start | gate=<name>`
2. Invoke Anderson placeholder via the `anderson` agent. Capture its JSON.
3. Log: `<ts> | smith-pipeline | $TICKET | gate-result | gate=<name>, findings=<N>`

Always returns `{"result": "success", "reason": "phase-1 dry-run all gates passed"}`
since the placeholder Anderson always returns no findings.

## Out of scope for Phase 1

- Real brainstorming / writing-plans / TDD invocations
- Real Anderson critique (3 review modes)
- 3-round critic loop with divergence detection
- Commit-per-gate hygiene
- Build/verify integration
```

- [ ] **Step 2: Commit**

```bash
git add smith/skills/smith-pipeline/SKILL.md
git commit -m "feat(smith): add smith-pipeline skill skeleton"
```

---

### Task 14: `smith-pr` skill skeleton

**Files:**
- Create: `skills/smith-pr/SKILL.md`

- [ ] **Step 1: Write `skills/smith-pr/SKILL.md`**

```markdown
---
name: smith-pr
description: Open the draft PR for a Smith-implemented ticket. Two paths: success (clean PR title and body) and WIP-stuck (escalation PR with needs-human-attention label, JIRA label swap, promoted spec/plan/brief). Always opens DRAFT — never marks ready-for-review, never merges.
---

# Smith PR

See `smith/docs/spec.md` Section 11.5 for the full contract.

## Inputs

- `$TICKET`, `$BRANCH`
- `$OUTCOME` — `success` or `stuck`
- `$STUCK_REASON` — required when `$OUTCOME=stuck`
- `$SMITH_DRY_RUN` — when `1`, log intended actions only

## Outputs

- Stdout: would-be PR URL placeholder in Phase 1 (`dry-run://pr/$TICKET`)
- Side effects (production): `git push`, `gh pr create --draft`, JIRA label
  ops, optional artifact promotion (stuck path)
- Side effects (dry-run): log entries only

## Phase 1 workflow

All actions are dry-run:

1. Compose PR title:
   - `$OUTCOME=success` → `[<TICKET>] <summary>`
   - `$OUTCOME=stuck` → `[WIP - agent-stuck] [<TICKET>] <summary>`
2. Compose PR body (full structure per spec Section 10.3; placeholder body
   acceptable for Phase 1).
3. Log: `<ts> | smith-pr | $TICKET | dry-run-pr | outcome=$OUTCOME, would-push=$BRANCH, title="<title>"`
4. Print `dry-run://pr/$TICKET`.

## Out of scope for Phase 1

- Real `git push`
- Real `gh pr create --draft`
- Label add/remove operations
- WIP-stuck artifact promotion
```

- [ ] **Step 2: Commit**

```bash
git add smith/skills/smith-pr/SKILL.md
git commit -m "feat(smith): add smith-pr skill skeleton"
```

---

### Task 15: `smith-pr-watch` skill skeleton

**Files:**
- Create: `skills/smith-pr-watch/SKILL.md`

- [ ] **Step 1: Write `skills/smith-pr-watch/SKILL.md`**

```markdown
---
name: smith-pr-watch
description: Fan-out poller for all open Smith-authored draft PRs. Per-PR: ensure worktree exists, fetch unresolved comments, address them via pr-feedback-helper, commit and push. Tracks per-thread fix cycles; tags needs-human-attention after 5 cycles on the same thread.
---

# Smith PR Watch

See `smith/docs/spec.md` Section 11.6 for the full contract.

## Inputs

- None (discovers state via `gh pr list --label smith-authored`)
- `$SMITH_DRY_RUN` env

## Outputs

- One log line per PR processed
- Side effects (production): per-PR worktree create, commit, push, label ops
- Side effects (dry-run): log only

## Phase 1 workflow

Phase 1 only lists candidate PRs and logs them:

1. `gh pr list --label smith-authored --state open --json number,title,headRefName`
   (in dry-run mode this is allowed because it's a read-only API call;
   alternately when `$SMITH_DRY_RUN_FIXTURE_PRS` is set, read that fixture.)
2. For each PR, log:
   `<ts> | smith-pr-watch | PR-<N> | dry-run-scan | branch=<head>`

No comment fetching, no worktree creation, no commits.

## Out of scope for Phase 1

- Per-PR worktree creation under `.smith/worktrees/`
- pr-feedback-helper integration
- Per-thread fix-cycle counter and `needs-human-attention` labelling
- Real commit + push
```

- [ ] **Step 2: Commit**

```bash
git add smith/skills/smith-pr-watch/SKILL.md
git commit -m "feat(smith): add smith-pr-watch skill skeleton"
```

---

### Task 16: `/smith-implement` slash command

**Files:**
- Create: `commands/smith-implement.md`

- [ ] **Step 1: Write `commands/smith-implement.md`**

```markdown
---
description: Run the full Smith pipeline against a specific JIRA ticket. Use --dry-run to walk the pipeline without any external side effects.
---

# /smith-implement

Args:
- `$1` (required): JIRA ticket key, e.g. `APP-5601`
- `$2` (optional): `--dry-run` to skip all external side effects

## Usage

```
/smith-implement APP-5601
/smith-implement APP-5601 --dry-run
```

## Workflow

Parse args. If `$2` is `--dry-run`, set env `SMITH_DRY_RUN=1` for all
subsequent skill invocations and (in Phase 1) set
`SMITH_DRY_RUN_FIXTURE` to point at the candidate fixture for jira_scan.

Then drive the pipeline by invoking these skills **in order** via the Skill
tool, passing `$TICKET` and `$SMITH_DRY_RUN` through:

1. `smith-claim` — produces a branch name (or aborts if pre-flight fails).
2. `smith-enrich` — produces an enriched brief path.
3. `smith-pipeline` — produces a pipeline-outcome JSON
   (`{"result": "success"|"stuck", "reason": "..."}`).
4. `smith-pr` — produces a (dry-run) PR URL.

At each step, if the skill exits non-zero, halt and report which step failed.

## Output

On success, print:

```
Smith implement complete (dry-run=<true|false>)
  Ticket:  $TICKET
  Branch:  <branch>
  Brief:   <brief path>
  Outcome: <success|stuck> (<reason>)
  PR:      <url>
```

Then `tail -5 .smith/log.txt` so the human can see what was logged.

## Phase 1 notes

In Phase 1, every skill is dry-run-aware. With `--dry-run`, no JIRA, git
remote, or GitHub state is changed. Without `--dry-run`, **the skills still
run in their Phase 1 placeholder mode** (they have not been wired to perform
real writes yet) — so it's safe to invoke without `--dry-run`, but you
won't get a real PR until Phase 4. Phase 6 enables the autonomous watchdog.
```

- [ ] **Step 2: Commit**

```bash
git add smith/commands/smith-implement.md
git rm smith/commands/.keep 2>/dev/null || true
git commit -m "feat(smith): add /smith-implement slash command"
```

---

### Task 17: `/smith-watchdog` slash command

**Files:**
- Create: `commands/smith-watchdog.md`

- [ ] **Step 1: Write `commands/smith-watchdog.md`**

```markdown
---
description: Start the autonomous Smith watchdog. Uses the loop skill to poll JIRA every 30 minutes (configurable) for eligible candidate tickets and to fan-out PR-watch across open Smith PRs.
---

# /smith-watchdog

Args: optional `--dry-run`

## Usage

```
/smith-watchdog
/smith-watchdog --dry-run
```

## Workflow

In Phase 1 this is a thin shell:

1. Resolve polling cadence via
   `bash smith/scripts/smith_config.sh polling_minutes` (default 30).
2. Invoke the global `loop` skill with that cadence, asking it to repeatedly
   invoke the `smith-watchdog` skill.

`/loop 30m /smith-watchdog-tick` (the tick command is the `smith-watchdog`
skill, surfaced as a no-arg invocation).

Pass `SMITH_DRY_RUN=1` through if invoked with `--dry-run`.

## Phase 1 limitations

The `smith-watchdog` skill currently just lists candidates and logs them —
no claim, no implementation, no PR-watch fan-out. Phase 6 makes this end-to-end.

## Kill switches

- Ctrl-C the Claude Code session
- `touch .smith/STOP` — next tick exits cleanly
- Add `no-auto-impl` label to a specific JIRA ticket
```

- [ ] **Step 2: Commit**

```bash
git add smith/commands/smith-watchdog.md
git commit -m "feat(smith): add /smith-watchdog slash command"
```

---

### Task 18: Run install.sh and verify discovery

**No new files.** This task wires the plugin into Claude Code's discovery via the symlinks.

- [ ] **Step 1: Run the installer**

```bash
cd ~/myposter-agent-repo
bash smith/install.sh
```

Expected output: `smith/install.sh: 9 created, 0 already linked` (2 commands + 1 agent + 6 skill dirs = 9).

- [ ] **Step 2: Inspect the symlinks**

```bash
ls -la .claude/commands/ .claude/agents/ .claude/skills/ | head -40
```

Expected: smith-* entries shown with `->` pointing into `../../smith/...`.

- [ ] **Step 3: Verify each symlink resolves to a real file**

```bash
for l in .claude/commands/smith-implement.md \
         .claude/commands/smith-watchdog.md \
         .claude/agents/anderson.md \
         .claude/skills/smith-watchdog/SKILL.md \
         .claude/skills/smith-claim/SKILL.md \
         .claude/skills/smith-enrich/SKILL.md \
         .claude/skills/smith-pipeline/SKILL.md \
         .claude/skills/smith-pr/SKILL.md \
         .claude/skills/smith-pr-watch/SKILL.md; do
  [[ -f "$l" ]] && echo "OK $l" || { echo "MISSING $l"; exit 1; }
done
```

Expected: 9 `OK` lines.

- [ ] **Step 4: Confirm symlinks are not staged as ordinary files**

```bash
git status --short .claude/ | head
```

Expected: each entry tagged as `??` (untracked symlink) — they should NOT be tracked. They are runtime install artefacts, not source.

- [ ] **Step 5: Add `.claude/` symlinks to `.gitignore`**

Append to `.gitignore` under the `### Smith ###` block (created in Task 1):

```
.claude/agents/anderson.md
.claude/commands/smith-implement.md
.claude/commands/smith-watchdog.md
.claude/skills/smith-watchdog
.claude/skills/smith-claim
.claude/skills/smith-enrich
.claude/skills/smith-pipeline
.claude/skills/smith-pr
.claude/skills/smith-pr-watch
```

- [ ] **Step 6: Commit the .gitignore update**

```bash
git add .gitignore
git commit -m "chore(smith): gitignore install.sh-managed .claude/ symlinks"
```

---

### Task 19: End-to-end dry-run smoke test

**Files:**
- Create: `test/smoke-dry-run.test.sh`

This test exercises the only code paths Phase 1 owns — the scripts and the install.sh. It does **not** invoke the slash command (the harness can't drive itself); instead it asserts that the scripts compose correctly given fixture inputs, and that the `.smith/log.txt` lines the skills are documented to produce would be valid log entries.

- [ ] **Step 1: Write the smoke test**

`test/smoke-dry-run.test.sh`:

```bash
#!/usr/bin/env bash
# End-to-end smoke test for Smith Phase 1 — verifies the script-level
# pipeline produces the expected outputs and log lines.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

FIX="${SCRIPT_DIR}/fixtures"

# 1. JIRA scan in stub mode returns 2 candidates from the fixture.
candidates=$(SMITH_DRY_RUN_FIXTURE="${FIX}/jira-candidates.json" \
  bash "${ROOT}/smith/scripts/jira_scan.sh")
n=$(echo "$candidates" | jq 'length')
assert_eq "2" "$n" "candidate-count"

# 2. Top candidate's components classify to "android"
top=$(echo "$candidates" | jq -c '.[0]')
top_components=$(echo "$top" | jq '.components')
platform=$(echo "$top_components" | bash "${ROOT}/smith/scripts/classify_platform.sh")
assert_eq "android" "$platform" "top-platform"

# 3. Second candidate classifies to "kmp"
second_components=$(echo "$candidates" | jq '.[1].components')
platform2=$(echo "$second_components" | bash "${ROOT}/smith/scripts/classify_platform.sh")
assert_eq "kmp" "$platform2" "second-platform"

# 4. Branch name composes deterministically for the top candidate
key=$(echo "$top" | jq -r '.key')
summary=$(echo "$top" | jq -r '.summary')
branch=$(bash "${ROOT}/smith/scripts/make_branch_name.sh" "$key" "$summary")
assert_eq "task/app-5601-hide-skeleton-loader-for-repeat-visits" "$branch" "top-branch"

# 5. iOS-only fixture classifies to "ios" (will be rejected by smith-watchdog filter)
ios_components=$(jq '.[0].components' < "${FIX}/jira-ios-only.json")
ios_platform=$(echo "$ios_components" | bash "${ROOT}/smith/scripts/classify_platform.sh")
assert_eq "ios" "$ios_platform" "ios-only-rejected"

# 6. Pre-flight scripts succeed inside the real repo
( cd "$ROOT" && bash "${ROOT}/smith/scripts/assert_agent_repo.sh" )
( cd "$ROOT" && bash "${ROOT}/smith/scripts/assert_clean_worktree.sh" ) >/dev/null

# 7. install.sh symlinks all resolve
for l in .claude/commands/smith-implement.md \
         .claude/commands/smith-watchdog.md \
         .claude/agents/anderson.md \
         .claude/skills/smith-watchdog/SKILL.md; do
  [[ -f "$ROOT/$l" ]] || { echo "FAIL: symlink missing: $l" >&2; exit 1; }
done

echo "PASS smoke-dry-run.test.sh"
```

- [ ] **Step 2: Run the smoke test**

Pre-condition: working tree must be clean for step 6. The previous commits leave it clean. If not, the engineer should commit or stash anything outstanding before running.

```bash
bash smith/test/smoke-dry-run.test.sh
```

Expected: `PASS smoke-dry-run.test.sh`.

- [ ] **Step 3: Commit**

```bash
git add smith/test/smoke-dry-run.test.sh
git commit -m "test(smith): add phase-1 end-to-end smoke test"
```

---

### Task 20: Phase 1 wrap-up — update README + final verification

**Files:**
- Modify: `smith/README.md`

- [ ] **Step 1: Update `smith/README.md` to reflect Phase 1 reality**

Replace the existing README content with:

```markdown
# Smith — Autonomous Ticket Implementation Agent

Self-contained Claude Code plugin that picks up small JIRA tickets and drives
them to a draft PR autonomously, with adversarial review by Mr. Anderson.

## Status

Phase 1 (skeleton + dry-run end-to-end). The plugin scaffold, slash commands,
agent, and all six skills are in place; every skill is a Phase 1 placeholder
that logs intended actions to `.smith/log.txt` without touching JIRA, git
remote, or GitHub. Subsequent phases (see `docs/plans/`) progressively wire
real behaviour.

See `docs/spec.md` for the full design.

## Install

From the agent-repo root:

```bash
./smith/install.sh
```

This creates symlinks under `.claude/{agents,commands,skills}/` so Claude
Code discovers Smith's items via the project-local discovery path.

The symlinks are gitignored — the source of truth is `smith/`.

## Run all script tests

```bash
for t in smith/test/*.test.sh smith/test/lib/*.test.sh; do
  bash "$t" || exit 1
done
echo "All Phase 1 tests pass."
```

## Slash commands

- `/smith-implement APP-XXXX [--dry-run]` — manual single-ticket pipeline.
- `/smith-watchdog [--dry-run]` — autonomous loop (Phase 6 enables real
  ticket pickup).

## Layout

```
smith/
  .claude-plugin/plugin.json   Plugin manifest
  agents/anderson.md           Adversarial critic
  commands/smith-*.md          Slash commands
  skills/smith-*/SKILL.md      Six skills
  scripts/                     Shared helpers (jira_scan, classify, ...)
  test/                        Script tests + fixtures
  docs/spec.md                 Design spec
  docs/plans/                  One plan per phase
  install.sh                   Symlinks plugin into .claude/
```

## Kill switches

- `touch .smith/STOP` — watchdog exits cleanly at next tick.
- Add `no-auto-impl` label to a JIRA ticket — watchdog skips it.
- Ctrl-C the Claude Code session.
```

- [ ] **Step 2: Run every test once more, end-to-end**

```bash
for t in smith/test/lib/*.test.sh smith/test/*.test.sh; do
  echo "=== $t ==="
  bash "$t"
done
```

Expected: every test prints `PASS …` and exits 0.

- [ ] **Step 3: Commit the README update**

```bash
git add smith/README.md
git commit -m "docs(smith): update README for phase 1 completion"
```

- [ ] **Step 4: Final sanity check**

```bash
git log smith/phase-1-skeleton --oneline ^origin/develop
git diff --stat origin/develop...HEAD
```

Expected: ~15 commits, ~25 files changed, all under `smith/` plus `.gitignore`. No changes outside `smith/`, `.gitignore`, or `.claude/` symlinks. iOS app, Android app, shared, Gradle config — all untouched.

- [ ] **Step 5: Manual verification — open Claude Code on the agent repo and try the slash commands**

This is a human-in-the-loop sanity check that the harness actually discovers the symlinked items:

```bash
cd ~/myposter-agent-repo
claude
```

Then in the Claude Code session, verify:
- `/smith-implement` shows up in autocomplete
- `/smith-watchdog` shows up in autocomplete
- Running `/smith-implement APP-5601 --dry-run` walks the four skills (you'll see their workflow markdown rendered as the agent invokes each one) and prints the success summary
- `tail -10 .smith/log.txt` shows the dry-run log entries

Phase 1 is complete when this manual verification passes.

---

## Self-Review Checklist

### Spec coverage

Mapping spec sections to plan tasks:

| Spec section | Covered by task |
|---|---|
| 1.1 Operating boundary | Task 5 (assert_agent_repo) |
| 3 Naming | Task 1 (plugin.json) + Tasks 16/17 (commands) + Task 9 (agent) |
| 5.3 Decision tree | Task 10 (smith-watchdog skeleton) |
| 6.1 JQL | Task 7 (jira_scan real-mode path) |
| 6.7 Platform classification | Task 4 (classify_platform components mode) |
| 7.1 Branch naming | Task 3 (make_branch_name) |
| 7.4 Pre-flight | Task 5 (both guards) |
| 8 Pipeline | Task 13 (smith-pipeline skeleton) |
| 8.1 Anderson agent | Task 9 (anderson.md placeholder) |
| 11.1–11.6 Skill contracts | Tasks 10–15 |
| 10.4 Observability | Documented in each skill's workflow (log lines) |
| 12.1 Things Smith never does | Enforced by dry-run mode; real enforcement Phase 4 |
| 13 Security model | Filesystem guard (Task 5); rest documented; enforced Phase 4 |
| 14 Testing strategy | Tasks 2-8 + Task 19 (smoke test) |
| 17 Source layout & packaging | All tasks (smith/ is the source of truth) |

Gaps: nothing in Phase 1 enforces sections 13.2 (network surface) or 13.6 (destructive-op denylist) at code level — those are tooling-level invariants applied in Phase 4 (smith-pr live mode) and Phase 5 (smith-pr-watch live mode). Phase 1 dry-run mode covers them by construction (no external writes).

### Placeholder scan

- "Phase 1 placeholder" appears in `anderson.md` and several SKILL.md files —
  this is intentional and labelled. Each placeholder explicitly states what
  Phase 1 does vs what later phases will add.
- No bare "TBD" / "TODO" / "fill in details" appear in tasks.

### Type consistency

- Branch-name format `task/<key-lower>-<slug>` matches across Task 3 test
  ("task/app-5485-..."), spec Section 7.1, and the JIRA fixtures' implied
  branches.
- Log-line format `<ts> | <skill> | <ticket> | <event> | <details>` used
  consistently across skill workflows (Tasks 10–15).
- `SMITH_DRY_RUN=1` (env, not arg) used consistently as the dry-run signal.
- `SMITH_DRY_RUN_FIXTURE` (path env) used consistently as the
  fixture-input override.
- Fixture filenames (`jira-candidates.json`, etc.) match between Task 7
  fixtures and Task 19 smoke test.
