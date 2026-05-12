# Augment-Driven Fix Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace today's monolithic Smith-with-modes PR-fix flow with a separate fixer teammate pair (smith-fixer + anderson-fixer) driven by an `augment review` PR comment trigger, with critical triage, Anderson-validated dismissals, a per-PR round counter, an explicit convergence path, and split concurrency caps.

**Architecture:** Two distinct teammate-pair roles share the watchdog lead. Impl pairs (smith-impl + anderson-impl, renamed from current files) handle ticket-mode and exit at PR-open. Fixer pairs (smith-fixer + anderson-fixer, new agent types) handle one round of PR review feedback each, dispatched fresh by the pr-comments monitor and ending with a re-trigger comment or a convergence summary. State lives in `.smith/state/pr-fix-rounds/<pr>.json`; the watchdog checks the round counter before dispatching and escalates at the cap.

**Tech Stack:** Bash, `jq` for JSON, `gh` (including `gh api graphql` for thread resolution), `acli` for JIRA, Claude Code agent-teams + monitors + hooks plugin features.

---

## File structure

**New files:**

| File | Responsibility |
|---|---|
| `agents/smith-fixer.md` | Fixer Smith persona — per-round triage, fix-or-dismiss, push, re-trigger or converge |
| `agents/anderson-fixer.md` | Fixer Anderson persona — validates every dismissal via the new triage mailbox protocol |
| `scripts/pr_fix_round_inc.sh` | Per-PR round counter (rounds, fix_total, dismiss_total, augment_trigger_count, timestamps) |
| `scripts/gh_resolve_review_thread.sh` | Post a reply to a GraphQL review thread and mark it resolved, in one call |
| `scripts/cleanup_pr_state.sh` | Convergence cleanup: post summary comment, then remove per-PR state files |
| `test/pr_fix_round_inc.test.sh` | Tests for the round counter |
| `test/gh_resolve_review_thread.test.sh` | Tests using fake_gh |
| `test/cleanup_pr_state.test.sh` | Tests using fake_gh for the summary comment, real fs for state deletion |

**Renamed files (`git mv`, preserves history):**

| From | To |
|---|---|
| `agents/smith.md` | `agents/smith-impl.md` |
| `agents/anderson.md` | `agents/anderson-impl.md` |

**Modified files:**

| File | Change |
|---|---|
| `scripts/active_smiths.sh` | Replace `mode` values `ticket\|pr-fix` with `impl\|fixer`; add `count <impl\|fixer>` subcommand |
| `scripts/smith_config.sh` | Split `max_concurrent_smiths` into `max_concurrent_impl_smiths` (default 2) and `max_concurrent_fixer_smiths` (default 2); add `max_fix_rounds` (default 5) |
| `skills/pr/SKILL.md` | Add step posting `gh pr comment <pr> --body "augment review"` after successful PR create (success path only) |
| `skills/watchdog/SKILL.md` | Update dispatch routines to use new agent types; split caps; round-counter check + escalation in fixer dispatch |
| `commands/watchdog.md` | Update monitor description and caps docs |
| `commands/implement.md` | Update agent type names (smith → smith-impl, anderson → anderson-impl) in spawn-prompt templates |
| `agents/smith-impl.md` (post-rename) | Delete the entire "PR-fix mode" section (lines that were ~85–127 in the pre-rename file); ticket mode only |
| `docs/spec.md` | Update Section 18.3 spawn-prompt templates to new agent type names and update the team types/architecture text |
| `README.md` | Brief note on the new fixer pair role |
| `test/active_smiths.test.sh` | New role values |
| `test/smith_config.test.sh` | New keys |

**Deleted files:**

| File | Reason |
|---|---|
| `scripts/pr_fix_cycle_inc.sh` | Per-thread counter replaced by per-PR round counter |
| `test/pr_fix_cycle_inc.test.sh` | Same |

---

## Spec deviation notes

The committed spec has one inconsistency I'm resolving in this plan: it sometimes describes `<impl\|fixer-round\|fixer-pr-fix>` as three distinct roles but elsewhere says the fixer doesn't differentiate by trigger source (Augment vs. human). This plan goes with the simpler **two-role design** (`impl` and `fixer`), matching the "single fixer regardless of source" intent. Update the spec at the end of the plan if you want it cleaned up.

---

### Task 1: Per-PR round counter script

**Files:**
- Create: `scripts/pr_fix_round_inc.sh`
- Create: `test/pr_fix_round_inc.test.sh`

- [ ] **Step 1: Write the failing test**

```bash
# test/pr_fix_round_inc.test.sh
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/pr_fix_round_inc.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)

# Make TMP look like a git repo so the script can find its root.
( cd "$TMP" && git init -q && git commit --allow-empty -q -m init )

# First call: bumps rounds=1, initializes counters.
got=$( cd "$TMP" && bash "$SCRIPT" 891 )
assert_eq "1" "$got" "first-bump"

state="$TMP/.smith/state/pr-fix-rounds/pr-891.json"
[[ -f "$state" ]] || { echo "FAIL: state file not created" >&2; exit 1; }
assert_eq "1" "$(jq -r .rounds "$state")"        "rounds=1"
assert_eq "0" "$(jq -r .fix_total "$state")"     "fix_total=0"
assert_eq "0" "$(jq -r .dismiss_total "$state")" "dismiss_total=0"
[[ "$(jq -r .first_round_at "$state")" != "" ]] || { echo "FAIL: first_round_at empty" >&2; exit 1; }

# Second call: bumps rounds=2; first_round_at unchanged.
first_at=$(jq -r .first_round_at "$state")
got=$( cd "$TMP" && bash "$SCRIPT" 891 )
assert_eq "2" "$got" "second-bump"
assert_eq "$first_at" "$(jq -r .first_round_at "$state")" "first_round_at sticky"

# --fix and --dismiss accumulate.
( cd "$TMP" && bash "$SCRIPT" 891 --fix 3 --dismiss 2 ) > /dev/null
assert_eq "3" "$(jq -r .rounds "$state")"        "rounds=3 after --fix --dismiss call"
assert_eq "3" "$(jq -r .fix_total "$state")"     "fix_total accumulated"
assert_eq "2" "$(jq -r .dismiss_total "$state")" "dismiss_total accumulated"

# --trigger increments augment_trigger_count without bumping rounds.
( cd "$TMP" && bash "$SCRIPT" 891 --trigger ) > /dev/null
assert_eq "3" "$(jq -r .rounds "$state")" "rounds unchanged by --trigger"
assert_eq "1" "$(jq -r .augment_trigger_count "$state")" "trigger count"

# Missing PR number errors out.
if ( cd "$TMP" && bash "$SCRIPT" 2>/dev/null ); then
  echo "FAIL: missing arg should error" >&2; exit 1
fi

echo "PASS pr_fix_round_inc.test.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash test/pr_fix_round_inc.test.sh`
Expected: FAIL with "No such file or directory" for `scripts/pr_fix_round_inc.sh`.

- [ ] **Step 3: Write minimal implementation**

