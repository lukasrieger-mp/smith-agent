#!/usr/bin/env bash
# Install Smith into a target repo:
#   1. Create symlinks at <target>/.claude/{agents,commands,skills}/...
#      pointing back at the smith-agent plugin source (this directory).
#   2. Ensure the target's .gitignore contains a `### Smith ###` block
#      with `.smith/` so the runtime state directory is not tracked.
#
# Idempotent. Refuses to overwrite non-symlink files. Re-running with the
# same target produces no error and no duplicate gitignore entries.
set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") <target-repo-path>

Installs Smith into the target git repository.
EOF
  exit 1
}

[[ $# -eq 1 ]] || usage

# Resolve our own location (the smith-agent plugin source root).
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Resolve the user-provided target.
TARGET="$1"
[[ -d "$TARGET" ]] || { echo "install: target not a directory: $TARGET" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd -P)"

# Verify target is a git repo (and that its toplevel matches — guards against
# pointing at a subdirectory).
git_toplevel=$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null) || {
  echo "install: target is not a git repository: $TARGET" >&2; exit 1
}
[[ "$git_toplevel" == "$TARGET" ]] || {
  echo "install: target is inside a git repo but not at its root: $TARGET" >&2
  echo "  toplevel is: $git_toplevel" >&2; exit 1
}

# --- 1. Symlink the plugin items into <target>/.claude/ ---

created=0; skipped=0
link_one() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ -L "$dest" ]]; then
    local current; current=$(readlink "$dest")
    if [[ "$current" == "$src" ]]; then
      skipped=$((skipped+1)); return
    fi
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
  if [[ -d "$PLUGIN_DIR/$kind" ]]; then
    while IFS= read -r -d '' f; do
      rel="${f#$PLUGIN_DIR/$kind/}"
      [[ "$rel" == ".keep" ]] && continue
      link_one "$PLUGIN_DIR/$kind/$rel" "$TARGET/.claude/$kind/$rel"
    done < <(find "$PLUGIN_DIR/$kind" -maxdepth 1 -mindepth 1 -type f -print0)
  fi
done

# Skills: directory symlinks (one per skill)
if [[ -d "$PLUGIN_DIR/skills" ]]; then
  while IFS= read -r -d '' d; do
    name="$(basename "$d")"
    [[ "$name" == ".keep" ]] && continue
    link_one "$PLUGIN_DIR/skills/$name" "$TARGET/.claude/skills/$name"
  done < <(find "$PLUGIN_DIR/skills" -maxdepth 1 -mindepth 1 -type d -print0)
fi

# --- 2. Ensure .gitignore has a Smith block ---

gitignore="$TARGET/.gitignore"
marker="### Smith ###"
ignore_entry=".smith/"

ensure_gitignore_block() {
  # If the entry already appears anywhere in .gitignore, we're done.
  if [[ -f "$gitignore" ]] && grep -qxF "$ignore_entry" "$gitignore"; then
    return
  fi
  # Build the block (header + entry). If file exists and doesn't end with a
  # newline, prepend one to avoid mashing onto an existing line.
  {
    if [[ -f "$gitignore" ]] && [[ -s "$gitignore" ]] && [[ "$(tail -c1 "$gitignore")" != "" ]]; then
      printf '\n'
    fi
    printf '\n%s\n%s\n' "$marker" "$ignore_entry"
  } >> "$gitignore"
}

ensure_gitignore_block

# --- 3. Summary ---

echo "smith-agent install.sh:"
echo "  plugin source: $PLUGIN_DIR"
echo "  target:        $TARGET"
echo "  symlinks:      $created created, $skipped already linked"
echo "  gitignore:     ensured .smith/ is ignored in $TARGET/.gitignore"
