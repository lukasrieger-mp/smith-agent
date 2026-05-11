#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

INSTALL="${ROOT}/install.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Canonicalize TMP (macOS /var → /private/var) so it matches scripts' `pwd -P`.
TMP=$(cd "$TMP" && pwd -P)

# Stage a fake plugin source tree
PLUGIN="$TMP/smith-agent"
mkdir -p "$PLUGIN"/{agents,commands,skills/smith-watchdog}
touch "$PLUGIN/agents/anderson.md"
touch "$PLUGIN/commands/smith-implement.md"
touch "$PLUGIN/skills/smith-watchdog/SKILL.md"
cp "$INSTALL" "$PLUGIN/install.sh"
chmod +x "$PLUGIN/install.sh"

# Stage a fake target git repo
TARGET="$TMP/target"
mkdir -p "$TARGET"
git -C "$TARGET" init -q
git -C "$TARGET" commit --allow-empty -m initial -q

# Missing arg -> fail
if bash "$PLUGIN/install.sh" 2>/dev/null; then
  echo "FAIL: should fail with no args" >&2; exit 1
fi

# Non-existent target -> fail
if bash "$PLUGIN/install.sh" /nope/does/not/exist 2>/dev/null; then
  echo "FAIL: should fail on nonexistent target" >&2; exit 1
fi

# Target not a git repo -> fail
NOTREPO="$TMP/notrepo"
mkdir -p "$NOTREPO"
if bash "$PLUGIN/install.sh" "$NOTREPO" 2>/dev/null; then
  echo "FAIL: should fail on non-git target" >&2; exit 1
fi

# Happy path: install against the target
bash "$PLUGIN/install.sh" "$TARGET" >/dev/null

# Symlinks land in $TARGET/.claude/
[[ -L "$TARGET/.claude/agents/anderson.md" ]] || { echo "FAIL: agent symlink missing" >&2; exit 1; }
[[ -L "$TARGET/.claude/commands/smith-implement.md" ]] || { echo "FAIL: command symlink missing" >&2; exit 1; }
[[ -L "$TARGET/.claude/skills/smith-watchdog" ]] || { echo "FAIL: skill dir symlink missing" >&2; exit 1; }

# Symlink targets are ABSOLUTE paths pointing into the plugin source
target_of=$(readlink "$TARGET/.claude/agents/anderson.md")
assert_eq "$PLUGIN/agents/anderson.md" "$target_of" "absolute-symlink"

# .gitignore now contains the Smith block
grep -qxF '### Smith ###' "$TARGET/.gitignore" || { echo "FAIL: missing smith marker in gitignore" >&2; exit 1; }
grep -qxF '.smith/' "$TARGET/.gitignore" || { echo "FAIL: missing .smith/ entry in gitignore" >&2; exit 1; }

# Re-running is idempotent: no error, no duplicate gitignore entries
bash "$PLUGIN/install.sh" "$TARGET" >/dev/null
count=$(grep -cF '.smith/' "$TARGET/.gitignore")
assert_eq "1" "$count" "idempotent-gitignore"

# Refuses to overwrite a non-symlink file
rm "$TARGET/.claude/agents/anderson.md"
echo "real file" > "$TARGET/.claude/agents/anderson.md"
if bash "$PLUGIN/install.sh" "$TARGET" 2>/dev/null; then
  echo "FAIL: should refuse to overwrite non-symlink" >&2; exit 1
fi

# Target pointing at a subdir (not repo root) -> fail
mkdir -p "$TARGET/subdir"
if bash "$PLUGIN/install.sh" "$TARGET/subdir" 2>/dev/null; then
  echo "FAIL: should refuse non-toplevel target" >&2; exit 1
fi

echo "PASS install.test.sh"