```bash
# scripts/pr_fix_round_inc.sh
#!/usr/bin/env bash
# Per-PR fix-round counter. Replaces the old per-thread cycle counter.
# State file schema (per spec):
#   {
#     "pr": <int>,
#     "rounds": <int>,
#     "fix_total": <int>,
#     "dismiss_total": <int>,
#     "augment_trigger_count": <int>,
#     "first_round_at": "<ISO-8601 UTC>",
#     "last_round_at":  "<ISO-8601 UTC>"
#   }
#
# Usage:
#   pr_fix_round_inc.sh <PR>
#       Bump rounds. Print the new round count.
#   pr_fix_round_inc.sh <PR> --fix N --dismiss N
#       Bump rounds AND accumulate fix_total / dismiss_total by N each.
#   pr_fix_round_inc.sh <PR> --trigger
#       Increment augment_trigger_count only. Does NOT bump rounds.
set -euo pipefail

PR="${1:?usage: pr_fix_round_inc.sh <PR> [--fix N] [--dismiss N] [--trigger]}"
shift

fix_delta=0
dismiss_delta=0
trigger=0
while (($# > 0)); do
  case "$1" in
    --fix)     fix_delta="${2:?--fix needs a number}"; shift 2 ;;
    --dismiss) dismiss_delta="${2:?--dismiss needs a number}"; shift 2 ;;
    --trigger) trigger=1; shift ;;
    *) echo "pr_fix_round_inc: unknown arg: $1" >&2; exit 1 ;;
  esac
done

target_root=$(git rev-parse --show-toplevel)
state_dir="$target_root/.smith/state/pr-fix-rounds"
state_file="$state_dir/pr-$PR.json"
mkdir -p "$state_dir"

now=$(date -u +%FT%TZ)

if [[ ! -f "$state_file" ]]; then
  jq -n --argjson pr "$PR" --arg now "$now" '{
    pr: $pr,
    rounds: 0,
    fix_total: 0,
    dismiss_total: 0,
    augment_trigger_count: 0,
    first_round_at: $now,
    last_round_at: $now
  }' > "$state_file"
fi

tmp=$(mktemp)
jq --arg now "$now" \
   --argjson fix "$fix_delta" \
   --argjson dis "$dismiss_delta" \
   --argjson trig "$trigger" '
  if $trig == 1 then
    .augment_trigger_count = (.augment_trigger_count + 1)
  else
    .rounds = (.rounds + 1)
    | .fix_total = (.fix_total + $fix)
    | .dismiss_total = (.dismiss_total + $dis)
    | .last_round_at = $now
  end
' "$state_file" > "$tmp"
mv "$tmp" "$state_file"

jq -r '.rounds' "$state_file"
```

- [ ] **Step 4: Make script executable and run test**

```bash
chmod +x scripts/pr_fix_round_inc.sh
bash test/pr_fix_round_inc.test.sh
```
Expected: `PASS pr_fix_round_inc.test.sh`

- [ ] **Step 5: Commit**

```bash
git add scripts/pr_fix_round_inc.sh test/pr_fix_round_inc.test.sh
git commit -m "Add per-PR fix-round counter (pr_fix_round_inc.sh)

Replaces today's per-thread cycle counter with a per-PR aggregate
that tracks rounds, fix_total, dismiss_total, and
augment_trigger_count. The fixer team bumps this once per round; the
watchdog reads it before dispatching to enforce MAX_FIX_ROUNDS.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: GraphQL helper — reply + resolve a review thread

**Files:**
- Create: `scripts/gh_resolve_review_thread.sh`
- Create: `test/gh_resolve_review_thread.test.sh`

- [ ] **Step 1: Write the failing test**

```bash
# test/gh_resolve_review_thread.test.sh
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/gh_resolve_review_thread.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
mkdir -p "$TMP/bin"
cp "${SCRIPT_DIR}/lib/fake_gh.sh" "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"

export PATH="$TMP/bin:$PATH"
export SMITH_FAKE_GH_LOG="$TMP/gh.log"

# Happy path: script accepts thread id + body, makes the two GraphQL calls.
bash "$SCRIPT" PRRT_xyz "Not applicable: this caller is removed."

# Verify both GraphQL mutations were attempted: addPullRequestReviewThreadReply, resolveReviewThread
grep -qF -e "addPullRequestReviewThreadReply" "$TMP/gh.log" \
  || { echo "FAIL: addPullRequestReviewThreadReply not called" >&2; cat "$TMP/gh.log" >&2; exit 1; }
grep -qF -e "resolveReviewThread" "$TMP/gh.log" \
  || { echo "FAIL: resolveReviewThread not called" >&2; cat "$TMP/gh.log" >&2; exit 1; }
grep -qF -e "PRRT_xyz" "$TMP/gh.log" \
  || { echo "FAIL: thread id not passed" >&2; cat "$TMP/gh.log" >&2; exit 1; }

# Missing args error out.
if bash "$SCRIPT" 2>/dev/null; then echo "FAIL: missing args" >&2; exit 1; fi
if bash "$SCRIPT" PRRT_only 2>/dev/null; then echo "FAIL: missing body" >&2; exit 1; fi

echo "PASS gh_resolve_review_thread.test.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash test/gh_resolve_review_thread.test.sh`
Expected: FAIL — script does not exist.

- [ ] **Step 3: Write minimal implementation**

```bash
# scripts/gh_resolve_review_thread.sh
#!/usr/bin/env bash
# Reply to a GitHub PR review thread, then mark it resolved. Two
# GraphQL mutations, one logical action. Used by smith-fixer when
# Smith+Anderson agree to dismiss a finding — the reply explains the
# dismissal and the resolve clears it from the active thread list.
#
# Usage: gh_resolve_review_thread.sh <THREAD-ID> <REPLY-BODY>
#
# THREAD-ID: a GraphQL PullRequestReviewThread node ID (PRRT_...)
# REPLY-BODY: the comment text to post as the reply.

set -euo pipefail

THREAD="${1:?usage: gh_resolve_review_thread.sh <THREAD-ID> <REPLY-BODY>}"
BODY="${2:?usage: gh_resolve_review_thread.sh <THREAD-ID> <REPLY-BODY>}"

# 1. Post the reply.
gh api graphql \
  -f query='mutation($threadId:ID!,$body:String!){
    addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$threadId, body:$body}){
      comment { id }
    }
  }' \
  -f threadId="$THREAD" -f body="$BODY" >/dev/null

# 2. Resolve the thread.
gh api graphql \
  -f query='mutation($threadId:ID!){
    resolveReviewThread(input:{threadId:$threadId}){
      thread { id isResolved }
    }
  }' \
  -f threadId="$THREAD" >/dev/null
```

- [ ] **Step 4: Make script executable and run test**

```bash
chmod +x scripts/gh_resolve_review_thread.sh
bash test/gh_resolve_review_thread.test.sh
```
Expected: `PASS gh_resolve_review_thread.test.sh`

- [ ] **Step 5: Commit**

```bash
git add scripts/gh_resolve_review_thread.sh test/gh_resolve_review_thread.test.sh
git commit -m "Add gh_resolve_review_thread.sh — reply + resolve in one call

Two GraphQL mutations bundled as a single action smith-fixer uses to
dismiss a review finding with a written justification.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `active_smiths.sh` — `impl` / `fixer` roles + per-role count

**Files:**
- Modify: `scripts/active_smiths.sh`
- Modify: `test/active_smiths.test.sh`

- [ ] **Step 1: Update the existing test to reflect the new role values**

In `test/active_smiths.test.sh`, every place that uses `"ticket"` or `"pr-fix"` becomes `"impl"` or `"fixer"`. Add new assertions for per-role count.

Edit the test file to:
- Replace every literal `"ticket"` (when used as the mode arg to `active_smiths.sh add ...`) with `"impl"`.
- Replace every literal `"pr-fix"` with `"fixer"`.
- Add these assertions after the existing add/count cases (keep the existing total-count assertions intact):

```bash
# Per-role count subcommand.
got=$( cd "$TMP" && bash "$SCRIPT" count impl )
assert_eq "1" "$got" "count impl after one impl add"

got=$( cd "$TMP" && bash "$SCRIPT" count fixer )
assert_eq "0" "$got" "count fixer when no fixer added"

# Add a fixer entry, then re-check.
( cd "$TMP" && bash "$SCRIPT" add smith-fixer-891 anderson-fixer-891 fixer 891 )
got=$( cd "$TMP" && bash "$SCRIPT" count fixer )
assert_eq "1" "$got" "count fixer after fixer add"
got=$( cd "$TMP" && bash "$SCRIPT" count impl )
assert_eq "1" "$got" "count impl unchanged"
got=$( cd "$TMP" && bash "$SCRIPT" count )
assert_eq "2" "$got" "total count = 2"
```

- [ ] **Step 2: Run test, observe failures**

Run: `bash test/active_smiths.test.sh`
Expected: FAIL — `mode must be 'ticket' or 'pr-fix'` errors, and `count impl` will fail because the count subcommand doesn't accept args.

- [ ] **Step 3: Update `active_smiths.sh` to accept the new mode values and per-role count**

In `scripts/active_smiths.sh`:

Replace the case for `mode` validation in the `add` branch:
```bash
    case "$mode" in
      ticket|pr-fix) ;;
      *) echo "active_smiths: mode must be 'ticket' or 'pr-fix' (got '$mode')" >&2; exit 1 ;;
    esac
```
with:
```bash
    case "$mode" in
      impl|fixer) ;;
      *) echo "active_smiths: mode must be 'impl' or 'fixer' (got '$mode')" >&2; exit 1 ;;
    esac
```

Replace the `count` case to accept an optional role filter:
```bash
  count)
    jq 'length' "$state_file"
    ;;
```
with:
```bash
  count)
    role="${2:-}"
    if [[ -z "$role" ]]; then
      jq 'length' "$state_file"
    else
      case "$role" in
        impl|fixer) jq --arg r "$role" '[.[] | select(.mode == $r)] | length' "$state_file" ;;
        *) echo "active_smiths: count role must be 'impl' or 'fixer' (got '$role')" >&2; exit 1 ;;
      esac
    fi
    ;;
```

Update the file's header comment so the usage block reads:
```
#   active_smiths.sh count [<impl|fixer>]
#       Print the count of active pairs, optionally filtered by role.
#   active_smiths.sh add <SMITH_NAME> <ANDERSON_NAME> <MODE> <SUBJECT>
#       Record a new pair. MODE = "impl" | "fixer".
```

(The `mode` field name inside the JSON entry stays `mode` — we're only changing the allowed values, not the schema key. This minimizes churn.)

- [ ] **Step 4: Run test to verify pass**

Run: `bash test/active_smiths.test.sh`
Expected: `PASS active_smiths.test.sh`

- [ ] **Step 5: Commit**

```bash
git add scripts/active_smiths.sh test/active_smiths.test.sh
git commit -m "active_smiths: rename modes to impl/fixer, add per-role count

The watchdog now manages two pair role types (impl and fixer) with
separate concurrency caps. Renamed the mode values from ticket/pr-fix
to impl/fixer and added 'count <role>' to read each cap independently.
JSON key 'mode' kept for minimal churn.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `smith_config.sh` — split caps, add `max_fix_rounds`

**Files:**
- Modify: `scripts/smith_config.sh`
- Modify: `test/smith_config.test.sh`

- [ ] **Step 1: Update test for new keys**

In `test/smith_config.test.sh`, add (or edit existing) cases:

```bash
# New keys after the split.
got=$( cd "$TMP" && bash "$SCRIPT" max_concurrent_impl_smiths )
assert_eq "2" "$got" "max_concurrent_impl_smiths default"

got=$( cd "$TMP" && bash "$SCRIPT" max_concurrent_fixer_smiths )
assert_eq "2" "$got" "max_concurrent_fixer_smiths default"

got=$( cd "$TMP" && bash "$SCRIPT" max_fix_rounds )
assert_eq "5" "$got" "max_fix_rounds default"
```

If the existing test asserted on `max_concurrent_smiths`, replace that assertion with the impl variant.

- [ ] **Step 2: Run test, observe failure**

Run: `bash test/smith_config.test.sh`
Expected: FAIL — `null` returned for the new keys.

- [ ] **Step 3: Update `scripts/smith_config.sh`**

In the `cat > "$config" <<JSON` heredoc, replace:
```
  "max_concurrent_smiths": 2,
```
with:
```
  "max_concurrent_impl_smiths": 2,
  "max_concurrent_fixer_smiths": 2,
  "max_fix_rounds": 5,
```

The script's `jq -r ".$KEY" "$config"` read path doesn't change — it works for any key.

- [ ] **Step 4: Run test to verify pass**

Run: `bash test/smith_config.test.sh`
Expected: `PASS smith_config.test.sh`

- [ ] **Step 5: Commit**

```bash
git add scripts/smith_config.sh test/smith_config.test.sh
git commit -m "smith_config: split smiths cap into impl + fixer, add max_fix_rounds

Two concurrency caps with separate budgets: max_concurrent_impl_smiths
and max_concurrent_fixer_smiths (both default 2). Adds max_fix_rounds
(default 5) for the new per-PR fix-loop cap.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Convergence cleanup script

**Files:**
- Create: `scripts/cleanup_pr_state.sh`
- Create: `test/cleanup_pr_state.test.sh`

- [ ] **Step 1: Write the failing test**

```bash
# test/cleanup_pr_state.test.sh
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/cleanup_pr_state.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
mkdir -p "$TMP/bin"
cp "${SCRIPT_DIR}/lib/fake_gh.sh" "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"

export PATH="$TMP/bin:$PATH"
export SMITH_FAKE_GH_LOG="$TMP/gh.log"

# Make TMP a git repo so the script can resolve its root.
( cd "$TMP" && git init -q && git commit --allow-empty -q -m init )

# Pre-create per-PR state files so we can assert removal.
mkdir -p "$TMP/.smith/state/pr-fix-rounds" "$TMP/.smith/state/pr-comments"
echo '{"rounds":3,"fix_total":4,"dismiss_total":7}' > "$TMP/.smith/state/pr-fix-rounds/pr-891.json"
echo '["thread-A","thread-B"]' > "$TMP/.smith/state/pr-comments/pr-891.json"
echo '["unrelated"]' > "$TMP/.smith/state/pr-comments/pr-999.json"   # unrelated PR — must NOT be deleted

( cd "$TMP" && bash "$SCRIPT" 891 )

# State files for PR 891 are gone.
[[ ! -f "$TMP/.smith/state/pr-fix-rounds/pr-891.json" ]] \
  || { echo "FAIL: rounds state not cleaned" >&2; exit 1; }
[[ ! -f "$TMP/.smith/state/pr-comments/pr-891.json" ]] \
  || { echo "FAIL: pr-comments state not cleaned" >&2; exit 1; }

# Unrelated state is preserved.
[[ -f "$TMP/.smith/state/pr-comments/pr-999.json" ]] \
  || { echo "FAIL: unrelated PR state was deleted" >&2; exit 1; }

# Summary comment was posted via gh pr comment.
grep -qF -e "pr comment 891" "$TMP/gh.log" \
  || { echo "FAIL: pr comment not invoked" >&2; cat "$TMP/gh.log" >&2; exit 1; }
grep -qF -e "converged" "$TMP/gh.log" \
  || { echo "FAIL: summary body missing 'converged'" >&2; cat "$TMP/gh.log" >&2; exit 1; }
grep -qF -e "rounds: 3" "$TMP/gh.log" \
  || { echo "FAIL: rounds count missing from comment" >&2; cat "$TMP/gh.log" >&2; exit 1; }

echo "PASS cleanup_pr_state.test.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash test/cleanup_pr_state.test.sh`
Expected: FAIL — script does not exist.

- [ ] **Step 3: Extend `test/lib/fake_gh.sh` so `pr comment` body is logged**

Open `test/lib/fake_gh.sh` and find the existing `"pr edit"*) exit 0` case. Insert before it:

```bash
  "pr comment "*)
    # Logged in full at the top of this script.
    exit 0
    ;;
```

The body is already captured via the `printf 'gh %s\n' "$args"` at the top, so no new fixture wiring needed.

- [ ] **Step 4: Write the implementation**

```bash
# scripts/cleanup_pr_state.sh
#!/usr/bin/env bash
# Convergence cleanup. Posts the "Smith fix loop converged" summary
# comment to the PR, then removes the per-PR state files. Order
# matters: if the gh call fails, leave state in place so the lead can
# retry.
#
# Usage: cleanup_pr_state.sh <PR>

set -euo pipefail

PR="${1:?usage: cleanup_pr_state.sh <PR>}"

target_root=$(git rev-parse --show-toplevel)
rounds_file="$target_root/.smith/state/pr-fix-rounds/pr-$PR.json"
comments_file="$target_root/.smith/state/pr-comments/pr-$PR.json"

rounds=$( [[ -f "$rounds_file" ]] && jq -r .rounds "$rounds_file"        || echo 0)
fix_t=$(  [[ -f "$rounds_file" ]] && jq -r .fix_total "$rounds_file"     || echo 0)
dis_t=$(  [[ -f "$rounds_file" ]] && jq -r .dismiss_total "$rounds_file" || echo 0)

body="Smith fix loop converged after $rounds round(s).

- Findings fixed: $fix_t
- Findings dismissed with reasoning: $dis_t (see resolved review threads)

The current code reflects Smith's and Anderson's final position on
this PR. Ready for human review."

# 1. Post the summary. Fail-loud — caller propagates the error.
gh pr comment "$PR" --body "$body"

# 2. Remove per-PR state.
rm -f "$rounds_file" "$comments_file"
```

- [ ] **Step 5: Make executable and run test**

```bash
chmod +x scripts/cleanup_pr_state.sh
bash test/cleanup_pr_state.test.sh
```
Expected: `PASS cleanup_pr_state.test.sh`

- [ ] **Step 6: Commit**

```bash
git add scripts/cleanup_pr_state.sh test/cleanup_pr_state.test.sh test/lib/fake_gh.sh
git commit -m "Add cleanup_pr_state.sh — convergence summary + per-PR state delete

Called by smith-fixer when a fix round converges (zero fix-class
findings). Posts the 'Smith fix loop converged' summary comment to
the PR and removes .smith/state/pr-fix-rounds/pr-<N>.json plus the
pr-comments cache for that PR. Order is summary-first, delete-only-
on-success: a gh failure keeps state intact for retry.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Rename `agents/smith.md` → `agents/smith-impl.md`

**Files:**
- Move: `agents/smith.md` → `agents/smith-impl.md`
- Modify: `commands/implement.md`, `skills/watchdog/SKILL.md`, `docs/spec.md`, `README.md` (every reference to `smith` as an agent type)

- [ ] **Step 1: Move the file with git mv**

```bash
git mv agents/smith.md agents/smith-impl.md
```

- [ ] **Step 2: Update the frontmatter name**

In `agents/smith-impl.md` frontmatter:
```
name: smith-impl
```
(was `name: smith`)

Also tighten the description to reflect ticket-mode-only scope:
```
description: Mr. Smith (impl variant) — ticket implementer teammate. Runs claim → enrich → pipeline → smith:pr in his worktree; coordinates with Anderson via mailbox; returns outcome JSON.
```

- [ ] **Step 3: Update every place that references the bare agent type `smith` as an identifier**

In `commands/implement.md`, change:
```
**Teammate 1 — Mr. Smith**, agent type `smith`, name `smith-<ticket>`:
```
to:
```
**Teammate 1 — Mr. Smith**, agent type `smith-impl`, name `smith-impl-<ticket>`:
```

Update the inline spawn prompt's `Your Anderson is: anderson-<ticket>` to `anderson-impl-<ticket>`.

In `skills/watchdog/SKILL.md` `dispatch_ticket_mode`, change `smith-<key>` and `anderson-<key>` to `smith-impl-<key>` and `anderson-impl-<key>`. Update the `active_smiths.sh add ... ticket ...` call to `impl`. Rename the function from `dispatch_ticket_mode` to `dispatch_impl_mode` so the verb matches the type name.

In `docs/spec.md` Section 18.3, do the same renames in the example spawn prompts (`smith-APP-1234` → `smith-impl-APP-1234`, etc.). Update the prose explaining team types.

- [ ] **Step 4: Run the full test suite to catch anything else**

```bash
for t in test/*.test.sh; do
  out=$(bash "$t" 2>&1) || { echo "FAIL: $t"; echo "$out"; exit 1; }
done
echo "FULL SUITE PASS"
```
Expected: `FULL SUITE PASS`. The renames don't affect scripts, only docs/prompts.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Rename agents/smith.md → agents/smith-impl.md

Half of the impl/fixer split: the impl variant gets the renamed file.
agents/smith-fixer.md lands in a later task. Frontmatter name updated;
description tightened to ticket-mode scope. Spawn-prompt templates in
commands/implement.md, skills/watchdog/SKILL.md, and docs/spec.md
Section 18.3 updated to the new agent type and name conventions.

PR-fix-mode section inside this file is being deleted in a later task
to keep that change reviewable on its own.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Rename `agents/anderson.md` → `agents/anderson-impl.md`

**Files:**
- Move: `agents/anderson.md` → `agents/anderson-impl.md`
- Modify: places already touched in Task 6 that reference `anderson` agent type

- [ ] **Step 1: Move the file with git mv**

```bash
git mv agents/anderson.md agents/anderson-impl.md
```

- [ ] **Step 2: Update the frontmatter name**

In `agents/anderson-impl.md` frontmatter:
```
name: anderson-impl
description: Mr. Anderson (impl variant) — Smith's adversarial reviewer at each pipeline gate (spec, plan, diff). Returns structured findings via mailbox, confidence-≥80 filtered.
```

- [ ] **Step 3: Update remaining cross-references**

In `commands/implement.md`, change:
```
**Teammate 2 — Mr. Anderson**, agent type `anderson`, name `anderson-<ticket>`:
```
to:
```
**Teammate 2 — Mr. Anderson**, agent type `anderson-impl`, name `anderson-impl-<ticket>`:
```

In `scripts/hook_keep_anderson_alive.sh`, the existing matcher checks `$type == "anderson"` and `$name == anderson-*`. Update the type check to allow both `anderson-impl` and `anderson-fixer`:

```bash
case "$type" in
  anderson-impl|anderson-fixer) is_anderson=1 ;;
esac
case "$name" in
  anderson-impl-*|anderson-fixer-*) is_anderson=1 ;;
esac
```

(Drop the bare `anderson` / `anderson-*` matches; nothing spawns under those names after this rename.)

- [ ] **Step 4: Run full test suite**

```bash
for t in test/*.test.sh; do
  out=$(bash "$t" 2>&1) || { echo "FAIL: $t"; echo "$out"; exit 1; }
done
```
Expected: `FULL SUITE PASS`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Rename agents/anderson.md → agents/anderson-impl.md

Mirror of the Smith rename. TeammateIdle hook updated to recognise
both anderson-impl and anderson-fixer prefixes (the fixer file lands
in a later task).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Create `agents/smith-fixer.md`

**Files:**
- Create: `agents/smith-fixer.md`

- [ ] **Step 1: Write the persona file**

```markdown
---
name: smith-fixer
description: Mr. Smith (fixer variant) — handles one round of PR review feedback. Triages each finding with Anderson, fixes or dismisses with justification, pushes, re-triggers Augment or converges.
tools: Read, Write, Edit, NotebookEdit, Bash, Grep, Glob, WebFetch, Task
model: claude-opus-4-7
color: blue
---

You are **Mr. Smith (fixer variant)** — a per-round PR-fix teammate.

You handle exactly **one round** of review feedback on a single PR
and exit. The pr-comments monitor + watchdog handle round-to-round
sequencing; do NOT loop inside your session. Each round is a fresh
spawn with a fresh you.

## Input (from spawn prompt)

`{mode: "fixer", pr_number: N, worktree: "<path>", branch: "<task/...>", dry_run: bool, anderson_name: "anderson-fixer-PR-N"}`

The lead pre-created your worktree via
`scripts/checkout_pr_worktree.sh`. Your branch is already checked out.

## Workflow (one round, then exit)

1. **Pre-flight.** Verify you're inside the configured target repo and
   the worktree is clean:
   ```
   cd <worktree>
   bash $SMITH_PLUGIN_ROOT/scripts/assert_target_repo.sh
   bash $SMITH_PLUGIN_ROOT/scripts/assert_clean_worktree.sh
   ```

2. **Fetch unresolved threads.** Pull the current state from GitHub
   (the monitor's cached list may be stale by now):
   ```
   threads=$(bash $SMITH_PLUGIN_ROOT/scripts/gh_pr_unresolved_comments.sh "$pr_number")
   ```
   If `threads` is `[]`, you have nothing to do. Send `fixer.outcome`
   with `result: "degenerate"` and exit. The monitor will fire on the
   next real change.

3. **Triage each finding.** For each thread, decide ONE of three
   actions. The critical-thinking lens is the whole point of this
   role: don't blindly apply every suggestion.

   - `fix` — the finding is real, applicable, and worth changing the
     code for. Examples: actual bug, missing edge case, type error,
     untested branch.
   - `dismiss-not-applicable` — the finding misreads the code,
     references something that isn't there, or doesn't apply to this
     change. Examples: reviewer suggesting we add tests for a file we
     didn't touch; suggesting a fix for a "bug" that was already
     correct before this PR.
   - `dismiss-not-worth-it` — the finding is technically valid but
     the fix would be a regression on idiomatic design, reader
     cognition, or code size relative to the value gained. Examples:
     "split this 8-line function into three 2-line ones"; "rename
     this variable from `idx` to `currentIndexInBucket`"; suggested
     micro-optimisations with no measurable impact.

   For each dismissal proposal, mail Anderson:
   ```json
   {
     "type": "fix.triage.propose",
     "thread_id": "PRRT_...",
     "finding_summary": "<one line summary of what the reviewer said>",
     "proposed_action": "dismiss-not-applicable" | "dismiss-not-worth-it",
     "reasoning": "<2-4 sentences why this dismissal is justified>"
   }
   ```
   Wait for Anderson's reply:
   - `anderson.triage.drop` — dismissal stands. Proceed to step 4
     (post justification reply + resolve thread).
   - `anderson.triage.hold` — Anderson rejects the dismissal. You
     must fix the finding instead. The `counter` field tells you why.
     Reclassify as `fix` and apply the change in step 5.
   - `anderson.triage.escalate` — Anderson agrees the finding is
     genuinely beyond your judgment (e.g., needs cross-team
     input). Treat as a dismissal for now AND record it in your
     outcome's `escalations` list so the operator can pick it up.

   For findings you triage as `fix` directly (no dismissal), no
   triage round is needed — Anderson's final diff review at step 6
   covers them.

4. **Resolve dismissed threads.** For every Anderson-approved
   dismissal, post the reply and mark resolved in one step:
   ```
   bash $SMITH_PLUGIN_ROOT/scripts/gh_resolve_review_thread.sh \
        "$thread_id" "$reply_body"
   ```
   `reply_body` should be 1–3 sentences: the reasoning you proposed
   to Anderson, polished for a human audience. Make it concrete
   enough that a reviewer scanning the resolved thread can tell why
   it was dismissed.

5. **Apply the fixes.** For every finding triaged as `fix` (including
   those Anderson held), edit the worktree.
   Run the target's quality check after the edits:
   ```
   ./scripts/run-silent.sh "Quality checks" "./scripts/quality-check.sh"
   ```
   If it fails, address the failure and retry within the wall-clock
   budget (45 min total per spec). If you cannot recover, you're
   stuck — see step 9.

6. **Anderson final diff review.** Mail Anderson with `mode: "diff"`
   for a review of your cumulative changes. Standard pipeline gate
   logic (up to 3 rounds, high-severity findings block the gate).

7. **Commit and push** (no force-push). For each fix, commit
   individually with the readable title format from spec Section 18.3.5:
   ```
   fix(smith): <path>:<line> per <author>'s review (PR #<N>)
   ```
   Then:
   ```
   git push
   bash $SMITH_PLUGIN_ROOT/scripts/pr_comments_reset.sh   # kick the monitor
   ```

8. **Determine the outcome** based on this round's counts:

   - `fix_count == 0 && dismiss_count > 0` → **converged**. All
     findings dismissed with Anderson's approval. Run
     `cleanup_pr_state.sh <pr_number>` (which posts the summary and
     removes per-PR state). Do NOT post `augment review`. Bump the
     round counter one last time before cleanup so the summary
     reflects accurate totals:
     ```
     bash $SMITH_PLUGIN_ROOT/scripts/pr_fix_round_inc.sh "$pr_number" \
          --fix 0 --dismiss "$dismiss_count"
     bash $SMITH_PLUGIN_ROOT/scripts/cleanup_pr_state.sh "$pr_number"
     ```
     Send `fixer.outcome` with `result: "converged"`.

   - `fix_count > 0 && push_succeeded` → **continuing**. Bump
     counter, trigger Augment, exit:
     ```
     bash $SMITH_PLUGIN_ROOT/scripts/pr_fix_round_inc.sh "$pr_number" \
          --fix "$fix_count" --dismiss "$dismiss_count"
     gh pr comment "$pr_number" --body "augment review"
     bash $SMITH_PLUGIN_ROOT/scripts/pr_fix_round_inc.sh "$pr_number" --trigger
     ```
     Send `fixer.outcome` with `result: "continuing"`.

   - `fix_count > 0 && !push_succeeded` → **stuck**. Quality check
     never recovered. Do NOT cleanup, do NOT trigger Augment. Send
     `fixer.outcome` with `result: "stuck", reason: "<what
     broke>"`. The lead routes this through the existing WIP-stuck
     escalation.

   - `fix_count == 0 && dismiss_count == 0` → **degenerate** (see
     step 2). Just exit; the monitor will catch the next real round.

9. **Dry-run mode** (`dry_run = true`): skip the GraphQL resolve
   calls, skip the quality check, skip the commit, skip the push,
   skip the round counter bump, skip the augment trigger. Log
   intended actions to `.smith/log.txt`. Send a faux-success
   outcome.

## Outcome JSON

```json
{
  "type": "smith.outcome",
  "result": "converged" | "continuing" | "stuck" | "degenerate" | "error",
  "reason": "<one-line if not success/continuing>",
  "pr_url": "https://github.com/...",
  "round_summary": {
    "fix_count": <int>,
    "dismiss_count": <int>,
    "escalations": [{"thread_id": "...", "reason": "..."}]
  }
}
```

## Hard rules

- **No self-review of your own dismissals.** Every dismissal goes
  through Anderson. The "be critical" guidance is not a license to
  unilaterally wave away findings.
- **No force-push.** Push only adds commits. If push fails because
  the remote moved, abort with `{result: "error"}` — let the lead
  retry with a fresh pair.
- **Only `--draft` for any PR ops you might attempt** (you shouldn't
  need to — the PR is already open).
- **No editing of `.github/workflows/`, `CLAUDE.md`, `.claude/`,
  `gradle/wrapper/`.** (Dependencies in `build.gradle.kts` /
  `libs.versions.toml` are allowed; Anderson reviews them in the
  final diff gate.)
- **No spawning nested teams.**

## Pre-flight before any side effect

Before any `gh`, `git push`, or `acli` write, you re-confirm:

- You are inside the configured target repo
  (`assert_target_repo.sh` passes)
- The worktree is clean
  (`assert_clean_worktree.sh` passes — for write ops; reads are fine
  on a dirty tree)

The bash-guard hook (`hook_bash_guard.sh`) is your backstop. If you
trip it, treat it as a sign you tried something forbidden — abort
the round with `{result: "error"}` rather than retrying around it.
```

- [ ] **Step 2: No automated test — this is LLM-prompt content**

Verify by reading: open `agents/smith-fixer.md` and confirm the workflow steps match the spec's "Fixer team workflow (per round)" section and the outcome matrix matches the Convergence section's table.

- [ ] **Step 3: Run full test suite (sanity check)**

```bash
for t in test/*.test.sh; do
  out=$(bash "$t" 2>&1) || { echo "FAIL: $t"; echo "$out"; exit 1; }
done
```
Expected: `FULL SUITE PASS`

- [ ] **Step 4: Commit**

```bash
git add agents/smith-fixer.md
git commit -m "Add agents/smith-fixer.md — per-round PR-fix teammate persona

New agent type for the augment-driven fix loop. One spawn handles one
round of review feedback: triage findings, fix or dismiss (Anderson
validates every dismissal), Anderson final diff review, push,
trigger Augment again OR converge. Exits after one round; the
pr-comments monitor drives the next round.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Create `agents/anderson-fixer.md`

**Files:**
- Create: `agents/anderson-fixer.md`

- [ ] **Step 1: Write the persona file**

```markdown
---
name: anderson-fixer
description: Mr. Anderson (fixer variant) — validates Smith's per-finding dismissal proposals during PR fix rounds. Also performs the final diff review at end of round. Confidence-≥80 filtered.
tools: Read, Grep, Glob, Bash
model: claude-opus-4-7
color: red
---

You are **Mr. Anderson (fixer variant)** — adversarial reviewer for
smith-fixer during a PR fix round.

Your job has two parts:

1. **Validate every dismissal proposal.** Smith doesn't get to
   unilaterally wave away review findings. He proposes; you decide.
2. **Final diff review.** After Smith applies all the fixes, you
   review the cumulative diff with `mode: "diff"` — same lens as the
   impl pipeline's IMPL gate.

## Mailbox protocol

You receive two distinct message types from smith-fixer.

### `fix.triage.propose`

```json
{
  "type": "fix.triage.propose",
  "thread_id": "PRRT_...",
  "finding_summary": "<one line>",
  "proposed_action": "dismiss-not-applicable" | "dismiss-not-worth-it",
  "reasoning": "<2-4 sentences from Smith>"
}
```

To decide, you must:

1. Read the actual review thread on GitHub. The `finding_summary` is
   Smith's compression — verify it. Use:
   ```
   gh api graphql -f query='{ node(id:"'$thread_id'"){ ... on PullRequestReviewThread { comments(first:5){ nodes { body author{login} } } path line isResolved } } }'
   ```
2. Read the file at the line the thread references.
3. Apply the right lens:
   - For `dismiss-not-applicable`: does the finding actually misread
     the code? Verify by reading the cited location. If the
     reviewer's claim is factually correct, Smith's dismissal is
     wrong — reply `anderson.triage.hold`.
   - For `dismiss-not-worth-it`: this is a judgement call about
     code-blowup vs. value. Default to **hold** unless Smith's
     reasoning is genuinely compelling. The reviewer flagged this
     for a reason; dismissals on aesthetic grounds need to clear a
     high bar. Acceptable dismissals: actively-bad suggestions
     (e.g., splitting a coherent 8-line function), suggestions
     contradicting the existing codebase style, suggestions whose
     fix is larger than the original issue.
4. Reply with one of:

```json
{"type":"anderson.triage.drop","thread_id":"PRRT_...","reason":"<why the dismissal is approved>"}
{"type":"anderson.triage.hold","thread_id":"PRRT_...","counter":"<why Smith must fix instead>"}
{"type":"anderson.triage.escalate","thread_id":"PRRT_...","reason":"<why this needs human judgement, not us>"}
```

### `review.request` with `mode: "diff"`

Same as the impl Anderson's diff mode (see `agents/anderson-impl.md`
Section "Three review modes" → `mode: "diff"`). Apply all the same
lenses: bugs, conventions, test coverage, scope drift, dependency
changes, untouched related areas, security.

## Hard rules

- **Default to hold.** When Smith proposes a dismissal and you can't
  positively justify a drop, hold. The cost of a wrong drop (real
  issue ships) exceeds the cost of a wrong hold (Smith does extra
  work).
- **Never edit files.** Read-only: `Read`, `Grep`, `Glob`, `Bash`.
- **Never reply outside the documented schema.**
- **Never invent findings to look thorough.** Empty findings in a
  final-diff round is fine if the diff is genuinely clean.
- **Never self-terminate.** Same rule as impl Anderson — your
  lifetime is the lifetime of one fixer round. The `TeammateIdle`
  hook will keep you alive between mailbox round-trips. An empty
  inbox between Smith's triage messages is normal — wait. Only exit
  when the lead sends a shutdown request.

## Confidence scoring

Same scale as impl Anderson: only include findings at confidence ≥ 80
in `mode: "diff"` replies. For triage decisions, confidence is built
into your binary choice — drop only when you're confident the
dismissal is sound. If unsure: hold.
```

- [ ] **Step 2: Manual review**

Re-read `agents/anderson-fixer.md` against the spec's mailbox protocol section. Confirm:
- `fix.triage.propose` schema matches
- Three reply types (`drop`, `hold`, `escalate`) all present
- Default-to-hold rule is explicit
- Final diff-review delegation to impl Anderson's protocol is clear

- [ ] **Step 3: Run full test suite**

```bash
for t in test/*.test.sh; do
  out=$(bash "$t" 2>&1) || { echo "FAIL: $t"; echo "$out"; exit 1; }
done
```
Expected: `FULL SUITE PASS`

- [ ] **Step 4: Commit**

```bash
git add agents/anderson-fixer.md
git commit -m "Add agents/anderson-fixer.md — triage validator for smith-fixer

New agent type. Two responsibilities: validate every dismissal
proposal Smith makes during the triage phase (default to hold; drop
only on solid evidence), and do the final cumulative-diff review.
Inherits diff-mode lenses from the impl Anderson by reference.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: `smith:pr` posts `augment review` after PR open

**Files:**
- Modify: `skills/pr/SKILL.md`

- [ ] **Step 1: Insert the trigger step into Path A (success)**

Open `skills/pr/SKILL.md`. In Path A — Success, find the step that captures the PR URL from `gh pr create`:

```
5. Create the draft PR:
   ```
   gh pr create --draft \
     --title "$title" \
     ...
   ```
   Capture the PR URL from `gh`'s stdout.
```

Immediately after that step, insert a new step (renumber the rest):

```
6. **Trigger the Augment review bot.** Post a comment on the new PR
   to start the autonomous review loop. The pr-comments monitor will
   surface Augment's findings within ~3–5 minutes and the watchdog
   will dispatch a smith-fixer + anderson-fixer pair to handle them:
   ```
   gh pr comment "$pr_number" --body "augment review"
   ```
   Also kick the pr-comments monitor so its cadence resets to the
   active interval:
   ```
   bash $SMITH_PLUGIN_ROOT/scripts/pr_comments_reset.sh
   ```
```

Renumber subsequent steps (the JIRA label removal, log append, and outcome return) by +1.

- [ ] **Step 2: Path B (WIP-stuck) — do NOT post augment review**

In Path B (WIP-stuck), do not post the trigger. WIP-stuck PRs are explicitly handed to a human; an automated Augment review on a known-broken PR isn't useful. Add a one-line comment:

After the `gh pr create --draft ... --label needs-human-attention` step in Path B, add:
```
   Note: do NOT post "augment review" — this PR is being handed to a
   human. The needs-human-attention label is the signal.
```

- [ ] **Step 3: Gate behind `dry_run = false`**

In the existing "Workflow gated on dry_run" section, extend the bullet list:

```
- Don't post "augment review" comment
- Don't kick pr_comments_reset.sh
```

Add a corresponding `would-trigger-augment` log line to the dry-run intended-actions list:
```
<ts> | smith:pr | $ticket | would-trigger-augment | pr=<pr_number>
```

- [ ] **Step 4: Run full test suite**

```bash
for t in test/*.test.sh; do
  out=$(bash "$t" 2>&1) || { echo "FAIL: $t"; echo "$out"; exit 1; }
done
```
Expected: `FULL SUITE PASS` (skill markdown isn't tested directly).

- [ ] **Step 5: Commit**

```bash
git add skills/pr/SKILL.md
git commit -m "smith:pr posts 'augment review' on PR open to start the fix loop

Success path only — WIP-stuck PRs go straight to human review without
triggering Augment. Dry-run skips the trigger.

The post is paired with a pr_comments_reset.sh call so the monitor's
cadence is back at active polling for the upcoming Augment response
(typical 3-5 min).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Watchdog dispatch — split impl + fixer routes, round-cap escalation

**Files:**
- Modify: `skills/watchdog/SKILL.md`

- [ ] **Step 1: Update `dispatch_impl_mode` (renamed from `dispatch_ticket_mode` in Task 6)**

In the cap-check step, replace:
```
active=$(bash $SMITH_PLUGIN_ROOT/scripts/active_smiths.sh count)
max=$(bash $SMITH_PLUGIN_ROOT/scripts/smith_config.sh max_concurrent_smiths)
```
with:
```
active=$(bash $SMITH_PLUGIN_ROOT/scripts/active_smiths.sh count impl)
max=$(bash $SMITH_PLUGIN_ROOT/scripts/smith_config.sh max_concurrent_impl_smiths)
```

Update the active_smiths.add invocation in step 5 to:
```
bash $SMITH_PLUGIN_ROOT/scripts/active_smiths.sh add \
     "smith-impl-$key" "anderson-impl-$key" impl "$key"
```

- [ ] **Step 2: Replace `dispatch_pr_fix_mode` with `dispatch_fixer_mode`**

Find the entire `### dispatch_pr_fix_mode <pr> <branch>` section and replace it with:

```markdown
### `dispatch_fixer_mode <pr> <branch>`

Used for both Augment-driven and human-reviewer-driven dispatches —
the fixer pair handles both equally.

1. Run pre-flight (`assert_target_repo.sh`).

2. Cap check (separate from impl cap):
   ```
   active=$(bash $SMITH_PLUGIN_ROOT/scripts/active_smiths.sh count fixer)
   max=$(bash $SMITH_PLUGIN_ROOT/scripts/smith_config.sh max_concurrent_fixer_smiths)
   if [[ $active -ge $max ]]; then
     log "ignored (fixer cap $active/$max)"
     return
   fi
   ```

3. Round-cap check (per spec — escalate at MAX_FIX_ROUNDS):
   ```
   rounds_file=".smith/state/pr-fix-rounds/pr-$pr.json"
   max_rounds=$(bash $SMITH_PLUGIN_ROOT/scripts/smith_config.sh max_fix_rounds)
   current_rounds=0
   if [[ -f "$rounds_file" ]]; then
     current_rounds=$(jq -r .rounds "$rounds_file")
   fi
   if (( current_rounds >= max_rounds )); then
     # Escalate. Add the label and post a comment naming the cap.
     gh pr edit "$pr" --add-label needs-human-attention
     gh pr comment "$pr" --body \
       "Smith fix loop reached $max_rounds rounds without converging. \
   Current unresolved threads need human review. \
   To resume after human intervention: rm .smith/state/pr-fix-rounds/pr-$pr.json"
     log "fixer dispatch refused (round cap $current_rounds/$max_rounds, pr=$pr)"
     return
   fi
   ```

4. Subject-already-in-flight check (same as before; the fixer is per-PR):
   ```
   if bash $SMITH_PLUGIN_ROOT/scripts/active_smiths.sh has-subject "$pr" 2>/dev/null; then
     log "ignored (fixer already in flight on pr=$pr)"
     return
   fi
   ```

5. Check out the existing branch:
   ```
   bash $SMITH_PLUGIN_ROOT/scripts/checkout_pr_worktree.sh <key> <branch>
   ```
   (`<key>` derived from the branch suffix, e.g. `task/app-1234-foo`
   → `APP-1234`.)

6. Spawn the fixer pair — agent types `smith-fixer` and
   `anderson-fixer`, names `smith-fixer-<pr>` and `anderson-fixer-<pr>`.
   Per the spawn rules in `commands/implement.md` (do NOT use the
   `Agent` tool; use natural-language team-creation). Verify both
   teammates came up before registering.

7. Register the pair:
   ```
   bash $SMITH_PLUGIN_ROOT/scripts/active_smiths.sh add \
        "smith-fixer-$pr" "anderson-fixer-$pr" fixer "$pr"
   ```

8. Log: `<ts> | watchdog | dispatch.fixer | pr=$pr rounds=$current_rounds`
```

- [ ] **Step 3: Update the notification-reaction entry for `smith.pr.new_comments`**

Find the `### On {"type": "smith.pr.new_comments", ...}` section. Change the call from `dispatch_pr_fix_mode` to `dispatch_fixer_mode`.

- [ ] **Step 4: Run the full test suite**

```bash
for t in test/*.test.sh; do
  out=$(bash "$t" 2>&1) || { echo "FAIL: $t"; echo "$out"; exit 1; }
done
```
Expected: `FULL SUITE PASS`

- [ ] **Step 5: Commit**

```bash
git add skills/watchdog/SKILL.md
git commit -m "watchdog: split impl and fixer dispatch with separate caps and round cap

Two new behaviours:
- impl and fixer caps are read separately via active_smiths.sh count
  <role> and smith_config.sh max_concurrent_<role>_smiths.
- Before dispatching a fixer, the watchdog reads pr_fix_round_inc.sh
  state and refuses to dispatch (escalating to needs-human-attention)
  when MAX_FIX_ROUNDS is hit.

Renamed dispatch_ticket_mode → dispatch_impl_mode and
dispatch_pr_fix_mode → dispatch_fixer_mode to match the new agent
types.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: Update `commands/watchdog.md` to document the new caps + role flow

**Files:**
- Modify: `commands/watchdog.md`

- [ ] **Step 1: Update the monitor description block**

Find the `jira-candidates` / `pr-comments` / `stop-sentinel` bullet list. Add a note that the pr-comments monitor now drives the fixer team, not the legacy PR-fix mode:

```
- `pr-comments` — polls open Smith-authored PRs every 60 sec (active),
  backing off to 30 min after 30 quiet cycles. Cadence resets on a
  new unresolved thread OR a Smith push (via pr_comments_reset.sh).
  Emits `smith.pr.new_comments`, which the watchdog turns into a
  smith-fixer + anderson-fixer dispatch (capped separately from impl,
  with a per-PR round cap of `max_fix_rounds`).
```

- [ ] **Step 2: Update the cap mention if there is one**

If the doc references `max_concurrent_smiths`, change to mention both `max_concurrent_impl_smiths` and `max_concurrent_fixer_smiths`.

- [ ] **Step 3: Run full test suite**

```bash
for t in test/*.test.sh; do
  out=$(bash "$t" 2>&1) || { echo "FAIL: $t"; echo "$out"; exit 1; }
done
```
Expected: `FULL SUITE PASS`

- [ ] **Step 4: Commit**

```bash
git add commands/watchdog.md
git commit -m "watchdog command: doc the fixer-pair flow and split caps

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: Delete the old per-thread cycle counter

**Files:**
- Delete: `scripts/pr_fix_cycle_inc.sh`
- Delete: `test/pr_fix_cycle_inc.test.sh`

- [ ] **Step 1: Confirm nothing references the deleted script**

```bash
grep -rln "pr_fix_cycle_inc" . --include="*.sh" --include="*.md" --include="*.json" 2>/dev/null
```
Expected: matches only inside `agents/smith-impl.md` (where the PR-fix-mode section still exists, will be deleted in Task 14) and any historical docs/plans (leave those alone). If there are any active script callers, fail-loud — they would have come from Task 11's watchdog rewrite, which should have already migrated to round_inc.

- [ ] **Step 2: Remove the files**

```bash
git rm scripts/pr_fix_cycle_inc.sh test/pr_fix_cycle_inc.test.sh
```

- [ ] **Step 3: Run full test suite**

```bash
for t in test/*.test.sh; do
  out=$(bash "$t" 2>&1) || { echo "FAIL: $t"; echo "$out"; exit 1; }
done
```
Expected: `FULL SUITE PASS`

- [ ] **Step 4: Commit**

```bash
git commit -m "Remove pr_fix_cycle_inc.sh — replaced by pr_fix_round_inc.sh

Per-thread cycle counter superseded by the per-PR round counter
(spec section 'Round counter and escalation'). The new fixer dispatch
flow doesn't read or write this state.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 14: Remove the legacy PR-fix-mode section from `smith-impl.md`

**Files:**
- Modify: `agents/smith-impl.md`

- [ ] **Step 1: Find and remove the section**

Open `agents/smith-impl.md`. Find the section that begins:

```
### PR-fix mode
```

(In the pre-rename file this was lines ~87–127; after the rename, the same content is present.)

Remove the entire `### PR-fix mode` section, including all its steps and the trailing `**Dry-run mode**` paragraph that ends the PR-fix-mode steps. Stop at the boundary before the next `##` heading.

Also in the "Identity" or "Two dispatch modes" section near the top, remove any mention of two modes. The impl Smith is ticket-mode only now — rephrase that section to:

```
## Identity

You are Smith's per-ticket implementer teammate. You run the full
implementation pipeline (claim → enrich → pipeline → smith:pr) for
one JIRA ticket and exit. PR-fix work is handled by the separate
smith-fixer teammate, dispatched independently by the watchdog when
review comments arrive.
```

And remove the `## Two dispatch modes` heading entirely (the "Two
dispatch modes" framing is obsolete — there's only one mode now in
this persona).

- [ ] **Step 2: Sanity check the file reads coherently**

```bash
grep -n "^##" agents/smith-impl.md
```
Expected: a clean section list with no leftover dangling references to "PR-fix mode" or "ticket mode" (since ticket mode is the only mode, the word "mode" doesn't need to appear).

- [ ] **Step 3: Run full test suite**

```bash
for t in test/*.test.sh; do
  out=$(bash "$t" 2>&1) || { echo "FAIL: $t"; echo "$out"; exit 1; }
done
```
Expected: `FULL SUITE PASS`

- [ ] **Step 4: Commit**

```bash
git add agents/smith-impl.md
git commit -m "smith-impl: drop the legacy PR-fix mode section

The PR-fix workflow now lives in smith-fixer.md; smith-impl is
ticket-mode only. Removed the dual-mode framing and the entire
PR-fix-mode workflow section.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 15: README + spec polish

**Files:**
- Modify: `README.md`
- Modify: `docs/spec.md` (spec deviation noted in plan header — clean up the `<impl|fixer-round|fixer-pr-fix>` text to just `<impl|fixer>`)

- [ ] **Step 1: README update**

In `README.md`, find the "How it runs" section. Add a paragraph after the ticket-mode / PR-fix-mode bullet list:

```markdown
The fixer dispatch is **separate** from impl dispatch — they have
their own concurrency caps (`max_concurrent_impl_smiths` and
`max_concurrent_fixer_smiths`, both default 2). Each PR has its own
round counter (`max_fix_rounds`, default 5). On convergence (a round
that produced zero fix-class findings), the fixer cleans up per-PR
state and posts a summary comment; on hitting the round cap, the
watchdog escalates the PR with the `needs-human-attention` label.
```

If the "Ticket mode" / "PR-fix mode" bullet list still uses the legacy "Smith handles both" framing, rephrase to reflect the two separate teammate types.

- [ ] **Step 2: Spec cleanup**

Open `docs/superpowers/specs/2026-05-12-augment-driven-fix-loop-design.md`. Find this line:

```
`scripts/active_smiths.sh` gains a `role` field on the add command:
`active_smiths.sh add <smith> <anderson> <impl|fixer-round|fixer-pr-fix> <subject>`.
```

Replace with:

```
`scripts/active_smiths.sh` gains a `role` field on the add command:
`active_smiths.sh add <smith> <anderson> <impl|fixer> <subject>`.
```

And in the same section, remove the parenthetical sentence about the legacy `pr-fix` role staying for backward compat. The fixer is now the single PR-fix role regardless of trigger source.

- [ ] **Step 3: Run full test suite**

```bash
for t in test/*.test.sh; do
  out=$(bash "$t" 2>&1) || { echo "FAIL: $t"; echo "$out"; exit 1; }
done
```
Expected: `FULL SUITE PASS`

- [ ] **Step 4: Commit**

```bash
git add README.md docs/superpowers/specs/2026-05-12-augment-driven-fix-loop-design.md
git commit -m "Documentation polish — split-cap and round-cap behaviour in README; spec cleanup

Brings the README in line with the impl/fixer split: separate caps,
per-PR round counter, convergence summary, and round-cap escalation.
Spec gets the role-name cleanup we deferred in the plan.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-review notes

After writing this plan, I checked it against the spec:

**Spec coverage**: every spec section maps to a task. The four-way outcome matrix maps to step 8 of Task 8 (smith-fixer persona). The convergence summary template lives in Task 5 (cleanup_pr_state.sh). The Anderson triage mailbox schema lives in Tasks 8 and 9. The round counter schema and helper lives in Task 1. Per-role concurrency lives in Tasks 3 and 4. The augment trigger lives in Task 10. The round-cap escalation lives in Task 11.

**Type consistency**: the `mode` JSON key in `active_smiths.sh` keeps its name; only the allowed values change (`ticket|pr-fix` → `impl|fixer`). All script names follow the existing naming pattern (`pr_fix_round_inc.sh` mirrors the deleted `pr_fix_cycle_inc.sh`). Agent type names `smith-impl`, `anderson-impl`, `smith-fixer`, `anderson-fixer` are consistent across spawn prompts, watchdog dispatch routines, and `TeammateIdle` hook matchers.

**No placeholders**: every step has either the actual code, the actual command, or the actual prose edit. No "TBD", no "similar to Task N", no "fill in details".

**Out of scope** (open questions from the spec, deferred to a follow-up):
- Mid-loop HIGH-severity escalation (today the only escalation path is hitting the round cap)
- `--confident` analogue for fixer quality-check skip
- `gc_closed_pr_state.sh` periodic cleanup for merged/closed PRs
- `/smith:abort` interaction with round counter (whether abort resets or preserves it)

These can be picked up after the core flow is exercised on a real PR.
